import std/[unittest, osproc, strutils, os, times, envvars]
import support

proc runGrim*(args: openArray[string]) =
  let code = startProcess(
    command = grimBin(),
    args = @args,
    options = {poUsePath, poStdErrToStdOut}).waitForExit()
  if code != 0:
    raise newException(ValueError, "grim failed (" & $code & "): grim " & args.join(" "))

proc runGrimOut(args: openArray[string]): string =
  execProcess(
    grimBin(),
    args = @args,
    options = {poUsePath, poStdErrToStdOut}).strip()

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
