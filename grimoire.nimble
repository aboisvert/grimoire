# Package

version       = "0.1.1"
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
  exec "nim c -o:grim src/grimoire.nim"
  exec "nim c -r --hints:off --path:src tests/tproperties.nim"
  exec "nim c -r --hints:off --path:src tests/tstore.nim"
  exec "nim c -r --hints:off --path:src tests/tgrimhome.nim"
  exec "nim c -r --hints:off --path:src tests/treference.nim"
  exec "nim c -r --hints:off --path:src tests/tintegration.nim"
  exec "nim c -r --hints:off --path:src tests/topcompat.nim"
