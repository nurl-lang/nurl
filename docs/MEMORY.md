# NURL Memory Model

This document describes how NURL manages memory: who owns a heap
allocation, when it is released, which rules the compiler enforces, and
what the resulting guarantee covers. The raw-memory boundary itself is
specified in spec §3.3d.

## TL;DR

- **Single owner, deterministic drop.** Every value that holds memory has
  exactly one owner, and the compiler releases it when the owner's scope
  ends. There is no garbage collector. `String`, `Vec`, the structs and
  enums that hold them, closures and the library containers (`HashMap`,
  `Set`, `Deque`, `BTree`, `Box`, `Rc`, `Arc`) are dropped by the compiler
  (§7.6). Opaque library state (`Mutex`, `Channel`, `Regex`, `File`,
  `TlsConn`, …) is a handle over a counted block that its last copy
  releases.
- **Nothing is released by hand.** `vec_free`, `string_free`, `*_close`
  and the other release calls remain as an optional *early* release. Raw
  memory (`nurl_alloc`, `nurl_free`, `mem_forget`, `*T` access, foreign
  calls) exists only inside `unsafe` functions.
- **Owned values move; reads borrow.** Storing, sending, returning or
  handing a value to a `sink` parameter moves it, and the old name is
  gone. A read that does not take ownership (`vec_get`, a field read,
  `string_data`) is a borrow that ends when its source is moved,
  released, reassigned or reallocated (§6.2).
- **The guarantee (§6.2).** Every program the compiler accepts outside
  the bodies of `unsafe` functions is memory-safe and leak-free, data
  races and the panic path included. Each hole found so far is a probe in
  `tools/fuzz/holes/` that CI holds rejected or clean under the
  sanitizers; none is known open. A view is tracked wherever it goes (§2.10).
- **Conservative, with a fix.** A program the rules cannot prove safe is
  rejected. Each diagnostic names the rule and a concrete change that
  satisfies it (§6.3).
- **Cycles.** `Rc` cycles are collected, and only types that can form one
  pay for it. Cycles of thread-shared handles are rejected at compile
  time (§7.7).

## 1. Ownership and auto-drop

NURL has no garbage collector. Values live on the stack by default, heap
memory comes from the runtime allocator, and the compiler tracks which
binding owns each heap value and emits its release.

### What gets owned

A binding owns a value when its initialiser produces a fresh one:

- a slice literal `[ T | … ]` or a slice-returning call,
- an allocating string call (`nurl_str_cat`, `nurl_str_int`,
  `nurl_read_file`, `nurl_argv_get`, …),
- a constructor of a `String`, `Vec`, owning struct, enum, closure or
  library handle,
- a named-struct literal `@ T { … }` whose fields are fresh values (each
  field is tracked on its own; a fresh raw string field only in `unsafe`
  code — in safe code a raw string in a value is a view, §2.13),
- a value of a type with a `% Drop` impl,
- a mutable string binding born from a literal or an owned string: it
  takes its own copy, and a copy of every value assigned to it after.

At the end of the owner's scope the compiler emits the matching drop.
Reassigning an owner drops the previous value first. Returning a value
transfers ownership to the caller. Both argv accessors return owned
copies, including an allocated empty string for an absent argument.

A `?` or `??` expression may select between a borrowed value and an owned
one. The result carries per-path ownership: the owned path is released by
whoever receives the result, the borrowed path is not.

### Where values are dropped

Every scope drops what it owns on every exit:

- a function or closure body, whether it returns with `^` or falls off its
  end;
- a `?` / `??` arm and a loop body, at its closing brace (a loop body once
  per iteration);
- a bare block.

A value that becomes the result of its construct is not dropped there: an
arm whose value is the match's value hands it to the join, and a body
whose final expression is an owned binding returns it. When the
construct's value is discarded (a statement-level match), what its arms
produced is dropped.

A closure body is its own scope. It drops the values it creates and never
the enclosing frame's.

### Temporaries

An allocating call used directly as another call's argument is a
**temporary**. It is dropped right after that call, unless the callee
keeps it (a `sink` parameter, or a parameter the callee stores into an
aggregate or container) or hands it back, in which case it leaves with
the result:

<!-- doctest-prelude
$ `stdlib/core/string.nu`
: Resp { i status }
@ takes String s → i { ^ ( string_len s ) }
: Resp resp @ Resp { 200 }
-->
```nurl
( nurl_eprint ( nurl_str_int . resp status ) )   // released after the call
: i n ( takes ( string_from `x` ) )              // likewise
```

A callee whose result may view the temporary — `( string_data ( mk ) )`,
a helper handing back a view of its parameter, a closure over it — leaves
it to the call further out that uses the view: it is released once that
call returns something that cannot point into it (a number, a value of
its own) and keeps nothing of it. A view kept past that point — bound,
returned, assigned, stored, or taken by a join — would leave the
temporary owned by nothing, and is rejected; bind the argument to a name
first, and the view borrows from the binding (agora #138, h378–h381):

<!-- doctest-prelude
$ `stdlib/core/string.nu`
@ mk → String { ^ ( string_from `a string long enough to own a heap buffer` ) }
-->
```nurl expect-error="may view its argument"
: s v ( string_data ( mk ) )               // rejected: nothing would own the String
( nurl_println v )
```

<!-- doctest-prelude
$ `stdlib/core/string.nu`
@ mk → String { ^ ( string_from `a string long enough to own a heap buffer` ) }
-->
```nurl
: String t ( mk )
: s v ( string_data t )                    // a view of `t`, until `t`'s scope ends
( nurl_println v )
( nurl_println ( string_data ( mk ) ) )    // the String is released after the println
```

### Explicit early release

A release call on an owned binding is allowed and moves the value: the
binding is consumed and its drop does not run again.

```nurl
$ `stdlib/core/string.nu`

: String s ( string_from `x` )
: i n ( string_len s )
( string_free s )      // redundant: s is dropped right here anyway
^ n
```

When such a call sits at the tail of its scope it is redundant, and
`--lint` reports it as `[redundant-free]`. An earlier release (more code
follows it) is legitimate; it lowers peak memory.

### Module globals

A mutable global whose type owns something — a `String`, a `Vec`, a
struct of them, an option, a closure, a library handle — owns its value
the way an `inout` parameter's caller does:

- it starts as the zero value, which drops as nothing;
- an assignment to it, or to one of its fields, drops what it replaces,
  and an owned value assigned to it moves in;
- a read borrows: `: T v g` is a view, `( f g )` lends it.

Every thread can reach a global, so only an `unsafe` function reads or
writes one that owns something: it vouches that no other thread replaces
the value while it is in use (a lock held, one thread only). The rest of
the program calls safe accessors around it. A zero `Vec` or handle holds
nothing to use yet, so a global that is filled on first use keeps a flag
beside it:

```nurl
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: ~ ( Vec String ) g_names 0
: ~ b g_names_made F

unsafe @ name_add s n → v {
    ? ! g_names_made { = g_names ( vec_new [String] ) = g_names_made T } {}
    ( vec_push [String] g_names ( string_from n ) )
}
```

A value that is there or not is an option global (`: ~ ?Model g_model 0`,
zero is `F`): `= g_model @ ?Model { F }` lets the old one go.
`( mem_addr g )` (`unsafe`) is a `*T` to any mutable global: a struct
global's fields for an `unsafe` helper, or an address a foreign call or
an atomic operation writes through. It also takes an `inout` parameter,
whose place is the caller's for the call (`mem_replace` is built on it). A raw-string global (`: ~ s g ```)
owns its text, as a mutable string binding does: a fresh string assigned
to it — from a call that hands it over on every path, or on this call
only (its guard slot says so, h202) — is released by the next assignment.
That release can free the text under a reader in another thread, so only
an `unsafe` function hands a string global a string to own (h273); in
safe code it holds literals.

A global of plain scalars needs no `unsafe`: an integer, bool, float or
`s` global is read and written with relaxed atomics, so threads racing on
it see whole values (a race on a plain load and store is undefined
behaviour). A struct or option global of plain values is more than one
word, which no atomic access covers, so it is `unsafe`-only like an
owning one (h272).

State that every thread shares and safe code reaches lives in a global
**set at start** instead: `: ( Locked T ) g ( make )` calls `make`, a
function of no arguments, once before `main`, and nothing writes `g`
afterwards. Its type must synchronise itself (`( Locked T )`,
`( Arc T )`, `( Channel T )`, `Mutex`, `Cond`, `Semaphore`) — a
`( Vec T )` pushed from two threads through it would race, so it is
rejected (h263). A read borrows the handle; `: ( Locked T ) h g`, a
struct field or a `^ g` clone it, so the global is never moved or
dropped.

### Parameter passing conventions

A parameter has one of three conventions:

| Convention | Spelling | Meaning |
|---|---|---|
| `in` | default (may be written) | an immutable borrow; a struct argument is copied into the callee's frame |
| `inout` | `inout T x` | an exclusive mutable borrow; passed by address |
| `sink` | `sink T x` | the callee takes ownership; the caller's binding is consumed |

**`inout`.** The argument must be a mutable (`: ~`) binding or a field of
one (`. obj field`), or a field through a pointer (`. p field` with `p` a
`*S` binding or parameter: the pointer is not reassigned, the memory it
points to is written), and the callee's writes land in the caller's storage.
A value assigned through an `inout` parameter replaces the caller's and
drops what it overwrites — a `String`, a `Vec`, a struct, and an option or
a result that owns something alike (h199). What is assigned becomes the
caller's: a local the callee owns moves over (its own drop no longer runs,
h200), and a parameter the callee only borrows is copied in, since its
caller still owns it (h201). A field the callee hands to a consumer, or
takes with `mem_take`, is emptied in the caller's struct, so nothing is
released twice. Reassigning an `inout` raw string (`s`) is an error, because the
callee cannot know whether the caller's old string is owned.

```nurl
: Counter { i n i max }
@ bump inout Counter c → v { = . c n + . c n 1 }
: ~ Counter c @ Counter { 0 10 }
( bump c )                       // c.n is now 1 in the caller
```

**`sink`.** The callee owns the argument and drops it unless it moves it
on (returns it, stores it, passes it to another `sink`). Using the
caller's binding afterwards is a use-after-move.

```nurl
$ `stdlib/core/vec.nu`

@ give_away sink ( Vec i ) g → v {}   // g is dropped here, by the callee
: ( Vec i ) xs ( vec_new [i] )
( give_away xs )                       // xs is consumed
```

**Inferred `sink`.** A parameter does not have to be spelled `sink` to be
one. If the body consumes it (releases it, stores it in an owner, passes
it — or one of its fields, or its payload — to another `sink` position)
or returns it,
the parameter is a `sink` for every caller (a function that takes a
field of its parameter owns the rest of it, and drops it on the way out):

```nurl expect-error="use of moved value 'xs'"
$ `stdlib/core/vec.nu`

@ dispose ( Vec i ) xs → v { ( vec_free [i] xs ) }   // param 0 is a sink
: ( Vec i ) xs ( vec_new [i] )
( dispose xs ) ( dispose xs )                          // use-after-move at the second call
```

Inference is decided after the whole module is compiled, so the order in
which functions are defined never changes the result. A function's name
and return type are never evidence of consumption. A destructor that
releases raw memory declares its consuming parameter explicitly.

**Closure parameters** are always borrowed (§7.5).

**Methods.** A method call is a call of the impl its receiver's type
selects, and the conventions above, declared or inferred, are that
impl's. A call through a trait object (`%Trait`) reaches whichever impl
the object holds, so every impl of the method must take each parameter
the same way: an impl that keeps an argument while another only reads it
is an error at the call (declare the parameter `sink` in the trait, or
keep a copy), and an impl may not keep its receiver, which the object
only lends. A raw-pointer parameter (`*T`) hands nothing over: storing it
is the raw code's business.

**Raw strings.** A raw string (`s`) parameter of safe code is a `sink`
only when it is declared one — never inferred: a function that hands its
borrowed `s` parameter on to a consumer (`string_adopt`, another `sink
s`) hands over a copy, and its caller keeps, and later frees, its own
string. A declared `sink s` parameter is the callee's own string, exactly
like a local bound to a fresh one: released on every way out unless it
moves on (returned, handed to another `sink`, adopted as a `String`), and
its views end with it. The caller of a `sink s` hands over a string it
owns — its own binding's (which then leaves the binding) or a fresh
temporary — and a copy of anything else: a literal, a view of a `String`,
a borrowed parameter, a field, a result a callee lent, or a result owned
on only some paths (decided per call, at run time). So no callee ever
adopts or frees memory it was only shown, and nothing is released by
hand. (`unsafe` code and the standard library manage a raw `sink s` by
hand, and their consuming parameters are still inferred.)

One implementation limit remains: an owned slice, or a struct whose
literal gave it one, cannot be passed to an explicit `sink` parameter —
wrap it in a `Vec`.

## 2. The ownership rules

The rules below are checked on every compile. They are a static analysis
only: they never change generated code, so an accepted program compiles
to the same IR with or without them. A violation is an `error:` that
stops the build, and every violation in a run is reported.

`--no-borrowck` is deprecated and prints a warning: a program compiled
without the checker is not held to the rules, so nothing guarantees it is
memory-safe. A correct program the rules reject is a bug worth reporting.

The rules' core — owned `Vec` trees, moves and drop flags, `sink`,
`inout`, borrows and views, reallocation, and calls checked against
function summaries — is proven sound in Lean
([`formal/`](../formal/README.md), phase A1): a well-typed core program
never touches freed or out-of-bounds memory. Phase A2 adds structs and
enums, closures and trait objects with their captures, panics with
unwinding and `recover`, the drop journal, and leak freedom
(`A2.memory_safe`, `A2.no_leak_end`). [`formal/RULES.md`](../formal/RULES.md)
gives the formal rule for each rule below.

### 2.1 Moves — use after move

An owned value moves out of a binding when it is:

- passed to a `sink` parameter (explicit or inferred),
- stored into an aggregate literal, an Option, a container or a field,
- sent through a channel,
- returned,
- copied into another immutable binding (§2.2),
- captured by a closure that runs on another thread or fiber.

Reading the binding afterwards is an error:

```text
error: use of moved value 'v' - it was consumed at line N
```

Rebinding the name (`:` or `=`) makes it usable again.

A value moved on only **some** paths is *maybe-moved*. Reading it is an
error too, because on the path that moved it the read touches released
memory:

```text
error: use of possibly-moved value 'x' — it was consumed on only some
       paths, at line N
```

The analysis follows the program's paths:

- `break` and `continue` end their path: a value released before a
  `break` is still readable after the loop on the other paths;
