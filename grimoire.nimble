# Package

version       = "0.1.3"
author        = "Alex Boisvert"
description   = "Local GPG-backed password manager CLI (grim)"
license       = "MIT"
srcDir        = "src"
# Entry module must be grimoire.nim so `import grimoire/...` resolves under nimble
# install (nimble only passes dependency --path flags, not this package's src).
bin           = @["grimoire"]
namedBin      = {"grimoire": "grim"}.toTable

requires "nim >= 2.2.12"
requires "checksums >= 0.2.0"

task test, "Run tests":
  exec "nimble build"
  exec "nim c -r --hints:off tests/tproperties.nim"
  exec "nim c -r --hints:off tests/tstore.nim"
  exec "nim c -r --hints:off tests/tgrimhome.nim"
  exec "nim c -r --hints:off tests/treference.nim"
  exec "nim c -r --hints:off tests/tintegration.nim"
  exec "nim c -r --hints:off tests/topcompat.nim"
