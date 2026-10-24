import std/[unittest, os, times, envvars]
import grimoire/store

proc makeTempDir(prefix: string): string =
  let base = getTempDir() / (prefix & "-" & $getTime().toUnix())
  createDir(base)
  base

suite "discoverGrimHome":
  test "ancestor .grimoire from subdir":
    let root = makeTempDir("grim-disc")
    defer: removeDir(root)
    let grim = root / ".grimoire"
    createDir(grim)
    let sub = root / "subdir"
    createDir(sub)
    check discoverGrimHome(sub) == grim

  test "deepest .grimoire wins":
    let root = makeTempDir("grim-deep")
    defer: removeDir(root)
    createDir(root / ".grimoire")
    let nestedGrim = root / "nested" / ".grimoire"
    createDir(root / "nested")
    createDir(nestedGrim)
    let deep = root / "nested" / "deep"
    createDir(deep)
    check discoverGrimHome(deep) == nestedGrim

  test "cwd inside grim home":
    let root = makeTempDir("grim-inside")
    defer: removeDir(root)
    let grim = root / "proj" / ".grimoire"
    createDir(root / "proj")
    createDir(grim)
    let inside = grim / "myvault" / "items"
    createDir(grim / "myvault")
    createDir(inside)
    check discoverGrimHome(inside) == grim

  test "no local .grimoire falls back to home":
    let root = makeTempDir("grim-fallback")
    defer: removeDir(root)
    let sub = root / "only" / "path"
    createDir(root / "only")
    createDir(sub)
    check discoverGrimHome(sub) == getHomeDir() / ".grimoire"

suite "grimHome override":
  test "GRIM_HOME takes precedence":
    let root = makeTempDir("grim-env")
    defer:
      delEnv("GRIM_HOME")
      removeDir(root)
    createDir(root / ".grimoire")
    putEnv("GRIM_HOME", root / "explicit")
    check grimHome() == root / "explicit"
