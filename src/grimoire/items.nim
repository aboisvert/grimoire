## op-shaped items stored as JSON under each vault.

import std/[json, os, strutils, random, uri, times]
import grimoire/[store, gpg, secretshome, jsonfmt]

const OpItemIdLen* = 26

proc randomLowerAlnum*(n: int): string =
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  result = newString(n)
  for i in 0 ..< n:
    result[i] = chars[rand(chars.high)]

proc generateOpItemId*(): string =
  randomLowerAlnum(OpItemIdLen)

proc itemsDir*(vaultId: string): string =
  vaultDir(vaultId) / "items"

proc itemFilePath*(vaultId, itemId: string): string =
  validateId(itemId)
  itemsDir(vaultId) / (itemId & ".json")

proc validateOpItemId*(id: string) =
  if id.len != OpItemIdLen or not id.allCharsInSet({'a' .. 'z', '0' .. '9'}):
    raise newException(GrimError, "invalid item id: " & id)

proc ensureItemsDir*(vaultId: string) =
  ensureDirMode(itemsDir(vaultId), {fpUserRead, fpUserWrite, fpUserExec})

proc listItemIds*(vaultId: string): seq[string] =
  discard readVaultMeta(vaultId)
  let dir = itemsDir(vaultId)
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".json"):
      result.add splitFile(path).name

proc readItemDoc*(vaultId, itemId: string): JsonNode =
  validateOpItemId(itemId)
  let path = itemFilePath(vaultId, itemId)
  if not fileExists(path):
    raise newException(GrimError, "item not found: " & itemId)
  parseJson(readFile(path))

proc writeItemDoc*(vaultId: string, doc: JsonNode) =
  if not doc.hasKey("id"):
    raise newException(GrimError, "item missing id")
  let itemId = doc["id"].getStr()
  validateOpItemId(itemId)
  ensureItemsDir(vaultId)
  let path = itemFilePath(vaultId, itemId)
  let tmp = path & ".tmp." & $getTime().toUnix()
  writeFile(tmp, formatJson(doc))
  setFilePermissions(tmp, {fpUserRead, fpUserWrite})
  moveFile(tmp, path)
  var vault = readVaultMeta(vaultId)
  vault.updated = utcNow()
  writeVaultMeta(vault)

proc isConcealedField(field: JsonNode): bool =
  if field.kind != JObject:
    return false
  let ftype = if field.hasKey("type"): field["type"].getStr() else: ""
  let purpose = if field.hasKey("purpose"): field["purpose"].getStr() else: ""
  ftype == "CONCEALED" or purpose == "PASSWORD"

proc encryptFieldValue(vaultId: string, meta: VaultMeta, plain: string): string =
  if meta.secretId.len > 0:
    encryptSymmetric(vaultSymmetricPassphrase(vaultId), plain)
  else:
    encryptToRecipient(meta.gpgRecipient, plain)

proc decryptFieldValue(vaultId: string, meta: VaultMeta, enc: string): string =
  if meta.secretId.len > 0:
    decryptSymmetric(vaultSymmetricPassphrase(vaultId), enc)
  else:
    decryptArmor(enc)

proc encryptFieldValues*(vaultId: string, fields: JsonNode) =
  let meta = readVaultMeta(vaultId)
  if fields.kind != JArray:
    return
  for field in fields:
    if field.kind != JObject:
      continue
    if not isConcealedField(field):
      continue
    if field.hasKey("value") and field["value"].kind != JNull:
      let plain = field["value"].getStr()
      field["value_enc"] = %encryptFieldValue(vaultId, meta, plain)
      field.delete("value")
    elif field.hasKey("value_enc"):
      discard

proc decryptFieldValues*(vaultId: string, fields: JsonNode) =
  let meta = readVaultMeta(vaultId)
  if fields.kind != JArray:
    return
  for field in fields:
    if field.kind != JObject:
      continue
    if not isConcealedField(field):
      continue
    if field.hasKey("value_enc"):
      let enc = field["value_enc"].getStr()
      field["value"] = %decryptFieldValue(vaultId, meta, enc)
      field.delete("value_enc")

proc encodeRefPart(s: string): string =
  encodeUrl(s, usePlus = false)

proc fieldReference*(vaultName, itemTitle, fieldId: string): string =
  "op://" & encodeRefPart(vaultName) & "/" &
    encodeRefPart(itemTitle) & "/" & encodeRefPart(fieldId)

proc itemSummary*(vaultId: string, doc: JsonNode): JsonNode =
  let meta = readVaultMeta(vaultId)
  result = %*{
    "id": doc["id"],
    "title": doc["title"],
    "category": doc["category"],
    "vault": {"id": meta.id, "name": meta.name},
  }
  if doc.hasKey("version"):
    result["version"] = doc["version"]
  if doc.hasKey("created_at"):
    result["created_at"] = doc["created_at"]
  if doc.hasKey("updated_at"):
    result["updated_at"] = doc["updated_at"]

proc itemForOutput*(
    vaultId: string, doc: JsonNode, reveal: bool): JsonNode =
  result = parseJson($doc)
  let meta = readVaultMeta(vaultId)
  if result.hasKey("vault") and result["vault"].kind == JObject:
    result["vault"]["id"] = %meta.id
    result["vault"]["name"] = %meta.name
  if reveal:
    if result.hasKey("fields"):
      decryptFieldValues(vaultId, result["fields"])
  else:
    if result.hasKey("fields") and result["fields"].kind == JArray:
      var outFields = newJArray()
      for field in result["fields"]:
        if field.kind != JObject:
          continue
        var f = newJObject()
        for k, v in field.pairs:
          if k notin ["value", "value_enc"]:
            f[k] = v
        if isConcealedField(field):
          let fid = if field.hasKey("id"): field["id"].getStr() else: "field"
          let title = if doc.hasKey("title"): doc["title"].getStr() else: ""
          f["reference"] = %fieldReference(meta.name, title, fid)
        outFields.add f
      result["fields"] = outFields

