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
