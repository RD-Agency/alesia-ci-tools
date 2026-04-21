#!/usr/bin/env bash
# Alesia Discord Deploy Notify — builds a stylish embed and POSTs to a Discord webhook.
# Consumes ${{ job.status }} via INPUT_STATUS and rich context from GITHUB_* env vars.

set -uo pipefail

WEBHOOK="${INPUT_WEBHOOK:?webhook required}"
STATUS_RAW="${INPUT_STATUS:-success}"
TITLE_OVR="${INPUT_TITLE:-}"
INCLUDE_LOGS="${INPUT_INCLUDE_LOGS:-true}"
LOG_LINES="${INPUT_LOG_LINES:-25}"

STATUS="$(echo "$STATUS_RAW" | tr '[:upper:]' '[:lower:]')"
case "$STATUS" in
  success)    COLOR=3066993   ; EMOJI="🚀" ; LABEL="déployé" ;;
  failure)    COLOR=15158332  ; EMOJI="💥" ; LABEL="échec"   ;;
  cancelled)  COLOR=15844367  ; EMOJI="✋" ; LABEL="annulé"  ;;
  *)          COLOR=9807270   ; EMOJI="ℹ️" ; LABEL="$STATUS" ;;
esac

REPO="${GITHUB_REPOSITORY:-unknown/unknown}"
REPO_SHORT="${REPO##*/}"
BRANCH="${GITHUB_REF_NAME:-${GITHUB_HEAD_REF:-main}}"
SHA="${GITHUB_SHA:-0000000000000000000000000000000000000000}"
SHA_SHORT="${SHA:0:7}"
ACTOR="${GITHUB_ACTOR:-unknown}"
WORKFLOW="${GITHUB_WORKFLOW:-workflow}"
JOB="${GITHUB_JOB:-job}"
RUN_ID="${GITHUB_RUN_ID:-0}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"
SERVER="${GITHUB_SERVER_URL:-https://github.com}"
EVENT="${GITHUB_EVENT_NAME:-push}"
COMMIT_URL="${SERVER}/${REPO}/commit/${SHA}"
RUN_URL="${SERVER}/${REPO}/actions/runs/${RUN_ID}"
COMPARE_URL="${SERVER}/${REPO}/compare/${SHA}~...${SHA}"
AVATAR="https://avatars.githubusercontent.com/${ACTOR}?size=64"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Commit message (first line, trim, escape)
COMMIT_MSG=""
if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
  COMMIT_MSG="$(
    jq -r '(.head_commit.message // .commits[0].message // .pull_request.title // "") | split("\n")[0]' \
      "$GITHUB_EVENT_PATH" 2>/dev/null || echo ""
  )"