- a binding declared in a loop body, the foreach element included, is a
  fresh binding in every iteration;
- a closure that releases a capture does so when it runs, so the capture
  is maybe-moved after the closure's first invocation;
- a module-level global is not tracked, since any call may reassign it.

Within one call the arguments run in order, and a move one of them makes
counts for the others. No other argument may hand the callee the moved
binding or a view of it — `( f m m )` with a `sink` and a borrowed
parameter, `( f ( string_data s ) ( eat s ) )` — and none may read it at
all after an earlier argument released it as it ran (`( g ( eat s )
( string_len s ) )`). A plain scalar computed from it before the callee
takes it is fine: `( take s + ( string_len s ) 1 )`.

```text
error: 'm' is moved by argument 1 of 'f' and also used by argument 2
```

A value with nothing to release (a struct of scalars, an enum of unit
variants) is copied, never moved.

### 2.1b Releasing what the compiler releases

Inside an `unsafe` function, `nurl_free` on a binding the compiler already
drops (an owned string, slice, `Drop` value or owning struct) would free
it twice, and is an error:

```text
error: 'piece' is auto-dropped at the end of its scope, so freeing it
       here frees it twice - delete this call
```

The rule recognises the binding through casts (`( nurl_free # s piece )`)
and applies inside closure bodies too. Only memory the compiler does not
track (a raw `nurl_alloc` block, a pointer from foreign code) is released
with `nurl_free`.

### 2.2 Second names

A value can acquire a second name in several ways. Each one is decided
the same way: an owner moves, a borrow is copied.

- `: ( Vec i ) b a` moves `a` into `b` when `a` owns its value; `a` is
  then dead.
- `: ~ ( Vec i ) cur a` is a *cursor*: a mutable working binding that
  borrows `a` (§7.6).
- `= b a` moves an owner and copies a borrow, like `:`.
- A `?` / `??` that selects one of several bindings
  (`: ( Vec i ) chosen ? flag a ( make )`) moves the selected owner on the
  paths that select it. The other paths keep their own owners.
- A call whose callee may return one of its arguments takes that argument
  as `sink` (§1), so the caller's binding is consumed rather than
  aliased.

So two live names can never both own one buffer.

### 2.3 Stack references must not escape

A closure that captures a `: ~` mutable multi-field struct, or any `: ~`
binding that it assigns or hands to an `inout` parameter (h298), captures
it by pointer into the enclosing frame
(a callback can count into its caller's binding; `recover \ → v { = out
( f ) }` hands a result out). Such a value is a *stack reference* and
must not outlive that frame. The checker tracks the scope depth a stack
reference points into, through bindings, assignments, field stores,
aggregate and closure literals, and `?` / `??` joins. An escape is an
error when a stack reference reaches:

- a `^` return,
- a container (`vec_push`, `vec_insert`, `vec_set`) or a thread
  (`thread_spawn`),
- an assignment into a binding of a longer-lived scope.

```text
error: returning a value that references a stack binding by pointer
         - it dangles after this function returns
         (move the captured data to a heap-backed handle)
```

Closures that capture by value (an immutable `:` capture, a binding the
closure only reads) never escape this way. A
counter that must outlive the frame, or be shared with a thread, is an
`Atomic` or a `Locked` (std/atomic.nu, std/thread.nu).

### 2.4 Exclusive access for `inout` arguments

An `inout` argument is an exclusive mutable borrow for the duration of
its call. Passing the same binding again in the same call, as another
`inout` or as an ordinary argument, is an error:

<!-- doctest-prelude
: Counter { i n i max }
@ swap_counters inout Counter a inout Counter b → v { : i t . a n = . a n . b n = . b n t }
: ~ Counter c @ Counter { 3 10 }
-->
```nurl expect-error="'c' is both mutably borrowed"
( swap_counters c c )    // error: 'c' is both mutably borrowed
                         //        and aliased by another argument
```

Reads of the binding inside other arguments (`( grow v ( vec_len v ) )`)
are evaluated before the call runs and are allowed.

A binding that does not own its value — a `: ~` copy of a parameter
(`: ~ T c p`) or of another binding (a cursor, `: ~ T cur root`), a field
read (`: ~ T h . o h`), what a call lends (`: ~ T s ( arc_get [T] a )`) —
shares that value: it owns none of it. It may be changed in place, and a
field assigned in this function leaves the old value to the owner; but it
may not be passed `inout` to a function that gives that parameter, or an
owned field of it, a new value (directly or through a function it calls):
the callee would release what the owner still holds, and the owner would
read and drop it again (h295, h367–h369). The check follows every path: a
binding that borrows on one of them is refused. `: ~ T c ( mem_dup p )` is
a value of its own, and so is one given a fresh value (`= cur ( vec_new )`)
before the call, or a match's payload bound out of the match (`: ~ T x ??
r { T v → v … }`). A copy of a value with a `% Drop` of its own, taken from
a local that owns it outright (a `let`, a `sink` parameter), holds that
local's drop: such a call makes it the owner, and the local is moved there
— reading it afterwards is a use of a moved value (h370).

The same holds for any argument a callee may change, `inout` or not —
what its summary says it mutates, reallocates or drops elements of: that
container cannot also reach the call through another argument, as the
same owner or as a view or borrow of it. Inside the callee the two names
are unrelated, so the change would leave the other one dangling — a
function that grows `v` and then reads `s`, called as
`( grow_then_read v ( slice_from_vec [i] v ) )`, reads freed memory. The
message names both arguments; take a copy, or split the call.

### 2.5 Iterator invalidation

A foreach loop `~ x xs { … }` borrows `xs` for its body. Mutating `xs`
inside the body is an error:

<!-- doctest-prelude
$ `stdlib/core/vec.nu`
: ~ ( Vec i ) xs ( vec_new [i] )
-->
```nurl expect-error="cannot mutate 'xs'"
~ x xs { ( vec_push [i] xs x ) }   // error: cannot mutate 'xs'
                                   //        while iterating over it
```

This covers the stdlib mutators (`vec_push`, `vec_insert`, `vec_remove`,
`vec_pop`, `vec_clear`, `vec_set`, `vec_reserve`, `vec_extend`,
`vec_free`, `vec_swap`, `vec_reverse`, …), an `inout` argument naming the
container, and any function that mutates the container passed to it or
takes it (`sink`), wherever that function is defined. Giving the
container a new value in the body (`= xs …`; for `~ x . r xs`, also `=
. r xs …` or `= r …`) is an error too, and so is running a closure there
that assigns it or hands it to such a function (h416–h420). A counter loop (`~ < k n { … }`)
borrows nothing, so `vec_set xs k v` inside it is allowed.

### 2.6 Loop-carried moves

A loop body runs more than once. A binding that existed before the loop
and is consumed in the body, without being rebound before the next
iteration, is moved when the next iteration reads it:

```nurl expect-error="use of moved value 'xs'"
$ `stdlib/core/vec.nu`

: ( Vec i ) xs ( vec_new [i] )
: ~ i k 0
~ < k 3 { ( vec_free [i] xs ) = k + k 1 }   // error: use of moved value 'xs'
```

Three shapes are fresh in every iteration and are allowed: consuming the
foreach element, consuming a binding declared in the body, and consuming
an outer binding that the body rebinds before its next read.

### 2.7 Escape through a callee

A function that stores a parameter in a container or hands it to a thread
makes that parameter *escaping*. Passing a stack reference (§2.3) to an
escaping parameter is an error, as is passing it on to another function's
escaping parameter, at any depth:

<!-- doctest-prelude
$ `stdlib/std/thread.nu`
: Counter { i n i max }
-->
```nurl expect-error="references a stack binding"
@ detach ( @ v ) cb → v { ( thread_spawn cb ) }   // param 0 escapes
: ~ Counter c @ Counter { 0 10 }
: ( @ v ) f \ → v { = . c n + . c n 1 }          // captures a `: ~` struct by pointer
( detach f )   // error: passing a value that references a stack binding
               //        by pointer to 'detach' - it escapes …
```

Passing a field of a stack reference counts the same. A parameter the
callee only reads or invokes does not escape. Summaries are final only
after the whole module is compiled, so forward and generic callees are
judged the same as functions defined above the call.

### 2.8 Escape through a return

A function that returns one of its parameters hands a stack reference
straight back. The result of such a call carries the reference, so the
rules of §2.3 and §2.7 apply to it:

<!-- doctest-prelude
: Counter { i n i max }
-->
```nurl expect-error="references a stack binding"
@ id ( @ v ) cb → ( @ v ) { ^ cb }
@ make → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( id f )              // error: returning a value that references
                            //        a stack binding by pointer …
}
```

A parameter can leave through a struct field (at any depth), a closure's
captured environment, a local binding, another function that returns it,
or one arm of a join; all count. A function that takes a reference and
returns a fresh value is not a passthrough.

### 2.9 `--strict-borrowck`

`--strict-borrowck` adds three audit checks on top of the rules:

1. an `inout` binding read by a sibling argument in any form (a field
   read, a read nested in another call), not only as a bare name;
2. a raw pointer taken with `# *T` from an owned binding that may outlive
   the binding's drop;
3. consuming a binding whose value may have passed to another name on
   some path.

These checks flag code that is safe, so they are off by default. The
guarantee of §6.2 does not depend on them.

### 2.10 Views end when their source may reallocate

`( string_data s )` and `( vec_data v )` return a *view*: a pointer into
the container's buffer. A view ends when its source is mutated in a way
that may reallocate (`vec_push`, `vec_extend`, `vec_reserve`, …) or is
released, moved or reassigned. Reading a view after that is an error:

```nurl expect-error="'p' borrows from 't', which ended"
$ `stdlib/core/string.nu`

: ~ String t ( string_from `a heap string` )
: s p ( string_data t )
( string_push_str t `, grown` ) // may reallocate
( nurl_println p )              // error: 'p' borrows from 't', which ended
                                //        at line N — it was passed to
                                //        'string_push_str', which may move
                                //        or free its buffer
```

Fetch the view again after the mutation. A view stays a view wherever it
goes: held in a `Slice` (`slice_from_vec`, `slice_of_str`, a CSV cell
from `csv_table_view`), a struct, an Option or a container, captured by a
closure, stored in a global or returned from a function, it is still a
view of its source and ends with it. Handed to a function that stores it
into another of its arguments — the first, or one passed `inout`,
wherever it sits (`( add h ( slice_from_vec [f] v ) )` with `add` pushing
the slice into `. h fs`) — it makes that argument's value hold the view,
as a `vec_push` written in place would. The rule applies in `unsafe`
code too, because it is decided from the program text, not from the
capacity at run time. A mutation inside one `?` arm does not end a view
in the other arm, and a function that mutates the container passed to it
ends views exactly as an inline mutation does, wherever it is defined.

A string binding (`s`) is a view or an owner. One that owns its buffer —
bound to an allocating call, or a mutable one born from a literal or an
owned string — is an owner like a `String`: a copy of it (`: s y x`, or an
argument a callee may hand back as is) is a view of its buffer, and ends
when the binding is given a new value (which frees the buffer) or ends.
Handed back by name, the binding's buffer goes to the caller. A value
assigned to an owning binding is copied unless it is fresh, so the binding
never borrows what it is given.

### 2.11 Closures hold their captures

A closure holds every value it captured for as long as it can run.
Invoking a closure reads all of its captures, so releasing a capture
through its original name and then invoking the closure is a use after
move:

```nurl expect-error="use of moved value 'v'" expect-error="closure 'f' still holds 'v'"
$ `stdlib/core/vec.nu`

: ( Vec i ) v ( vec_new [i] )
: ( @ i ) f \ → i { ^ ( vec_len [i] v ) }
( vec_free [i] v )
( nurl_println_int ( f ) )     // error: use of moved value 'v' …
                               //        The closure 'f' still holds 'v'
```

This holds for a direct call, for a call through a function that invokes
its closure parameter, for a closure captured by another closure, and for
a mutation inside the body as much as a read. Running a closure is also
what its body does to its captures: one that changes, reallocates or
drops elements of a capture ends the views and borrows of that capture at
the call — made directly, or by a callee the closure is handed to.
Capturing an already-released value is rejected at the closure literal.

A closure that changes a capture this way is a second route to it, so
the exclusive-call rule (§2.4) covers it. Handed to a call — or called
itself — it may not meet another argument that reaches that capture:
the binding itself, a borrow or a view of it, or another closure that
captured it. Inside the callee the two would be unrelated names, and the
change through the closure would leave the other dangling (h274–h277,
h280). Hand the callee what it needs as a parameter instead — the
WebSocket deflate loop gives its handler the context it reads with
(`ws_serve_messages_deflate_with_context`). A closure that runs a
closure it captured does what that one does (h278), and a closure whose
body changes a capture may not also hold a view or a borrow of it
(h279). Inside a closure body, running a closure the caller chose — a
closure parameter, or a closure a parameter holds in a field or an
element — ends the views of every binding the closure captured by
reference: its captures are not known here, so it may re-enter this
closure and grow what it captured (h285–h287). A closure
stored into a struct, or handed to a function that keeps it, makes that
owner depend on the captures: releasing a capture while the owner may
still run the closure is an error. Loading a closure value, and dropping
the closure's own environment at the end of its scope, is not a use.

A closure holds a copy of the handle of a value it captures by value —
and so does one a call returns over an argument it captured without
taking it over (`: f ( mkc x )`, an iterator from `iter_from_vec` or
`map_iter`), or through a combinator that took such a closure over
(`( iter_map ( iter_from_vec v ) g )`). It reads through that copy when
it runs, so it ends when the value does: the binding released, given a
new value — with `=`, or by a callee that may replace the `inout`
argument or an owned field of it — or a field of it replaced. The value
growing, or its elements set, removed or cleared, does not end it; the
closure reads what the value holds then (h299–h310). Returning such a
closure past the value is rejected as returning any view is. A closure
stored into an owner — a container, a struct field — copies in what it
holds a handle of, so the owner does not depend on that.

The mechanized proof (`formal/A2`, [`RULES.md`](../formal/RULES.md))
covers this rule, with one difference on the conservative side: the
calculus admits, beside a closure that changes a binding, another closure
that changes it the same way; the compiler rejects any other route to it.

### 2.12 A stored value belongs to its owner

A value stored into an owner (an aggregate literal, a container through
`vec_push` or `map_set`, a function that keeps its parameter) belongs to
that owner. Releasing it again through the original name is an error:

```text
error: 's' is consumed here, but its value was stored into an owner at line N …
```

To hand a value on and keep one, store a copy (`string_clone`,
`vec_clone`, `mem_dup`).

