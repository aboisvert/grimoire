# grim CLI usage

**grim** is the command-line interface for [grimoire](README.md): a local, GPG-backed secret store with a shape similar to the 1Password CLI (`op`). Vaults, items, and configuration live on disk under a *grim home* directory.

Build the binary:

```bash
nim c -o:grim src/grimoire.nim
```

Throughout this document, `grim` means your built binary (or an installed copy on `PATH`).

## Global options

| Command | Description |
|---------|-------------|
| `grim --help` / `grim -h` / `grim help` | Print a short command summary and exit successfully. |
| `grim --version` / `grim -v` / `grim version` | Print `grim` and the version string (currently `0.1.0`). |

If you run `grim` with no arguments, it prints the same summary as `--help` and exits with code **2** (usage error).

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Runtime error (missing vault, GPG failure, permission denied, and so on) |
| `2` | Usage error (unknown flag, missing required argument) |
| *other* | Exit code of the child process started by `grim run` |

Errors are printed on stderr as `grim: <message>`.

## Environment and data layout

### Environment variables

| Variable | Purpose |
|----------|---------|
| `GRIM_HOME` | Override the grim data directory. If unset, grim walks upward from the current working directory for `.grimoire`, otherwise uses `~/.grimoire`. |
| `GRIM_VAULT` | Default vault id for commands that accept `--vault` when the flag is omitted. |
| `GRIM_GPG_RECIPIENT` | Default GPG key hint for `grim vault create --format json` when `--gpg-recipient` is omitted. |
| `SECRETS_HOME` | Directory for external symmetric key files (`<id>.txt.gpg`). If unset, grim walks upward for `.secrets`, otherwise `~/.secrets`. |
| `OP_SERVICE_ACCOUNT_TOKEN` | Authenticate as a scoped service account (`ops_…` token from `grim service-account create`). |
| `OP_ACCOUNT` | Select account by id, name, or email when not using a service token. Cannot be combined with `OP_SERVICE_ACCOUNT_TOKEN`. |

**Not supported:** `OP_CONNECT_HOST` and `OP_CONNECT_TOKEN` (1Password Connect). If either is set, grim refuses to run commands that perform authentication.

### On-disk layout (under grim home)

- `config.properties` — default vault, account metadata, optional `gpg.recipient`
- `vaults/<vault-id>/` — vault metadata and `items/*.json`
- `service-accounts/` — hashed service-account token records

### Identifiers

- **Vault ids** and **secret ids** (grim `secret` commands): 1–128 characters, must start with a letter or digit, then only `a-z`, `A-Z`, `0-9`, `.`, `_`, `-`.
- **Item ids** (op-style items): exactly 26 lowercase alphanumeric characters; assigned automatically on create.

### Choosing a vault

Many commands take `--vault <id>`. If omitted, grim resolves the vault in order:

1. `GRIM_VAULT`
2. `default.vault` in `config.properties` (set with `grim vault use`)
3. The only vault, if exactly one exists

Otherwise grim errors and asks you to pass `--vault`, set `GRIM_VAULT`, or run `grim vault use`.

Vault references in `op://` URLs and some item commands can be a vault **id** or a unique vault **name**.

### Authentication

- **Local (default):** Full access to all vaults. No login step; grim ensures a local account record exists for `grim account list`.
- **Service account:** Set `OP_SERVICE_ACCOUNT_TOKEN` to a token created with `grim service-account create`. Access is limited to vaults and capabilities in the token’s grant. Use `--account` on supported commands to match the local account id/name/email when needed.

### Flag syntax

Flags may be written as `--name value`, `--name=value`, `-n value`, or `-n=value`.

---

## `grim vault`

Manage encrypted vaults (containers for items). Each vault has a GPG recipient fingerprint and optionally an external **symmetric** key id (`--secret`) used to encrypt concealed fields.

### `grim vault list`

List vaults visible to the current auth context.

```
grim vault list [--format human|json] [--account <account>]
```

| Option | Description |
|--------|-------------|
| `--format human` | Default. Prints a table: ID, NAME, DESCRIPTION, UPDATED. |
| `--format json` | JSON array of `{"id","name"}` objects. |
| `--account` | Account hint when using service tokens (id, name, or email). |

**Explanation:** Use this to discover vault ids for `--vault`, scripting, or after `grim vault create`. With a service token, only granted vaults appear.

### `grim vault get <id>`

Show metadata for one vault.

```
grim vault get <id> [--format human|json]
```

| Option | Description |
|--------|-------------|
| `--format human` | Default. Prints id, description, GPG recipient, optional secret id, created, updated. |
| `--format json` | Same fields as JSON; includes `secret` only when set. |

