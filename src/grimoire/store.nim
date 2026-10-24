## On-disk layout under GRIM_HOME / ~/.grimoire.

import std/[os, strutils, times, tables]
import grimoire/properties

type
  GrimError* = object of CatchableError

  VaultMeta* = object
    id*: string
    description*: string
    gpgRecipient*: string
    created*: string
    updated*: string

  SecretMeta* = object
    id*: string
    description*: string
    valueEnc*: string
    created*: string
    updated*: string

proc isIdChar(c: char): bool =
  c.isAlphaNumeric or c in {'.', '_', '-'}

proc utcNow*(): string =
  format(now().utc(), "yyyy-MM-dd'T'HH:mm:ss'Z'")

proc grimHome*(): string =
  let fromEnv = getEnv("GRIM_HOME")
  if fromEnv.len > 0:
    result = fromEnv
  else:
    result = getHomeDir() / ".grimoire"

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

proc secretsDir*(vaultId: string): string =
  vaultDir(vaultId) / "secrets"

proc secretPropertiesPath*(vaultId, secretId: string): string =
  validateId(secretId)
  secretsDir(vaultId) / (secretId & ".properties")

proc listVaultIds*(): seq[string] =
  ensureGrimHome()
  for kind, path in walkDir(grimHome()):
    if kind == pcDir:
      let name = path.splitPath().tail
      if name == "secrets" or name.startsWith("."):
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
  result.description = props.getOrDefault("description")
  result.gpgRecipient = props["gpg.recipient"]
  result.created = props.getOrDefault("created")
  result.updated = props.getOrDefault("updated")

proc writeVaultMeta*(meta: VaultMeta) =
  validateId(meta.id)
  ensureDirMode(vaultDir(meta.id), {fpUserRead, fpUserWrite, fpUserExec})
  ensureDirMode(secretsDir(meta.id), {fpUserRead, fpUserWrite, fpUserExec})
  var props = initOrderedTable[string, string]()
  props["id"] = meta.id
  if meta.description.len > 0:
    props["description"] = meta.description
  props["gpg.recipient"] = meta.gpgRecipient
  props["created"] = meta.created
  props["updated"] = meta.updated
  writePropertiesFileAtomic(vaultPropertiesPath(meta.id), props)

proc createVault*(meta: VaultMeta) =
  if vaultExists(meta.id):
    raise newException(GrimError, "vault already exists: " & meta.id)
  writeVaultMeta(meta)

proc deleteVault*(vaultId: string) =
  let dir = vaultDir(vaultId)
  if not dirExists(dir):
    raise newException(GrimError, "vault not found: " & vaultId)
  removeDir(dir)
  var cfg = readConfig()
  if cfg.getOrDefault("default.vault") == vaultId:
    cfg.del("default.vault")
    writeConfig(cfg)

proc listSecretIds*(vaultId: string): seq[string] =
  discard readVaultMeta(vaultId)
  let sdir = secretsDir(vaultId)
  if not dirExists(sdir):
    return
  for kind, path in walkDir(sdir):
    if kind == pcFile and path.endsWith(".properties"):
      let sid = splitFile(path).name
      result.add sid

proc readSecretMeta*(vaultId, secretId: string): SecretMeta =
  validateId(secretId)
  discard readVaultMeta(vaultId)
  let path = secretPropertiesPath(vaultId, secretId)
  if not fileExists(path):
    raise newException(GrimError, "secret not found: " & secretId)
  let props = readPropertiesFile(path)
  if props.getOrDefault("id") != secretId:
    raise newException(
      GrimError,
      "secret id mismatch: file " & props.getOrDefault("id") & " vs " & secretId)
  if not props.hasKey("value"):
    raise newException(GrimError, "secret missing value: " & secretId)
  result.id = secretId
  result.description = props.getOrDefault("description")
  result.valueEnc = props["value"]
  result.created = props.getOrDefault("created")
  result.updated = props.getOrDefault("updated")

proc writeSecretMeta*(vaultId: string, meta: SecretMeta) =
  validateId(meta.id)
  discard readVaultMeta(vaultId)
  var props = initOrderedTable[string, string]()
  props["id"] = meta.id
  if meta.description.len > 0:
    props["description"] = meta.description
  props["value"] = meta.valueEnc
  props["created"] = meta.created
  props["updated"] = meta.updated
  writePropertiesFileAtomic(secretPropertiesPath(vaultId, meta.id), props)
  var vault = readVaultMeta(vaultId)
  vault.updated = utcNow()
  writeVaultMeta(vault)

proc createSecret*(vaultId: string, meta: SecretMeta) =
  if fileExists(secretPropertiesPath(vaultId, meta.id)):
    raise newException(GrimError, "secret already exists: " & meta.id)
  writeSecretMeta(vaultId, meta)

proc deleteSecret*(vaultId, secretId: string) =
  let path = secretPropertiesPath(vaultId, secretId)
  if not fileExists(path):
    raise newException(GrimError, "secret not found: " & secretId)
  removeFile(path)

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
