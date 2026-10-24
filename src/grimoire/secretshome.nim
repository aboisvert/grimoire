## External symmetric keys under SECRETS_HOME / discovered `.secrets`.

import std/[os, tables]
when not defined(posix):
  import std/sysrand
import checksums/sha2
import grimoire/[store, gpg]

const SymmetricSecretRandomBytes = 1024

var vaultPassphraseCache = initTable[string, string]()

proc discoverSecretsHome*(startDir: string): string =
  var dir = absolutePath(startDir)
  while dir.len > 0:
    let (_, tail) = splitPath(dir)
    if tail == ".secrets" and dirExists(dir):
      return dir
    let nested = dir / ".secrets"
    if dirExists(nested):
      return nested
    let parent = dir.parentDir()
    if parent == dir or parent.len == 0:
      break
    dir = parent
  getHomeDir() / ".secrets"

proc secretsHome*(): string =
  let fromEnv = getEnv("SECRETS_HOME")
  if fromEnv.len > 0:
    result = fromEnv
  else:
    result = discoverSecretsHome(getCurrentDir())

proc externalSecretGpgPath*(secretId: string): string =
  validateId(secretId)
  secretsHome() / (secretId & ".txt.gpg")

proc externalSecretExists*(secretId: string): bool =
  fileExists(externalSecretGpgPath(secretId))

proc readRandomBytes*(n: int): string =
  result = newString(n)
  when defined(posix):
    var f = open("/dev/random", fmRead)
    defer: f.close()
    let got = f.readBuffer(result[0].addr, n)
    if got != n:
      raise newException(GrimError, "could not read " & $n & " bytes from /dev/random")
  else:
    var buf = newSeq[byte](n)
    fillRandom(buf)
    copyMem(result[0].addr, buf[0].addr, n)

proc generateSymmetricSecretPlain*(): string =
  let raw = readRandomBytes(SymmetricSecretRandomBytes)
  var h = initSha_256()
  h.update(raw)
  $h.digest()

proc assertExternalSecretExists*(secretId: string) =
  let path = externalSecretGpgPath(secretId)
  if not fileExists(path):
    raise newException(
      GrimError, "external secret not found: " & path)

proc readExternalSecretPlain*(secretId: string): string =
  let path = externalSecretGpgPath(secretId)
  if not fileExists(path):
    raise newException(GrimError, "external secret not found: " & path)
  decryptGpgFile(path)

proc writeExternalSecretGpg*(
    secretId, recipient, plaintext: string) =
  validateId(secretId)
  let home = secretsHome()
  createDir(home)
  let path = home / (secretId & ".txt.gpg")
  encryptToRecipientFile(recipient, plaintext, path)

proc reencryptExternalSecret*(
    secretId, plaintext, newRecipient: string) =
  writeExternalSecretGpg(secretId, newRecipient, plaintext)

proc reencryptExternalSecretForVault*(vaultId, newRecipient: string) =
  let meta = readVaultMeta(vaultId)
  if meta.secretId.len == 0:
    return
  let plain = readExternalSecretPlain(meta.secretId)
  reencryptExternalSecret(meta.secretId, plain, newRecipient)
  vaultPassphraseCache.del(vaultId)

proc vaultSymmetricPassphrase*(vaultId: string): string =
  if vaultId in vaultPassphraseCache:
    return vaultPassphraseCache[vaultId]
  let meta = readVaultMeta(vaultId)
  if meta.secretId.len == 0:
    raise newException(GrimError, "vault is not symmetric: " & vaultId)
  let plain = readExternalSecretPlain(meta.secretId)
  vaultPassphraseCache[vaultId] = plain
  plain

proc clearVaultPassphraseCache*() =
  vaultPassphraseCache.clear()