**Explanation:** Inspects encryption settings without listing items. Does not reveal secret values.

### `grim vault create`

Create a new vault. Behavior splits into **human** mode (explicit GPG recipient) and **op-compatible JSON** mode.

**Human mode** (no `--format json`):

```
grim vault create <id> --gpg-recipient <key-hint>
  [--secret <external-secret-id>]
  [--description <text>]
  [--default]
  [--account <account>]
```

| Argument / option | Description |
|-------------------|-------------|
| `<id>` | Vault id (also used as default name). |
| `--gpg-recipient` | **Required.** Email, key id, or fingerprint hint; resolved to a single public-key fingerprint via GPG. |
| `--secret` | Optional external symmetric key id. The file `SECRETS_HOME/<id>.txt.gpg` must already exist (pubkey-encrypted to the vault recipient). |
| `--description` | Free-text description stored in vault metadata. |
| `--default` | Set this vault as the default (`grim vault use` equivalent at create time). |
| `--account` | Account hint for service-token auth checks. |

**JSON / op-style mode** (`--format json` on the command line):

```
grim vault create <NAME> --format json
  [--gpg-recipient <key-hint>]
  [--secret <external-secret-id>]
  [--account <account>]
```

| Argument / option | Description |
|-------------------|-------------|
| `<NAME>` | Vault id and display name (validated as an id). |
| `--format json` | **Required** to select this code path. Prints `{"id","name"}` on success. |
| `--gpg-recipient` | Optional. If omitted, uses `GRIM_GPG_RECIPIENT`, `gpg.recipient` in config, or the first secret key in your GPG keyring. |
| `--secret` | Same as human mode. |

**Explanation:** A vault defines how item fields are encrypted: either directly to the GPG recipient, or with a symmetric passphrase loaded from `SECRETS_HOME`. Create the external `.txt.gpg` file separately (or use `grim vault rotate-secret` to generate one).

### `grim vault edit <id>`

Update vault metadata and optionally re-wrap encryption.

```
grim vault edit <id>
  [--gpg-recipient <key-hint>]
  [--secret <id>|--secret ""]
  [--description <text>]
```

| Option | Description |
|--------|-------------|
| `--gpg-recipient` | New recipient fingerprint. Re-encrypts the external secret file or all pubkey-encrypted item fields. |
| `--secret` | Set, change, or clear the external symmetric key id. Clearing or changing is **blocked** if the vault already has items (re-encrypt items first). |
| `--description` | Replace description text. |

**Explanation:** Use when rotating GPG keys or attaching/detaching an external symmetric key. Recipient changes are destructive to old ciphertext in the sense that fields are re-encrypted to the new key material.

### `grim vault delete <id>`

Delete a vault and all its items.

```
grim vault delete <id> [--force]
```

| Option | Description |
|--------|-------------|
| `--force` | Skip confirmation. **Required** when stdin is not a TTY (e.g. in CI). |

Without `--force` on a TTY, grim prompts: `Delete vault <id>? [y/N]`.

**Explanation:** Removes the vault directory under `vaults/`. Clears `default.vault` in config if it pointed at this id.

### `grim vault use <id>`

```
grim vault use <id>
```

**Explanation:** Sets `default.vault` in `config.properties` so later commands can omit `--vault` when you have multiple vaults.

### `grim vault rotate-secret <newSecretId>`

Generate or supply a new external symmetric key and re-encrypt all concealed item fields.

```
grim vault rotate-secret <newSecretId>
  [--vault <id>]
  [--value <plaintext>|--stdin]
```

| Argument / option | Description |
|-------------------|-------------|
| `<newSecretId>` | Id for the new `SECRETS_HOME/<newSecretId>.txt.gpg` file. Must not already exist. |
| `--vault` | Vault to update; default resolution applies if omitted. |
| `--value` / `--stdin` | Provide the symmetric passphrase explicitly. Mutually exclusive with each other. |
| *(none)* | If stdin is a TTY and empty, grim generates a random passphrase (SHA-256 of 1024 bytes from `/dev/random`, hex-encoded). If stdin is piped and non-empty, uses piped data as the passphrase. |

**Explanation:** Writes a new pubkey-encrypted secret file, re-encrypts every concealed field in the vault to the new symmetric key, updates vault metadata `secret`, and clears the in-memory passphrase cache. Old secret files are left on disk. Vaults that used only GPG per-field encryption migrate to symmetric encryption.

---

## `grim item`

Op-compatible item CRUD. **All item subcommands require `--format json`** (human format is not supported here). Output is always JSON.

