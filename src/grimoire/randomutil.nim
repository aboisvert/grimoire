## Cryptographic random strings for ids, tokens, and temp paths.

import std/sysrand

proc randomLowerAlnum*(n: int): string =
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  const nChars = chars.len
  result = newString(n)
  var buf = newSeq[byte](n)
  if not urandom(buf):
    raise newException(ValueError, "could not read random bytes")
  for i in 0 ..< n:
    result[i] = chars[buf[i] mod nChars]
