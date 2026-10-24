## Shared CLI helpers and usage errors.

import std/[strutils, terminal, os, json]
import grimoire/jsonfmt
export jsonfmt.formatJson

type
  UsageError* = object of CatchableError
  OutputFormat* = enum
    ofHuman, ofJson

const
  Version* = "0.1.0"

  HelpBody* = """Local, GPG-backed secrets manager with a 1Password CLI (op) compatible surface.

Usage:
  grim <command> [options] [arguments]

Global options:
  -h, --help       Show this help
  -v, --version    Print version

Commands:
  vault             Manage vaults and GPG recipients
  item              Manage vault items (JSON API)
  account           Local account metadata
  service-account   Scoped tokens for automation
  secret            Single-field secrets (human-oriented)
  read              Print a secret reference to stdout
  inject            Substitute grim:// and op:// references in text
  run               Run a command with resolved secret references

Environment:
  GRIM_HOME                    Data directory (default ~/.grimoire)
  SECRETS_HOME                 External symmetric key files (*.txt.gpg)
  OP_SERVICE_ACCOUNT_TOKEN     Authenticate with a service account token

Vault:
  grim vault list [--format human|json] [--account <name>]
  grim vault get <id> [--format human|json]
  grim vault create <id> --gpg-recipient <key> [--secret <id>]
        [--description <text>] [--default] [--account <name>]
  grim vault create <name> --format json [--gpg-recipient <key>] [--account <name>]
  grim vault edit <id> [--gpg-recipient <key>] [--secret <id>] [--description <text>]
  grim vault delete <id> [--force]
  grim vault use <id>
  grim vault rotate-secret <newSecretId> [--vault <id>] [--value <text>|--stdin]

Item (--format json required):
  grim item list [--vault <ref>] [--account <name>]
  grim item get <id> | -  --vault <ref> [--reveal] [--account <name>]
  grim item create - [--vault <ref>] [--account <name>]   (JSON on stdin)
  grim item edit <id> --vault <ref> [--account <name>]    (JSON on stdin)

Account:
  grim account list --format json

Service account:
  grim service-account create <name> --vault <vault:caps> --raw [--expires-in <dur>]
        Caps: read_items, write_items (comma-separated)

Secret:
  grim secret list [--vault <id>] [--format human|json]
  grim secret get <id> [--vault <id>] [--reveal] [--format human|json]
  grim secret create <id> [--vault <id>] [--description <text>]
        [--value <text>|--stdin]
  grim secret edit <id> [--vault <id>] [--description <text>] [--value <text>|--stdin]
  grim secret delete <id> [--vault <id>] [--force]

Scripting:
  grim read [--no-newline] <grim://|op:// reference>
  grim inject [-i <file>] [-o <file>]
  grim run [--env-file <file>] [--no-masking] -- <command> [args...]

References:
  grim://<vault>/<secret>          Secret by title in a vault
  op://<vault>/<item>/<field>     Item field (op-compatible)

Exit codes: 0 success, 1 error, 2 usage; grim run returns the child exit code."""

  ## Shown on usage errors and when argv is empty.
  TopUsage* = HelpBody

proc printHelp*() =
  stdout.writeLine("grim " & Version & "\n\n" & HelpBody)

proc failUsage*(msg: string) {.noreturn.} =
  raise newException(UsageError, msg)

proc parseFormat*(s: string): OutputFormat =
  case s.toLowerAscii
  of "human": ofHuman
  of "json": ofJson
  else: failUsage("unknown --format: " & s)

proc echoJson*(node: JsonNode) =
  stdout.writeLine formatJson(node)

proc readFlagValue*(
    args: seq[string], i: var int, dashed: string): string =
  if i + 1 >= args.len or args[i + 1].startsWith("-"):
    failUsage(dashed & " expects a value")
  inc i
  args[i]

proc splitFlag*(arg: string): (string, string, bool) =
  ## name, inline value, hasInline
  var name = ""
  var inline = ""
  var hasInline = false
  if arg.startsWith("--") and arg.len > 2:
    let body = arg[2 ..^ 1]
    let eq = body.find('=')
    if eq >= 0:
      name = body[0 ..< eq]
      inline = body[eq + 1 ..^ 1]
      hasInline = true
    else:
      name = body
  elif arg.startsWith('-') and arg.len > 1:
    let body = arg[1 ..^ 1]
    let eq = body.find('=')
    if eq >= 0:
      name = body[0 ..< eq]
      inline = body[eq + 1 ..^ 1]
      hasInline = true
    else:
      name = body
  else:
    failUsage("expected flag, got: " & arg)
  if name.len == 0:
    failUsage("invalid option: " & arg)
  (name, inline, hasInline)

proc readSecretPrompt*(prompt: string, confirm = false): string =
  stderr.write prompt
  when defined(posix):
    discard execShellCmd("stty -echo 2>/dev/null")
    try:
      result = stdin.readLine()
    finally:
      discard execShellCmd("stty echo 2>/dev/null")
  else:
    result = stdin.readLine()
  stderr.writeLine ""
  if confirm:
    stderr.write "Confirm value: "
    when defined(posix):
      discard execShellCmd("stty -echo 2>/dev/null")
      try:
        let again = stdin.readLine()
        if again != result:
          failUsage("values do not match")
      finally:
        discard execShellCmd("stty echo 2>/dev/null")
    else:
      let again = stdin.readLine()
      if again != result:
        failUsage("values do not match")
    stderr.writeLine ""

proc readValueInput*(
    valueFlag, stdinFlag: bool, valueArg: string, confirm: bool): string =
  if valueFlag and stdinFlag:
    failUsage("use only one of --value or --stdin")
  if valueFlag:
    result = valueArg
  elif stdinFlag:
    result = readAll(stdin).strip(leading = false)
  elif not stdin.isatty:
    result = readAll(stdin).strip(leading = false)
  else:
    result = readSecretPrompt("Value: ", confirm)
  if result.len == 0:
    failUsage("secret value must not be empty")
