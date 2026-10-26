import std/[unittest, osproc, strutils, os, times, envvars, streams]
import support

proc startGrim(args: openArray[string]): Process =
  result = startProcess(
    grimBin(), args = @args, options = {poUsePath, poStdErrToStdOut})
  result.inputStream.close()

proc runGrim*(args: openArray[string]) =
  var p = startGrim(args)
  let code = p.waitForExit()
  if code != 0:
    raise newException(ValueError, "grim failed (" & $code & "): grim " & args.join(" "))

proc runGrimOut(args: openArray[string]): string =
  var p = startGrim(args)
  var outp = p.outputStream
  result = ""
  var line = newStringOfCap(120)
  while true:
    if outp.readLine(line):
      result.add(line)
      result.add("\n")
    elif not p.running:
      break
  p.close()
  result = result.strip()

suite "integration":
  var gpgHome = ""
  var fpr = ""
  setup:
    discard setupGrimHome()
    (gpgHome, fpr) = setupGpgHome()

  test "vault and secret lifecycle":
    runGrim(@[
      "vault", "create", "personal", "--gpg-recipient", fpr, "--default"])
    runGrim(@[
      "secret", "create", "db", "--vault", "personal",
      "--description", "database", "--value", "s3cret"])
    let concealed = runGrimOut(@[
      "secret", "get", "db", "--vault", "personal"])
    check "<concealed>" in concealed
    let revealed = runGrimOut(@[
      "secret", "get", "db", "--vault", "personal", "--reveal"])
    check "s3cret" in revealed
    check runGrimOut(@["read", "grim://personal/db"]) == "s3cret"

  test "multiple secrets in one vault get distinct item ids":
    runGrim(@[
      "vault", "create", "multi", "--gpg-recipient", fpr])
    runGrim(@[
      "secret", "create", "alpha", "--vault", "multi", "--value", "one"])
    runGrim(@[
      "secret", "create", "beta", "--vault", "multi", "--value", "two"])
    check "one" in runGrimOut(@[
      "secret", "get", "alpha", "--vault", "multi", "--reveal"])
    check "two" in runGrimOut(@[
      "secret", "get", "beta", "--vault", "multi", "--reveal"])
    let listed = runGrimOut(@["secret", "list", "--vault", "multi"])
    check "alpha" in listed
    check "beta" in listed

  test "inject template":
    runGrim(@[
      "vault", "create", "app", "--gpg-recipient", fpr])
    runGrim(@[
      "secret", "create", "token", "--vault", "app", "--value", "tok"])
    let tpl = "Bearer {{ grim://app/token }}"
    writeFile("inject-in.txt", tpl)
    runGrim(@["inject", "-i", "inject-in.txt", "-o", "inject-out.txt"])
    check readFile("inject-out.txt") == "Bearer tok"
    removeFile("inject-in.txt")
    removeFile("inject-out.txt")

  test "recipient rotation":
    runGrim(@[
      "vault", "create", "rot", "--gpg-recipient", fpr])
    runGrim(@[
      "secret", "create", "x", "--vault", "rot", "--value", "plain"])
    let fpr2 = addTestKey(gpgHome, "grim2@test.local")
    runGrim(@[
      "vault", "edit", "rot", "--gpg-recipient", fpr2])
    check runGrimOut(@[
      "read", "grim://rot/x"]) == "plain"

  test "local .grimoire discovered from cwd without GRIM_HOME":
    let savedCwd = getCurrentDir()
    defer: setCurrentDir(savedCwd)
    delEnv("GRIM_HOME")
    let project = getTempDir() / ("grim-proj-" & $getTime().toUnix())
    defer: removeDir(project)
    createDir(project / ".grimoire")
    createDir(project / "work")
    setCurrentDir(project / "work")
    runGrim(@["vault", "create", "localvault", "--gpg-recipient", fpr])
    check fileExists(project / ".grimoire" / "localvault" / "vault.properties")

  test "symmetric vault via external secret":
    let secrets = setupSecretsHome()
    const symKey = "symmetric-vault-key-material"
    writeTestExternalSecret(secrets, "vaultkey", fpr, symKey)
    runGrim(@[
      "vault", "create", "symvault", "--gpg-recipient", fpr, "--secret", "vaultkey"])
    runGrim(@[
      "secret", "create", "db", "--vault", "symvault", "--value", "s3cret"])
    check runGrimOut(@[
      "read", "grim://symvault/db"]) == "s3cret"

  test "symmetric vault recipient rotation re-wraps external secret":
    let secrets = setupSecretsHome()
    const symKey = "rotation-key-material"
    writeTestExternalSecret(secrets, "rotkey", fpr, symKey)
    runGrim(@[
      "vault", "create", "symrot", "--gpg-recipient", fpr, "--secret", "rotkey"])
    runGrim(@[
      "secret", "create", "x", "--vault", "symrot", "--value", "plain"])
    let fpr2 = addTestKey(gpgHome, "sym2@test.local")
    runGrim(@["vault", "edit", "symrot", "--gpg-recipient", fpr2])
    check runGrimOut(@["read", "grim://symrot/x"]) == "plain"
    putEnv("GNUPGHOME", gpgHome)
    check runGpg(@["--batch", "--quiet", "--decrypt",
      secrets / "rotkey.txt.gpg"]).strip() == symKey

  test "local .secrets discovered from cwd without SECRETS_HOME":
    let savedCwd = getCurrentDir()
    defer: setCurrentDir(savedCwd)
    delEnv("SECRETS_HOME")
    let project = getTempDir() / ("grim-secproj-" & $getTime().toUnix())
    defer: removeDir(project)
    createDir(project / ".secrets")
    createDir(project / "work")
    const symKey = "discovered-secret-key"
    writeTestExternalSecret(project / ".secrets", "disckey", fpr, symKey)
    discard setupGrimHome()
    setCurrentDir(project / "work")
    runGrim(@[
      "vault", "create", "discvault", "--gpg-recipient", fpr, "--secret", "disckey"])
    runGrim(@[
      "secret", "create", "t", "--vault", "discvault", "--value", "ok"])
    check runGrimOut(@["read", "grim://discvault/t"]) == "ok"

  test "symmetric vault secret rotation":
    let secrets = setupSecretsHome()
    const symKey = "rotation-key-material"
    writeTestExternalSecret(secrets, "rotkey", fpr, symKey)
    runGrim(@[
      "vault", "create", "symrot2", "--gpg-recipient", fpr, "--secret", "rotkey"])
    runGrim(@[
      "secret", "create", "x", "--vault", "symrot2", "--value", "plain"])
    runGrim(@[
      "vault", "rotate-secret", "newrotkey", "--vault", "symrot2"])
    check runGrimOut(@["read", "grim://symrot2/x"]) == "plain"
    putEnv("GNUPGHOME", gpgHome)
    check runGpg(@["--batch", "--quiet", "--decrypt",
      secrets / "rotkey.txt.gpg"]).strip() == symKey
    check fileExists(secrets / "newrotkey.txt.gpg")

  test "pubkey vault migrates to symmetric on rotate-secret":
    let secrets = setupSecretsHome()
    runGrim(@["vault", "create", "pubmigrate", "--gpg-recipient", fpr])
    runGrim(@[
      "secret", "create", "y", "--vault", "pubmigrate", "--value", "migrate-me"])
    const newKey = "user-chosen-symmetric-key-material!!"
    runGrim(@[
      "vault", "rotate-secret", "migratekey", "--vault", "pubmigrate",
      "--value", newKey])
    check runGrimOut(@["read", "grim://pubmigrate/y"]) == "migrate-me"
    let props = readFile(getEnv("GRIM_HOME") / "pubmigrate" / "vault.properties")
    check "secret=migratekey" in props
    putEnv("GNUPGHOME", gpgHome)
    check runGpg(@["--batch", "--quiet", "--decrypt",
      secrets / "migratekey.txt.gpg"]).strip() == newKey

  test "rotate-secret rejects existing secret id":
    let secrets = setupSecretsHome()
    writeTestExternalSecret(secrets, "taken", fpr, "already-there")
    runGrim(@["vault", "create", "v", "--gpg-recipient", fpr])
    var failed = false
    try:
      runGrim(@["vault", "rotate-secret", "taken", "--vault", "v"])
    except ValueError:
      failed = true
    check failed