Items are stored as JSON documents under `vaults/<vault>/items/<id>.json`. Concealed fields (`type: CONCEALED` or `purpose: PASSWORD`) are encrypted at rest.

### `grim item list`

```
grim item list --format json [--vault <ref>] [--account <account>]
```

| Option | Description |
|--------|-------------|
| `--format json` | Required. |
| `--vault` | Limit to one vault (id or unique name). If omitted, lists items in all vaults allowed by the auth context. |
| `--account` | Account hint for service tokens. |

**Explanation:** Returns a JSON array of summaries (`id`, `title`, `category`, `vault`, timestamps). Use for discovery before `item get` or building `op://` references.

### `grim item get`

```
grim item get <id> --vault <ref> --format json [--reveal] [--account <account>]
grim item get - --vault <ref> --format json [--account <account>]   # batch
```

| Option | Description |
|--------|-------------|
| `<id>` | Item id (26 chars) or unique item title in the vault. |
| `--vault` | **Required** for single-item get. |
| `--reveal` | Decrypt concealed field values in the output. Without it, concealed values are omitted and `reference` fields contain `op://` URLs. |
| `-` | Read batch requests from stdin instead of a single id (see below). |

**Batch mode:** Pass `-` as the item argument and send JSON on stdin: either a JSON array of objects or newline-separated JSON documents. Each object should include `"id"` and a `"vault"` object with `"id"` or `"name"` (or rely on `--vault` for all entries). Batch get does not pass `--reveal`; output is always non-revealing.

**Explanation:** Primary way to read structured secrets (logins, API keys in fields) in automation. Match 1Password CLI patterns for scripts.

### `grim item create`

```
grim item create - --format json [--vault <ref>] [--account <account>]
```

JSON item template on **stdin** (the lone `-` argument is required). `--vault` is optional; default vault resolution applies.

**Explanation:** Creates a new item with a generated id, encrypts concealed fields, and prints the created item JSON (without revealed values). Template fields match op item shape (`title`, `category`, `fields`, etc.).

### `grim item edit <id>`

```
grim item edit <id> --vault <ref> --format json [--account <account>]
```

JSON item template on **stdin**. Replaces/updates the item; version is incremented.

**Explanation:** Same as create but preserves `created_at` and bumps `version`. Requires write access when using a service token.

---

## `grim secret`

A simpler, human-oriented interface for **password-category** items: one concealed field `value`, with the secret **id** equal to the item **title**. These appear in `grim item list` as category `PASSWORD` but are easiest to manage here.

### `grim secret list`

```
grim secret list [--vault <id>] [--format human|json]
```

| Option | Description |
|--------|-------------|
| `--format human` | Default. Table of ID (title) and UPDATED. |
| `--format json` | Array of `{"id","description","updated"}` (`description` is currently always empty). |

**Explanation:** Lists only `PASSWORD` category items in the vault.

### `grim secret get <id>`

```
grim secret get <id> [--vault <id>] [--reveal] [--format human|json]
```

| Option | Description |
|--------|-------------|
| `--reveal` | Show the secret value. Without it, value is `<concealed>` or JSON `"concealed": true`. |
| `--format json` | With `--reveal`, includes `"value"`; otherwise `"concealed": true`. |

**Explanation:** Reads the single `value` field. `<id>` is the secret title.

### `grim secret create <id>`

```
grim secret create <id> [--vault <id>] [--description <text>]
  [--value <text>|--stdin]
```

| Option | Description |
|--------|-------------|
| Value source | `--value`, `--stdin`, piped stdin (non-TTY), or interactive prompt with confirmation on a TTY. |
| `--description` | Accepted for CLI symmetry; secret items do not store a separate description today. |

**Explanation:** Fails if a secret with the same title already exists. Creates a one-field PASSWORD item.

### `grim secret edit <id>`

```
grim secret edit <id> [--vault <id>] [--value <text>|--stdin]
```

Same value input rules as create, but **no** confirmation prompt. Piped stdin (non-TTY) is treated as the new value when non-empty.

**Explanation:** Updates the concealed value in place (upsert by title).

### `grim secret delete <id>`

```
grim secret delete <id> [--vault <id>] [--force]
```

Same confirmation rules as `grim vault delete`.

**Explanation:** Deletes the backing item file for that secret title.

---

## `grim account`

### `grim account list`

```
grim account list --format json
```

Only `--format json` is allowed. Prints a JSON object with local account `id`, `name`, and `email` (if configured).

**Explanation:** Mimics `op account list` for scripts that verify which “account” grim represents. Ensures default account fields exist in config on first run.

---

## `grim service-account`

