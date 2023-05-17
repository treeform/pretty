import macros, sets, strutils, typetraits, math, tables, json

when not defined(js):
  import terminal

type
  NodeKind = enum
    RootNode
    PlainStringNode
    TypeNameNode
    StringNode
    NumberNode
    BoolNode
    ObjectNode
    TupleNode
    PointerNode
    SeqNode
    ArrayNode
    SetNode
    ProcNode
    EnumNode
    TableNode
    HashSetNode

  Node = ref object
    kind: NodeKind
    name: string
    value: string
    nodes*: seq[Node]

  PrettyContext* = ref object
    highlight*: bool
    lineWidth*: int
    haveSeen: HashSet[uint64]
    root*: Node
    parent: Node

const
  ESC* = "\e["

proc pickColors(kind: NodeKind): string =
  case kind:
    of StringNode: "32m"
    of NumberNode: "34m"
    of BoolNode: "36m"
    of TypeNameNode: "36m"
    of PointerNode: "31m"
    of ProcNode: "31m"
    of EnumNode: "32m"
    else: "0m"

proc escapeString*(v: string, q = "\""): string =
  result.add q
  for c in v:
    case c:
    of '\0': result.add r"\0"
    of '\\': result.add r"\\"
    of '\b': result.add r"\b"
    of '\f': result.add r"\f"
    of '\n': result.add r"\n"
    of '\r': result.add r"\r"
    of '\t': result.add r"\t"
    else:
      if ord(c) > 128:
        result.add "\\x" & toHex(ord(c), 2).toLowerAscii()
      result.add c
  result.add q

proc escapeChar(v: string): string =
  escapeString(v, "'")

proc newPrettyContext*(): PrettyContext =
  result = PrettyContext()
  result.root = Node()
  result.root.kind = RootNode
  result.parent = result.root

  when defined(js):
    result.highlight = false
    result.lineWidth = 80
  else:
    result.highlight = stdout.isatty()
    result.lineWidth = terminalWidth()

proc add*(ctx: PrettyContext, v: string) =
  ctx.parent.nodes.add Node(kind: PlainStringNode, value: v)

proc add*(ctx: PrettyContext, name: string, v: string | cstring) =
  ctx.parent.nodes.add Node(kind: StringNode, name: name, value: escapeString($v))

proc add*(ctx: PrettyContext, name: string, v: char) =
  ctx.parent.nodes.add Node(kind: StringNode, name: name, value: escapeChar($v))

proc add*(ctx: PrettyContext, name: string, v: bool) =
  ctx.parent.nodes.add Node(kind: BoolNode, name: name, value: $v)

proc add*(ctx: PrettyContext, name: string, v: SomeNumber) =
  ctx.parent.nodes.add Node(kind: NumberNode, name: name, value: $v)

proc add*[N, T](ctx: PrettyContext, name: string, v: array[N, T]) =
  let p = ctx.parent
  let node = Node(kind: ArrayNode, name: name)
  ctx.parent = node
  let objName = ""
  ctx.parent.nodes.add Node(kind: TypeNameNode, value: objName)
  for e in v:
    ctx.add("", e)
  ctx.parent = p
  ctx.parent.nodes.add(node)

proc add*[T](ctx: PrettyContext, name: string, v: seq[T]) =
  let p = ctx.parent
  let node = Node(kind: SeqNode, name: name)
  ctx.parent = node
  let objName = ""
  ctx.parent.nodes.add Node(kind: TypeNameNode, value: objName)
  for e in v:
    ctx.add("", e)
  ctx.parent = p
  ctx.parent.nodes.add(node)

proc add*[K, V](ctx: PrettyContext, name: string, v: Table[K, V]) =
  let p = ctx.parent
  let node = Node(kind: TableNode, name: name)
  ctx.parent = node
  let objName = "Table"
  ctx.parent.nodes.add Node(kind: TypeNameNode, value: objName)
  for k, v in v:
    ctx.add($k, v)
  ctx.parent = p
  ctx.parent.nodes.add(node)

