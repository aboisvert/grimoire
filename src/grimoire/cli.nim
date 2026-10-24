## Shared CLI helpers and usage errors.

import std/[strutils, terminal, osproc, os] # osproc: stty for hidden prompts

type
  UsageError* = object of CatchableError
  OutputFormat* = enum
    ofHuman, ofJson

const
  Version* = "0.1.0"

  TopUsage* = """
Usage:
  grim vault list|get|create|edit|delete|use ...
  grim item list|get|create|edit ...
  grim account list ...
  grim service-account create ...
  grim secret list|get|create|edit|delete ...
  grim read [--no-newline] <grim://|op://>reference
  grim inject [-i file] [-o file]
  grim run [--env-file file] [--no-masking] -- <command> [args...]

  grim --help
  grim --version
"""

proc failUsage*(msg: string) {.noreturn.} =
  raise newException(UsageError, msg)

proc parseFormat*(s: string): OutputFormat =
  case s.toLowerAscii
  of "human": ofHuman
  of "json": ofJson
  else: failUsage("unknown --format: " & s)

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
