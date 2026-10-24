## Shared JSON serialization (pretty-printed).

import std/json

proc formatJson*(node: JsonNode): string =
  pretty(node)
