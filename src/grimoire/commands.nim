## grim subcommand implementations.

import std/[os, strutils, json, sequtils, terminal, osproc, envvars, strtabs]
import grimoire/[cli, store, gpg, reference]

proc die(msg: string) {.noreturn.} =
  stderr.writeLine "grim: " & msg
  quit(1)

proc echoJson(node: JsonNode) =
  stdout.writeLine $node

proc padRight(s: string, width: int): string =
  if s.len >= width:
    s
  else:
    s & " ".repeat(width - s.len)

proc runVaultList(args: seq[string]) =
  var fmt = ofHuman
  var i = 0
  while i < args.len:
    let (name, inline, hasInline) = splitFlag(args[i])
    if name == "format":
      var v = inline
      if not hasInline:
        v = readFlagValue(args, i, "--format")
      fmt = parseFormat(v)
    else:
      failUsage("unknown option: " & args[i])
    inc i
  let ids = listVaultIds()
  if fmt == ofJson:
    var arr = newJArray()
    for id in ids:
      let m = readVaultMeta(id)
      arr.add(%*{
        "id": m.id,
        "description": m.description,
        "gpg_recipient": m.gpgRecipient,
        "created": m.created,
        "updated": m.updated,
      })
    echoJson(arr)
  else:
    if ids.len == 0:
      return
    var rows: seq[(string, string, string)] = @[]
    for id in ids:
      let m = readVaultMeta(id)
      rows.add (m.id, m.description, m.updated)
    let w0 = max(2, rows.mapIt(it[0].len).max())
    let w1 = max(11, rows.mapIt(it[1].len).max())
    stdout.writeLine padRight("ID", w0) & "  " &
      padRight("DESCRIPTION", w1) & "  UPDATED"
    for row in rows:
      stdout.writeLine padRight(row[0], w0) & "  " &
        padRight(row[1], w1) & "  " & row[2]

proc runVaultGet(args: seq[string]) =
  var fmt = ofHuman
  var id = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      if name == "format":
        var v = inline
        if not hasInline:
          v = readFlagValue(args, i, "--format")
        fmt = parseFormat(v)
      else:
        failUsage("unknown option: " & arg)
    elif id.len == 0:
      id = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if id.len == 0:
    failUsage("usage: grim vault get <id> [--format human|json]")
  let m = readVaultMeta(id)
  if fmt == ofJson:
    echoJson(%*{
      "id": m.id,
      "description": m.description,
      "gpg_recipient": m.gpgRecipient,
      "created": m.created,
      "updated": m.updated,
    })
  else:
    stdout.writeLine "ID:            " & m.id
    stdout.writeLine "Description:   " & m.description
    stdout.writeLine "GPG recipient: " & m.gpgRecipient
    stdout.writeLine "Created:       " & m.created
    stdout.writeLine "Updated:       " & m.updated

proc runVaultCreate(args: seq[string]) =
  var id = ""
  var recipientHint = ""
  var description = ""
  var makeDefault = false
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "gpg-recipient", "gpg_recipient":
        if hasInline:
          recipientHint = inline
        else:
          recipientHint = readFlagValue(args, i, "--gpg-recipient")
      of "description":
        if hasInline:
          description = inline
        else:
          description = readFlagValue(args, i, "--description")
      of "default":
        makeDefault = true
      else:
        failUsage("unknown option: " & arg)
    elif id.len == 0:
      id = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if id.len == 0 or recipientHint.len == 0:
    failUsage(
      "usage: grim vault create <id> --gpg-recipient <key> " &
      "[--description <text>] [--default]")
  let fp = resolveRecipient(recipientHint)
  let now = utcNow()
  createVault(VaultMeta(
    id: id,
    description: description,
    gpgRecipient: fp,
    created: now,
    updated: now,
  ))
  if makeDefault:
    setDefaultVault(id)

