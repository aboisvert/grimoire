## grim:// and op:// references and template substitution.

import std/[strutils, uri]
import grimoire/[store, items]

type
  GrimRef* = object
    vault*: string
    secret*: string

  OpRef* = object
    vaultPart*: string
    itemPart*: string
    fieldPart*: string

proc decodeRefPart(s: string): string =
  decodeUrl(s)

proc parseGrimRef*(s: string): GrimRef =
  const prefix = "grim://"
  if not s.startsWith(prefix):
    raise newException(GrimError, "invalid grim reference: " & s)
  var rest = s[prefix.len ..^ 1]
  if rest.endsWith("/value"):
    rest = rest[0 ..< rest.len - "/value".len]
  let slash = rest.find('/')
  if slash < 0:
    raise newException(GrimError, "invalid grim reference: " & s)
  result.vault = rest[0 ..< slash]
  result.secret = rest[slash + 1 ..^ 1]
  if result.vault.len == 0 or result.secret.len == 0:
    raise newException(GrimError, "invalid grim reference: " & s)
  if result.secret.find('/') >= 0 or ' ' in result.secret:
    raise newException(GrimError, "invalid grim reference: " & s)

proc parseOpRef*(s: string): OpRef =
  const prefix = "op://"
  if not s.startsWith(prefix):
    raise newException(GrimError, "invalid op reference: " & s)
  let rest = s[prefix.len ..^ 1]
  let p1 = rest.find('/')
  if p1 < 0:
    raise newException(GrimError, "invalid op reference: " & s)
  let p2 = rest.find('/', p1 + 1)
  if p2 < 0:
    raise newException(GrimError, "invalid op reference: " & s)
  result.vaultPart = decodeRefPart(rest[0 ..< p1])
  result.itemPart = decodeRefPart(rest[p1 + 1 ..< p2])
  result.fieldPart = decodeRefPart(rest[p2 + 1 ..^ 1])

proc resolveOpReference*(refStr: string): string =
  let r = parseOpRef(refStr)
  let vid = resolveVaultByRef(r.vaultPart)
  let iid = resolveItemInVault(vid, r.itemPart)
  fieldPlaintext(vid, iid, r.fieldPart)

proc refPlaintext*(refStr: string): string =
  if refStr.startsWith("op://"):
    resolveOpReference(refStr)
  else:
    let r = parseGrimRef(refStr)
    let vid = resolveVaultByRef(r.vault)
    let iid = resolveItemInVault(vid, r.secret)
    fieldPlaintext(vid, iid, "value")

proc findGrimRefAt(text: string, start: int): (int, int) =
  let at = text.find("grim://", start)
  if at < 0:
    return (-1, -1)
  var i = at + "grim://".len
  while i < text.len and text[i] notin {'/', ' ', '\t', '\n', '\r', '}'}:
    inc i
  if i >= text.len or text[i] != '/':
    return (-1, -1)
  inc i
  while i < text.len and text[i] notin {'/', ' ', '\t', '\n', '\r', '}'}:
    inc i
  var endPos = i
  if endPos + "/value".len <= text.len and
      text[endPos ..< endPos + "/value".len] == "/value":
    endPos += "/value".len
  (at, endPos)

proc findOpRefAt(text: string, start: int): (int, int) =
  let at = text.find("op://", start)
  if at < 0:
    return (-1, -1)
  var i = at + "op://".len
  var slashes = 0
  while i < text.len and slashes < 2:
    if text[i] == '/':
      inc slashes
    elif text[i] in {' ', '\t', '\n', '\r', '"', '\''}:
      break
    inc i
  if slashes < 2:
    return (-1, -1)
  while i < text.len and text[i] notin {' ', '\t', '\n', '\r', '"', '\''}:
    inc i
  (at, i)

proc substituteRefs*(text: string): string =
  result = text
  var start = 0
  while true:
    let (gb, ge) = findGrimRefAt(result, start)
    let (ob, oe) = findOpRefAt(result, start)
    var useOp = false
    var b = gb
    var e = ge
    if ob >= 0 and (gb < 0 or ob < gb):
      useOp = true
      b = ob
      e = oe
    if b < 0:
      break
    let refStr = result[b ..< e]
    let plain =
      if useOp:
        resolveOpReference(refStr)
      else:
        refPlaintext(refStr)
    result = result[0 ..< b] & plain & result[e ..^ 1]
    start = b + plain.len

proc substituteGrimRefs*(text: string): string =
  substituteRefs(text)

proc substituteInjectTemplates*(text: string): string =
  result = text
  while true:
    let open = result.find("{{")
    if open < 0:
      break
    let close = result.find("}}", open + 2)
    if close < 0:
      break
    let inner = result[open + 2 ..< close].strip()
    if not (inner.startsWith("grim://") or inner.startsWith("op://")):
      result = result[0 ..< open] & inner & result[close + 2 ..^ 1]
      continue
    let plain = refPlaintext(inner)
    result = result[0 ..< open] & plain & result[close + 2 ..^ 1]
