# grimoire

*Grimoire* (pronounced *grim-wahr*) means “book of secrets” in French.   Here we use 'grim' for short.

**grim** is a local, GPG-backed password manager with a CLI shaped like 1Password (`op`) for scripts and automation. Vaults, items, and secrets live (encrypted) on disk under `GRIM_HOME` (default `~/.grimoire`).

### How vaults are encrypted

Each vault is always bound to a **GPG recipient**—a public/private key pair (yours or a group's). That key is what ultimately controls who can open the vault.

You can encrypt item data in either of two ways:

1. **Directly to the GPG key** — fields are encrypted so only the holder of the matching private key can decrypt them.

2. **With a shared secret** — a symmetric passphrase encrypts the fields instead. The passphrase is **not** stored in plain text in the vault; it lives under `SECRETS_HOME` in a file that is encrypted to the **same** GPG recipient. You still need the matching GPG private key to decrypt that file and use the vault.

See [USAGE.md](USAGE.md) for `grim vault create`, `--gpg-recipient`, and `--secret`.

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
