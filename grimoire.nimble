# Package

version       = "0.1.0"
author        = "Alex Boisvert"
description   = "Local GPG-backed password manager CLI (grim)"
license       = "MIT"
srcDir        = "src"
bin           = @["grim"]

requires "nim >= 2.2.12"

task test, "Run tests":
  exec "nim c -r --hints:off --path:src tests/tproperties.nim"
  exec "nim c -r --hints:off --path:src tests/tstore.nim"
  exec "nim c -r --hints:off --path:src tests/treference.nim"
  exec "nim c -r --hints:off --path:src tests/tintegration.nim"