proc add*[T](ctx: PrettyContext, name: string, v: HashSet[T]) =
  let p = ctx.parent
  let node = Node(kind: HashSetNode, name: name)
  ctx.parent = node
  let objName = "HashSet"
  ctx.parent.nodes.add Node(kind: TypeNameNode, value: objName)
  for v in v:
    ctx.add("", v)
  ctx.parent = p
  ctx.parent.nodes.add(node)

proc add*(ctx: PrettyContext, name: string, v: object) =
  let p = ctx.parent
  let node = Node(kind: ObjectNode, name: name)
  ctx.parent = node
  let objName = ($type(v)).replace(":ObjectType", "")
  ctx.parent.nodes.add Node(kind: TypeNameNode, value: objName)
  for n, e in v.fieldPairs:
    ctx.add(n, e)
  ctx.parent = p
  ctx.parent.nodes.add(node)

proc add*(ctx: PrettyContext, name: string, v: ref object) =
  if v == nil:
    ctx.parent.nodes.add Node(kind: PointerNode, name: name, value: "nil")
  else:
    let id = cast[uint64](v)
    if id in ctx.haveSeen:
      # circular objects
      ctx.parent.nodes.add Node(kind: PointerNode, name: name, value: "...")
    else:
      ctx.haveSeen.incl(id)
      ctx.add(name, v[])

proc add*(ctx: PrettyContext, name: string, v: tuple) =
  let p = ctx.parent
  let node = Node(kind: TupleNode, name: name)
  ctx.parent = node
  for n, e in v.fieldPairs:
    if n.startsWith("Field"):
      ctx.add("", e)
    else:
      ctx.add(n, e)
  ctx.parent = p
  ctx.parent.nodes.add(node)

proc add*(ctx: PrettyContext, name: string, v: proc) =
  when compiles($v):
    var procName = $v
  else:
    var procName = v.type.name
  procName = procName.split("{.", 1)[0]
  ctx.parent.nodes.add Node(kind: ProcNode, name: name, value: procName)

proc add*[T](ctx: PrettyContext, name: string, v: ptr T) =
  if v == nil:
    ctx.parent.nodes.add Node(kind: PointerNode, name: name, value: "nil")
  else:
    let id = cast[uint64](v)
    if id in ctx.haveSeen:
      # circular objects
      ctx.parent.nodes.add Node(kind: PointerNode, name: name, value: "...")
    else:
      ctx.haveSeen.incl(id)
      ctx.add(name, v[])

proc add*(ctx: PrettyContext, name: string, v: pointer) =
  let h = "0x" & cast[uint64](v).toHex()
  ctx.parent.nodes.add Node(kind: PointerNode, name: name, value: h)

proc add*[T](ctx: PrettyContext, name: string, v: UncheckedArray[T]) =
  let h = "0x" & cast[uint64](v).toHex()
  ctx.parent.nodes.add Node(kind: PointerNode, name: name, value: h)

proc add*(ctx: PrettyContext, name: string, v: enum) =
  ctx.parent.nodes.add Node(kind: EnumNode, name: name, value: $v)

proc add*(ctx: PrettyContext, name: string, v: type) =
  ctx.parent.nodes.add Node(kind: TypeNameNode, name: name, value: $v)

proc add*(ctx: PrettyContext, name: string, v: distinct) =
  ctx.add(name, v.distinctBase(recursive = true))

proc add*[T](ctx: PrettyContext, name: string, v: set[T]) =
  let p = ctx.parent
  let node = Node(kind: SetNode, name: name)
  ctx.parent = node
  for e in v:
    ctx.add("", e)
  ctx.parent = p
  ctx.parent.nodes.add(node)

