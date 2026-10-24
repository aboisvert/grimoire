## Local account and service-account token grants.

import std/[json, os, strutils, times, parseutils, random, tables]
import checksums/sha1
import grimoire/[store, jsonfmt]

proc randomLowerAlnum(n: int): string =
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  result = newString(n)
  for i in 0 ..< n:
    result[i] = chars[rand(chars.high)]

type
  Grant* = object
    vaultId*: string
    readItems*: bool
    writeItems*: bool

  AuthContext* = object
    owner*: bool
    grants*: seq[Grant]

const ServiceAccountsDir* = "service-accounts"

proc serviceAccountsPath*(): string =
  grimHome() / ServiceAccountsDir

proc failAuth*(msg: string) {.noreturn.} =
  raise newException(GrimError, msg)

proc connectForbidden*() =
  if getEnv("OP_CONNECT_HOST").len > 0 or getEnv("OP_CONNECT_TOKEN").len > 0:
    failAuth("1Password Connect is not supported")

proc tokenHash*(token: string): string =
  $secureHash(token)

proc parseGrant*(grant: string): Grant =
  let parts = grant.split(':', 2)
  if parts.len != 2:
    failAuth("invalid grant: " & grant)
  result.vaultId = parts[0]
  validateId(result.vaultId)
  let caps = parts[1].split(',')
  for c in caps:
    case c.strip()
    of "read_items":
      result.readItems = true
    of "write_items":
      result.writeItems = true
    else:
      failAuth("unknown grant capability: " & c)

proc parseExpiresIn*(s: string): DateTime =
  if s.len == 0:
    failAuth("empty expires-in")
  let unit = s[^1]
  let numStr = s[0 ..< s.len - 1]
  var amount = 0
  let parsed = parseInt(numStr, amount)
  if parsed != numStr.len or amount <= 0:
    failAuth("invalid expires-in: " & s)
  let base = now().utc()
  case unit
  of 's': result = base + initDuration(seconds = amount)
  of 'm': result = base + initDuration(minutes = amount)
  of 'h': result = base + initDuration(hours = amount)
  of 'd': result = base + initDuration(days = amount)
  of 'w': result = base + initDuration(days = amount * 7)
  else:
    failAuth("invalid expires-in unit: " & $unit)

proc ensureLocalAccount*(): JsonNode =
  var cfg = readConfig()
  if not cfg.hasKey("account.id"):
    cfg["account.id"] = "grimoire-local"
  if not cfg.hasKey("account.name"):
    cfg["account.name"] = "grimoire"
  writeConfig(cfg)
  %*{
    "id": cfg["account.id"],
    "name": cfg["account.name"],
    "email": cfg.getOrDefault("account.email"),
  }

proc accountMatches*(accountHint: string): bool =
  if accountHint.len == 0:
    return true
  let acct = ensureLocalAccount()
  let hint = accountHint
  hint == acct["id"].getStr() or hint == acct["name"].getStr() or
    (acct.hasKey("email") and acct["email"].getStr() == hint)

proc loadServiceAccount*(token: string): JsonNode =
  let path = serviceAccountsPath() / tokenHash(token)
  if not fileExists(path):
    failAuth("invalid service account token")
  let doc = parseJson(readFile(path))
  if doc.hasKey("expires_at"):
    let exp = parse(doc["expires_at"].getStr(), "yyyy-MM-dd'T'HH:mm:ss'Z'")
    if now() > exp:
      failAuth("service account token expired")
  doc

proc saveServiceAccount*(
    token, name: string, grants: seq[Grant], expiresAt = "") =
  ensureDirMode(serviceAccountsPath(), {fpUserRead, fpUserWrite, fpUserExec})
  var doc = %*{"name": name, "grants": newJArray()}
  for g in grants:
    var caps = "read_items"
    if g.writeItems:
      caps = "read_items,write_items"
    doc["grants"].add %*{"vault": g.vaultId, "grant": g.vaultId & ":" & caps}
  if expiresAt.len > 0:
    doc["expires_at"] = %expiresAt
  let path = serviceAccountsPath() / tokenHash(token)
  writeFile(path, formatJson(doc))
  setFilePermissions(path, {fpUserRead, fpUserWrite})

proc generateServiceToken*(): string =
  "ops_" & randomLowerAlnum(32)

proc grantsFromDoc*(doc: JsonNode): seq[Grant] =
  if not doc.hasKey("grants"):
    return
  for entry in doc["grants"]:
    if entry.hasKey("grant"):
      result.add parseGrant(entry["grant"].getStr())
    elif entry.hasKey("vault"):
      let v = entry["vault"].getStr()
      result.add Grant(vaultId: v, readItems: true, writeItems: entry{"write"}.getBool(false))

proc resolveAuth*(accountFlag: string, requireAuth = true): AuthContext =
  connectForbidden()
  let token = getEnv("OP_SERVICE_ACCOUNT_TOKEN")
  let envAccount = getEnv("OP_ACCOUNT")
  let accountHint =
    if accountFlag.len > 0: accountFlag
    elif envAccount.len > 0: envAccount
    else: ""

  if token.len > 0:
    if envAccount.len > 0 and accountFlag.len == 0:
      failAuth("OP_ACCOUNT cannot be used with OP_SERVICE_ACCOUNT_TOKEN")
    if accountHint.len > 0 and not accountMatches(accountHint):
      failAuth("account not found: " & accountHint)
    let doc = loadServiceAccount(token)
    result.owner = false
    result.grants = grantsFromDoc(doc)
    return result

  if accountHint.len > 0 and not accountMatches(accountHint):
    failAuth("account not found: " & accountHint)
  if requireAuth:
    discard ensureLocalAccount()
  result.owner = true

proc vaultAllowed*(ctx: AuthContext, vaultId: string, needWrite: bool): bool =
  if ctx.owner:
    return vaultExists(vaultId)
  for g in ctx.grants:
    if g.vaultId != vaultId:
      continue
    if needWrite:
      return g.writeItems
    return g.readItems
  false

proc filterVaultIds*(ctx: AuthContext): seq[string] =
  if ctx.owner:
    return listVaultIds()
  var allowed: seq[string] = @[]
  for g in ctx.grants:
    if g.readItems and vaultExists(g.vaultId):
      allowed.add g.vaultId
  allowed

