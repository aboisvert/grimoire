## On-disk layout: GRIM_HOME override, nearest ancestor `.grimoire`, or ~/.grimoire.

import std/[os, strutils, times, tables]
import grimoire/properties

type
  GrimError* = object of CatchableError

  VaultMeta* = object
    id*: string
    name*: string
    description*: string
    gpgRecipient*: string
    secretId*: string
    created*: string
    updated*: string

proc isIdChar(c: char): bool =
  c.isAlphaNumeric or c in {'.', '_', '-'}

proc utcNow*(): string =
  format(now().utc(), "yyyy-MM-dd'T'HH:mm:ss'Z'")

proc discoverGrimHome*(startDir: string): string =
  var dir = absolutePath(startDir)
  while dir.len > 0:
    let (_, tail) = splitPath(dir)
    if tail == ".grimoire" and dirExists(dir):
      return dir
    let nested = dir / ".grimoire"
    if dirExists(nested):
      return nested
    let parent = dir.parentDir()
    if parent == dir or parent.len == 0:
      break
    dir = parent
  getHomeDir() / ".grimoire"

proc grimHome*(): string =
  let fromEnv = getEnv("GRIM_HOME")
  if fromEnv.len > 0:
    result = fromEnv
  else:
    result = discoverGrimHome(getCurrentDir())

proc validateId*(id: string) =
  if id.len == 0 or id.len > 128 or id == ".." or
      id.find('/') >= 0 or id.find('\\') >= 0:
    raise newException(GrimError, "invalid id: " & id)
  if not id[0].isAlphaNumeric:
    raise newException(GrimError, "invalid id: " & id)
  for c in id:
    if not isIdChar(c):
      raise newException(GrimError, "invalid id: " & id)

proc ensureDirMode*(path: string, perms: set[FilePermission]) =
  createDir(path)
  setFilePermissions(path, perms)

proc ensureGrimHome*() =
  ensureDirMode(grimHome(), {fpUserRead, fpUserWrite, fpUserExec})

proc configPath*(): string =
  grimHome() / "config.properties"

proc readConfig*(): Properties =
  let path = configPath()
  if fileExists(path):
    readPropertiesFile(path)
  else:
    initOrderedTable[string, string]()

proc writeConfig*(props: Properties) =
  ensureGrimHome()
  writePropertiesFileAtomic(configPath(), props)

proc setDefaultVault*(vaultId: string) =
  validateId(vaultId)
  var cfg = readConfig()
  cfg["default.vault"] = vaultId
  writeConfig(cfg)

proc defaultVaultFromConfig*(): string =
  let cfg = readConfig()
  if cfg.hasKey("default.vault"):
    cfg["default.vault"]
  else:
    ""

proc vaultDir*(vaultId: string): string =
  validateId(vaultId)
  grimHome() / vaultId

proc vaultPropertiesPath*(vaultId: string): string =
  vaultDir(vaultId) / "vault.properties"

proc listVaultIds*(): seq[string] =
  ensureGrimHome()
  for kind, path in walkDir(grimHome()):
    if kind == pcDir:
      let name = path.splitPath().tail
      if name in ["secrets", "service-accounts"] or name.startsWith("."):
        continue
      try:
        validateId(name)
        if fileExists(vaultPropertiesPath(name)):
          result.add name
      except GrimError:
        discard

proc vaultExists*(vaultId: string): bool =
  fileExists(vaultPropertiesPath(vaultId))

proc readVaultMeta*(vaultId: string): VaultMeta =
  validateId(vaultId)
  let path = vaultPropertiesPath(vaultId)
  if not fileExists(path):
    raise newException(GrimError, "vault not found: " & vaultId)
  let props = readPropertiesFile(path)
  if not props.hasKey("id"):
    raise newException(GrimError, "vault missing id: " & vaultId)
  if props["id"] != vaultId:
    raise newException(
      GrimError,
      "vault id mismatch: file " & props["id"] & " vs " & vaultId)
  if not props.hasKey("gpg.recipient"):
    raise newException(GrimError, "vault missing gpg.recipient: " & vaultId)
  result.id = vaultId
  result.name =
    if props.hasKey("name"): props["name"] else: vaultId
  result.description = props.getOrDefault("description")
  result.gpgRecipient = props["gpg.recipient"]
  if props.hasKey("secret"):
    result.secretId = props["secret"]
    validateId(result.secretId)
  result.created = props.getOrDefault("created")
  result.updated = props.getOrDefault("updated")

proc writeVaultMeta*(meta: VaultMeta) =
  validateId(meta.id)
  ensureDirMode(vaultDir(meta.id), {fpUserRead, fpUserWrite, fpUserExec})
  ensureDirMode(vaultDir(meta.id) / "items", {fpUserRead, fpUserWrite, fpUserExec})
  var props = initOrderedTable[string, string]()
  props["id"] = meta.id
  props["name"] =
    if meta.name.len > 0: meta.name else: meta.id
  if meta.description.len > 0:
    props["description"] = meta.description
  props["gpg.recipient"] = meta.gpgRecipient
  if meta.secretId.len > 0:
    props["secret"] = meta.secretId
  props["created"] = meta.created
  props["updated"] = meta.updated
  writePropertiesFileAtomic(vaultPropertiesPath(meta.id), props)

proc createVault*(meta: VaultMeta) =
  if vaultExists(meta.id):
    raise newException(GrimError, "vault already exists: " & meta.id)
  if meta.name.len == 0:
    var m = meta
    m.name = meta.id
    writeVaultMeta(m)
  else:
    writeVaultMeta(meta)

proc resolveVaultByRef*(vaultRef: string): string =
  if vaultRef.len == 0:
    raise newException(GrimError, "empty vault reference")
  try:
    validateId(vaultRef)
    if vaultExists(vaultRef):
      return vaultRef
  except GrimError:
    discard
  var matches: seq[string] = @[]
  for vid in listVaultIds():
    let meta = readVaultMeta(vid)
    if meta.name == vaultRef:
      matches.add vid
  if matches.len == 1:
    return matches[0]
  if matches.len > 1:
    raise newException(GrimError, "ambiguous vault: " & vaultRef)
  raise newException(GrimError, "vault not found: " & vaultRef)

proc deleteVault*(vaultId: string) =
  let dir = vaultDir(vaultId)
  if not dirExists(dir):
    raise newException(GrimError, "vault not found: " & vaultId)
  removeDir(dir)
  var cfg = readConfig()
  if cfg.getOrDefault("default.vault") == vaultId:
    cfg.del("default.vault")
    writeConfig(cfg)

proc resolveVault*(explicit: string): string =
  if explicit.len > 0:
    validateId(explicit)
    if not vaultExists(explicit):
      raise newException(GrimError, "vault not found: " & explicit)
    return explicit
  let fromEnv = getEnv("GRIM_VAULT")
  if fromEnv.len > 0:
    validateId(fromEnv)
    if not vaultExists(fromEnv):
      raise newException(GrimError, "vault not found: " & fromEnv)
    return fromEnv
  let fromCfg = defaultVaultFromConfig()
  if fromCfg.len > 0:
    if not vaultExists(fromCfg):
      raise newException(GrimError, "vault not found: " & fromCfg)
    return fromCfg
  let vaults = listVaultIds()
  if vaults.len == 1:
    return vaults[0]
  raise newException(
    GrimError,
    "no vault selected; use --vault, GRIM_VAULT, grim vault use, or create a vault")