proc add*(ctx: PrettyContext, name: string, v: JsonNode) =
  case v.kind:
    of JObject:
      let p = ctx.parent
      let node = Node(kind: SetNode, name: name)
      ctx.parent = node
      let objName = "object"
      ctx.parent.nodes.add Node(kind: TypeNameNode, value: objName)
      for k, e in v:
        ctx.add($k, e)
      ctx.parent = p
      ctx.parent.nodes.add(node)
    of JArray:
      let p = ctx.parent
      let node = Node(kind: ArrayNode, name: name)
      ctx.parent = node
      let objName = "array"
      ctx.parent.nodes.add Node(kind: TypeNameNode, value: objName)
      for e in v:
        ctx.add("", e)
      ctx.parent = p
      ctx.parent.nodes.add(node)
    of JString:
      ctx.parent.nodes.add Node(kind: StringNode, name: name, value: escapeString(v.getStr))
    of JInt, JFloat:
      ctx.parent.nodes.add Node(kind: NumberNode, name: name, value: $v)
    of JBool:
      ctx.parent.nodes.add Node(kind: BoolNode, name: name, value: $v)
    of JNull:
      ctx.parent.nodes.add Node(kind: BoolNode, name: name, value: "null")

proc isBlock(ctx: PrettyContext, node: Node): bool =
  var total = 0
  for n in node.nodes:
    if ctx.isBlock(n):
      return true
    if n.kind in {ObjectNode}:
      return true
    if n.name != "":
      total += n.name.len + 2
    total += n.value.len
    if total > ctx.lineWidth:
      return true
  return false

proc prettyString*(ctx: PrettyContext, node: Node, indent: int = 0): string =

  result.add " ".repeat(indent)

  if node.name != "":
    result.add node.name
    result.add ": "

  if node.nodes.len == 0:
    if ctx.highlight:
      result.add ESC & pickColors(node.kind) & node.value & ESC & "0m"
    else:
      result.add node.value
  else:

    let useBlock = ctx.isBlock(node)

    if node.kind == RootNode:
      if useBlock:
        for i, n in node.nodes:
          if i == 0:
            result.add ctx.prettyString(n, indent)
          else:
            result.add "\n"
            result.add ctx.prettyString(n, indent + 2)
      else:
        for i, n in node.nodes:
          if i != 0:
            result.add " "
          result.add ctx.prettyString(n)
    else:

      case node.kind:
        of TupleNode: result.add "("
        of ArrayNode: result.add "["
        of SeqNode: result.add "@["
        of SetNode: result.add "{"
        of ObjectNode:
          result.add ctx.prettyString(node.nodes[0])
          result.add "("
        of TableNode: result.add "{"
        of HashSetNode: result.add "["
        else: discard
      if useBlock:
        result.add "\n"
        for i, n in node.nodes[1..^1]:
          if i != 0:
            result.add ",\n"
          result.add ctx.prettyString(n, indent + 2)
        result.add "\n"
        result.add " ".repeat(indent)
      else:
        for i, n in node.nodes[1..^1]:
          if i != 0:
            result.add ", "
          result.add ctx.prettyString(n)
      case node.kind:
        of TupleNode: result.add ")"
        of ArrayNode: result.add "]"
        of SeqNode: result.add "]"
        of SetNode: result.add "}"
        of ObjectNode: result.add ")"
        of TableNode: result.add "}.toTable"
        of HashSetNode: result.add "].toHashSet"
        else: discard

proc prettyString*(ctx: PrettyContext): string =
  return ctx.prettyString(ctx.root)

macro prettyWalk*(n: varargs[untyped]): untyped =

  var command = nnkStmtList.newTree(
    nnkLetSection.newTree(
      nnkIdentDefs.newTree(
        newIdentNode("context"),
        newEmptyNode(),
        nnkCall.newTree(
          newIdentNode("newPrettyContext")
        )
      )
    )
  )

  for i in 0..n.len-1:
    if n[i].kind == nnkStrLit:
      command.add nnkCall.newTree(
        nnkDotExpr.newTree(
          newIdentNode("context"),
          newIdentNode("add")
        ),
        n[i]
      )
    elif n[i].kind == nnkIdent:
      command.add nnkCall.newTree(
        nnkDotExpr.newTree(
          newIdentNode("context"),
          newIdentNode("add")
        ),
        newLit(n[i].repr),
        n[i]
      )
    else:
      command.add nnkCall.newTree(
        nnkDotExpr.newTree(
          newIdentNode("context"),
          newIdentNode("add")
        ),
        newLit(""),
        n[i]
      )

  command.add newIdentNode("context")

  return nnkBlockStmt.newTree(
    newEmptyNode(),
    command
  )

