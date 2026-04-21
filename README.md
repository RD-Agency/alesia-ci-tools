# Alesia CI Tools

Composite GitHub Action that posts a **stylish Discord embed** after every Alesia deploy workflow — success, failure or cancelled — with the commit, branch, actor, duration, a link to the run, and (on failure) an excerpt of the failing job's logs.

![example](https://raw.githubusercontent.com/RD-Agency/alesia-ci-tools/main/assets/preview.png)

## Usage

Add one step at the end of your deploy job:

```yaml
- name: Discord notify
  if: always()
  uses: RD-Agency/alesia-ci-tools@main
  with:
    webhook: ${{ secrets.DISCORD_DEPLOY_WEBHOOK }}
    status: ${{ job.status }}
```

The webhook URL is stored as an **organization-level secret** (`DISCORD_DEPLOY_WEBHOOK`), scoped to Alesia repos.

## Inputs

| Name | Required | Default | Description |
|---|---|---|---|
| `webhook` | ✅ | — | Discord webhook URL |
| `status` | ✅ | — | `${{ job.status }}` |
| `title` | ❌ | auto | Override embed title |
| `github-token` | ❌ | `${{ github.token }}` | Used to fetch failure logs |
| `include-logs` | ❌ | `true` | Attach log excerpt on failure |
| `log-lines` | ❌ | `25` | Max lines of failure log |

## Colors & icons

| Status | Color | Emoji | Label (fr) |
|---|---|---|---|
| success | 🟢 `#2ecc71` | 🚀 | déployé |
| failure | 🔴 `#e74c3c` | 💥 | échec |
| cancelled | 🟡 `#f1c40f` | ✋ | annulé |
