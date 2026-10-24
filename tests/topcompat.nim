import std/[unittest, osproc, strutils, os, json, re, strtabs, streams]
import support

proc inheritedEnv(): StringTableRef =
  result = newStringTable(modeCaseInsensitive)
  for key, value in envPairs():
    result[key] = value

proc runOut(args: openArray[string], stdinData = ""): string =
  let p = startProcess(
    command = grimBin(),
    args = @args,
    env = inheritedEnv(),
    options = {poUsePath, poStdErrToStdOut})
  if stdinData.len > 0:
    p.inputStream.write(stdinData)
    p.inputStream.flush()
  p.inputStream.close()
  let output = p.outputStream.readAll()
  discard p.waitForExit()
  output

proc runCode(args: openArray[string]): int =
  startProcess(
    command = grimBin(),
    args = @args,
    env = inheritedEnv(),
    options = {poUsePath, poStdErrToStdOut}).waitForExit()

proc createAutomationVault(fpr: string) =
  let code = runCode(@[
    "vault", "create", "Automation", "--format", "json", "--gpg-recipient", fpr])
  if code != 0:
    let vaults = parseJson(runOut(@["vault", "list", "--format", "json"]))
    check vaults.len >= 1
    check vaults[0]["id"].getStr() == "Automation"

suite "op compatibility":
  var fpr = ""
  setup:
    discard setupGrimHome()
    (_, fpr) = setupGpgHome()

  test "version and account list":
    check runOut(@["--version"]).strip() == "grim 0.1.0"
    let accounts = parseJson(runOut(@["account", "list", "--format", "json"]))
    check accounts.len == 1

  test "vault list json shape":
    createAutomationVault(fpr)
    let vaults = parseJson(runOut(@["vault", "list", "--format", "json"]))
    check vaults[0]["id"].getStr() == "Automation"
    check vaults[0]["name"].getStr() == "Automation"

  test "item create list get batch":
    createAutomationVault(fpr)
    const secret = "FICTIONAL-ONLY-SECRET"
    let tpl = $(%*{
      "title": "Example API",
      "category": "API_CREDENTIAL",
      "fields": [
        %*{
          "id": "credential",
          "type": "CONCEALED",
          "label": "credential",
          "value": secret,
        },
      ],
    })
    let createText = runOut(
      @["item", "create", "-", "--vault", "Automation", "--format", "json"], tpl)
    check createText.len > 0
    let receipt = parseJson(createText)
    let itemId = receipt["id"].getStr()
    check itemId.match(re"^[a-z0-9]{26}$")
    let list = parseJson(runOut(@[
      "item", "list", "--format", "json", "--vault", "Automation"]))
    let listText = $list
    check secret notin listText
    let batchOut = runOut(@["item", "get", "-", "--format", "json"], $list & "\n")
    check secret notin batchOut
    check "reference" in batchOut
    let revealed = runOut(@[
      "item", "get", itemId, "--vault", "Automation", "--format", "json", "--reveal"])
    check secret in revealed

  test "read op ref newline default":
    createAutomationVault(fpr)
    const secret = "FICTIONAL-READ-SECRET"
    let tpl = $(%*{
      "title": "Read Item",
      "category": "API_CREDENTIAL",
      "fields": [%*{"id": "credential", "type": "CONCEALED", "value": secret}],
    })
    discard runOut(
      @["item", "create", "-", "--vault", "Automation", "--format", "json"], tpl)
    let list = parseJson(runOut(@[
      "item", "list", "--format", "json", "--vault", "Automation"]))
    let itemId = list[0]["id"].getStr()
    let detail = parseJson(runOut(@[
      "item", "get", itemId, "--vault", "Automation", "--format", "json"]))
    let fieldRef = detail["fields"][0]["reference"].getStr()
    check runOut(@["read", fieldRef]) == secret & "\n"
    check runOut(@["read", "--no-newline", fieldRef]) == secret

  test "run resolves op env with no-masking":
    createAutomationVault(fpr)
    discard runOut(@[
      "secret", "create", "envsecret", "--vault", "Automation", "--value", "RESOLVED-VAL"])
    let list = parseJson(runOut(@[
      "item", "list", "--format", "json", "--vault", "Automation"]))
    let itemId = list[0]["id"].getStr()
    let detail = parseJson(runOut(@[
      "item", "get", itemId, "--vault", "Automation", "--format", "json"]))
    let fieldRef = detail["fields"][0]["reference"].getStr()
    var env = newStringTable(modeCaseInsensitive)
    env["X"] = fieldRef
    let merged = inheritedEnv()
    for key, value in env.pairs:
      merged[key] = value
    let p = startProcess(
      command = grimBin(),
      args = @["run", "--no-masking", "--", "printenv", "X"],
      env = merged,
      options = {poUsePath, poStdErrToStdOut})
    let got = p.outputStream.readAll().strip()
    check p.waitForExit() == 0
    check got == "RESOLVED-VAL"

  test "service account and connect blocked":
    createAutomationVault(fpr)
    let token = runOut(@[
      "service-account", "create", "Bot", "--vault", "Automation:read_items", "--raw"]).strip()
    check token.startsWith("ops_")
    putEnv("OP_SERVICE_ACCOUNT_TOKEN", token)
    check parseJson(runOut(@["vault", "list", "--format", "json"])).len == 1
    putEnv("OP_CONNECT_HOST", "https://example.invalid")
    check runCode(@["vault", "list", "--format", "json"]) == 1
    putEnv("OP_CONNECT_HOST", "")
    putEnv("OP_SERVICE_ACCOUNT_TOKEN", "")
