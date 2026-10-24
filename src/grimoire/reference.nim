## grim:// references and template substitution.

import std/strutils
import grimoire/[store, gpg]

type
  GrimRef* = object
    vault*: string
    secret*: string

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

proc refPlaintext*(refStr: string): string =
  let r = parseGrimRef(refStr)
  validateId(r.vault)
  validateId(r.secret)
  let meta = readSecretMeta(r.vault, r.secret)
  decryptArmor(meta.valueEnc)

proc findGrimRefAt(text: string, start: int): (int, int) =
  ## Returns (begin, endExclusive) slice for a grim:// reference, or (-1, -1).
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

proc substituteGrimRefs*(text: string): string =
  result = text
  var start = 0
  while true:
    let (b, e) = findGrimRefAt(result, start)
    if b < 0:
      break
    let refStr = result[b ..< e]
    let plain = refPlaintext(refStr)
    result = result[0 ..< b] & plain & result[e ..^ 1]
    start = b + plain.len

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
    if not inner.startsWith("grim://"):
      result = result[0 ..< open] & inner & result[close + 2 ..^ 1]
      continue
    let plain = refPlaintext(inner)
    result = result[0 ..< open] & plain & result[close + 2 ..^ 1]