### 2.13 A raw string in a value is a view

A raw string (`s`) held by a struct, an option, an enum, a slice or a
container is a view: it owns nothing, and nothing releases what it points
at. Owned text in a value is a `String` (a field, a payload, a
`( Vec String )`), which releases itself wherever the value goes. So in
safe code a *fresh* string — the result of a call that hands its string
over (`nurl_str_cat`, `nurl_str_int`, `nurl_read_file`, …) — cannot be
stored there, nor handed to a parameter that keeps it (`vec_push [s]`,
`map_set`):

<!-- doctest-prelude
$ `stdlib/core/string.nu`
: Rec { s name i n }
: s a `a`
: s b `b`
-->
```nurl expect-error="owned by nothing"
: Rec r @ Rec { ( nurl_str_cat a b ) 1 }   // error: a fresh string stored
                                           // here is owned by nothing
```
<!-- doctest-prelude
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
: i k 7
: ~ ( Vec s ) names ( vec_new [s] )
-->
```nurl expect-error="handed to 'vec_push'"
( vec_push [s] names ( nurl_str_int k ) )  // error: … handed to 'vec_push',
                                           // which keeps it
```

Hold a `String` instead, or bind the string first — `: s x ( nurl_str_cat
a b )` — and store the binding: the value then holds a view of `x`, which
the walk keeps from outliving it (§2.10). A string binding that owns its
buffer is an owner like a `String`: a copy of it is a view of the buffer,
and a closure or a struct handed back holding one is checked like any
view. A parameter that takes a string over says so with `sink`, and
adopts it (`string_adopt`, §1). `unsafe` code and the standard library
manage raw strings by hand, and there a field a struct literal gave a
fresh string is the struct's to release.

## 3. Outside the rules

The rules cover all safe code. What they do not check is a stated
boundary:

- **The body of an `unsafe` function.** Raw pointers, pointer casts, the
  raw-memory primitives and foreign calls are allowed only there, and the
  function's author vouches for it (spec §3.3d).
- **Positive thread-safety assertions.** `% Send T { }` and `% Sync T { }`
  stop the derivation at `T`: nothing inside is examined, and what a
  `Sync` type holds is not frozen through it (§6.5). Asserted wrongly,
  they let two threads race an `Rc`'s count or a `Cell`'s bytes, so
  outside the standard library they are written `unsafe % Send T { }` /
  `unsafe % Sync T { }` — an unchecked promise, spelled like an unchecked
  body — and `nurlc --unsafe-report` lists them. Every other marker is
  checked code and needs no `unsafe`: `% NotSend`, `% NotSync` and
  `% Frozen` only add checks (a value that may not cross, may not be
  shared, or lends only read-only views), and `% Resource` only changes
  when a cycle is collected (§7.7). A safe module may write
  `% Frozen T { }` on a type with a `Cell` inside: the compiler then
  rejects more, never less — what a frozen `T` lends is read-only, and
  the `Cell` still does not make `T` `Sync`, so it cannot reach two
  threads through an `Arc` or a read guard either (`h317`).
- **Foreign-function claims.** A foreign (`&`) declaration's `in`, `sync`
  and `nocapture` (spec §7.2) say what the C code does with a pointer —
  only reads it, changes it only atomically or under its own lock, keeps
  nothing of it in its result — and every call's checks take them at
  their word: a frozen view may be handed to `in` or `sync`, a temporary
  is released after an `in` call. A foreign function is called only from
  an `unsafe` function outside the standard library, and its claims are
  listed by `--unsafe-report` beside it.
- **Logical leaks.** A cache or map that a program keeps growing and never
  shrinks holds memory that is still reachable. That is program
  behaviour, not a leak the memory model can see.

A panic is not outside the model: what a panic abandons is reclaimed
(§7.2).

## 4. Practical guidance

- **Read the diagnostic as a rule and a fix.** It names what moved or
  ended where, and the change that satisfies the rule: clone the value,
  keep the owner in an outer scope, send it through a channel, declare
  the parameter `sink`.
- **Copy to keep.** Handing an owned value to a consumer and keeping it is
  not possible; that is the move. Take a copy (`string_clone`,
  `vec_clone`, `mem_dup`) or restructure so the consumer borrows.
- **Use the safe element access.** `vec_at`, `vec_put` and `vec_get` are
  bounds-checked and compile to the same loop as raw pointer access when
  the loop only reads. A loop that writes one `Vec` while reading others
  (a kernel: `c[k] = a[k] + b[k]`) indexes `Slice`s of them instead
  (`slice_from_vec`, `slice_at`, `slice_put`): a slice keeps its data
  pointer and length in registers, so the bounds checks leave the loop
  and it vectorises exactly as raw pointer code does, where `vec_at` /
  `vec_put` re-read both from each Vec's control block past every store.
  A matrix row, or any run a loop walks to its length, is a
  `slice_window` (`slice_prefix` from 0): it is checked once, and the
  loop over it needs no check per element. Several windows of one `Vec`
  may be read and written together when its elements own nothing.
  `vec_data` + `unsafe` is not faster than either — `mlp`'s training loop,
  rewritten over windows, runs 26% faster than its raw-pointer form.
  A buffer a library owns is lent the same way: `gpu_host_f32` views a
  GPU staging buffer as a `Slice f32` that lives no longer than it, and
  yoloe's mask and image-packing loops over windows of it run 10–30%
  faster than the `nurl_peek_f32` / `nurl_poke_f32` loops they replace.
  A file is lent the same way: `file_map` (stdlib/std/mmap.nu) maps it
  and `mapped_bytes` views it as a `Slice u` held to the `MappedFile`;
  binary formats read and write little-endian words in a byte view with
  `slice_u16_le` / `slice_u32_le` / `slice_u64_le` and their
  `slice_put_*` twins — one check per word, the bytes fused into one
  load by LLVM. safetensor's dequantiser reads that way, 6–24% faster
  than the pointer loops it replaces; a view that has to outlive its
  storage becomes a Vec of its own with `slice_to_vec`.
- **Put a contract where it is kept.** A function that only its caller
  can make sound (an address it is handed, a size it trusts, kernel code
  it runs) is `raw @` (spec §3.3e): the caller that allocated, checked or
  wrote it is the `unsafe` one, and the code above that stays safe.
- **Share mutable state through a handle.** Between threads, send it
  through a `Channel` or keep it in a `Locked` (§6.5); an `Arc` shares a
  value nobody changes. Independent work over an index range is
  `par_map_index n threads f` (stdlib/std/par.nu): the results come back
  by index, with no result slot handed to a thread by its address. Within a thread, to share a closure beyond the
  data it mutates, move that data into a heap-backed handle and capture
  the handle by value.
- **Graphs.** A graph that is built once can be an `Rc` / `Arc` structure.
  A large graph that is rewired constantly is simpler and cheaper as a
  `Vec` of nodes addressed by index (§7.7).

## 5. Summary of checks

| Fault | Where it is caught |
|---|---|
| Use after move, maybe-moved read | §2.1 |
| Double release (two owners of one buffer) | §2.1, §2.2, §2.12 |
| `nurl_free` of a compiler-dropped value | §2.1b |
| Stack reference escaping its frame | §2.3, §2.7, §2.8 |
| Aliased `inout` argument | §2.4 |
| Mutating a container while iterating it | §2.5 |
| Consuming an outer binding in a loop | §2.6 |
| Stale view after reallocation, wherever the view was put | §2.10 |
| A container changed by a call while a view of it is another argument | §2.4 |
| A closure run that changes a capture with live views | §2.11 |
| A closure that changes a capture, beside another route to it in one call | §2.11 |
| A closure read out of an owner, called after the owner changed | §7.5 |
| A borrowed part of a temporary that cannot be copied | §6.2 |
| A view of a temporary kept past the call that uses it | §1 |
| Releasing a value a closure still holds | §2.11 |
| Borrow used after its owner moved, ended, or was reassigned | §6.2 |
| Non-shareable value crossing a thread boundary | §6.5 |
| Changing an `Arc`'s payload, which clones read without a lock | §6.5 |
| Cycle of thread-shared handles | §7.7 |
| Out-of-bounds element access | bounds-checked (`vec_at` panics, `vec_get` returns None) |
| Raw pointers, casts, raw memory, foreign calls | only inside `unsafe` (spec §3.3d) |
| A raw pointer handed out by a call, a caller-given length, a C `FILE*` | only inside `unsafe` (§6.2) |
| A null string read as text | reads as the empty string |
| An allocation size that cannot be represented | panics before allocating |

Integer division and remainder by zero panic with a message; they are not
undefined behaviour.

## 6. The guarantee

### 6.1 Two layers

Memory safety rests on two mechanisms:

1. **Auto-drop (§1, §7) makes the base safe.** Every value has one owner
   at a time, tracked by a drop flag that a move clears (§7.6), and a
   borrowed value stored into an owner is copied. The compiler therefore
   never releases a value twice of its own accord.
2. **The ownership rules (§2, §6.2) reject the programs** in which the
   programmer's code would: a value read after it moved, a borrow used
   after its source ended, a reference that outlives its frame, state
   shared between threads without synchronisation.

### 6.2 The guarantee

**Every program the compiler accepts, outside the bodies of `unsafe`
functions, is memory-safe and leak-free:** no use after free, no double
free, no read through a dangling view, no out-of-bounds access, no data
race, and nothing it allocated is left unreleased, on the panic path as
much as the normal one (§7.2). Rc cycles are collected (§7.7).

0.71.0 named one exception: a `Slice` built from a `Vec` was not tracked
as a view of it (hole probe `tools/fuzz/holes/h32`). It is closed: views
are now values (§2.10), tracked through every place one can be put.

