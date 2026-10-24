## Invoke the system gpg binary for encrypt/decrypt and key lookup.

import std/[os, strutils, osproc, streams]
import grimoire/store

type
  GpgError* = object of CatchableError

proc gpgBin*(): string =
  let exe = findExe("gpg")
  if exe.len == 0:
    raise newException(GpgError, "gpg not found in PATH")
  exe

proc runGpg*(args: openArray[string], stdinData = ""): string =
  let gpg = gpgBin()
  var cmd = @[gpg]
  for a in args:
    cmd.add a
  let p = startProcess(
    command = gpg,
    args = cmd[1 ..^ 1],
    options = {poUsePath, poStdErrToStdOut})
  if stdinData.len > 0:
    p.inputStream.write(stdinData)
    p.inputStream.flush()
  p.inputStream.close()
  let output = p.outputStream.readAll()
  let code = p.waitForExit()
  if code != 0:
    raise newException(GpgError, output.strip())
  output

proc resolveRecipient*(hint: string): string =
  let colonList = runGpg(@[
    "--batch", "--with-colons", "--list-keys", hint])
  var pubCount = 0
  var firstFpr = ""
  for line in colonList.splitLines():
    if line.startsWith("pub:"):
      inc pubCount
    elif line.startsWith("fpr:") and firstFpr.len == 0:
      let parts = line.split(':')
      if parts.len >= 10 and parts[9].len > 0:
        firstFpr = parts[9]
  if pubCount == 0 or firstFpr.len == 0:
    raise newException(GpgError, "no GPG key matched: " & hint)
  if pubCount > 1:
    raise newException(
      GpgError,
      "multiple GPG keys matched; use a full fingerprint: " & hint)
  firstFpr

proc encryptToRecipient*(recipient, plaintext: string): string =
  runGpg(@[
    "--batch", "--yes", "--trust-model", "always",
    "--encrypt", "--recipient", recipient, "--armor"], plaintext).strip()

proc decryptArmor*(armor: string): string =
  runGpg(@["--batch", "--quiet", "--decrypt"], armor).strip()

proc reencryptVaultSecrets*(
    vaultId, oldRecipient, newRecipient: string) =
  let secretIds = listSecretIds(vaultId)
  var updated: seq[(string, string)] = @[]
  for sid in secretIds:
    let meta = readSecretMeta(vaultId, sid)
    try:
      let plain = decryptArmor(meta.valueEnc)
      let enc = encryptToRecipient(newRecipient, plain)
      updated.add (sid, enc)
    except CatchableError as e:
      raise newException(
        GpgError,
        "re-encrypt failed for secret " & sid & ": " & e.msg)
  for pair in updated:
    var meta = readSecretMeta(vaultId, pair[0])
    meta.valueEnc = pair[1]
    meta.updated = utcNow()
    writeSecretMeta(vaultId, meta)
