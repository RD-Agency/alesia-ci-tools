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

---

# Claude PR review

Reusable workflow (`.github/workflows/claude-pr-review.yml`) : Claude relit chaque pull request, poste un commentaire de review, et **fusionne automatiquement** la PR quand il ne trouve rien de bloquant et que tous les autres checks sont verts.

## Installer sur un dépôt

1. Copier [`templates/claude-auto-review.yml`](templates/claude-auto-review.yml) dans `.github/workflows/claude-auto-review.yml`.
2. Ajouter le secret `CLAUDE_CODE_OAUTH_TOKEN` (généré avec `claude setup-token`).
   Pour RD-Agency, un secret d'organisation suffit.
3. Optionnel : secret `PR_MERGE_TOKEN` (PAT fine-grained, *Contents* + *Pull requests* en écriture). Sans lui, le merge est fait par `GITHUB_TOKEN`, et GitHub **ne déclenche pas** les workflows `on: push` (déploiements) après le merge.

## Fonctionnement

| Étape | Détail |
|---|---|
| Review | Claude (lecture seule) lit le diff et rend un verdict structuré : `approve` ou `request_changes`. |
| Commentaire | Un seul commentaire par PR, mis à jour à chaque nouveau commit. |
| Changements demandés | Le check `claude-review` passe en rouge, pas de merge. |
| Approuvé | Attend que les autres checks soient verts (30 min max), puis fusionne **exactement le commit relu**. |
| Garde-fous | Pas de merge pour les PR de forks, les auteurs sans droit d'écriture, ni les brouillons. |

## Options (`with:`)

| Nom | Défaut | Rôle |
|---|---|---|
| `auto_merge` | `true` | `false` = review seulement |
| `merge_method` | `squash` | `squash`, `merge` ou `rebase` |
| `checks_timeout_minutes` | `30` | Attente max des autres checks |
| `extra_instructions` | `""` | Règles de review propres au dépôt |