proc runVaultEdit(args: seq[string]) =
  var id = ""
  var recipientHint = ""
  var descriptionSet = false
  var description = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "gpg-recipient", "gpg_recipient":
        if hasInline:
          recipientHint = inline
        else:
          recipientHint = readFlagValue(args, i, "--gpg-recipient")
      of "description":
        descriptionSet = true
        if hasInline:
          description = inline
        else:
          description = readFlagValue(args, i, "--description")
      else:
        failUsage("unknown option: " & arg)
    elif id.len == 0:
      id = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if id.len == 0:
    failUsage(
      "usage: grim vault edit <id> [--gpg-recipient <key>] [--description <text>]")
  var meta = readVaultMeta(id)
  if descriptionSet:
    meta.description = description
  if recipientHint.len > 0:
    let newFp = resolveRecipient(recipientHint)
    if newFp != meta.gpgRecipient:
      reencryptVaultSecrets(id, meta.gpgRecipient, newFp)
      meta.gpgRecipient = newFp
  meta.updated = utcNow()
  writeVaultMeta(meta)

proc runVaultDelete(args: seq[string]) =
  var id = ""
  var force = false
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      if name == "force":
        force = true
      else:
        failUsage("unknown option: " & arg)
    elif id.len == 0:
      id = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if id.len == 0:
    failUsage("usage: grim vault delete <id> [--force]")
  if not force:
    if not stdin.isatty:
      failUsage("refusing to delete vault on non-tty stdin without --force")
    stderr.write "Delete vault " & id & "? [y/N] "
    let ans = stdin.readLine().strip().toLowerAscii()
    if ans != "y" and ans != "yes":
      return
  deleteVault(id)

proc runVaultUse(args: seq[string]) =
  if args.len != 1 or args[0].startsWith("-"):
    failUsage("usage: grim vault use <id>")
  setDefaultVault(args[0])

proc runSecretList(args: seq[string]) =
  var fmt = ofHuman
  var vaultFlag = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "format":
        var v = inline
        if not hasInline:
          v = readFlagValue(args, i, "--format")
        fmt = parseFormat(v)
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      else:
        failUsage("unknown option: " & arg)
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  let vault = resolveVault(vaultFlag)
  let ids = listSecretIds(vault)
  if fmt == ofJson:
    var arr = newJArray()
    for sid in ids:
      let m = readSecretMeta(vault, sid)
      arr.add(%*{
        "id": m.id,
        "description": m.description,
        "created": m.created,
        "updated": m.updated,
      })
    echoJson(arr)
  else:
    if ids.len == 0:
      return
    var rows: seq[(string, string, string)] = @[]
    for sid in ids:
      let m = readSecretMeta(vault, sid)
      rows.add (m.id, m.description, m.updated)
    let w0 = max(2, rows.mapIt(it[0].len).max())
    let w1 = max(11, rows.mapIt(it[1].len).max())
    stdout.writeLine padRight("ID", w0) & "  " &
      padRight("DESCRIPTION", w1) & "  UPDATED"
    for row in rows:
      stdout.writeLine padRight(row[0], w0) & "  " &
        padRight(row[1], w1) & "  " & row[2]

proc runSecretGet(args: seq[string]) =
  var fmt = ofHuman
  var vaultFlag = ""
  var reveal = false
  var id = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "format":
        var v = inline
        if not hasInline:
          v = readFlagValue(args, i, "--format")
        fmt = parseFormat(v)
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      of "reveal":
        reveal = true
      else:
        failUsage("unknown option: " & arg)
    elif id.len == 0:
      id = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if id.len == 0:
    failUsage(
      "usage: grim secret get <id> [--vault <id>] [--reveal] [--format human|json]")
  let vault = resolveVault(vaultFlag)
  let m = readSecretMeta(vault, id)
  if fmt == ofJson:
    var node = %*{
      "id": m.id,
      "description": m.description,
      "created": m.created,
      "updated": m.updated,
    }
    if reveal:
      node["value"] = %decryptArmor(m.valueEnc)
    else:
      node["concealed"] = %true
    echoJson(node)
  else:
    stdout.writeLine "ID:          " & m.id
    stdout.writeLine "Description: " & m.description
    stdout.writeLine "Created:     " & m.created
    stdout.writeLine "Updated:     " & m.updated
    if reveal:
      stdout.writeLine "Value:       " & decryptArmor(m.valueEnc)
    else:
      stdout.writeLine "Value:       <concealed>"

