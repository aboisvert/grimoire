## op-compatible command handlers (item, account, service-account, vault json).

import std/[os, strutils, json, times, re]
import grimoire/[cli, store, gpg, items, auth, secretshome]

proc echoJson(node: JsonNode) =
  stdout.writeLine $node

proc skipFormatFlag(args: seq[string], i: var int, inline: string, hasInline: bool) =
  if not hasInline:
    discard readFlagValue(args, i, "--format")
  elif inline.toLowerAscii != "json":
    failUsage("this command requires --format json")

proc popAccountFlag(args: var seq[string]): string =
  var i = 0
  while i < args.len:
    if args[i] == "--account" and i + 1 < args.len:
      result = args[i + 1]
      args.delete(i + 1)
      args.delete(i)
      return result
    if args[i].startsWith("--account="):
      result = args[i][10 ..^ 1]
      args.delete(i)
      return result
    inc i
  ""

proc requireFormatJson(args: seq[string]) =
  var fmt = ""
  for arg in args:
    if arg.startsWith("--format="):
      fmt = arg[9 ..^ 1]
    elif arg == "--format" and fmt.len == 0:
      discard
  for i, arg in args:
    if arg == "--format" and i + 1 < args.len:
      fmt = args[i + 1]
  if fmt.toLowerAscii != "json":
    failUsage("this command requires --format json")

proc runAccountList(args: seq[string]) =
  var fmt = "json"
  var i = 0
  while i < args.len:
    let (name, inline, hasInline) = splitFlag(args[i])
    if name == "format":
      if hasInline:
        fmt = inline
      else:
        fmt = readFlagValue(args, i, "--format")
    else:
      failUsage("unknown option: " & args[i])
    inc i
  if fmt.toLowerAscii != "json":
    failUsage("account list only supports --format json")
  connectForbidden()
  let acct = ensureLocalAccount()
  echoJson(%*[acct])

proc runVaultListOp(args: seq[string]) =
  var fmt = "json"
  var account = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (name, inline, hasInline) = splitFlag(arg)
      case name
      of "format":
        if hasInline:
          fmt = inline
        else:
          fmt = readFlagValue(args, i, "--format")
      of "account":
        if hasInline:
          account = inline
        else:
          account = readFlagValue(args, i, "--account")
      else:
        failUsage("unknown option: " & arg)
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  let ctx = resolveAuth(account)
  let ids = filterVaultIds(ctx)
  if fmt.toLowerAscii == "json":
    var arr = newJArray()
    for vid in ids:
      let m = readVaultMeta(vid)
      arr.add %*{"id": m.id, "name": m.name}
    echoJson(arr)
  else:
    failUsage("vault list for op compatibility requires --format json")

proc runVaultCreateOp*(args: seq[string]) =
  var name = ""
  var fmt = "json"
  var account = ""
  var recipientHint = ""
  var secretHint = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (n, inline, hasInline) = splitFlag(arg)
      case n
      of "format":
        if hasInline:
          fmt = inline
        else:
          fmt = readFlagValue(args, i, "--format")
      of "account":
        if hasInline:
          account = inline
        else:
          account = readFlagValue(args, i, "--account")
      of "gpg-recipient", "gpg_recipient":
        if hasInline:
          recipientHint = inline
        else:
          recipientHint = readFlagValue(args, i, "--gpg-recipient")
      of "secret":
        if hasInline:
          secretHint = inline
        else:
          secretHint = readFlagValue(args, i, "--secret")
      else:
        failUsage("unknown option: " & arg)
    elif name.len == 0:
      name = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  discard resolveAuth(account)
  if name.len == 0:
    failUsage("usage: grim vault create NAME --format json [--gpg-recipient key]")
  validateId(name)
  let fp =
    if recipientHint.len > 0:
      resolveRecipient(recipientHint)
    else:
      resolveDefaultRecipient()
  if secretHint.len > 0:
    validateId(secretHint)
    assertExternalSecretExists(secretHint)
  let now = utcNow()
  createVault(VaultMeta(
    id: name,
    name: name,
    gpgRecipient: fp,
    secretId: secretHint,
    created: now,
    updated: now,
  ))
  if fmt.toLowerAscii == "json":
    echoJson(%*{"id": name, "name": name})

