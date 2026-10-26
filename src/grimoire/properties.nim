## Java-style properties read/write with minimal escaping.

import std/[strutils, tables, os, times]
import grimoire/randomutil

type
  Properties* = OrderedTable[string, string]

proc unescapeValue*(s: string): string =
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      case s[i + 1]
      of '\\': result.add '\\'
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      else: result.add s[i + 1]
      i += 2
    else:
      result.add s[i]
      inc i

proc escapeValue*(s: string): string =
  for c in s:
    case c
    of '\\': result.add "\\\\"
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else: result.add c

proc parseProperties*(text: string): Properties =
  for rawLine in text.splitLines():
    var line = rawLine.strip()
    if line.len == 0 or line[0] == '#':
      continue
    let eq = line.find('=')
    if eq < 0:
      continue
    let key = line[0 ..< eq].strip()
    let value = unescapeValue(line[eq + 1 ..^ 1].strip())
    if key.len > 0:
      result[key] = value

proc readPropertiesFile*(path: string): Properties =
  parseProperties(readFile(path))

proc getProp*(props: Properties, key: string): string =
  if props.hasKey(key):
    props[key]
  else:
    ""

proc serializeProperties*(props: Properties): string =
  for key, value in props.pairs():
    result.add key
    result.add '='
    result.add escapeValue(value)
    result.add '\n'

proc writePropertiesFileAtomic*(path: string, props: Properties) =
  let dir = path.parentDir
  createDir(dir)
  let tmp = dir / (".tmp-" & $getTime().toUnix() & "-" & randomLowerAlnum(12))
  writeFile(tmp, serializeProperties(props))
  setFilePermissions(tmp, {fpUserRead, fpUserWrite})
  moveFile(tmp, path)
  setFilePermissions(path, {fpUserRead, fpUserWrite})
