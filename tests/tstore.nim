import std/unittest
import grimoire/store

suite "store ids":
  test "valid ids":
    validateId("a")
    validateId("Vault-1.test")

  test "reject bad ids":
    expect GrimError:
      validateId("")
    expect GrimError:
      validateId("../x")
    expect GrimError:
      validateId("-bad")