proc windowsColorPrint(s: string) =
  ## This function addresses a known issue on Windows systems when using
  ## Visual Studio Code, where strings are printed with Unix escape characters
  ## for color coding, leading to incorrect wrapping.
  ## Instead of relying on Unix-style escape characters, this function converts
  ## Unix terminal codes into the Windows color API to ensure proper
  ## colorization and formatting of the output string.
  var i = 0
  while i < s.len:
    if s[i] == '\e':
      # Escape sequence detected.
      if s[i + 2 ..< i + 4] == "0m":
        resetAttributes()
        i += 4
      else:
        # Only basic color codes are supported.
        case s[i + 2 ..< i + 5]:
          of "30m": setForegroundColor(fgBlack)
          of "31m": setForegroundColor(fgRed)
          of "32m": setForegroundColor(fgGreen)
          of "33m": setForegroundColor(fgYellow)
          of "34m": setForegroundColor(fgBlue)
          of "35m": setForegroundColor(fgMagenta)
          of "36m": setForegroundColor(fgCyan)
          of "37m": setForegroundColor(fgWhite)
          else: resetAttributes()
        i += 5
    elif s[i] == '\n':
      # Newline character detected
      # use Windows-style carriage return and line feed
      stdout.write("\r\n")
      inc i
    else:
      # Regular character, write it to the console
      stdout.write(s[i])
      inc i
  stdout.write("\r\n")
  resetAttributes()

template print*(n: varargs[untyped]): untyped =
  {.cast(gcSafe), cast(noSideEffect).}:
    try:
      when defined(windows):
        windowsColorPrint(prettyString(prettyWalk(n)))
      else:
        debugEcho prettyString(prettyWalk(n))
    except:
      discard

type TableStyle* = enum
  Fancy
  Plain

proc printStr(s: string) =
  when defined(js):
    line.add(s)
  else:
    stdout.write(s)

proc printStr(c: ForeGroundColor, s: string) =
  when defined(js):
    line.add(s)
  else:
    stdout.styledWrite(c, s)

# Work around for both jsony and print needs this.
template prettyFieldPairs*(x: untyped): untyped =
  when compiles(x[]):
    x[].fieldPairs
  else:
    x.fieldPairs