proc runSecretCreate(args: seq[string]) =
  var vaultFlag = ""
  var description = ""
  var valueFlag = false
  var stdinFlag = false
  var valueArg = ""
  var id = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      of "description":
        if hasInline:
          description = inline
        else:
          description = readFlagValue(args, i, "--description")
      of "value":
        valueFlag = true
        if hasInline:
          valueArg = inline
        else:
          valueArg = readFlagValue(args, i, "--value")
      of "stdin":
        stdinFlag = true
      else:
        failUsage("unknown option: " & arg)
    elif id.len == 0:
      id = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if id.len == 0:
    failUsage(
      "usage: grim secret create <id> [--vault <id>] [--description <text>] " &
      "[--value <text>|--stdin]")
  let vault = resolveVault(vaultFlag)
  let plain = readValueInput(valueFlag, stdinFlag, valueArg, confirm = true)
  let vmeta = readVaultMeta(vault)
  let enc = encryptToRecipient(vmeta.gpgRecipient, plain)
  let now = utcNow()
  createSecret(vault, SecretMeta(
    id: id,
    description: description,
    valueEnc: enc,
    created: now,
    updated: now,
  ))

proc runSecretEdit(args: seq[string]) =
  var vaultFlag = ""
  var descriptionSet = false
  var description = ""
  var valueFlag = false
  var stdinFlag = false
  var valueArg = ""
  var id = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      of "description":
        descriptionSet = true
        if hasInline:
          description = inline
        else:
          description = readFlagValue(args, i, "--description")
      of "value":
        valueFlag = true
        if hasInline:
          valueArg = inline
        else:
          valueArg = readFlagValue(args, i, "--value")
      of "stdin":
        stdinFlag = true
      else:
        failUsage("unknown option: " & arg)
    elif id.len == 0:
      id = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if id.len == 0:
    failUsage(
      "usage: grim secret edit <id> [--vault <id>] [--description <text>] " &
      "[--value <text>|--stdin]")
  let vault = resolveVault(vaultFlag)
  var meta = readSecretMeta(vault, id)
  if descriptionSet:
    meta.description = description
  var changeValue = valueFlag or stdinFlag
  if not changeValue and not stdin.isatty:
    let piped = readAll(stdin).strip(leading = false)
    if piped.len > 0:
      valueArg = piped
      valueFlag = true
      changeValue = true
  if changeValue:
    let plain = readValueInput(valueFlag, stdinFlag, valueArg, confirm = false)
    let vmeta = readVaultMeta(vault)
    meta.valueEnc = encryptToRecipient(vmeta.gpgRecipient, plain)
  meta.updated = utcNow()
  writeSecretMeta(vault, meta)

proc runSecretDelete(args: seq[string]) =
  var vaultFlag = ""
  var force = false
  var id = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      of "force":
        force = true
      else:
        failUsage("unknown option: " & arg)
    elif id.len == 0:
      id = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if id.len == 0:
    failUsage("usage: grim secret delete <id> [--vault <id>] [--force]")
  let vault = resolveVault(vaultFlag)
  if not force:
    if not stdin.isatty:
      failUsage("refusing to delete secret on non-tty stdin without --force")
    stderr.write "Delete secret " & id & "? [y/N] "
    let ans = stdin.readLine().strip().toLowerAscii()
    if ans != "y" and ans != "yes":
      return
  deleteSecret(vault, id)

proc runRead(args: seq[string]) =
  var noNewline = false
  var refStr = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      if name == "no-newline":
        noNewline = true
      else:
        failUsage("unknown option: " & arg)
    elif refStr.len == 0:
      refStr = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if refStr.len == 0:
    failUsage("usage: grim read [--no-newline] grim://<vault>/<secret>[/value]")
  let plain = refPlaintext(refStr)
  stdout.write plain
  if not noNewline:
    stdout.writeLine ""

