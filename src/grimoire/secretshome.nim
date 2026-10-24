## External symmetric keys under SECRETS_HOME / discovered `.secrets`.

import std/[os, tables]
import grimoire/[store, gpg]

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