**No hole is known open.** The last ones are closed. *A field of a
call's lent result handed to a `sink`* — `( string_free . ( box_get b )
name )` — went over as is, and the owner released it again (agora #150,
h424–h425): the callee is handed a copy now, as a bare lent result is
(h228), unless the field left with the read. *An option of a
String kept by a callee* — `( vec_push [?String] out o )`, directly or
through a helper — was not tied to the container's life the way a String
or a struct is ("stored in 'out'"): the row that ties them was written
only for handle types (agora #149, h421–h423). *A `~` loop's
container released in its body* — given a new value (`= xs …`, `= . r
xs …`), handed to a callee that takes it, or reassigned by a closure the
body runs — released what the loop was reading (agora #147, h416–h420):
the foreach rule asked only for container mutators and `inout`
arguments, and now asks for those too (§2.5). And an `inout` callee that
hands a field of its parameter to a callee that takes it empties the
caller's field; its replacement summary now says so, so a borrow of the
field the caller holds ends at the call (§2.4). *An option
parameter's payload handed back* — as the value of a `??` (`^ ?? o { T s
→ s F → … }`), through a local over the parameter, in a generic — left
the caller's option holding what the function gave away (agora #146,
h408–h415): the parameter was only kept. A parameter whose value a
function moves on through a cursor over it is an inferred `sink` now,
as a parameter whose field it takes is. *A field handed to a
callee that takes it* was taken from bindings that could not give it
(agora #145, h389–h404). A function that hands a field of its by-value
parameter to a consumer owns the parameter and drops the rest of it, but
its caller's binding was not moved, and the caller read the struct after
the call: such a parameter is an inferred `sink` now (§1, Inferred `sink`). A `vec_at`
copy, a binding read out of another's field and a closure's capture have
the field emptied only in their own copy, while the owner releases it
again: handing such a field to a callee that takes it is rejected (§7.6).
And a closure or a view over a struct outlived a field of it handed to a
`sink` — the borrow sweep took the hand-over for a change of elements,
which a view of the binding outlives; it ends them as a field replaced
does. *A field a closure gives a new value through its by-reference
capture* leaked the value it held (agora #144, h405–h407): it is released
under the binding's drop flag, which the env carries, and a binding that
borrows its value cannot be given one there — the value stored would have
no owner — so that assignment is rejected (§2.11).

**Closed before it:** *a closure a
function returns over a parameter* it captured without taking it over is
a view of the caller's argument (h299), and the function's summary of it
(`retclo`) recorded only a closure literal written in the `^` over the
parameter by name. Bound to a local first, joined, given a new value, or
over a local view of the parameter (`: s v ( string_data s ) ^ \ → v {
… v … }`), it was the caller's to release the argument under — and the
closure read freed memory. What a returned value that may hold a closure
lends is now read off its source expression, through the closures, views
and borrows of the frame it names (agora #141, h384–h388). *A `UdpSocket`*
was the runtime record's address with no drop: read after `udp_close` it
read freed memory, and a socket never closed leaked its record and fd. It
is a handle with a drop now, as every other resource is; `udp_close` only
stops the socket early, and its last owner releases it (agora #139,
h382–h383). Handing one to a fiber as its only owner needed a way to move
a payload out of an option binding: a closure handed to a thread or
fiber that captures a match's payload, or a binding read out of one,
moves the option's owner with it, so the crossing check (§6.5) sees one
owner (agora #140). *A view of a call's temporary argument kept past the
statement* — `: s v ( first ( string_from … ) )`, a closure over the
temporary, a return or an assignment of the view, a callee that keeps
it — left the temporary owned by nothing: it leaked. Such a view is
rejected now (§1, Temporaries; agora #138, h378–h381).

**Closed before them:** *an `inout` argument whose
binding does not own its value*, is closed (agora #135, h367–h370): a
cursor over another binding, a field read or a value `arc_get` lends,
handed to a callee that gives that parameter (or a field of it) a new
value, released what the owner still held. The rule had covered only a
`: ~` copy of a parameter (h295); the walk now refuses any argument in a
borrow state on any path (§2.4).

The one before it, *a share made before a library handle moves to a
thread*, is closed (agora #121, h349–h358). A library
handle over a counted block (§7.6) is copied by sharing, and its copies
are one state. A copy made *before* the handle moved — `( PNCounter_share
a )`, a literal that stores `. h c`, a `Vec` or a closure holding one, a
copy taken out of a `Locked` — is another owner no checker can follow to
the move, since any store of a borrowed handle makes one. So the
crossing checks at run time: a value going to another thread carries
every owner of such a handle it reaches, or the crossing panics (§6.5).

**Every other hole is closed.** The 0.72.0 and 0.73.0 release reviews found safe programs
the compiler accepted and that leaked, freed memory they did not own or read
freed memory; converting the packages' handles to `Arc`, removing
gratuitous `unsafe` across `packages/`, modelling closures for the
mechanized proof and making closure types generic arguments found more;
all are closed, each a probe CI now holds (h142–h630):

- an owner moved by one argument of a call and read by another (§2.1),
  and a keyword-argument call to a forward function that consumes its
  argument;
- a raw string handed to `string_adopt` or a `sink s` parameter: only a
  declared `sink` takes a raw string over, its callee releases it, and a
  caller hands over its own string or a copy (§1);
- a view that left through a helper's return value (`^ ( pick x )`, a
  closure or a `Vec` the helper built): a returned call result is the
  caller's own string, or a copy, and a call's result holds views of what
  the callee lends, stores or hands back inside it;
- a view stored into storage the caller holds — a `Vec` parameter, an
  alias of one, a field of an `inout` struct — or into a field of a
  struct that outlives the binding viewed: rejected;
- `mem_forget`, `mem_take`, `mem_put_back` and the `rcbox` primitives in
  safe code: `unsafe` only, as spec §3.3d says;
- a destructor that panicked (it ran twice), reassigned a field of its
  receiver (the old value leaked) or handed its receiver to a disposer
  (its fields leaked), and a closure defined inside a `% Drop` impl (it
  ran the impl's epilogue): see §7.6;
- a closure value called with a fresh string (the string leaked);
- a source whose path merely contains `/stdlib/`, which was compiled as
  the trusted standard library: only a file inside the real standard
  library tree (where `stdlib/` imports resolve) is trusted.
- a zero value of a type that has none: a struct literal that left out a
  `Vec`, a library handle or a closure field, an enum literal that left
  out such a payload, an option or result literal that gave only its tag,
  a bare variant whose payload is one, `vec_zeroed` / `rc_zero` / … of
  one, or a number where one was expected (`: ( Vec i ) v 0`, a `0`
  argument). Each made a value with no control block, shared block or
  code, and the first use read or called through null; outside `unsafe`
  none of them is accepted (spec §4.1);
- a `;` defer that used a field a returned literal had moved out of its
  struct (`^ @ ?V { T . x f }`): under a defer the literal takes a copy and
  the struct keeps its own;
- a drop hook with nothing of its own to do (`@ H_drop sink H h → v {}`,
  the hook a handle over an `Arc` needs) dropped its receiver at the end
  of the hook, through the drop glue that calls the hook: unbounded
  recursion, a stack overflow at `-O0` and a hang at `-O2`. A drop hook is
  its receiver's destructor; the fields go afterwards by drop glue;
- a field taken out of a struct *cursor* — a binding copied from another
  (`: E b a`, `: E m m0` over a `??` payload), which still drops its own
  slot — by a returned literal, a binding read from it, or a `sink`
  argument: the owner freed what the taker now held. The take empties the
  field in each owner the cursor is over (a parameter owner is consumed
  with it), and a literal copies a field nobody gave up while the struct
  still holds that very handle;
- a returned literal that took a closure field of a struct this function
  owns skipped the struct's drop, leaking every other field it held: the
  closure moves out as a handle field does;
- a `?` join whose arm is a call answering ownership per call, copied
  because the last identifier inside the call was an owned string: the
  result the call handed over was never released. It is freed right after
  the copy.

Making module state and raw-pointer records manage themselves (field
stores through a pointer that replace, module globals that own) found
nine more, closed the same way (h195–h203):

- a closure stored into a struct field or a slice kept only a view of a
  `String` its maker's frame owned, and read it after the frame ended:
  the stored environment now owns its captures (§7.5);
- a binding read out of a field (`: String b . s name`) read freed memory
  once the field was assigned, here or through an `inout` parameter: the
  replaced value is handed to that binding instead of dropped;
- an option or a result field, and a whole `inout` option, assigned over
  without dropping what it held (§1);
- a local option moved into an `inout` place, and a borrowed parameter
  assigned over one, each leaving two owners of one value (§1);
- a raw-string global assigned the result of a call that answers
  ownership per call — or a `?` join of one — recorded the fresh string
  as not its own, and each reassignment leaked the one before: the global
  takes over the owner the call's guard slot proves (§1);
- a mutable string binding declared from a `?` join of views or literals
  (`: ~ s r ? c a b`) and then advanced like a cursor (`= r ( rest_of
  r )`) had no owner slot, so no fresh string assigned to it was ever
  released: it gets the empty one a cursor declared from an identifier
  or a call already had.

Making the TCP handles close themselves found four more (h204, h205,
h207, h208), and probing h205's rule a fifth (h206):

- a closure a fiber or a thread runs, capturing a `??` arm's payload (or
  a parameter its caller frees), only viewed it, and the fiber read what
  the arm's end had released: every spawn runs on a copy of the
  environment that owns what the environment only viewed
  (`nurl_closure_own_copy`, §7.4);
- an aggregate literal moving a binding into one field while another
  field handed the same binding to a callee that consumes or keeps it
  (`^ @ Two { t ( wrap t ) }`) made two owners of one value: a literal's
  fields are checked against each other as a call's arguments are, a
  callee whose summary is not final being decided at module end;
- a literal nested in another's field (`^ @ Two { t @ Holder { t } }`)
  moved the binding a second time unseen: a nested literal hands the
  names it moved in bare up to the literal around it, which checks them
  as moves of that field;
- a parameter handed to a callee that keeps it — and releases it, or
  keeps it in a result the caller then releases — was still readable
  after the call, though the call had cleared its drop flag: a parameter
  moves into a callee that keeps it, as a local does, unless the callee
  puts it in its container argument (an escape: `vec_push`, §7.6).

Rebuilding the standard library's own owners on self-releasing parts
found a sixth (h209): a struct holding a value with a `% Drop` of the
program's own inside a container — `: Imp { ( Vec R ) xs }`, or a Box,
an option, an enum payload — was never dropped. It could not be copied,
so it was no handle, and the compiler wrote a field-by-field drop only
for a struct whose own fields had the `% Drop`. Such a struct now gets
that drop wherever the value sits inside it (`__holds_user_drop`).
Rebuilding `BTree` found a seventh (h210), in the library rather than
the compiler: `btree_remove` took a value out of an inner node before
merging the kids around it, and the merge moved the emptied slot down.
A take from a place empties the place, so a value must leave its slot
only on the path that refills it.
An eighth (h211) was in the runtime: a share that read an owner count
of 1 stored 2 instead of taking the locked add, on the premise that only
the one owner could be sharing. A clone is asked of a borrow, and every
thread holding an `Arc` borrows the handle in its payload at once, so the
threads' shares were lost and the value freed under the payload. A share
now always takes the locked add; only a release keeps the shortcut.
Following an `Arc`'s payload through the borrow walk (§6.5) found two
more in the walk itself. A binding bound to a call whose lent argument
was itself a lending call — `( vec_at ( vec_at top 0 ) 0 )`, `( vec_get
( arc_get a ) 0 )`, a `??` over one — borrowed only what the outer call
was handed directly, which was a temporary, so it borrowed nothing and
outlived `top` (h214). Such a binding, and a match's payloads, now
borrow what the inner calls lend: the row carries the call's source
expression. And a helper that handed back an element its accessor lent
(`^ ( vec_at xs 0 )`) said it lent nothing, because the accessor — a
generic, instantiated at the end of the module — had no summary yet when
the helper's was written: a caller's temporary was dropped under the
result, and a caller could release `xs` while still reading it (h215).
The positions handed to such a callee are noted, and which parameters
the helper lends is settled on the final summaries. A third was a value
handed out of a block through a binding the block declared — `: v { : t
( vec_at outer 0 ) t }` — which borrowed nothing: the walk resolves names
where the value is used, and the block's own had ended (h216). A
value-position block now notes what each binding it declares holds, and
its value names that instead.
Probing the one source the walk still left unmodelled — the result of
a call through a closure value — found that a body's *final value*, the
one it falls off with when no `^` is written, was not judged as `^`
judges it. A closure falling off with what it only lent — `( vec_at
outer 0 )`, a capture by name, a field of one, a binding that owns
nothing — handed that to a caller that takes a closure's result as its
own, and the caller released `outer`'s element (h217). A function
falling off with a lend — `@ idv ( Vec i ) v → ( Vec i ) { v }`, `{ (
vec_at xs 0 ) }`, `{ . b items }` — was summarised as handing over a
value of its own, and every caller released its argument's contents
(h218). Written with `^`, both were sound. Now a function body whose
final statement is a name, a call, a field read or a literal compiles
it as the `^` it means (the statement's end is read off the source text, so
nothing is lexed twice), and a closure's final value is copied unless
the body owns it — the callee's answer for a call, the drop flag for a
binding it keeps, and always for a field read except out of a call that
handed the whole over. `tools/metamorph/spellings.py` holds the
spellings side by side (`returned-lend`). Following that through found
three more. A closure handing back a value that cannot be copied (a `%
Drop` value with no clone) that it does not own — its parameter, its
capture, a field of either, what a lending call lent — released it twice
(h219): rejected. A raw string a closure lent, and any other view it
handed back, was not followed at the call (h220): the string now comes
back a copy, a view of an argument is followed as a function's is, and a
view of what the closure captured — which its caller cannot see — is
rejected. And a function handing back a field it cannot copy out of a
struct it drops returned it released (h221): rejected.

What a closure holds follows the same rules. A body that moves a value it
cannot copy out of its capture — into a literal, a container, a callee
that keeps it — takes that capture over: the enclosing binding no longer
drops it, and a second use of the closure is a use after the move
(h222). A closure that only reads such a capture holds a copy of its
bits while the binding owns what they point at, so it is a view of the
binding (its source expression `\(r)`) and the walk ends it with the
binding — handed out of the frame, it is rejected (h224). A closure that
stays in its frame and may move such a capture out carries the binding's
drop flag: the body clears it where it moves the value, and the frame
drops what was not taken — a closure never run leaks nothing (h236). One
handed back right where it is made owns such a capture in its env under a
flag of its own: the env's drop releases what the body did not take, and
running it again after the move stops with a panic (h239). So does any
closure that may leave its frame — handed to a thread, a fiber or a
callee, or bound to a name the function uses other than as a callee: the
binding is moved when the closure is made (h240–h243). A copy of such an
env takes its captures over — the env it was copied from, reached
through its own address, gives them up — so the copy a thread runs owns
them, and the original, run after that, stops with a panic (h244). And a `sink`
parameter is a binding of the function's own frame: a view of it handed
back is rejected as a view of a local is (h225).

An option or result of a value that cannot be copied (`?Res`, `! Res E`)
is registered like an option of a String: its binding drops the payload
(h223) — and a result's error that cannot be copied (h237), and an option
of an option, whose inner option is the payload (h238), and a match arm's payload is a cursor over the binding — or over
the parameter, whose caller keeps it (h226). A field scrutinee lends its
payload to the arm, and a lent payload that cannot be copied cannot be
handed to an owner (h227).

What a call only lends (`vec_at`, an accessor) is not a `sink`'s to
release: one that can be copied is handed over as a copy (h228). One that
cannot be copied cannot be stored where it is kept or released — a
callee's keeping or `sink` parameter, a literal's field — decided on the
lending call's final summary at module end (h230); nor can such a field
leave a struct that still drops it (h229).

An enum lends its payload to a match's arms (h231): read in place, handed
to a `sink` as a copy, never released by the arm. An enum a call handed
over and nothing binds is given an owner for the rest of the scope
(h233), and any other temporary — discarded, or read for a field that
owns nothing — is dropped where it is left, when the call handed it over
(h232). One handed straight to another call is dropped after that call,
or becomes the result when the callee hands it back (h234). `mem_dup` —
and so every generic that copies its `T`, `box_clone` among them — is
rejected for a value that cannot be copied (h235).

Taking the packages' `unsafe` apart found four more. Every copy of an
`Rc` is the same value, and a view of it (`rc_get`) ended only when the
handle it came from was handed to `rc_set` — not another handle on the
same value: a clone (h245), a field holding one (h247), or a parameter
the caller filled with the same value (h246). The walk now ends the
borrows of every `( Rc T )` handle a function holds, of that type, when
any of them is handed to a call that may drop or replace what it holds.
And `vec_put_back` took on trust that `x` came out of slot `i`: written
back into another slot, two slots held one value (h248). It is raw, for
`unsafe` code, as `mem_put_back` is.

And three were in the standard library's surface rather than the
checker: functions that take a runtime handle — the address of the
runtime's record for a socket — as a plain integer were callable from
safe code, so a made-up number was read as one (`tcp_conn_view`, h249), or
freed (`nurl_tcp_close`, a preamble builtin, h250; `nurl_udp_close`, a
foreign function the library declares, h251). They are raw now: the
library declares such a foreign function `unsafe & …` and marks such a
builtin raw, and a program reaches sockets through `TcpConn` (with
`tcp_starttls` and `tls_accept_conn` for a TLS upgrade).

The library's raw symbol table was the same: `nurl_sym_*`
(stdlib/core/symtab.nu) took the table's address as a plain integer (h252),
and the owning `SymTab` around it could be built from a made-up number
(h253) or shared between threads in an `Arc` (h254). The raw table is
`unsafe` only; `SymTab` is sealed (only `symtab_new` makes one), moves
rather than copies, and is `% NotSync`.

The unikernel HAL was another of the kind: `mmio_write32` and the
`virtio_*` / `virtq_*` helpers take a physical address as an `i`, so safe
code wrote to a made-up address (h255). They are raw now; a driver's
functions that reach a device register are `unsafe`. And the file layer:
`file_from_raw` took any string as a C stream and closed it with its
`File`, and `file_raw` handed a `File`'s `FILE*` out as text (h256). Both
are raw; `file_is_open` answers what a caller used the stream for.

Packages had the same shape where the language could not say it: a
function whose soundness rests on its caller — gpukit's `gk_run` and
`gk_run_dev` compile and launch kernel source over device addresses
passed as integers, `gk_buf_wrap` takes any integer as device memory —
could only be marked `unsafe`, which promises safety to every caller, so
safe code reached them with a made-up address or a kernel of its own.
Grammar v2.9's `raw` (spec §3.3e) puts that promise on the caller: these
are `raw @`, `GkBuf` / `GkMemImpl` / onnx's `RTensor` are `raw :` structs,
and the operations above them check what the kernels index (sizes
through overflow-checked products, a view inside its buffer, an
expression a kernel splices in limited to `x`, numbers and math
functions) before they launch. onnx's tensors also carry the engine and
run they came from: a tensor of an earlier run, whose device memory
rt_reset released, is refused rather than read.

Taking `unsafe` out of the rest of the packages found seventeen more
(h257–h273), closed the same way: a binding read out of a field and
stored back moves when it owns the value (h257); a file's bytes are lent
as a checked view held to its `MappedFile` (h258), and a `ZipArchive`
owns or shares the bytes it reads (h260); a join nothing takes owns
nothing (h259); a temporary argument is dropped after the call whether
the result is an option, a result with an enum error, or a value that
cannot be copied (h261, h265), and a field read out of a call's result
leaves the rest of it to be dropped (h266; a closure field too, h323;
one it cannot take apart is lent by an owner the temporary is given,
h329, h330); a field that cannot be copied
moves whole out of a struct literal (h264); an option taken out of a
`Locked` empties its slot (h267); a number, a pointer or a struct is
never passed where another of them is declared (h262, h268, h269); a
payload or a forwarded call result handed back lends the parameter it
came from (h270, h271); and module globals do not race — a global set at
start holds only a type that synchronises itself (h263), a struct or
option global is `unsafe`-only (h272), and safe code may not hand an
`s` global a string to own (h273; §1).

Modelling closures for the mechanized proof (`formal/`, phase A2) found
seven more (h274–h280), all of one family: a closure that changes a
binding it captured, run where something else holds a view of that
binding. A closure handed to a call beside the binding itself, a borrow
of one of its elements, or another closure that captured it (h274–h277,
h280) — inside the callee the two are unrelated names; a closure that
runs a captured closure did not carry what that one does (h278); and a
closure that captured both a `Vec` and a view of it, growing the one and
reading the other (h279). They are closed by the exclusive-call rule
below, extended to closures.

Modelling the *handing* of such closures to calls then found an eighth
(h285): a closure holding a view of a `Vec` it captured across a call to
one of its own closure *parameters*, where the caller hands that parameter
a closure that re-enters and grows the `Vec`. Running a *captured* closure
carries its effect onto the enclosing closure (h278), but running a
*parameter* carried none — a parameter's captures are the caller's to
choose. Checking the compiler against the finished calculus found the same
with the closure behind what a parameter holds: a struct field (h286) and
a `Vec` element (h287), where the closure read out of the parameter was
taken to hold nothing. All three are closed the same way, additively:
inside a closure body, a call to an *opaque* closure — a closure
parameter, or a closure a parameter holds, a field, an element, a closure
a call handed back: one whose captures nobody at the call knows — ends
the views of every binding that closure captured by reference, exactly as
a call that runs a growing closure whose captures are known does (h280).

Making closure types and trait objects generic type arguments found four
(h281–h284): an option or a result of a capturing closure owned nothing,
so handing one back — from a binding, in a struct field, or as
`!( @ i i ) E` — returned an environment the frame had just freed
(h281, h282, h284); and a closure read out of a struct's field did not
own its environment and was tracked only by its captures, so replacing
the field and calling the closure called freed memory (h283). An option
or result of a closure owns its environment now, and a closure read out
of an owner borrows it (§7.5).

Writing a multi-threaded database in safe code (`packages/nurldb`) found
eleven (h288–h298). Shared state: a helper taking a struct that holds an
`Arc` lent its payload unfrozen (h288), and a foreign function writing
through an unmarked `*T` was no change to anything (h289; §6.5). Guards: a
struct holding a lock guard had no drop (h290), and a panic skipped the
drop of a struct whose destructor is written at module end (h291), or
left it registered after it was dropped (h294). The panic journal: a
temporary made in a call's argument leaked when the callee panicked
(h292), a thread kept its last panic message (h293), and a `??` arm
handing its payload out kept the payload registered (h296). Parameters: a
`: ~` copy of a parameter passed `inout` to a function that replaces one
of its fields released the caller's (h295; §2.4). Closures: a closure
replaced through an `inout` parameter was taken for the callee's own —
its new environment freed on return, the old one leaked (h297; §7.5) —
and a closure handing a captured binding to an `inout` parameter took the
binding by value, so a String the callee replaced was released under the
caller (h298; §2.3).

Probing what the standard library's doc comments still asked of callers
(`map_iter`: "do NOT free the map until iteration is finished") found
seventeen more (h299–h315), most of them closures that outlived what they read. A
closure a call returns over an argument it captured stayed usable after
the caller released the argument — in user code (h299) and in the
library's iterators (h300, and h301, where `map_iter` captured a raw
pointer the checker could not see); an option-of-String parameter was
not recorded as captured at all (h302); a nested call's view, stored by
the callee, and an iterator chain over a temporary source held nothing
of what they read (h304, h305); and a closure holding a copy of a handle
it captured by value outlived the handle when the binding was given a
new value — directly (h306) or by an `inout` callee replacing it or a
field of it (h307–h309), or when it was bound and returned by name past
the frame that released the value (h310; a closure literal written in the
return takes its captures over). Lends returned through a join were not
the function's (h311–h314: `lru_get`'s cached value released or read
after an eviction), and a match's scrutinee call took effect after the
arm's first statement, which could read a borrow it had ended (h315).
`map_keys` over owned keys copied each key and
emptied its slot too, leaking the key and corrupting the map (h303;
§7.6). A thread-safety marker asserted by safe code raced an `Rc`'s count
(h318: a positive marker is `unsafe` now, §3), and the heartbeat thread
of dist/heartbeat.nu grew a membership table the data plane grew too,
under a lock nothing made the caller take (h319, §6.5). Fixing
`std/pool.nu`'s checkout guard (Agora #73) found more: a destructor —
a drop hook or a `% Drop` impl — that stored a field of its receiver that
cannot be copied into a literal, a container or another field moved it
there without emptying it, and the receiver's drop glue released it again
(h322); a local struct's such field did the same (h324–h326), and a
returned literal holding one released it with the local on the way out
(h327) — the field is lent, as a parameter's is (§7.6) — and an outer
block's binding given one out of an inner block's struct went on
borrowing it after that block dropped the struct (h328). A field read out
of a call's result was nobody's when the read could not take it apart: a
closure field (h323: it leaves the temporary as h266's handle fields do,
its environment the read's own; §7.4), any owning field of a struct with
a `% Drop` of its own (h329), and a field that cannot be copied (h330) —
the temporary leaked and its destructors never ran. Such a temporary now
gets an owner for the rest of the scope, as h233's enum does (§7.6).
Working agora #66 found the borrow checker's view of a binding read out
of a field (`: String n . h name`) empty: the right-hand side's reads went
with the row before the binding's, so the borrow borrowed nothing and
outlived its struct handed to a `sink` (h331) or given a new value
(h332) — and a library handle's copy made that way outlived its struct
taken by a thread (h333, the shape #66 was found with). It borrows the
field's path now (§7.6). The rest of #66 is the thread rule for library
handles (§6.5): a thread's capture of one the spawner kept (h336), a
parameter (h337), an `Arc` of one (h338), a closure capturing one kept in
an `Arc` (h339) or sent on a channel (h340), and a closure several
threads run changing what it captured (h342: a route handler pushing to
a `Vec`). Making the standard
library's shared handles honest for it found `tcp_close_listener` then
`tcp_accept` reading the freed socket record on one thread (h341): a stop
now keeps the record until the last owner, and closes the fd only once no
accept is in progress. Making the MCP task store thread-safe for it found
the store handing out a task as a bare address, which its eviction at the
cap or a sweep past the TTL freed under a kept handle (h343): a task
handle (`McpTask`) is now one owner of its task. A trait object answered
Send and Sync for whatever it boxed, an `Rc` among them, because its
type has no field to walk (h344): it now crosses only when its trait
declares `: Send` (and is shared only with `: Send Sync`), a promise
every impl is held to. Closing #121 — the
copies a crossing to another thread may leave behind (h349–h357), checked
at run time (§6.5) — found four ownership holes on one thread: an `inout`
parameter given a binding read out of a field (h345) or a closure's
capture (h346) stored the value as is, two owners of one buffer; a
closure's `inout` parameter given a fresh value dropped it on return
(h347); and a binding read out of a library handle field, consumed, left
the field empty — a null handle the struct was still read through (h348).
An `inout` parameter is given a copy of a binding whose value another
owner keeps, is never an owner of its own, and a field viewer of a
library handle takes its struct with it (§7.6). A `% Sync` marker on a
container vouched for its value too: an `Rc` in a `Locked` in an `Arc`
crossed to every thread (h358). And a function whose only panic was an
index past the end leaked its bindings under `recover` (h359): the
journal's elision took the runtime's index panic for a call that cannot
panic. Meeting the trait object's promise, the check missed what a
`%Trait` of a `: Send` trait boxed (h360): its vtable now carries the
boxed type's check. And a value with a destructor moved on — into a
literal, a `sink` parameter, a closure, a `dyn` box — was dropped once
more by a panic later in its scope (h361–h363): its journal registration
had read its drop flag when it was made, and now reads it when the panic
drains (§7.2). Making `arc_get` lend a trait object's payload (§7.7)
found the checker taking a method called through a trait object for one
that changes nothing: an `inout` receiver writing the shared box
(h364), an impl replacing what a view read (h365), a helper handing its
parameter to such a method (h366). A `dyn` call is now summarised as the
union of its impls. And a binding that only borrowed its value, handed
`inout` to a callee that gives that parameter a new value, released the
value under its owner (h367–h370). It is now refused, and a `: ~` copy
of a `% Drop` struct takes its owner's drop flag, so the replacing call
makes it the owner (§7.6). nurldb's tests then found a `?` statement
whose arm ended in an assignment from a join (`= lo ? c ( f ) ( g )`)
dropping the value `lo` had just received as the statement's discarded
value (h371, h372): an assignment's value is lent to whatever reads it.
A join that hands a binding its own value back (`= x ? c x ( f )`) had x
drop it first (h373, h374): where such a join lends, the value is copied
in. And a closure's env was not in the panic journal (h375–h377): a
literal handed to a call, a bound closure, a struct literal's closure
field; each function's closure bindings are now one frame-table entry,
and an argument's closure and literal fields are journaled while the
call runs (§7.2). Converting `UdpSocket` to a handle with a drop closed
its use after `udp_close` and its leak (h382, h383), and probing the
temporaries such a conversion leans on found a view of a call's
temporary argument kept past its statement leaving the temporary owned
by nothing (h378–h381): such a view is rejected (§1, Temporaries). On
the way, a closure returned over a parameter in a spelling the summary
missed (h384–h388) was found and closed (above), and so were a field
handed to a callee that takes it from a binding that cannot give it
(h389–h404) and a field a closure assigned through its by-reference
capture (h405–h407), an option parameter's payload handed back
(h408–h415), a loop's container released in its body (h416–h420), an option kept
by a callee (h421–h423), and a field of a call's lent result handed to a
`sink` (h424–h425).

The rules that carry it:

- **An owned value moves.** Storing it into an aggregate, an Option or a
  container, sending it, returning it, handing it to a `sink` parameter
  or capturing it in a closure another thread runs moves it. A later read
  of the old name, or of a name it moved out of on *some* path, is an
  error. A value with nothing to release is copied.
- **A read that does not take ownership is a borrow.** `vec_get`, a field
  read, a match payload of a borrowed value, and a call result the callee
  lends all borrow from their source. A borrow can be read and passed on,
  never released, stored as an owner or sent. It ends when its source is
  moved, released, reassigned, has the field replaced, or is handed to a
  call that may drop its elements; any read after that is an error. A
  borrow of a borrow borrows from the original owner.
- **A view also ends at reallocation.** `string_data`, a `Slice` and
  whatever holds one are views of the buffer and end at any mutation that
  may reallocate it (§2.10), wherever the view has travelled.
- **A call is exclusive.** A container a call may change cannot also
  reach it as another argument — the same owner twice, or a view or
  borrow of it: inside the callee the two names are unrelated (§2.4).
- **Running a closure is what its body does.** A closure that changes,
  reallocates or drops elements of a capture ends the views and borrows of
  that capture where it runs — called directly, or handed to a callee that
  may run it (§2.11) — and one that runs a closure it captured does what
  that one does. Such a closure is a route to the capture: no other
  argument of a call it is handed to (or of the call of it) may reach the
  capture — the binding, a view or a borrow of it, a closure that captured
  it — and it may not itself hold a view of what it changes.
- **A part of a temporary is a copy.** An element borrowed out of a call's
  fresh result (`( vec_get [String] ( mk ) 0 )`) is copied before the
  temporary is dropped; one that cannot be copied is an error naming the
  fix — bind the container to a name.
- **A view of a temporary stays in its statement.** A call's result that
  may view a temporary argument (`( string_data ( mk ) )`) is used inside
  a call that consumes the view; kept past it — bound, returned, assigned,
  stored, taken by a join — it is an error naming the same fix (§1,
  Temporaries).
- **A container keeps what it is handed.** A view stored in a `Vec`, used
  as a map key or handed to a function that keeps its argument may live no
  longer than its source.
- **Threads and fibers.** A closure run on another thread or fiber moves
  its captures. Handles whose copy is a share of one object (`Channel`,
  `Mutex`, `Arc`, `Locked`, `HttpServer`) are captured as a share of their
  own, so both sides keep using them and either may end first. State
  threads share and change is a `Locked`; an `Arc`'s payload is frozen
  once made (§6.5).
- **Raw memory only in `unsafe`** (spec §3.3d): a raw pointer taken by a
  call or handed back by one, a primitive that reads or writes as far as
  its caller says (`memmem`, `fwrite`, `nurl_str_at`), a C `FILE*`. A
  string (`s`) in safe code is NUL-terminated, or null — and a null string
  reads as the empty string.
- **Allocation sizes are checked.** A count whose byte size cannot be
  represented panics before anything is allocated.

`vec_get` and its kin are specified as returning a borrow of the element.
Every verdict is independent of the order in which functions are defined:
a question that depends on a callee is answered once the whole module is
compiled.

### 6.3 Conservative, with a fix in every message

The rules decide from the program text, so they reject some programs that
would have run correctly. That is the price of a guarantee that does not
depend on the program's inputs. Each diagnostic names the rule, the line
where the value moved or the borrow ended, and a change that satisfies
the rule. A rejected program that has no reasonable fix is a rule to
refine: report it at https://github.com/nurl-lang/nurl/issues.

### 6.4 Trusted computing base

The guarantee rests on a surface that is trusted rather than checked:

- **`unsafe` functions.** Each one vouches that it is memory-safe and
  leak-free for every caller. A `raw` function (spec §3.3e) vouches for
  nothing itself: each `unsafe` caller vouches for its call.
- **`unsafe % Send` / `unsafe % Sync` assertions** on types whose safety
  the compiler cannot see (§3, §6.5).
- **Foreign-function claims**: the `in`, `sync` and `nocapture` markers
  on a foreign declaration's parameters (spec §7.2). `sync` is a
  data-race claim about the C function: that it changes what it is
  handed only atomically or under a lock of its own.
- `nurlc --unsafe-report` lists all three as a program contains them
  outside the standard library, one `file:line` each — the whole surface
  a reviewer of that program has to trust.
- **The standard library and the runtime.** Their raw code, the `Rc`
  cycle collector and the panic journal included, is the base every safe
  program stands on. A library function that trusts its caller's
  pointer or length (`slice_from_raw`, `vec_borrow_raw`, `vec_set_len`,
  `nurl_str_at`, …) is `unsafe` to call (§6.2).
- **The standard library's marker assertions and foreign claims**, in
  both directions: a `% Send` / `% Sync` it writes (`Mutex`, `Locked`,
  `RwLocked`, `Channel`) is trusted as the program's is, and so is each
  `% NotSend`, `% NotSync` and `% Frozen` it must not leave out — a read
  guard not marked `% Frozen` (stdlib/std/rwlock.nu `% Frozen RGuard {}`)
  would lend a value other threads read as a mutable one, and a
  connection handle not marked `% NotSend` would cross threads. The same
  holds for the `in` / `sync` / `nocapture` of its foreign declarations
  (`nurl_rc_share sync *u p`: the count is changed with an atomic).
- **The compiler itself.** A program accepted in violation of §6.2 is a
  compiler bug (§6.6).

### 6.5 Threads, and how this compares to Rust

The model uses Rust's vocabulary (move, borrow, readers XOR writer) for
ideas that are genuinely analogous, but the mechanics differ:

- Ownership is single-owner with scope-bound drop. There are **no
  lifetimes** in types, no lifetime parameters and no lifetime syntax.
- A borrowed value stored into a struct, an Option or a container is
  copied into it (§7.6). A view (`string_data`, a `Slice`, a raw string
  in a value) may be stored there too, captured by a closure, kept in a
  global or returned: it stays a view of its source wherever it goes and
  ends with it (§2.10, §2.13). A struct Rust would give a lifetime
  parameter, like protobuf's `ProtoReader` over a `( Slice u )`, needs
  none. A value that must outlive its source is an owned copy, an `Rc` /
  `Arc`, or an index into an owning container.
- `in` / `inout` / `sink` are call conventions resolved per call, not
  reference types.
- Leaks are part of the guarantee. Safe Rust permits leaks
  (`mem::forget`, `Rc` cycles); in NURL `mem_forget` is `unsafe` and `Rc`
  cycles are collected.

**Shared mutable state.** Three handles carry it between threads, each
`Send` and `Sync`: a `Locked T` (one thread at a time; `locked_await`
waits on it until a closure says it is done), an `RwLocked T` (many
readers or one writer) and an `Atomic` (one word, changed only with atomic
instructions). A read guard is `% Frozen`: what it lends — the value, a
`Slice` of a `Vec` in it — is read-only, checked as an `Arc`'s payload is
(§9.13 of the spec), and a struct holding one is frozen in the same way.
A holder — a thread, or a fiber, which may move between threads — may
read a lock it already reads (the second guard is counted, so it never
waits behind a writer queued for the first); asking for one it holds for
writing, or to write one it reads, panics rather than wait for itself.
A `PFile` reads and writes at an offset, with no shared file position, so
threads share one too. A guard is a value like any other: dropped at the
end of its scope (a bare block, a block that computes a number, a loop
body), by the unwind of a panic, or when the struct holding it is.

**Send and Sync.** `Send` ("may move to another thread") and `Sync` ("may
be reached from two threads at once") are marker traits
(`stdlib/core/marker.nu`) that the compiler derives structurally over a
type's whole graph: struct fields, enum payloads, generic arguments,
aggregate members and closure captures. Four cases are built in:

| | Send | Sync | why |
|---|---|---|---|
| `Rc` | ✗ | ✗ | the reference count is not atomic |
| `Cell` | ✓ | ✗ | a raw byte buffer with unsynchronised writes |
| a library handle (§7.6) | ✓ | ✗ unless asserted | its copies are one state, changed in place |
| a trait object `%Trait` | ✗ unless `: Send` | ✗ unless `: Send Sync` | its box holds any type implementing the trait |
| everything else | ✓ | ✓ | unless a field says otherwise |

A trait object's type does not say what its box holds, so the trait
answers for it: `% Job [T] : Send { … }` holds every type implementing
`Job` to Send where its impl is (rejected there if it reaches an `Rc`),
and a `%Job` may then move; `: Send Sync` makes it Sync as well (h344).

They are checked where a value crosses: `thread_spawn` and `spawn` (every
capture must be Send), `chan_send` (the value must be Send), and `Arc T`
(T must be Send and Sync). `[T: Send]` bounds are answered by the same
derivation. A marker asserting a container Sync vouches for the container,
never for what it holds: where the Sync question reaches a `Locked`, a
`Channel` or a `Pool`, its value must be Send (one thread at a time has
it), and an `RwLocked`'s must be Send and Sync, wherever it crosses, since
several readers reach it at once (h357, h358; Rust's `Mutex<T>: Sync where
T: Send`).

A closure's captures are not part of its type, so for closures the
question is asked of the **value**, followed from where the closure is
built to where it crosses: through bindings, struct fields, calls that
return it, other closures that capture it, and parameters of functions
that spawn or keep it. The error is reported where the value leaves,
naming the capture and the line the closure was built on. A closure
whose origin cannot be followed (a `Vec` element, a call through a
closure value) is rejected where it crosses; build it at the hand-over
or take it as a parameter.

The derivation can be wrong in two directions, and each has a marker:
`% Send T { }` / `% Sync T { }` assert safety the compiler cannot see
(`Mutex` is what makes its contents shareable), `% NotSend T { }` /
`% NotSync T { }` assert danger it cannot see (a foreign connection
handle). A negative marker outranks a positive one on the same type. A
positive marker is taken on trust, so a program writes it
`unsafe % Send T { }` (§3, §6.4); a negative one, like `% Frozen`, only
adds checks and is safe code.

**Shared mutation.** A closure run on another thread moves its captures,
so the spawner cannot keep using a plain `Vec` a worker was handed — nor
a library handle whose copies are one state changed in place with no
lock (a `PNCounter`, a `TcpConn`, a `Cell`): it moves as the `Vec` does
(h336). A thread's closure may not capture a parameter of one, which its
caller keeps (`sink` hands it over, h337), and a call that keeps a
closure beside a handle another thread takes it from — a channel, an
`Arc`, a server — moves the closure's captures that are not Sync (h340).
Where several threads reach a value at once — an `Arc`'s payload, a
closure kept in an `Arc` or in a handle asserted `% Sync`, such as a
server's handler — what it holds or captures must be Sync, and such a
handle is not (h338, h339). A closure several threads run may not change
what it captured, either, unless that synchronises itself: a handler
that pushes to a `Vec` it captured grows one environment from every
worker at once (h342); it counts in an `Atomic` or keeps the list in a
`Locked`. Share handles used on both sides are the ones asserted
`% Sync` — `Channel`, `Mutex`, `Arc`, `Locked`, `RwLocked`, `Atomic`,
`PFile`, `Pool`, and the handles servers share (`TcpListener`,
`HttpServer`, `QuicServer`, `H3Server`, a router's `Route`, a cluster's
`RpcEntry`, an MCP `McpTaskStore` and its `McpTask`s), each with the reason beside its
marker — and a handle made only of `Arc`s and such handles (nurldb's
`Store`), whose fields answer.

**The crossing check.** Moving a handle whose copies are one state is
sound only if no other owner of that state stays behind, and a copy is
made by any store of a borrowed handle into an owner — a literal storing
`. h c`, a `Vec` push, a closure capture — or by an explicit
`PNCounter_share`, so the checker cannot follow every one to the move.
The crossing checks at run time instead (agora #121): `( mem_send_check
[T] x what )` walks T's graph — fields, payloads, `Vec` elements, a
container's contents through its `S_sendck` hook (`HashMap`, `Set`,
`Deque`, `BTree`, `Box` have one), a closure's captures through its
environment's descriptor, a trait object's box through its vtable, a
handle's state — counting how many places in
the value hold each such handle's counted block, and panics, naming the
crossing and the handle, if a block has more owners than that: an owner
left on this side. Several owners of one state that all go along cross —
a node's transport and the job node beside it holding a share of it — and
a block's state is walked once, however many places hold it. It compiles
to nothing for a T that reaches none, and costs a load and a table entry
per handle for one that does. The standard
library's crossings call it: `thread_spawn`, `thread_spawn_owned`,
`spawn`, `spawn_owned`, `spawn_joinable` (before the thread copies the
environment), `chan_send`, a pool taking a value back, and a `Locked`:
every value going in (`locked_new`, `locked_set`, `locked_restore`), the
value again after a closure ran on it under the lock (`locked_with`,
`locked_update`, `locked_apply`, `locked_await`), checked before the lock
is let go — a failure panics with it held, as a panic in the closure
does — and `locked_get`'s copy, which for such a handle is the same state
and is never handed out. An `RwLocked` needs no check: its value is
Sync, so it holds no such handle (above). The checker keeps its part: the
binding a moved handle came from, a parameter of one (h337), and a
binding read out of a field of one (h356), whose struct goes along, are
dead past the crossing — what is left behind is only ever a copy the
check sees. A trait object's type does not say what its box holds, so
its vtable does: an impl of a `: Send` trait — the only trait objects
that cross — whose type reaches such a handle puts that type's check in
the vtable's last slot, and the walk runs it on the box (h360).

*An `Arc`'s payload is frozen once made.* `Arc` makes the reference
count atomic, not the data: every thread holding a clone reads the
payload with ordinary loads. So safe code never changes it, on any
thread — the one that made it included (h213) — and whatever lock it
holds: a `Mutex` the type does not tie to the data proves nothing about
the threads that read it without taking that lock. What a call lends
through an `Arc` parameter is a view of the payload — `arc_get`'s
result, or a helper's over it — and the borrow walk follows it wherever
the rules follow a borrow: into a binding, a borrow of it, a name it is
copied to, a field, an element an accessor lends out of it, either arm of
a `?` or `??`, a match payload. A call that hands one to a parameter its
callee changes — a container mutator, a `String`'s or a map's, a helper
of the program's, at any depth — is the error, reported at that call;
summaries that close only after every body is compiled (writes through
raw pointers) are waited for, and the verdict is reached on the final
ones (h212). `arc_set`, which replaces the payload, is for `unsafe` code
only. A payload whose type synchronises itself (asserted
`% Sync`: `Mutex`, `Channel`, `Locked`) is changed through its own
operations.

*State threads share and change is a `Locked [T]`* (stdlib/std/thread.nu):
a shared handle of its own over a mutex and the value, reached only
through `locked_with` (runs a closure on the value with the lock held),
`locked_get` (a copy), `locked_set`, and `locked_take` / `locked_restore`
(the value checked out to one thread to change in place, every other
operation waiting until it is back). The lock that guards the data is
the one its type names, so no lock is counted and none can be forgotten.
State one thread changes is an `Rc`; a value built first is shared whole
with `arc_new`.

*A lock beside the data is not a lock on it.* A library handle whose
state is changed in place with no lock of its own, handed to a thread
together with a `Mutex` its caller is asked to take around its own
changes, is a race the first caller that forgets writes: nothing ties the
mutex to the state. `dist/heartbeat.nu` was that shape — its thread read
the membership table under a caller-supplied mutex (h319). The thread
holds only what it needs now, in values that synchronise themselves: the
node's liveness (`pktable_liveness`: a copy of the self pubkey and the
table's incarnation, an `Atomic` every copy of which is the same word),
and the table is `% NotSend`. State a thread must change with its
caller is a `Locked`; state it only reads, a copy or an `Atomic`;
`mqtt_listen` takes its client over (`sink`), since its thread is the
client's only user.

### 6.6 How the guarantee is checked

The guarantee is a property of the rules. The compiler's implementation
of them is tested continuously:

- **Mechanized soundness proof (Lean 4).** The ownership calculus
  (`formal/`, `./check.sh`) is mechanically proven sound in Lean 4 with
  zero `sorry`, on Lean's standard axioms only: `A2.memory_safe` and
  `A2.no_leak_end` in `formal/A2/Soundness.lean` — well-typed programs
  never get stuck on a use after free, a double free, a dangling borrow or
  view or an out-of-bounds access, and leak nothing at exit, on the panic
  path too. The calculus covers owned values, moves and drop flags,
  borrows and views, `inout` with its bounds, structs and enums, closures
  and trait objects with their captures (§2.11), panics and the drop
  journal; `formal/corpus/map.tsv` maps every regression probe
  (`h01–h630`) to the rule that rejects it. See
  [`formal/README.md`](../formal/README.md).
- **Hole probes.** Every way safe code has been shown to break the
  guarantee is kept as a program that must be rejected, or run clean
  under the sanitizers (`tools/fuzz/holes/check.sh`, in CI: no probe may
  still compile and fault).
- **Inverse-oracle fuzzing.** Generated programs that violate ownership,
  nested in every context the language has (`?` / `??` arms, loops,
  defers, closures, generic bodies, trait methods), must be rejected with
  the matching diagnostic.
- **Consistency.** The same situation written in different spellings must
  get the same verdict, and correct controls must keep compiling.
- **Sanitizers.** The whole test corpus, the compiler's self-compile and
  a serving HTTP process run under AddressSanitizer, UndefinedBehavior-
  Sanitizer and LeakSanitizer and must report nothing. These check the
  compiler; a program's safety does not depend on running them.

## 7. Release of memory

### 7.1 Ordinary code does not leak

Auto-drop is exhaustive in straight-line code, across `?` / `??`
branches and through loop bodies: owned strings, slices, `Drop` values,
closures, library handles and owned struct fields at any nesting depth
are released at scope exit. A binding declared in an arm that falls
through is dropped at the end of the arm.

`;` defers are covered as well. Values registered before a defer (which
its body may use) are released after the defer chain runs, and values
registered after it at their normal scope exits. An owned value returned
on one path and not on another is released on the path that does not
return it (spec §5.3).

### 7.2 Panics

A panic jumps to the nearest `recover` frame without unwinding through
the frames in between. Their drops are performed by an **allocation
journal** instead:

- While a `recover` frame is active, every owned value registered in a
  frame inside it is recorded: raw buffers (owned strings, slices, struct
  field buffers), owned bindings together with their drop flags, `sink`
  arguments taken over from the caller, and values with a typed drop.
- A value released normally, or moved out of the extent (assigned into a
  binding the caller owns), is removed from the journal, so the journal
  never releases something twice or releases what the caller now owns.
- An owned binding's drop flag is read when a panic drains the journal,
  not when the binding is recorded: a value moved on — into a literal, a
  `sink` parameter, a closure's capture, a `dyn` box — has its flag
  cleared, and only its new owner releases it (h361–h363).
- A closure binding is recorded with its owner slot, all of a function's
  as one entry (`nurl_jframe_clo_drop`): a panic drops the env of each
  one whose slot says it owns it, as its scope exit would (h375, h376).
- A String / Vec / struct made by a call right in an argument is recorded
  while the callee runs (it is the caller's until the call returns), and
  so is a closure literal or a closure a call returned, handed on as an
  argument, and every owned field of a struct literal argument (h375,
  h377); a
  value whose destructor is written at module end (a struct holding a
  guard) is recorded and forgotten like any other; a value a `??` arm
  hands out as the match's value leaves the journal with its scope.
- A call's result given an owner for the rest of the scope — an enum a
  match takes and nothing binds (h233), a result read for a field it
  cannot give up (h329, h330) — is recorded once, with its drop flag. Read
  again in a loop's condition, the round before leaves the journal and is
  released before the next takes its place.
- On a panic, the values still recorded since the target frame's mark are
  released before the jump, while their frames are still valid.
- A destructor that panics while they are released (a double panic) is
  caught by the same `recover`: each value leaves the journal before its
  drop runs, the second panic releases what is still recorded, and the
  `recover` reports the first panic's message, the cause. With no
  `recover` frame, a panic ends the process before anything is released.

The journal belongs to the thread outside fibers and to the fiber inside
one. The scheduler switches it with the fiber, so fibers sharing a worker,
or moving between workers, never drain each other's extents. Functions
that cannot reach a panic do not register anything and pay nothing, and
neither does a binding that never owns while it is registered (a
parameter its function does not take over, a value read out of a
container, a temporary a callee sinks): its drop flag is false whenever
a panic could read it, so its registration is dropped when the flags are
folded. One whose flag is always true is registered without a flag.

### 7.3 What a panic does not reclaim

Raw memory managed by an `unsafe` function (§7.4) is never auto-dropped,
so a panic that abandons it mid-scope leaks it, exactly as omitting its
`nurl_free` would. An `unsafe` function that holds raw memory across a
call that may panic keeps it in the caller's frame (`stdlib/std/panic.nu`
shows the pattern).

### 7.4 Manually-managed memory

The compiler does not track memory allocated as raw bytes (`nurl_alloc`
behind a `*T`) or a value given up with `mem_forget`. Both are possible
only in `unsafe` code, which releases them with `nurl_free`. Nothing else
is managed by hand: `string_free`, `vec_free` and the other release calls
on compiler-managed values and handles are optional early releases.

Code that reaches for raw memory rarely needs to:

- **State kept for the program's life** is a module global (§1).
- **A record whose address must stay put** while its container grows is a
  `( Box T )` in the container (`box_ptr` is its address).
- **A buffer a C function fills** is a `( Vec u )` (`vec_data`, then
  `vec_set_len`).
- **A C function that writes a result through a pointer** declares the
  parameter `inout` (`& \`lib\` @ cuMemGetInfo_v2 inout i free inout i
  total → i32`): the call passes the address of a mutable binding, and
  nothing is allocated for the result.