proc runItemList(args: seq[string]) =
  var vaultFlag = ""
  var account = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (n, inline, hasInline) = splitFlag(arg)
      case n
      of "format":
        skipFormatFlag(args, i, inline, hasInline)
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      of "account":
        if hasInline:
          account = inline
        else:
          account = readFlagValue(args, i, "--account")
      else:
        failUsage("unknown option: " & arg)
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  let ctx = resolveAuth(account)
  var vaultIds: seq[string] =
    if vaultFlag.len > 0:
      @[resolveVaultByRef(vaultFlag)]
    else:
      filterVaultIds(ctx)
  var arr = newJArray()
  for vid in vaultIds:
    if not vaultAllowed(ctx, vid, needWrite = false):
      continue
    for iid in listItemIds(vid):
      let doc = readItemDoc(vid, iid)
      arr.add itemSummary(vid, doc)
  echoJson(arr)

proc runItemGet(args: seq[string]) =
  var itemId = ""
  var vaultFlag = ""
  var account = ""
  var reveal = false
  var batched = false
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg == "-":
      itemId = arg
      batched = true
    elif arg.startsWith("-"):
      let (n, inline, hasInline) = splitFlag(arg)
      case n
      of "format":
        skipFormatFlag(args, i, inline, hasInline)
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      of "account":
        if hasInline:
          account = inline
        else:
          account = readFlagValue(args, i, "--account")
      of "reveal":
        reveal = true
      else:
        failUsage("unknown option: " & arg)
    elif itemId.len == 0:
      itemId = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  let ctx = resolveAuth(account)
  if batched:
    let input = readAll(stdin).strip()
    var entries: seq[JsonNode] = @[]
    if input.len > 0:
      if input[0] == '[':
        let parsed = parseJson(input)
        if parsed.kind == JArray:
          for el in parsed:
            entries.add el
      else:
        entries = parseJsonDocuments(input)
    for entry in entries:
      var vid = ""
      if entry.hasKey("vault") and entry["vault"].hasKey("id"):
        vid = resolveVaultByRef(entry["vault"]["id"].getStr())
      elif entry.hasKey("vault") and entry["vault"].hasKey("name"):
        vid = resolveVaultByRef(entry["vault"]["name"].getStr())
      elif vaultFlag.len > 0:
        vid = resolveVaultByRef(vaultFlag)
      else:
        failUsage("batch item get requires vault on each entry")
      let iid = entry["id"].getStr()
      if not vaultAllowed(ctx, vid, false):
        raise newException(GrimError, "access denied for vault: " & vid)
      let doc = readItemDoc(vid, iid)
      stdout.write $itemForOutput(vid, doc, reveal = false)
    return
  if vaultFlag.len == 0:
    failUsage("item get requires --vault")
  let vid = resolveVaultByRef(vaultFlag)
  if not vaultAllowed(ctx, vid, false):
    raise newException(GrimError, "access denied for vault: " & vid)
  let iid = resolveItemInVault(vid, itemId)
  let doc = readItemDoc(vid, iid)
  echoJson itemForOutput(vid, doc, reveal)

proc runItemCreate(args: seq[string]) =
  var vaultFlag = ""
  var account = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg == "-":
      discard
    elif arg.startsWith("-"):
      let (n, inline, hasInline) = splitFlag(arg)
      case n
      of "format":
        skipFormatFlag(args, i, inline, hasInline)
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      of "account":
        if hasInline:
          account = inline
        else:
          account = readFlagValue(args, i, "--account")
      else:
        failUsage("unknown option: " & arg)
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  let ctx = resolveAuth(account)
  let vid =
    if vaultFlag.len > 0:
      resolveVaultByRef(vaultFlag)
    else:
      resolveVault("")
  if not vaultAllowed(ctx, vid, needWrite = true):
    raise newException(GrimError, "write access denied for vault: " & vid)
  let itemTpl = parseJson(readAll(stdin))
  let stored = persistItemFromTemplate(vid, itemTpl)
  echoJson itemForOutput(vid, readItemDoc(vid, stored["id"].getStr()), reveal = false)

