---
name: grim-cli
description: >-
  Operate the grim CLI (grimoire): GPG-backed local vaults, secrets, op-compatible
  items, grim:// and op:// references, inject/run. Use for passwords, API keys,
  credentials, vault setup, service-account tokens, or when the user mentions grim
  or grimoire. Prefer grim-agent when it covers the task; use this skill for raw grim.
---

# grim CLI

`grim` is a local, GPG-encrypted secret store. Data lives under `GRIM_HOME` (default `~/.grimoire`). Many subcommands mirror 1Password CLI (`op`) for scripts and agents.

## Agent rules

- **Never** print, log, quote, or summarize secret values in chat unless the user explicitly asked to reveal one.
- Prefer **`--format json`** for list/get discovery; concealed fields stay concealed without `--reveal`.
- Pass **`op://`** or **`grim://`** references between commands instead of copying plaintext.
- Use **`grim run`** or **`grim inject`** to give secrets to child processes; treat those processes as trusted.
- **`OP_CONNECT_*` is unsupported** — grim refuses Connect.
- Destructive commands (`vault delete`, `secret delete`) prompt on a TTY; use **`--force`** only in non-interactive automation when appropriate.

## Build and path

```bash
nim c --path:src -o:grim src/grim.nim
```

Set `GRIM_BIN` or put `grim` on `PATH`. Integration tests use the repo’s `./grim` binary.

## Auth

| Mode | How |
|------|-----|
| Owner (desktop) | Default; uses your GPG keyring to decrypt vaults |
| Service account | `export OP_SERVICE_ACCOUNT_TOKEN=ops_...` from `grim service-account create` |

```bash
grim account list --format json
export OP_SERVICE_ACCOUNT_TOKEN="$(grim service-account create Bot --vault MyVault:read_items --raw)"
grim vault list --format json
```

Grants look like `VaultId:read_items` or `VaultId:read_items,write_items`. Creating tokens requires desktop auth (no `OP_SERVICE_ACCOUNT_TOKEN` set).

## Vaults

**op-style (JSON, automation):**

```bash
grim vault create Automation --format json --gpg-recipient YOUR_KEY_ID
grim vault list --format json
```

**grim-style (human + explicit GPG):**

```bash
grim vault create myvault --gpg-recipient YOUR_KEY_ID --description "Personal"
grim vault use myvault          # default vault for secret/* without --vault
grim vault get myvault
grim vault edit myvault --description "Updated"
```

## Items (op-compatible)

Item commands require **`--format json`**. Create/edit read JSON from **stdin** (`-` as placeholder arg).

```bash
grim item list --format json --vault Automation
grim item get ITEM_ID --vault Automation --format json
grim item get ITEM_ID --vault Automation --format json --reveal   # includes field values
echo '{"title":"API","category":"API_CREDENTIAL","fields":[{"id":"credential","type":"CONCEALED","value":"..."}]}' \
  | grim item create - --vault Automation --format json
```

Batch get: pipe a JSON array (or JSONL) of list entries to `grim item get - --format json --vault Automation`.

List/get output includes per-field **`reference`** (`op://vault/title/field`) for use with `read`, `run`, and `inject`.

## Secrets (grim-native)

Simple titled secrets in the default or named vault:

```bash
grim secret list --vault myvault
grim secret create api-key --vault myvault --value '...'    # confirms on TTY
echo 'secret' | grim secret create api-key --stdin --vault myvault
grim secret get api-key --vault myvault --reveal
grim secret edit api-key --vault myvault --stdin
grim secret delete api-key --vault myvault --force
```

## References and injection

| Scheme | Example |
|--------|---------|
| grim | `grim://vault/secret` or `grim://vault/secret/value` |
| op | `op://VaultName/Item Title/credential` |

```bash
grim read 'op://Automation/My API/credential'
grim read --no-newline 'grim://myvault/api-key'
echo 'KEY={{op://Automation/My API/credential}}' | grim inject
grim inject -i template.env -o .env.local
```

`grim run` substitutes `op://` and `grim://` in **environment variable values** (and in `--env-file` lines), then execs the command:

```bash
grim run --env-file .env.tpl -- ./app
VAR='op://Automation/My API/credential' grim run -- printenv VAR
```

## When to use grim-agent instead

The **grimoire-agent** companion repo adds `find`, verified creates, env helpers, and macOS keychain service accounts. Use **`grim-agent`** for fuzzy credential lookup and safer high-level flows; use **`grim`** when you need exact `op` CLI compatibility or low-level vault/secret control.

## More detail

Command flags and edge cases: [reference.md](reference.md)