An empty owned string allocates nothing. Every empty copy (`nurl_strdup`
of the empty literal, an empty `nurl_strdup_n`, slice or concatenation)
is the runtime's one shared empty string, which never goes away:
`nurl_free` releases it by doing nothing and `nurl_realloc` grows it into
a block of its own. So `unsafe` code releases an owned string with
`nurl_free`, never libc `free`, grows it with `nurl_realloc`, and writes
nothing past its terminator.

Everything the standard library hands out releases itself. Opaque state
lives behind a library handle over a counted block (`stdlib/core/rcbox.nu`:
`[ owners ][ T ]`, the last owner drops `T`): `Mutex`, `Channel`,
`Regex`, `Rng`, `Bitset`, `File`, `TlsConn`, the QUIC and HTTP connection
state, `ProcChild` and others. Every copy (a struct field, a `Vec`
element, a closure capture, `T_share`) is the same object, and the last
one releases it. The last owner of a `ProcChild` shuts the child down
(pipes closed, SIGTERM, a short grace period, SIGKILL, reaped); the last
owner of a thread handle detaches it unless it was joined. The `*_free` /
`*_close` functions remain as an early release of one owner.

### 7.5 Closure environments

A capturing closure is a value `{ fn, env }` whose environment is one
heap block. The environment is owned by exactly one place at a time,
which drops it:

