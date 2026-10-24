# grim CLI reference

## Environment

| Variable | Purpose |
|----------|---------|
| `GRIM_HOME` | Data directory (default `~/.grimoire`) |
| `OP_SERVICE_ACCOUNT_TOKEN` | Scoped API access (`ops_...` token) |
| `OP_CONNECT_HOST` / `OP_CONNECT_TOKEN` | **Blocked** — grim exits with error |

Layout: `config.properties`, `vaults/<id>/` (metadata, `items/*.json`, legacy secrets).

## Exit codes

- `2` — usage error (`UsageError`)
- `1` — other errors
- Child exit code from `grim run`

## Commands

### `grim vault`

| Subcommand | Notes |
|------------|--------|
| `list` | `--format human\|json`; `--account` for service token |
| `get` | Human or JSON metadata |
| `create` | Human: `<id> --gpg-recipient KEY`; op: `NAME --format json` (GPG from `--gpg-recipient` or default) |
| `edit` | `--gpg-recipient`, `--description` (re-encrypts on recipient change) |
| `delete` | `--force` or TTY confirm |
| `use` | Set default vault id |

### `grim item` (requires `--format json`)

| Subcommand | Notes |
|------------|--------|
| `list` | `--vault`, `--account` |
| `get` | `--vault` required; `--reveal` for values; `-` + stdin for batch |
| `create` | `-` + JSON stdin; `--vault` required |
| `edit` | `ID --vault V` + JSON stdin |

### `grim secret`

| Subcommand | Notes |
|------------|--------|
| `list` | `--vault`, `--format human\|json` |
| `get` | `--reveal` for value; JSON adds `concealed` or `value` |
| `create` | `--value`, `--stdin`, or TTY prompt (with confirm on create) |
| `edit` | `--value` / `--stdin` / piped stdin |
| `delete` | `--force` or TTY confirm |

### `grim account`

- `list --format json` — local account descriptor

### `grim service-account`

- `create NAME --vault VAULT:CAPS --raw [--expires-in 90d]`
- Caps: `read_items`, `write_items` (comma-separated)
- Prints raw token once; store securely

### `grim read`

- `grim read [--no-newline] <grim://\|op:// reference>`

### `grim inject`

- Reads stdin or `-i file`; writes stdout or `-o file`
- Replaces `{{op://...}}` / `{{grim://...}}` (and bare refs in `substituteRefs` paths via templates)

### `grim run`

- `grim run [--env-file path] [--no-masking] -- COMMAND [args...]`
- With `--env-file`, merges file after inheriting OS env; without it, substitutes refs in inherited env values only
- `connectForbidden` + auth run before exec

## ID rules

Vault and secret ids: 1–128 chars, alphanumeric start, `[a-zA-Z0-9._-]`. Item ids are 26-char lowercase alnum (op-style).

## GPG

Vaults encrypt concealed item fields and secret values to `--gpg-recipient` (fingerprint). Changing recipient re-encrypts vault contents.
