import std/os
import grimoire/[cli, commands]

proc main() =
  try:
    runGrim(commandLineParams())
  except UsageError as e:
    stderr.writeLine "grim: " & e.msg
    quit(2)
  except CatchableError as e:
    stderr.writeLine "grim: " & e.msg
    quit(1)

when isMainModule:
  main()