| Where the closure is kept | Who drops the environment |
|---|---|
| a `:` binding | the binding, at scope exit (each iteration in a loop) |
| a closure or call result passed straight to a call | the call site, right after the call, unless it went into an aggregate literal first |
| a statement whose value is discarded | that statement |
| a function result | the caller |
| a closure field read out of a call's result (`. ( mk ) cb`) | whatever takes the read — the field leaves the temporary, whose rest is dropped there (h323) |
| a struct field | the struct, with its other fields; copying the struct copies the environment |
| a slice of closures | the slice, element by element |
| a container whose element type is a closure (`( Vec ( @ i i ) )`, a map's values, an `Rc`, a generic struct's field) | the container, element by element; copying the container copies each environment |
| an option or a result of a closure | the option, when its tag says the closure is there; copying the option copies the environment |
| another closure's captures | that closure's environment (nested environments form a tree) |
| a `?` / `??` join | whatever consumes the join |
| a fiber, a thread, a signal handler, a sqlite authorizer | the runtime, which keeps its own copy |

Two rules make this sound without reference counting:

- **A place that keeps a closure it did not create stores a copy.**
  `nurl_closure_clone` copies the environment and, through its
  descriptor, the environments of closures it captured. A function that
  stores, captures, spawns or returns a closure argument keeps a copy,
  and the caller's closure stays the caller's. A `sink` closure parameter
  is the exception: the callee takes the closure over.