proc runInject(args: seq[string]) =
  var inPath = ""
  var outPath = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "i":
        if hasInline:
          inPath = inline
        else:
          inPath = readFlagValue(args, i, "-i")
      of "o":
        if hasInline:
          outPath = inline
        else:
          outPath = readFlagValue(args, i, "-o")
      else:
        failUsage("unknown option: " & arg)
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  let input = if inPath.len > 0: readFile(inPath) else: readAll(stdin)
  let output = substituteInjectTemplates(input)
  if outPath.len > 0:
    writeFile(outPath, output)
  else:
    stdout.write output

proc parseEnvFile(text: string): seq[(string, string)] =
  for rawLine in text.splitLines():
    var line = rawLine.strip()
    if line.len == 0 or line[0] == '#':
      continue
    if line.startsWith("export "):
      line = line[7 ..^ 1].strip()
    let eq = line.find('=')
    if eq < 0:
      continue
    var key = line[0 ..< eq].strip()
    var value = line[eq + 1 ..^ 1].strip()
    if value.len >= 2:
      if (value[0] == '"' and value[^1] == '"') or
          (value[0] == '\'' and value[^1] == '\''):
        value = value[1 ..^ 2]
    result.add (key, value)

proc runRun(args: seq[string]) =
  var envFile = ""
  var i = 0
  while i < args.len:
    if args[i] == "--":
      inc i
      break
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      if name == "env-file":
        if hasInline:
          envFile = inline
        else:
          envFile = readFlagValue(args, i, "--env-file")
      else:
        failUsage("unknown option: " & arg)
    else:
      failUsage("unexpected argument before --: " & arg)
    inc i
  if i >= args.len:
    failUsage("usage: grim run [--env-file file] -- <command> [args...]")
  let cmd = args[i]
  let cmdArgs = if i + 1 < args.len: args[i + 1 ..^ 1] else: @[]
  var env: seq[(string, string)] = @[]
  for key, value in envPairs():
    if envFile.len > 0:
      env.add (key, value)
    else:
      env.add (key, substituteGrimRefs(value))
  if envFile.len > 0:
    for pair in parseEnvFile(readFile(envFile)):
      env.add (pair[0], substituteGrimRefs(pair[1]))
  let envTable = newStringTable(mode = modeCaseInsensitive)
  for pair in env:
    envTable[pair[0]] = pair[1]
  let code = startProcess(
    command = cmd,
    args = cmdArgs,
    env = envTable,
    options = {poUsePath, poParentStreams}).waitForExit()
  quit(code)

proc dispatchVault*(sub: string, args: seq[string]) =
  case sub
  of "list": runVaultList(args)
  of "get": runVaultGet(args)
  of "create": runVaultCreate(args)
  of "edit": runVaultEdit(args)
  of "delete": runVaultDelete(args)
  of "use": runVaultUse(args)
  else: failUsage("unknown vault subcommand: " & sub)

proc dispatchSecret*(sub: string, args: seq[string]) =
  case sub
  of "list": runSecretList(args)
  of "get": runSecretGet(args)
  of "create": runSecretCreate(args)
  of "edit": runSecretEdit(args)
  of "delete": runSecretDelete(args)
  else: failUsage("unknown secret subcommand: " & sub)

proc runGrim*(args: seq[string]) =
  if args.len == 0:
    failUsage(TopUsage)
  if args[0] in ["-h", "--help", "help"]:
    stdout.writeLine TopUsage
    return
  if args[0] in ["-v", "--version", "version"]:
    stdout.writeLine "grim " & Version
    return
  case args[0]
  of "vault":
    if args.len < 2:
      failUsage("usage: grim vault <list|get|create|edit|delete|use> ...")
    dispatchVault(args[1], args[2 ..^ 1])
  of "secret":
    if args.len < 2:
      failUsage("usage: grim secret <list|get|create|edit|delete> ...")
    dispatchSecret(args[1], args[2 ..^ 1])
  of "read":
    runRead(args[1 ..^ 1])
  of "inject":
    runInject(args[1 ..^ 1])
  of "run":
    runRun(args[1 ..^ 1])
  else:
    failUsage("unknown command: " & args[0] & "\n" & TopUsage)