proc printTable*[T](arr: seq[T], style = Fancy) =
  ## Given a list of items prints them as a table.

  # Turns items into table props.
  var
    header: seq[string]
    widths: seq[int]
    number: seq[bool]
    table: seq[seq[string]]

  var headerItem: T
  for k, v in headerItem.prettyFieldPairs:
    header.add(k)
    widths.add(len(k))
    number.add(type(v) is SomeNumber)

  for i, item in arr:
    var
      row: seq[string]
      col = 0
    for k, v in item.prettyFieldPairs:
      let text =
        when type(v) is char:
          escapeChar($v)
        elif type(v) is string:
          v.escapeString("")
        else:
          $v
      row.add(text)
      widths[col] = max(text.len, widths[col])
      inc col
    table.add(row)

  case style:
  of Fancy:
    # Print header.
    printStr("╭─")
    for col in 0 ..< header.len:
      for j in 0 ..< widths[col]:
        printStr("─")
      if col != header.len - 1:
        printStr("─┬─")
      else:
        printStr("─╮")
    printStr("\n")

    # Print header.
    printStr("│ ")
    for col in 0 ..< header.len:
      if number[col]:
        for j in header[col].len ..< widths[col]:
          printStr(" ")
        printStr(header[col])
      else:
        printStr(header[col])
        for j in header[col].len ..< widths[col]:
          printStr(" ")
      printStr(" │ ")
    printStr("\n")

    # Print header divider.
    printStr("├─")
    for col in 0 ..< header.len:
      for j in 0 ..< widths[col]:
        printStr("─")
      if col != header.len - 1:
        printStr("─┼─")
      else:
        printStr("─┤")
    printStr("\n")

    # Print the values
    for i, item in arr:
      var col = 0
      printStr("│ ")
      for k, v in item.prettyFieldPairs:
        let text = table[i][col]
        if number[col]:
          printStr(" ".repeat(widths[col] - text.len))
          printStr(fgBlue, text)
        else:
          printStr(fgGreen, text)
          printStr(" ".repeat(widths[col] - text.len))
        printStr(" │ ")
        inc col
      printStr("\n")

    # Print footer.
    printStr("╰─")
    for col in 0 ..< header.len:
      for j in 0 ..< widths[col]:
        printStr("─")
      if col != header.len - 1:
        printStr("─┴─")
      else:
        printStr("─╯")
    printStr("\n")

  of Plain:
     # Print header.
    for col in 0 ..< header.len:
      printStr(header[col])
      for j in header[col].len ..< widths[col]:
        printStr(" ")
      printStr("   ")
    printStr("\n")

    # Print the values
    for i, item in arr:
      var col = 0
      for k, v in item.prettyFieldPairs:
        let text = table[i][col]
        if number[col]:
          for j in text.len ..< widths[col]:
            printStr(" ")
          printStr(fgBlue, text)
        else:
          printStr(fgGreen, text)
          if not number[col]:
            for j in text.len ..< widths[col]:
              printStr(" ")
        printStr("   ")
        inc col
      printStr("\n")

proc printBarChart*[N:SomeNumber](data: seq[(string, N)]) =
  ## prints a bar chart like this:
  ## zpu: ######### 20.45
  ## cpu: ################################################# 70.00
  ## gpu: ########################### 45.56
  ##
  const fillChar = "#"
  proc maximize(a: var SomeNumber, v: SomeNumber) = a = max(a, v)
  proc minimize(a: var SomeNumber, v: SomeNumber) = a = min(a, v)
  proc frac(a: SomeFloat): SomeFloat = a - floor(a)
  when defined(js):
    let
      highlight = false
      lineWidth = 120
  else:
    let
      highlight = stdout.isatty()
      lineWidth = terminalWidth()
  var
    maxKeyWidth = 0
    minNumber: N = 0
    maxNumber: N = 0
    maxLabel = 0

  for (k, v) in data:
    maximize(maxKeyWidth, k.len)
    maximize(maxLabel, ($v).len)
    minimize(minNumber, v)
    maximize(maxNumber, v)

  var
    chartWidth = lineWidth - maxKeyWidth - 3 - maxLabel - 2
  if minNumber != 0:
    chartWidth -= maxLabel + 1
  var
    barScale = chartWidth.float / (maxNumber.float - minNumber.float)
    preZero = (-minNumber.float * barScale).ceil.int

  for (k, v) in data:
    var line = ""
    printStr " ".repeat(maxKeyWidth - k.len)
    printStr fgGreen, k
    printStr ": "

    let barWidth = v.float * barScale
    if minNumber == 0:
      printStr fillChar.repeat(floor(barWidth).int)
      printStr " "
      printStr fgBlue, $v
    else:
      if barWidth >= 0:
        printStr " ".repeat(preZero + maxLabel)
        printStr fillChar.repeat(floor(barWidth).int)
        printStr " "
        printStr fgBlue, $v
      else:
        printStr " ".repeat(preZero + barWidth.int + maxLabel - ($v).len)
        printStr fgBlue, $v
        printStr " "
        printStr fillChar.repeat(floor(-barWidth).int - 1)
    printStr "\n"