- **A move clears the source on its own path only.** `: h g`, `= h g` and
  `^ g` hand `g`'s environment on; a path that did not move `g` still
  drops it.

Every environment starts with a pointer to a compiler-emitted descriptor
`{ size, drop, clone, … }` (below). `nurl_closure_drop` (null-safe) is what every
owner calls. Releasing an environment by hand is a compile error.
`unsafe` code that hands an environment to C and needs it past the call
keeps a `nurl_closure_clone` and releases that with `nurl_closure_drop`.

A closure run by a thread or fiber moves the bindings it captures into its
environment (§6.2); a handle whose copies are one state is captured as a
share of its own, so the crossing check sees an owner left behind (§6.5).
The runtime keeps its own copy of the environment — or, for a closure
written right in the spawn's argument (a literal, a call's result), the
environment itself: the caller hands it over (`nurl_closure_handover`)
instead of dropping it after the call, and the spawn adopts it in place
(agora #142).

**A closure stored into a struct, a slice, a container or an option owns
what it captured.** A closure made in a function views the `String`s, `Vec`s and handles it
captures: the function still owns them and drops them at its end. Stored
into a struct field (a literal's or by `=`, through a pointer too), a
slice of closures, an option or a container's element, the closure may
outlive that function, so the stored
environment copies in what it only viewed: `nurl_closure_adopt` (a
literal's environment, in place) and `nurl_closure_own_copy` (a binding's,
in a copy) switch it to a second descriptor, `own`, whose `drop` and
`clone` cover those captures too (h195). The descriptor is
`{ size, drop, clone, trace, own, adopt }`; `own` and `adopt` are null for
an environment that already owns everything it captured.

**A closure binding reached through a pointer is such a place too.** An
`inout` closure parameter, and a closure binding another closure captured
by pointer, own their environment: a closure assigned there is made owned
(a literal's or a call's environment moves in, anything else is copied),
and the environment it replaces is released. The caller hands one over
owned — a binding that only borrows its closure is copied first — and
owns what the place holds afterwards, a panic in the callee included: a
closure binding's owner slot is a flag, and the environment dropped is
always the one its value holds (h297).

**A closure read out of an owner borrows from it.** A closure binding
that does not own its environment — read out of a struct's field
(`: ( @ i i ) g . s f`), an option's payload (`T g →`), a container's
element (a `vec_get` payload, a foreach element) — is a borrow of that
owner, as a `String` read out of it is: the owner dying, given a new
value, a field of it replaced or its elements dropped ends the binding,
and calling it afterwards is a compile error (h283). `( mem_dup g )` is a
copy that owns its environment. Accessors that hand a closure back as a
result (`vec_at`, `rc_get`) hand back such a copy — a closure result is
always its caller's own — while a foreach element and a `vec_get` payload
are lent, at no cost. A closure type as a generic type argument is
written as a type anywhere else is (`( Vec ( @ i i ) )`,
`( vec_new [( @ i i )] )`); in mangled names it is its slug,
`fn1_3_i64_3_i64` (docs/spec.md §4.8).

**Closure parameters are always borrowed.** A call through a closure value
cannot see what the body does with its arguments, so the contract is
fixed:

- the caller keeps what it passes and drops a temporary it made for the
  call right after it;
- what the body stores or returns is a copy, and every closure result is
  owned by its caller — whether the body returns it with `^` or falls off
  its end with it (h217); a raw string it lent comes back a copy (h220);
- a result that cannot be copied has to be the body's own: its parameter,
  its capture, a field of either or what a call lent is rejected (h219);
- a view it hands back (a Slice, a struct of views) may point into its
  arguments, which the call follows, never into what it captured (h220);
- a capture it cannot copy and moves out (into a literal, a container, a
  callee that keeps it) is the env's from then on, so the closure runs
  at most once (h222); one it only reads keeps the closure a view of the
  binding, which does not leave the binding's frame (h224);
- releasing a parameter inside the body is a compile error.

Accordingly, every `*_free_with` (`vec_free_with`, `box_free_with`,
`rc_free_with`, `arc_free_with`, `btree_free_with`, …) *lends* each
element to its hook and then drops the container as `*_free` does. A hook
is for teardown the element type does not do itself (counting, logging,
closing a foreign handle), never for releasing what the container owns.

A `: ~` binding the body assigns, or hands to an `inout` parameter, is
captured by pointer (§2.3): the assignment replaces the caller's value and
drops the old one, and the closure cannot leave the frame. Any other
capture is taken by value, as mutable as its binding.

### 7.6 Drop flags, handles and copies

**Drop flags.** Every owning binding carries a drop flag, and its drop is
gated on it, so a value leaves its binding exactly once whichever way it
goes:

- `: b a` / `= b a` over an owner moves the value: `b` takes `a`'s flag
  and `a`'s is cleared on that path. Over a binding that does not own its
  value (a parameter, a borrow) `b` borrows too.
- A value from a lending call (`vec_get`, an accessor returning what a
  parameter holds) is borrowed; a constructor's result is owned.
- A `sink` argument clears the caller's flag, and the callee drops the
  value unless it moves it on.
- `= a ( make … )` drops the value `a` held first.

**Drop glue.** A `% Drop` impl releases what only it knows how to (a raw
buffer, an OS resource). The fields the compiler manages (`String`,
`Vec`, library handles, values with a `% Drop` of their own) are dropped
after it returns, as a Rust `Drop`'s fields are. A field the impl
released by hand is emptied and skipped, and one it replaces releases the
value it held. A raw `s` field of a `Drop` type belongs to the impl alone.
A function a `Drop` impl hands its receiver to (a disposer) drops that
parameter by its drop glue — the fields, never the impl again — whether
the value reached it from the impl or straight from its owner. A closure
defined inside an impl is its own function, with no receiver to drop.

A destructor that panics is not run again by the unwind: a value leaves
the panic journal before its destructor runs, and while the destructor
runs its receiver's slot is journaled for the drop glue, so a panic inside
it still releases the fields the receiver holds (§7.2).

A `% Drop` type is dropped by its impl wherever it lives: a local, a
`Vec` element, a struct field. A struct holding one is move-only and gets
a compiler-written drop of its fields. A struct with an enum or
trait-object field is move-only in the same way. A `( dyn Trait v )` box
owns `v`: boxing an owned local moves it in, boxing a borrowed value
copies it.

**Handles.** `String`, `Vec T`, owning structs, owning enums (`Json`,
`TomlValue`), Options and results that own memory, and library handles
are dropped, moved and copied by the same rules:

- **Field reads.** A binding read out of a field (`: String n . s name`)
  borrows that field: `s` moved, consumed or given a new value ends it,
  a call changing another field of `s` does not (h331, h332) — a callee
  handed `s` `inout` ends it only when it may replace that field. A store
  replacing that very field hands the binding the value it held, and a
  `sink` handed the binding takes the field over (a String, Vec or
  handle field, emptied where it lives). A String or a Vec left empty is
  still one; a library handle field left empty holds none, so a binding
  read out of one takes its struct along when it is consumed — handed to
  a `sink`, or to another thread — and reading the struct after is an
  error until it is given a fresh value (h348, h356).
- **`inout` parameters.** An `inout` parameter is the caller's binding,
  in a closure as in a function: never an owner of its own (h347). Given
  a fresh value, it drops the value it held; given a binding that owns
  its value outright, it takes that value over; given one whose value
  another owner keeps — a parameter it only borrows, a binding read out
  of another binding's field, a closure's capture — it gets a copy (h201,
  h345, h346). A cursor over it, or what a call lent back of it, is its
  own value and is stored as is.
- **Cursors.** `: ~ cur root` borrows `root`. Consuming the cursor
  consumes `root`'s value; reassigning the cursor releases nothing.
- **Stores move.** A value stored into a literal, a field or a container
  element leaves its binding. A parameter stored that way makes the
  function keep its argument, which the caller hands over like a `sink`.
- **Borrowed values are copied into owners.** A borrowed value (a `vec_get`
  payload, a field read, a join) stored into a literal, a field or a
  keeping parameter is deep-copied, so the new owner and the old never
  share a buffer. A literal returned as is lends instead, and so does a
  field written back where it was read.
- **Fields.** A field of an owned struct handed to a consumer is emptied
  in the struct, so the struct's drop skips it — and so is one of a
  `vec_get` element (in its slot), an option's payload (in its owner), a
  cursor (in the binding it reads) and an `inout` parameter (in the
  caller's struct). A binding that only borrows its struct — a `vec_at`
  copy, a binding read out of another's field — would have the field
  emptied only in its own copy, and so would a closure's capture: handing
  such a field to a callee that takes it is rejected, since the owner
  still holds it (h394–h400). A field returned out of a
  struct this function owns is copied (or moved, into a returned
  literal).
- **Call results.** Whether a call returns an owned value or a borrow of
  an argument is taken from the callee's summary. A function that lends
  on some paths and returns a fresh value on others answers per call, at
  run time.
- **Values that cannot be copied.** A `% Drop` value with no clone (a
  sqlite `Database`, a `Statement`) read out of a parameter is lent, and
  so is one read out of any field — of a local, or of the value a
  destructor is dropping: the struct still drops it, and a `% Drop` value
  has no empty state to leave in its place (h322, h324–h327). A returned
  literal hands one back only lent by a parameter, as `^ . p f` does, and
  a binding may not borrow one past the block its struct is dropped in
  (h328).
- **A call's result read for a field it cannot give up** — the struct has
  a `% Drop` of its own, or the field cannot be copied — gets an owner of
  its own for the rest of the scope, which drops it, and the field is lent
  out of it as a local's is (h329, h330); a field a read can take apart
  leaves the temporary instead (h266, h323).
  Where a copy would be needed (stored into an owner, handed to a keeping
  callee), compilation stops with an error naming the type.
- **Joins.** A `?` / `??` yielding an owning value hands its binding what
  the chosen arm owned; an arm that yields an outer binding lends it, and
  an arm that ends in a lending call lends what that call does — returned
  from a function, the function lends it (h311).
- **Returns.** A returned binding that does not own what it holds is
  copied on the way out, so the caller always owns the result.

**Ownership primitives** for library code:

| Call | Meaning |
|---|---|
| `( mem_take x )` | `x`, read out of a container by hand, owns that value from here on (`vec_pop`, `vec_remove`); `unsafe` only |
| `( mem_put_back x )` | the next store of `x` through a pointer writes back a value read from that slot; the container keeps owning it; `unsafe` only |
| `( mem_dup x )` | an owned copy: deep for an owning value, the value itself otherwise |
| `( mem_forget x )` | gives up `x`'s value without releasing it; `unsafe` only |
| `( mem_replace [T] place x )` | `x` goes into `place` (a mutable binding, a field of one, or a field through a pointer) and what `place` held comes back, owned; nothing is dropped or copied (stdlib/core/mem.nu, `unsafe`) |
| `( vec_retain [A] v keep )` | the elements `keep` answers T for stay, in order; the rest are dropped, in place (stdlib/core/vec.nu) |
| `( vec_put_back [A] v i x )` | `x`, read out of slot `i` and updated, goes back: the check-in of a table that lends its records by value; a function handing its parameter on to it writes it back too, for its own callers. Nothing checks that `i` is the slot `x` was read from, so it is `unsafe` only, as `mem_put_back` is (h248) |

**Foreign results a caller owns.** A C function returning a string it
allocated declares its result `→ sink s` (spec §7.2): the binding the
result lands in owns it, so nothing frees it by hand.

**Raw memory that releases itself.** A `RawBlock`
(`( raw_block n )`, stdlib/core/mem.nu) is `n` bytes from the C
allocator, released when the block is dropped; code works through a
typed pointer into it (`# *f ( raw_block_ptr xb )`) and frees nothing by
hand. Moved into a struct, it goes with the struct. The pointer is
malloc's own result, so a loop over several blocks keeps the alias facts
a `Vec`'s data pointer, read back from its control block, does not carry.

**Containers drop their elements.** `vec_free` and `vec_clear` drop the
elements, and `vec_append` moves them from one `Vec` to another
(`vec_extend` copies bits, for elements that own nothing).

**Library handles.** A generic struct `S` whose module defines
`S_drop [..] sink ( S .. ) x` is a library handle. Defining `S_clone` (an
owner of copied contents) or `S_share` (another owner of the same value)
makes it copyable. Every instance is owned, dropped and copied like a
`Vec`, and the module keeps its layout private. `HashMap`, `Set`,
`Deque`, `BTree`, `Box`, `Rc`, `Arc` and `Channel` are library handles. A
non-generic struct with `S_drop sink S x` is one too: `Mutex`, `Cond`
and `Semaphore` are each one reference-counted object, and every copy is
the same lock. A program's own `% Drop` impl for an instance wins over
the library's.

A drop hook is its receiver's destructor, as a `% Drop` impl is: the
receiver is never dropped again on the way out of the hook (that would
run the hook again), and its fields are, once the hook returns — so a
hook that only observes the value (logging, counting) needs nothing more,
and one over a counted block gives its receiver up with `mem_forget` in an
`unsafe` hook. A program's own handle whose hook is `unsafe` is sealed:
its literals and field writes are raw memory too (§6.4).

The standard library's own handles hold their state in a
`( Shared T )` (stdlib/core/rcbox.nu): a counted block whose generic hooks
release it, so no handle hook releases anything itself
(`@ Regex_drop sink Regex r → v {}`), and the share hook's
`shared_clone [T]` names the state for the cycle rules (§7.7). Making
one is raw (the standard library's, or `unsafe` code's); a zero handle is
`# Regex # s 0`.

A program's own handle — one state that every copy shares — wraps a
shared handle of the standard library, and every hook and accessor is safe
code. Which one is decided by what the state does:

| The state | Its handle holds | Read | Changed |
|---|---|---|---|
| built once, then only read (an index, a model, a dataset) | `( Arc Impl )` | `arc_get` lends it | never: build it whole, then `arc_new` |
| changed, one thread (a builder, a cursor, a parser's state) | `( Rc Impl )` | `rc_get` lends it | `rc_take` … `rc_restore` |
| changed, shared between threads (a cache, a connection pool) | `( Locked Impl )` | `locked_get` copies it | `locked_take` … `locked_restore` |
| read on every request, changed rarely (keys, a policy) | `( Locked ( Arc Impl ) )` | `locked_get` shares the snapshot | take it, `arc_new` a changed copy, restore |

<!-- doctest-prelude
$ `stdlib/std/rc.nu`
: CacheImpl { i hits }
@ __cache_put inout CacheImpl c s key s val → v { = . c hits + . c hits 1 }
-->
```nurl
: Cache { ( Rc CacheImpl ) a }
@ Cache_share Cache h → Cache { ^ @ Cache { ( rc_clone [CacheImpl] . h a ) } }
@ Cache_drop sink Cache h → v {}
@ cache_new → Cache { ^ @ Cache { ( rc_new [CacheImpl] @ CacheImpl { 0 } ) } }

@ cache_hits Cache h → i { ^ . ( rc_get [CacheImpl] . h a ) hits }

@ cache_put Cache h s key s val → v {
    : ~ CacheImpl c ( rc_take [CacheImpl] . h a )   // the state, checked out
    ( __cache_put c key val )                        // helpers take `inout CacheImpl`
    ( rc_restore [CacheImpl] . h a c )               // …and checked back in
}
```

The empty hook makes `Cache` a handle; its field is dropped once the hook
returns, and the last owner releases the state. A check-out moves the
state into a local — nothing is copied — and every operation on the value
through any copy of the handle panics (`Rc`) or waits (`Locked`) until it
is restored; one never restored (its owner panicked) leaves the handle
empty, and nothing leaks. A helper that changes the state takes it
`inout`, so a public function checks it out once and the helpers it calls
work on the local. Reaching into the state through a pointer (`arc_ptr`,
`rc_ptr`) is `unsafe`, and changing an `Arc`'s payload that way is a data
race once the handle crosses a thread; the counted blocks of
`stdlib/core/rcbox.nu` are the standard library's own.

**Raw memory reached from an `unsafe` structure.** A struct behind a
`nurl_alloc` pointer is not dropped by the compiler. A parameter stored
there only is a view, never dropped by the callee. A field of an owned
local stored there is copied. A parameter's field stored there is taken
over from the caller.

**A field written through a pointer is replaced.** `= . p f v`, `p` a
`*S`, drops what `f` held, as every other `=` drops what it overwrites:
an `unsafe` setter over a handle's state is the store alone.

<!-- doctest-prelude
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/rcbox.nu`
: MetaImpl { ( Vec String ) feats }
: Meta { ( Shared MetaImpl ) ctl }
@ Meta_drop sink Meta h → v {}
unsafe @ _Meta_ptr Meta h → *MetaImpl { ^ ( shared_ptr [MetaImpl] . h ctl ) }
-->
```nurl
unsafe @ meta_set_feats Meta h ( Vec String ) feats → v {
    : *MetaImpl m ( _Meta_ptr h )
    = . m feats feats              // the old list is dropped here
}
```

The memory must hold a value of the field's type, and the compiler sees
to the three ways it might not:

- **Fresh memory is filled, not replaced.** Through a pointer bound to an
  allocation in the same function (`nurl_alloc`, `nurl_malloc`,
  `nurl_zalloc`, `malloc`, `calloc`, `alloc`, `zalloc`, through a cast
  too) a field store drops nothing.
- **Memory handed out for a struct that owns something is zeroed** when
  the allocation is cast to a pointer to it (`# *S ( nurl_alloc Z S )`),
  and a zero value drops as nothing: a helper that fills the struct
  through a parameter replaces zeros. (`nurl_zalloc` / `arc_zero` memory
  is zero already.)
- **A value claimed out of a place leaves a zero behind.** `: T x . p f`
  then `( mem_take x )` empties `p f`, as handing `. p f` to a consumer
  (`( vec_free [u] . p buf )`) does: a later store there replaces nothing
  `x` owns.

A value written back into the slot it was read from (`mem_put_back`, or
`: item . p k … = . p k item`) replaces nothing either: the slot still
holds it. An **element** written through a pointer (`= . p i v`) is a slot
of memory a container manages, past whose length nothing lives: what it
held is not dropped — `vec_push` writes there, and `vec_set` claims the
old element (`mem_take`) before writing the new one.

**SIMD.** A function taking or returning a SIMD vector by value is always
inlined, so callers and callees agree on how the vector is passed.

### 7.7 Reference-count cycles

Reference counting releases a value when its last handle goes, except a
value that holds, through its own contents, a handle to itself: a graph
node listing its neighbours, a parent and child pointing at each other, a
callback stored in the value it captured. NURL collects such cycles.

**Only types that can close a cycle pay.** The compiler walks a payload
type's ownership graph (fields, Option and enum payloads, `Vec` elements,
library handle contents, closure captures) to the `Rc` handles it can
hold. `Rc T` is *cyclic* when that graph leads from `T` back to `T`, or to
a closure. `( mem_cyclic [T] )` answers it as a constant. Every other
instance (`Rc String`, `Rc Config`, a tree whose nodes hold no `Rc` back)
compiles to plain counting.

**The collector** is synchronous trial deletion (Bacon and Rajan) in the
runtime. A cyclic block is `[ strong ][ weak ][ cc ][ value ]`. A handle
that goes without taking the count to zero files its block as a possible
root. When enough roots accumulate, on `( rc_collect )`, and when the
owning context ends (the thread, the fiber, the program), trial deletion
finds the blocks held only by each other, drops their values and frees
them. The compiler generates a trace function for each cyclic type, and a
closure environment's descriptor traces the handles the environment owns.
`Rc` is not `Send`, so every block belongs to one thread or fiber, and
collection takes no lock.

**Memory waits, resources do not.** A value whose last handle goes is
dropped immediately, cyclic type or not. Only a value already caught in
an unreachable cycle waits for a collection. That is invisible for
memory, but not for a file or a socket, so:

- A type whose drop is externally observable carries `% Resource`
  (`stdlib/core/marker.nu`): `File`, `BufReader`, `UdpSocket`, `TlsConn`,
  `HttpConn`, `QuicClient`, `ProcChild`, `Database`, `Statement`. Anything
  that owns one is one by structure, and `( mem_resource [T] )` answers it
  as a constant. Releasing memory, a lock or a count is not observable:
  `Mutex` is not a resource. Mark a type of your own when its drop does
  something the outside world sees.
- A cyclic `Rc` of a resource type is collected the moment it may have
  become garbage: a handle that goes without taking the count to zero runs
  trial deletion from that block at once, so the cycle's files close where
  the last outside handle went. Inside a container's release this waits
  until the release finishes, so dropping a `Vec` of handles into one
  graph is a single pass.
- Tearing such a structure down is linear. Rewiring a large *live*
  resource-capable graph is not: every replaced edge that leaves a count
  above zero walks the graph to find it still alive. Keep a large mutable
  graph's OS handles outside it (a table the nodes refer to by index) so
  the graph's type is not resource-capable.
- A resource hidden from the type (behind a `dyn`, inside closure
  captures) is released by the collector. When opening a file or socket
  fails for lack of descriptors (EMFILE / ENFILE), the current context's
  unreachable cycles are collected and the open is retried once.

**Long chains** are released without recursion: a release nests at most
64 deep and queues the rest, so dropping the head of a million-node list
does not overflow the stack.

**Weak handles.** `rc_downgrade` / `weak_upgrade` give a non-owning
handle for a back-edge. The value is dropped when the strong count reaches
zero, and the block is freed when the weak count is zero too.

**Thread-shared handles cannot form cycles.** `Arc`, `Channel`,
`DChannel` and the library handles over a counted block cross threads,
and a collector for them would have to stop every thread at a safe point.
Their cycles are rejected at compile time instead:

- **An `Arc` whose payload can lead back to it is frozen once made.**
  `( mem_ts_cyclic [( Arc T )] )` walks the thread-shared graph. Every
  `Arc`'s payload is frozen in safe code (§6.5): what `arc_get` lends is
  a view no call may change, so nothing stored through it can close a
  cycle. For such an `Arc`, `arc_set` / `arc_ptr` are compile errors even
  in `unsafe` code. The payload is built first and shared whole, a tree
  from its leaves up. A trait object reads as any other payload: a
  `( Arc %Job )` lends its object, and a method called on it runs on the
  shared box (the trait declares `: Send Sync` for that to cross a
  thread). `ArcWeak` (`arc_downgrade` / `arc_weak_upgrade`)
  points back without owning. A closure inside a library handle's state
  (a job handler, a route) is not followed by this walk: it reached that
  state through a call handed the handle, which the store rule below
  checked, so a cycle through it would pass through the handle and was
  refused there.
- **A store into an existing thread-shared handle may not lead back to
  it.** A call that keeps a value and is handed an existing thread-shared
  handle (`chan_send ch v`, `job_register node … f`,
  `supervisor_add sup … start`) is checked: if the value, or a closure's
  captures, can reach that handle, it is a compile error. A handle value
  stored there is judged by its type, so a structure of shared handles is
  built from its leaves up or points back with a weak reference. A closure
  whose captures cannot be followed is rejected rather than guessed at.

A cycle through raw memory (a hand-written `*T`, `rc_ptr` stores,
`mem_forget`) is invisible, as raw memory always is (§7.4), and exists
only in `unsafe` code.
