# The core IR

Status: **stage S1 of [PROPOSAL_CORE_IR.md](PROPOSAL_CORE_IR.md)** (AGORA-858).
nurlc builds the core IR as it compiles and `--emit-core` prints it. Nothing
in the compiler reads it yet: the borrow walk and `mem_*` decide exactly what
they decided before. This note says what the IR is, how the walk builds it,
and how to keep it complete. Read
[COMPILER_INTERNALS.md](COMPILER_INTERNALS.md) first.

## 1. What it is

Per function, closure bodies included: its variables and a list of
statements in evaluation order. It is the statement language of the formal
model (`formal/A2`), extended only where NURL has more.

- A **variable** is a parameter, a binding, a capture of a closure body, or
  a temporary. Names are resolved: two bindings of one name are two
  variables.
- A **place** is a variable and a path: field names, `*` (an element),
  `#n` (the n-th member of an option, a result or another inline
  aggregate). A global is a place of its own, `g:name`.
- An **operand** is a place, or `c`: a value with nothing to track (a
  number, a literal, a unit variant, a global of numbers).
- **Every producer is bound before anything consumes it.** A call's
  result, a literal, a join, a value block, a closure and a try each land
  in a temporary. A consumer only ever sees an operand. This is
  [ELABORATION.md](ELABORATION.md)'s rule, applied to every form.

## 2. The text `--emit-core` prints

`nurlc --emit-core file.nu` checks the program as `--check` does and prints
the IR on stdout instead of LLVM IR. Tab-separated header lines, one
statement a line:

```
fn    <name> <return type> <parameters> <line> <file> <flags> <template>
v     <id> <kind> <depth> <flags> <line> <value block> <name> <type>
<statements>
endfn
ty    <type> <class> <drops> <base> A <n> <type arguments> F <n> (<field> <type>)… V <n> (<variant> <payloads> <type>…)…
virt  <virtual callee> <impl function>…
```

- `fn` flags: bit 0 the body may use raw memory (`unsafe`, or a file of the
  standard library), bit 1 it does so itself (a read or a store through a
  pointer, a cast that makes an address). `template` is the generic an
  instance was made from.
- `v` kind: 0 parameter, 1 binding, 2 temporary, 3 capture. Flags: 1
  mutable, 2 `inout`, 4 `sink`, 8 a capture taken by pointer (a `: ~`
  binding the closure assigns, MEMORY.md §2.3). `depth` counts the scopes
  open where it was made. `value block` is the temporary of the value
  block it was bound in, -1 for none.
- `ty` lists every type the IR mentions, and the types those hold: the
  borrow walk's binding class, whether it has something to release, and
  its layout.
- `virt` lists, for each `dyn` method the IR calls (`m__dyn__Trait`), the
  impl functions the call may run.

Statements:

| statement | meaning |
|---|---|
| `let <v> <rvalue>` | the variable is bound; `none` leaves it empty (a join's or a value block's temporary) |
| `assign <place> <rvalue>` | a store |
| `eval <rvalue>` | evaluated for its effects; the result is a number or nothing |
| `if <op>` … `else` … `end` | `?`, and the operand of `\|` / `&` that may not run |
| `match <op>`, `arm <pattern>` …, `end` | `??`; a payload binding is `let <v> payload <op> <variant> <i>` in its arm |
| `loop` … `loopcond <op>` … `end` | `~ cond { }`: the condition's statements, the condition, the body |
| `foreach <v> <op>` … `end` | `~ x xs { }` |
| `scope` … `end` | a scope: what is bound in it is released at its `end` |
| `defer` … `end` | `; { }`: runs at every exit from here on |
| `drop <v>` | a temporary's statement ended |
| `ret <op>` (`-`: no value), `break`, `continue` | exits |
| `line <n>` | the statements that follow are on that source line |

Rvalues:

