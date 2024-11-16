## Put your tests here.

import pretty {.all.}
import json, tables, sets

block:
  let
    a = true
    b = 1
    c = 1.34
    d = "one"

  print "status", a, b, c, d

block:
  let
    a = true
    b = 1
    c = 1.34
    d = "one"

  var ctx = prettyWalk("status", a, b, c, d)

  ctx.lineWidth = 120
  ctx.highlight = true
  echo prettyString(ctx)
  #doAssert prettyString(ctx) == "\27[0mstatus\27[0m a: \27[36mtrue\27[0m b: \27[34m1\27[0m c: \27[34m1.34\27[0m d: \27[32m\"one\"\27[0m"

  ctx.highlight = false
  echo prettyString(ctx)
  #doAssert prettyString(ctx) == "status a: true b: 1 c: 1.34 d: \"one\""

  ctx.lineWidth = 10
  echo prettyString(ctx)
  #doAssert prettyString(ctx) == """status
  # a: true
  # b: 1
  # c: 1.34
  # d: "one""""

block:
  # Object

  type Foo = object
    a: string
    b: bool
    c: int

  var foo = Foo(a: "hi there", b: false, c: 12345)

  print foo

  var ctx = prettyWalk(foo)
  ctx.lineWidth = 120
  ctx.highlight = false
  echo prettyString(ctx)

  ctx.lineWidth = 10
  ctx.highlight = false
  echo prettyString(ctx)

block:
  # Ref Object

  type Bar = ref object
    a: string
    b: bool
    c: int

  var barNil: Bar
  print barNil

  var bar = Bar(a: "hi there", b: false, c: 12345)

  print bar

  var ctx = prettyWalk(bar)

  ctx.lineWidth = 120
  ctx.highlight = false
  echo prettyString(ctx)

  ctx.lineWidth = 10
  ctx.highlight = false
  echo prettyString(ctx)

block:
  # Nested Ref Object

  type Foo = object
    a: string
    b: bool
    c: int

  type Bar = ref object
    a: string
    b: bool
    c: int

  type Baz = ref object
    foo: Foo
    bar: Bar
    baz: Baz

  var baz = Baz(bar: Bar(a: "hi there", b: false, c: 12345))

  print baz

  var
    baz2 = Baz(bar: Bar(a: "hi there", b: false, c: 12345))
    baz3 = Baz(baz: baz2)
    baz4 = Baz(baz: baz3)

  print baz4

  var
    baz01 = Baz()
    baz02 = Baz(baz: baz01)
    baz03 = Baz(baz: baz02)
  baz01.baz = baz03
  print baz03

block:
  # Seq
  print @[1, 2, 3]

  # Array
  print [1, 2, 3]

  # tuple
  print (1, 2, 3)

  var
    a = @[1, 2, 3]
    b = [1, 2, 3]
    c = (1, 2, 3)

  print a, b, c

block:
  # Procs
  proc adder(a, b: int): int = a + b
  print adder

  let v = adder
  print v

block:
  # cstring
  print "hey".cstring
  let a = "hello".cstring
  print a

block:
  # pointers
  var a = 1234
  var b = a.addr
  var c: ptr int
  print a, b, c
  var d: pointer = cast[pointer](b)
  print d
  var ua: ptr UncheckedArray[int]
  print ua

block:
  # enums
  type Colors = enum
    Red, White, Blue

  var c = Red
  print Red, c

block:
  # tables
  print {"a": 1, "b": 2}.toTable
  var a: Table[int, int]
  for i in 0 .. 30:
    a[i] = i
  print a

block:
  # tables
  print [1, 2, 3, 4].toHashSet
  var a: HashSet[int]
  for i in 0 .. 30:
    a.incl(i)
  print a

block:
  # json
  let json = %*{
    "a": 123,
    "b": "hi",
    "c": true
  }
  print json

  var json2 = newJArray()
  for i in 0 ..< 20:
    json2.add(%("element" & $i))
  print json2

block:
  # test unicode
  print "hi there 😊"
  print "《自然哲学的数学原理》"
  print "Пожалуйста"