proc runItemEdit(args: seq[string]) =
  var itemId = ""
  var vaultFlag = ""
  var account = ""
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (n, inline, hasInline) = splitFlag(arg)
      case n
      of "format":
        skipFormatFlag(args, i, inline, hasInline)
      of "vault":
        if hasInline:
          vaultFlag = inline
        else:
          vaultFlag = readFlagValue(args, i, "--vault")
      of "account":
        if hasInline:
          account = inline
        else:
          account = readFlagValue(args, i, "--account")
      else:
        failUsage("unknown option: " & arg)
    elif itemId.len == 0:
      itemId = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if vaultFlag.len == 0 or itemId.len == 0:
    failUsage("usage: grim item edit ID --vault V --format json")
  let ctx = resolveAuth(account)
  let vid = resolveVaultByRef(vaultFlag)
  if not vaultAllowed(ctx, vid, needWrite = true):
    raise newException(GrimError, "write access denied for vault: " & vid)
  let iid = resolveItemInVault(vid, itemId)
  let itemTpl = parseJson(readAll(stdin))
  let stored = persistItemFromTemplate(vid, itemTpl, existingId = iid)
  echoJson itemForOutput(vid, readItemDoc(vid, iid), reveal = false)

proc runServiceAccountCreate(args: seq[string]) =
  var name = ""
  var grantStr = ""
  var account = ""
  var expiresIn = ""
  var raw = false
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("-"):
      let (n, inline, hasInline) = splitFlag(arg)
      case n
      of "vault":
        if hasInline:
          grantStr = inline
        else:
          grantStr = readFlagValue(args, i, "--vault")
      of "account":
        if hasInline:
          account = inline
        else:
          account = readFlagValue(args, i, "--account")
      of "expires-in", "expires_in":
        if hasInline:
          expiresIn = inline
        else:
          expiresIn = readFlagValue(args, i, "--expires-in")
      of "raw":
        raw = true
      else:
        failUsage("unknown option: " & arg)
    elif name.len == 0:
      name = arg
    else:
      failUsage("unexpected argument: " & arg)
    inc i
  if not raw or name.len == 0 or grantStr.len == 0:
    failUsage(
      "usage: grim service-account create NAME --vault GRANT --raw [--expires-in 90d]")
  if expiresIn.len > 0 and not expiresIn.match(re"^[1-9]\d*[smhdw]$"):
    failUsage("invalid --expires-in")
  discard resolveAuth(account)
  if getEnv("OP_SERVICE_ACCOUNT_TOKEN").len > 0:
    failAuth("service-account create requires desktop auth")
  let grant = parseGrant(grantStr)
  let token = generateServiceToken()
  var expStr = ""
  if expiresIn.len > 0:
    expStr = format(parseExpiresIn(expiresIn), "yyyy-MM-dd'T'HH:mm:ss'Z'")
  saveServiceAccount(token, name, @[grant], expStr)
  stdout.writeLine token

proc dispatchItem*(sub: string, args: seq[string]) =
  case sub
  of "list": runItemList(args)
  of "get": runItemGet(args)
  of "create": runItemCreate(args)
  of "edit": runItemEdit(args)
  else: failUsage("unknown item subcommand: " & sub)

proc dispatchAccount*(sub: string, args: seq[string]) =
  case sub
  of "list": runAccountList(args)
  else: failUsage("unknown account subcommand: " & sub)

proc dispatchServiceAccount*(sub: string, args: seq[string]) =
  case sub
  of "create": runServiceAccountCreate(args)
  else: failUsage("unknown service-account subcommand: " & sub)
