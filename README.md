# grimoire

**grim** is a local, GPG-backed password manager with a CLI shaped like 1Password (`op`) for scripts and automation. Vaults, items, and secrets live on disk under `GRIM_HOME` (default `~/.grimoire`).

## Build

```bash
nimble build
```

Requires Nim ≥ 2.2.12.

## Test

```bash
nimble test
```

Or manually:

```bash
nimble build
nim c -r --hints:off --path:src tests/tproperties.nim
nim c -r --hints:off --path:src tests/tstore.nim
nim c -r --hints:off --path:src tests/treference.nim
nim c -r --hints:off --path:src tests/tintegration.nim
nim c -r --hints:off --path:src tests/topcompat.nim
```

## Quick start

```bash
./grim vault create Automation --format json --gpg-recipient YOUR_KEY_ID
./grim vault list --format json
./grim account list --format json
```

Human-oriented vault and secret commands, plus `read`, `inject`, and `run` for `grim://` and `op://` references. See `grim --help` or `skills/grim-cli/SKILL.md`.

## Cursor agent skill

Agents can load **`grim-cli`** so they know how to call `grim` safely (JSON discovery, references, service accounts, no secret leakage).

Source: `skills/grim-cli/`

Install into Cursor (symlink by default):

```bash
chmod +x scripts/install-skill.sh
./scripts/install-skill.sh user      # ~/.cursor/skills/grim-cli
./scripts/install-skill.sh project   # .cursor/skills/grim-cli in this repo
./scripts/install-skill.sh user --copy # copy instead of symlink
./scripts/install-skill.sh user --force  # replace existing install
```

For higher-level agent workflows (find, env helpers, verified creates), see the separate **grimoire-agent** project and its `grim-agent` skill.

## Configuration

| Variable | Purpose |
|----------|---------|
| `GRIM_HOME` | Override data directory |
| `OP_SERVICE_ACCOUNT_TOKEN` | Use a `grim service-account create` token |

1Password Connect (`OP_CONNECT_*`) is intentionally unsupported.