### `grim service-account create <name>`

Create a scoped API token for non-interactive access.

```
grim service-account create <name>
  --vault <vault-id>:<capabilities>
  --raw
  [--expires-in <duration>]
  [--account <account>]
```

| Option | Description |
|--------|-------------|
| `--vault` | Grant string: `VAULT_ID:cap1,cap2`. Capabilities: `read_items`, `write_items` (comma-separated). |
| `--raw` | **Required.** Prints the raw token once to stdout (prefix `ops_`). Store it securely; it cannot be retrieved again. |
| `--expires-in` | Optional expiry such as `90d`, `12h`, `30m`, `3600s`, `2w` (positive integer + unit `s|m|h|d|w`). |

Cannot be run while `OP_SERVICE_ACCOUNT_TOKEN` is set (desktop/local auth only).

**Explanation:** Tokens are stored hashed under `service-accounts/`. Use the token as `OP_SERVICE_ACCOUNT_TOKEN` to limit automation to specific vaults and read/write item permissions.

---

## `grim read`

Resolve a single reference and print the field value to stdout.

```
grim read [--no-newline] <reference>
```

| Option | Description |
|--------|-------------|
| `--no-newline` | Do not append a trailing newline after the value. |

**References:**

- `grim://<vault>/<secret>[/value]` — vault id or name, secret title (grim secret id). Optional `/value` suffix.
- `op://<vault>/<item>/<field>` — vault and item by id or title; field by id or label. URL-encoded parts are decoded.

**Explanation:** Shell-friendly secret lookup for scripts (`DB_URL=$(grim read 'op://Prod/db/password')`). Uses default vault only indirectly via vault name resolution in the URL.

---

## `grim inject`

Replace `{{...}}` templates in a file or stream.

```
grim inject [-i <file>] [-o <file>]
```

| Option | Description |
|--------|-------------|
| `-i` | Input file. Default: stdin. |
| `-o` | Output file. Default: stdout. |

Inside the text, `{{grim://...}}` and `{{op://...}}` are replaced with resolved plaintext. Non-URL inner content is left as-is (braces removed).

**Explanation:** Use for config templates, Kubernetes manifests, or docker-compose files before deployment. Does not modify the input file unless `-o` is set.

---

## `grim run`

Run a subprocess with environment variables resolved from grim references.

```
grim run [--env-file <path>] [--no-masking] -- <command> [args...]
```

| Option | Description |
|--------|-------------|
| `--env-file` | Load additional `KEY=VALUE` lines (and optional `export KEY=VALUE`). Values undergo reference substitution. When set, grim starts from the **current process environment** and appends variables from the file (later entries override). |
| `--no-masking` | Accepted for compatibility with `op run`; grim does not implement output masking. |
| `--` | **Required** separator before the command to run. |

**Without `--env-file`:** grim copies the current environment and substitutes `grim://` and `op://` references **in each existing env var value** before exec.

**With `--env-file`:** grim does **not** substitute refs in inherited env vars; only values from the file are substituted (after merge).

**Explanation:** Run apps locally or in CI with secrets injected from grim without exporting them in your shell profile. Exit code is the child’s exit code. Performs auth checks and rejects Connect env vars.

**Example:**

```bash
export API_KEY='op://Automation/my-token/credential'
grim run --env-file ./app.env -- ./server
```

---

## Reference substitution summary

| Mechanism | Where it applies |
|-----------|----------------|
| `grim read <ref>` | Single reference → stdout |
| `grim inject` | `{{grim://...}}` / `{{op://...}}` in file or stdin |
| `grim run` | `op://` / `grim://` substrings in env values (see rules above) |
| `substituteRefs` | Used by `grim run` for env var values |

Concealed item fields are encrypted per vault (GPG recipient or external symmetric key). Service accounts enforce vault and read/write grants on item commands.

---

## Quick examples

```bash
# Vault lifecycle
grim vault create prod --gpg-recipient you@example.com --default
grim vault list --format json

# Simple secret
grim secret create db-password --vault prod --stdin   # type password, Ctrl-D
grim read 'grim://prod/db-password'

# Op-style item (automation)
echo '{"title":"API","category":"API_CREDENTIAL","fields":[{"id":"credential","type":"CONCEALED","value":"sekrit"}]}' \
  | grim item create - --format json --vault prod

# Service account for CI
grim service-account create ci-bot --vault prod:read_items --raw --expires-in 90d

# Run with secrets
grim run -- printenv API_KEY   # if API_KEY in env contains op://...
```

For agent-oriented patterns (JSON discovery, safety rules), see `skills/grim-cli/SKILL.md`.