| rvalue | meaning |
|---|---|
| `use <op>` | a value handed to a new holder |
| `call <function> <n> <op>…` | every argument an operand, in parameter order |
| `callind <n> <op>…` | a call through a closure value, the first operand |
| `agg <variant> <n> <op>…` ⇥ `<type>` | a struct, enum, option, result or slice literal (`-`: no variant) |
| `closure <function> <n> <op>…` | a closure literal: its body's function and what it captures |
| `payload <op> <variant> <i>` | payload `i` of the matched value |
| `scalar <n> <op>…` | a computation of numbers that reads the operands |
| `opaque <token> <n> <op>…` | **a construct the walk did not lower** (§4) |

A join (`?`, `??`), a value block and a try assign their arms' values to
one temporary declared before them. An arm is a scope: what it binds and
the temporaries it made are released at its `end`, after its value went to
the join's temporary.

## 3. How the walk builds it

The compiler has no tree: `gen_expr` and its callees parse, type and emit
in one pass. The IR is built by the same pass, on an **operand stack**:

- **Every expression leaves exactly one operand.** `gen_expr` records the
  stack's height when it starts and calls `core_expr_exit` when its
  dispatch returns.
- A construct **pops what it consumed and pushes its own**: `gen_ident`
  pushes the name's place, a call pops its arguments and pushes its
  result's temporary, `. obj f` replaces the object by its field.
- **A statement leaves one operand** (`core_stmt_exit`). The block that
  holds it discards it before the next statement (`core_discard`), which
  is also where the temporaries the statement made are released. A tail's
  operand is the block's value, and its temporaries ride on to the
  statement around the block.

So an argument, a field or an arm never has to be threaded through the
compiler's functions: whatever evaluated it left it on the stack, in
evaluation order. The hooks are few: one per construct, at the point where
the compiler itself has resolved what the construct is (which field, which
callee, which variant).

Functions with many ways out are lowered by a **wrapper**: the generator
keeps its name and becomes four lines around its old body
(`__gen_member_body`, `__gen_agg_lit_body`, `__gen_slice_literal_body`,
`__gen_field_store_body`, `__gen_call_kwargs_body`; a call's is
`__gen_call_nested`). The wrapper reads the operands the body left.

Variables are numbered per function. A binding's number is stored beside
its name in the scoped symbol table (`<name>__cv`), with the number of the
function being built above 2²⁰: a closure body tells its maker's bindings
(captures) from its own. A closure body is built as its own function
(`core_closure_begin` / `core_closure_end`), and the enclosing function's
builder is set aside while it is.

With `--emit-core` off (`g_core_live` 0) every hook is one test of a
global.

## 4. Completeness is checked, not assumed

A construct with no hook cannot leave the right operand by accident:

- `core_expr_exit` finds the stack one operand higher than at entry, or
  the construct is counted. A computation of numbers that left its
  operands on the stack is a `scalar` read of them. Anything else is an
  `opaque` rvalue and a `core-gap` line on stderr with the function and
  line.
- A closure literal, a try and a slice literal must be acknowledged by
  their own hook (`g_core_acks`): one operand left over is not their
  value.
- A name no hook bound is `core-gap name <name>`.
- The reader (`tools/ncore/fromnurlc.py`) checks every `call` of a
  compiled function against its parameter count.

`--emit-core` ends with the count of constructs not lowered. It is 0 over
the hole probes and the compiler's own source, and it has to stay 0: a new
expression form gets its hook in the PR that adds the form.

## 5. Reading it

`tools/ncore` is the reference checker of the proposal. `fromnurlc.py` runs
nurlc and reads the IR into the form `check.py` checks:

```
cd tools/ncore
PYTHONUTF8=1 python run.py --nurlc --list subset.txt
PYTHONUTF8=1 python run.py --nurlc <probe>.nu
```

It passes `--no-borrowck`: the IR is the same, and a refusal of the borrow
walk does not hide the function it was in.
