#[
autogenerated by docgen
loc: /home/runner/work/Nim/Nim/lib/std/private/jsutils.nim(77, 5)
rdoccmd: 
]#
import "/home/runner/work/Nim/Nim/lib/std/private/jsutils.nim"
{.line: ("/home/runner/work/Nim/Nim/lib/std/private/jsutils.nim", 77, 5).}:
  import std/jsffi
  assert not "123".toJs.isSafeInteger
  assert 123.isSafeInteger
  assert 123.toJs.isSafeInteger
  assert 9007199254740991.toJs.isSafeInteger
  assert not 9007199254740992.toJs.isSafeInteger

