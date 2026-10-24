## Invoke the system gpg binary for encrypt/decrypt and key lookup.

import std/[os, strutils, osproc, streams, times, tables]
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

proc runGpgPassphrase*(passphrase: string, args: openArray[string]): string =
  let gpg = gpgBin()
  let p = startProcess(
    command = gpg,
    args = @args,
    options = {poUsePath, poStdErrToStdOut})
  p.inputStream.write(passphrase)
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

proc encryptToRecipientFile*(
    recipient, plaintext, outPath: string) =
  let tmp = outPath & ".tmp." & $getTime().toUnix()
  defer:
    if fileExists(tmp):
      removeFile(tmp)
  discard runGpg(@[
    "--batch", "--yes", "--trust-model", "always",
    "--cipher-algo", "AES256",
    "--encrypt", "--recipient", recipient, "-o", tmp], plaintext)
  moveFile(tmp, outPath)

proc decryptArmor*(armor: string): string =
  runGpg(@["--batch", "--quiet", "--decrypt"], armor).strip()

proc decryptGpgFile*(path: string): string =
  let data = readFile(path)
  runGpg(@["--batch", "--quiet", "--decrypt"], data).strip()

proc encryptSymmetric*(passphrase, plaintext: string): string =
  let base = getTempDir() / ("grim-sym-" & $getTime().toUnix())
  let inPath = base & ".in"
  let outPath = base & ".asc"
  defer:
    if fileExists(inPath):
      removeFile(inPath)
    if fileExists(outPath):
      removeFile(outPath)
  writeFile(inPath, plaintext)
  discard runGpgPassphrase(passphrase, @[
    "--batch", "--yes", "--pinentry-mode", "loopback", "--passphrase-fd", "0",
    "--symmetric", "--cipher-algo", "AES256", "--armor", "-o", outPath, inPath])
  readFile(outPath).strip()

proc decryptSymmetric*(passphrase, armor: string): string =
  let inPath = getTempDir() / ("grim-sym-in-" & $getTime().toUnix() & ".asc")
  defer:
    if fileExists(inPath):
      removeFile(inPath)
  writeFile(inPath, armor)
  runGpgPassphrase(passphrase, @[
    "--batch", "--quiet", "--pinentry-mode", "loopback", "--passphrase-fd", "0",
    "--decrypt", inPath]).strip()

proc defaultRecipientHint*(): string =
  let fromEnv = getEnv("GRIM_GPG_RECIPIENT")
  if fromEnv.len > 0:
    return fromEnv
  let cfg = readConfig()
  if cfg.hasKey("gpg.recipient"):
    return cfg["gpg.recipient"]
  ""

proc resolveDefaultRecipient*(): string =
  let hint = defaultRecipientHint()
  if hint.len > 0:
    return resolveRecipient(hint)
  let colonList = runGpg(@["--batch", "--with-colons", "--list-secret-keys"])
  var pubCount = 0
  var firstFpr = ""
  for line in colonList.splitLines():
    if line.startsWith("sec:"):
      inc pubCount
    elif line.startsWith("fpr:") and firstFpr.len == 0:
      let parts = line.split(':')
      if parts.len >= 10 and parts[9].len > 0:
        firstFpr = parts[9]
  if pubCount == 1 and firstFpr.len > 0:
    return firstFpr
  raise newException(
    GpgError,
    "no GPG recipient; set --gpg-recipient, GRIM_GPG_RECIPIENT, or gpg.recipient in config")