proc persistItemFromTemplate*(
    vaultId: string, itemTemplate: JsonNode, existingId = ""): JsonNode =
  let meta = readVaultMeta(vaultId)
  var doc = parseJson($itemTemplate)
  let itemId =
    if existingId.len > 0:
      existingId
    else:
      generateOpItemId()
  doc["id"] = %itemId
  doc["vault"] = %*{"id": meta.id, "name": meta.name}
  let now = utcNow()
  if existingId.len == 0:
    doc["version"] = %1
    doc["created_at"] = %now
    doc["updated_at"] = %now
  else:
    let prev = readItemDoc(vaultId, existingId)
    if prev.hasKey("created_at"):
      doc["created_at"] = prev["created_at"]
    var ver = 1
    if prev.hasKey("version"):
      ver = prev["version"].getInt() + 1
    doc["version"] = %ver
    doc["updated_at"] = %now
  if doc.hasKey("fields"):
    encryptFieldValues(vaultId, doc["fields"])
  writeItemDoc(vaultId, doc)
  doc

proc findItemsByTitle*(vaultId: string, title: string): seq[string] =
  let want = title
  for iid in listItemIds(vaultId):
    let doc = readItemDoc(vaultId, iid)
    if doc{"title"}.getStr() == want:
      result.add iid

proc resolveItemInVault*(vaultId, itemRef: string): string =
  ## itemRef is item id or unique title.
  if itemRef.len == OpItemIdLen and itemRef.allCharsInSet({'a' .. 'z', '0' .. '9'}):
    validateOpItemId(itemRef)
    if fileExists(itemFilePath(vaultId, itemRef)):
      return itemRef
  let matches = findItemsByTitle(vaultId, itemRef)
  if matches.len == 1:
    return matches[0]
  if matches.len > 1:
    raise newException(GrimError, "ambiguous item title: " & itemRef)
  raise newException(GrimError, "item not found: " & itemRef)

proc fieldPlaintext*(vaultId, itemId, fieldId: string): string =
  let doc = readItemDoc(vaultId, itemId)
  if not doc.hasKey("fields") or doc["fields"].kind != JArray:
    raise newException(GrimError, "item has no fields")
  for field in doc["fields"]:
    if field.kind != JObject:
      continue
    let fid = if field.hasKey("id"): field["id"].getStr() else: ""
    let label = if field.hasKey("label"): field["label"].getStr() else: ""
    if fid != fieldId and label != fieldId:
      continue
    if field.hasKey("value_enc"):
      let meta = readVaultMeta(vaultId)
      return decryptFieldValue(vaultId, meta, field["value_enc"].getStr())
    if field.hasKey("value"):
      return field["value"].getStr()
    raise newException(GrimError, "field has no value: " & fieldId)
  raise newException(GrimError, "field not found: " & fieldId)

proc reencryptVaultItems*(vaultId, newRecipient: string) =
  let meta = readVaultMeta(vaultId)
  if meta.secretId.len > 0:
    return
  for iid in listItemIds(vaultId):
    var doc = readItemDoc(vaultId, iid)
    if not doc.hasKey("fields") or doc["fields"].kind != JArray:
      continue
    for field in doc["fields"]:
      if field.kind != JObject or not field.hasKey("value_enc"):
        continue
      let plain = decryptArmor(field["value_enc"].getStr())
      field["value_enc"] = %encryptToRecipient(newRecipient, plain)
    writeItemDoc(vaultId, doc)

proc reencryptVaultItemsForNewSymmetricKey*(
    vaultId, oldSecretId, newPlainPassphrase: string) =
  let oldSymmetric = oldSecretId.len > 0
  let oldPass =
    if oldSymmetric: readExternalSecretPlain(oldSecretId) else: ""
  for iid in listItemIds(vaultId):
    var doc = readItemDoc(vaultId, iid)
    if not doc.hasKey("fields") or doc["fields"].kind != JArray:
      continue
    var touched = false
    for field in doc["fields"]:
      if field.kind != JObject or not isConcealedField(field):
        continue
      if not field.hasKey("value_enc"):
        continue
      let enc = field["value_enc"].getStr()
      let plain =
        if oldSymmetric: decryptSymmetric(oldPass, enc)
        else: decryptArmor(enc)
      field["value_enc"] = %encryptSymmetric(newPlainPassphrase, plain)
      touched = true
    if touched:
      writeItemDoc(vaultId, doc)

proc deleteItem*(vaultId, itemId: string) =
  let path = itemFilePath(vaultId, itemId)
  if not fileExists(path):
    raise newException(GrimError, "item not found: " & itemId)
  removeFile(path)

proc parseJsonDocuments*(input: string): seq[JsonNode] =
  var documents: seq[JsonNode] = @[]
  var start = -1
  var depth = 0
  var quoted = false
  var escaped = false
  for i, character in input:
    if quoted:
      if escaped:
        escaped = false
      elif character == '\\':
        escaped = true
      elif character == '"':
        quoted = false
      continue
    if character == '"':
      quoted = true
    elif character == '{' or character == '[':
      if depth == 0:
        start = i
      inc depth
    elif character == '}' or character == ']':
      dec depth
      if depth == 0 and start >= 0:
        let slice = input[start .. i]
        let parsed = parseJson(slice)
        if parsed.kind == JArray:
          for el in parsed:
            documents.add el
        else:
          documents.add parsed
        start = -1
  if depth != 0 or quoted:
    raise newException(GrimError, "incomplete JSON document")
