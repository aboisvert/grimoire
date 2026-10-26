# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

# Nimble install builds in buildtemp and only adds dependency --path flags, not this
# package's srcDir (nimble build from a dev tree does). Needed for `import grimoire/...`.
import std/os
switch("path", joinPath(thisDir(), "src"))
