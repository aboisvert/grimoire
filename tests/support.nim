import std/[os, osproc, strutils, streams]

var tempDirSeq = 0

proc makeTempDir(prefix: string): string =
  # Unique across tests in one process without a wall-clock timestamp.
  # The name stays short so GNUPGHOME + "/S.gpg-agent.browser" fits in
  # macOS's 103-byte Unix socket path limit. A fractional timestamp plus
  # a large random suffix made that socket path too long and gpg-agent
  # failed to start.
  for _ in 0 .. 100:
    inc tempDirSeq
    let base = getTempDir() / (prefix & "-" & $getCurrentProcessId() & "-" & $tempDirSeq)
    if not dirExists(base):
      createDir(base)
      return base
  raise newException(ValueError, "could not create temp dir for " & prefix)

proc gpgPath(): string =
  let exe = findExe("gpg")
  if exe.len == 0:
    raise newException(ValueError, "gpg not found in PATH")
  exe

proc runGpg*(args: openArray[string]): string =
  execProcess(
    gpgPath(),
    args = @args,
    options = {poUsePath, poStdErrToStdOut})

proc fingerprintForEmail(email: string): string =
  let list = runGpg(@["--batch", "--with-colons", "--list-keys", email])
  for line in list.splitLines():
    if line.startsWith("fpr:"):
      let parts = line.split(':')
      if parts.len >= 10:
        return parts[9]
  raise newException(ValueError, "no fingerprint for " & email)

proc generateTestKey(home, email: string) =
  let batch = home / ("batch-" & email.replace('@', '_') & ".gen")
  writeFile(batch, """
Key-Type: RSA
Key-Length: 2048
Name-Real: Grim Test
Name-Email: """ & email & """
Expire-Date: 0
%no-protection
%commit
""")
  let p = startProcess(
    gpgPath(),
    args = @["--batch", "--generate-key", batch],
    options = {poUsePath, poStdErrToStdOut})
  let output = p.outputStream.readAll()
  let code = p.waitForExit()
  if code != 0:
    raise newException(ValueError,
      "failed to generate test GPG key for " & email & ":\n" & output)

proc setupGpgHome*(): (string, string) =
  ## Returns (gpgHome, recipientFingerprint).
  let home = makeTempDir("grim-gnupg")
  setFilePermissions(home, {fpUserRead, fpUserWrite, fpUserExec})
  putEnv("GNUPGHOME", home)
  generateTestKey(home, "grim@test.local")
  (home, fingerprintForEmail("grim@test.local"))

proc addTestKey*(home, email: string): string =
  putEnv("GNUPGHOME", home)
  generateTestKey(home, email)
  fingerprintForEmail(email)

proc setupGrimHome*(): string =
  let home = makeTempDir("grim-home")
  putEnv("GRIM_HOME", home)
  home

proc setupSecretsHome*(): string =
  let home = makeTempDir("grim-secrets")
  putEnv("SECRETS_HOME", home)
  home

proc writeTestExternalSecret*(
    secretsHome, secretId, recipient, plaintext: string) =
  createDir(secretsHome)
  let path = secretsHome / (secretId & ".txt.gpg")
  let plainPath = secretsHome / (secretId & ".txt.plain")
  let tmp = path & ".tmp"
  writeFile(plainPath, plaintext)
  defer: removeFile(plainPath)
  discard runGpg(@[
    "--batch", "--yes", "--trust-model", "always",
    "--cipher-algo", "AES256",
    "--encrypt", "--recipient", recipient, "-o", tmp, plainPath])
  moveFile(tmp, path)

proc grimBin*(): string =
  let root = currentSourcePath().parentDir().parentDir()
  root / "grim"
