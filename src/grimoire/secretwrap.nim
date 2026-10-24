## grim secret commands as single-field items.

import std/json
import grimoire/items

const SecretCategory* = "PASSWORD"
const SecretFieldId* = "value"

proc listSecretTitles*(vaultId: string): seq[string] =
  for iid in listItemIds(vaultId):
    let doc = readItemDoc(vaultId, iid)
    result.add doc["title"].getStr()

proc secretItemTemplate*(title, plainValue: string): JsonNode =
  %*{
    "title": title,
    "category": SecretCategory,
    "fields": [
      {
        "id": SecretFieldId,
        "label": SecretFieldId,
        "type": "CONCEALED",
        "value": plainValue,
      },
    ],
  }

proc findSecretItemId*(vaultId, title: string): string =
  resolveItemInVault(vaultId, title)

proc readSecretPlain*(vaultId, title: string): string =
  let iid = findSecretItemId(vaultId, title)
  fieldPlaintext(vaultId, iid, SecretFieldId)

proc upsertSecret*(vaultId, title, plainValue: string) =
  let matches = findItemsByTitle(vaultId, title)
  if matches.len == 0:
    discard persistItemFromTemplate(vaultId, secretItemTemplate(title, plainValue))
  else:
    let iid = matches[0]
    var doc = readItemDoc(vaultId, iid)
    if doc.hasKey("fields") and doc["fields"].kind == JArray and doc["fields"].len > 0:
      doc["fields"][0]["value"] = %plainValue
      doc["fields"][0]["type"] = %"CONCEALED"
      doc["fields"][0]["id"] = %SecretFieldId
    discard persistItemFromTemplate(vaultId, doc, existingId = iid)

proc deleteSecretItem*(vaultId, title: string) =
  deleteItem(vaultId, findSecretItemId(vaultId, title))
