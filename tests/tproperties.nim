import std/unittest
import grimoire/properties

suite "properties":
  test "escape and unescape":
    let raw = "line1\nline2\ttab\\slash"
    let props = parseProperties("value=" & escapeValue(raw))
    check getProp(props, "value") == raw

  test "comments and blanks":
    let text = """
# comment
a=1
b=hello
"""
    let p = parseProperties(text)
    check getProp(p, "a") == "1"
    check getProp(p, "b") == "hello"
    check getProp(p, "c") == ""