fi
[[ -z "$COMMIT_MSG" ]] && COMMIT_MSG="(no commit message)"
# Truncate to 200 chars
if (( ${#COMMIT_MSG} > 200 )); then
  COMMIT_MSG="${COMMIT_MSG:0:197}…"
fi

# Elapsed: best-effort using run creation time fetched via API
ELAPSED="—"
if command -v gh >/dev/null 2>&1 && [[ "$RUN_ID" != "0" ]]; then
  START_ISO="$(gh api "/repos/${REPO}/actions/runs/${RUN_ID}" --jq '.run_started_at // .created_at' 2>/dev/null || echo "")"
  if [[ -n "$START_ISO" ]]; then
    START_EPOCH="$(date -u -d "$START_ISO" +%s 2>/dev/null || echo 0)"
    NOW_EPOCH="$(date -u +%s)"
    if (( START_EPOCH > 0 )); then
      DIFF=$(( NOW_EPOCH - START_EPOCH ))
      if (( DIFF < 60 )); then
        ELAPSED="${DIFF}s"
      elif (( DIFF < 3600 )); then
        ELAPSED="$((DIFF / 60))m $((DIFF % 60))s"
      else
        ELAPSED="$((DIFF / 3600))h $(((DIFF % 3600) / 60))m"
      fi
    fi
  fi
fi

TITLE_DEFAULT="${EMOJI}  ${REPO_SHORT} · ${LABEL}"
TITLE="${TITLE_OVR:-$TITLE_DEFAULT}"

DESC="[\`${SHA_SHORT}\`](${COMMIT_URL}) — ${COMMIT_MSG}"

# Build embeds with jq
JQ_ARGS=(
  --arg title "$TITLE"
  --arg description "$DESC"
  --arg url "$RUN_URL"
  --argjson color "$COLOR"
  --arg author "$ACTOR"
  --arg author_url "${SERVER}/${ACTOR}"
  --arg author_icon "$AVATAR"
  --arg footer "Alesia · ${WORKFLOW} · attempt ${RUN_ATTEMPT}"
  --arg footer_icon "https://github.githubassets.com/favicons/favicon-dark.svg"
  --arg repo_val "[${REPO}](${SERVER}/${REPO})"
  --arg branch_val "\`${BRANCH}\`"
  --arg event_val "\`${EVENT}\`"
  --arg elapsed_val "$ELAPSED"
  --arg run_val "[#${RUN_ID}](${RUN_URL})"
  --arg ts "$TIMESTAMP"
)
MAIN_EMBED=$(jq -n "${JQ_ARGS[@]}" '
{
  title: $title,
  description: $description,
  url: $url,
  color: $color,
  timestamp: $ts,
  author: { name: $author, url: $author_url, icon_url: $author_icon },
  footer: { text: $footer, icon_url: $footer_icon },
  fields: [
    { name: "Repo",     value: $repo_val,    inline: true },
    { name: "Branch",   value: $branch_val,  inline: true },
    { name: "Event",    value: $event_val,   inline: true },
    { name: "Durée",    value: $elapsed_val, inline: true },
    { name: "Run",      value: $run_val,     inline: true }
  ]
}
')

EMBEDS_JSON="[${MAIN_EMBED}]"

# On failure, optionally attach a log excerpt as a second embed
if [[ "$STATUS" == "failure" && "$INCLUDE_LOGS" == "true" && -n "${GH_TOKEN:-}" && "$RUN_ID" != "0" ]]; then
  LOG="$(gh run view "$RUN_ID" -R "$REPO" --log-failed 2>/dev/null \
        | tail -n "$LOG_LINES" \
        | sed -E 's/\x1b\[[0-9;]*m//g' \
        | cut -c1-240 \
        | awk 'BEGIN{total=0} {len=length($0)+1; if (total+len>1800) exit; print; total+=len}')"
  if [[ -n "$LOG" ]]; then
    LOG_EMBED=$(jq -n \
      --arg title "📜 Logs (derniers échecs)" \
      --arg desc "\`\`\`\n${LOG}\n\`\`\`" \
      --argjson color "$COLOR" \
      '{ title: $title, description: $desc, color: $color }')
    EMBEDS_JSON=$(echo "$EMBEDS_JSON" | jq --argjson extra "$LOG_EMBED" '. + [$extra]')
  fi
fi

PAYLOAD=$(jq -n \
  --arg username "Alesia CI" \
  --arg avatar "https://raw.githubusercontent.com/RD-Agency/alesia-ci-tools/main/assets/alesia-bot.png" \
  --argjson embeds "$EMBEDS_JSON" \
  '{ username: $username, avatar_url: $avatar, embeds: $embeds }')

# Post (retry once on transient errors)
post() {
  curl -fsS -X POST \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD" \
    "$WEBHOOK" \
    -o /tmp/discord.resp \
    -w 'HTTP %{http_code}\n' 2>&1
}

echo "Posting Discord embed (status=$STATUS) for ${REPO}@${SHA_SHORT}..."
if ! post; then
  echo "First attempt failed, retrying in 3s..."
  sleep 3
  post || { echo "Discord notification failed (non-fatal)."; exit 0; }
fi
echo "Discord notification sent ✓"
