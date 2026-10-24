import std/unittest
import grimoire/[reference, store]

suite "references":
  test "parse grim ref":
    let r = parseGrimRef("grim://myvault/mysecret/value")
    check r.vault == "myvault"
    check r.secret == "mysecret"

  test "reject invalid ref":
    expect GrimError:
      discard parseGrimRef("http://x/y")
