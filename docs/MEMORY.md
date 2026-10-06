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
  races and the panic path included.
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
  field is tracked on its own),
- a value of a type with a `% Drop` impl.

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

```nurl
( nurl_eprint ( nurl_str_int . resp status ) )   // released after the call
: i n ( takes ( string_from `x` ) )              // likewise
```

### Explicit early release

A release call on an owned binding is allowed and moves the value: the
binding is consumed and its drop does not run again.

```nurl
: String s ( string_from `x` )
: i n ( string_len s )
( string_free s )      // redundant: s is dropped right here anyway
^ n
```

When such a call sits at the tail of its scope it is redundant, and
`--lint` reports it as `[redundant-free]`. An earlier release (more code
follows it) is legitimate; it lowers peak memory.

### Parameter passing conventions

A parameter has one of three conventions:

| Convention | Spelling | Meaning |
|---|---|---|
| `in` | default (may be written) | an immutable borrow; a struct argument is copied into the callee's frame |
| `inout` | `inout T x` | an exclusive mutable borrow; passed by address |
| `sink` | `sink T x` | the callee takes ownership; the caller's binding is consumed |

**`inout`.** The argument must be a mutable (`: ~`) binding or a field of
one (`. obj field`), and the callee's writes land in the caller's storage.
A value assigned through an `inout` parameter replaces the caller's and
drops what it overwrites. A field the callee hands to a consumer, or takes
with `mem_take`, is emptied in the caller's struct, so nothing is released
twice. Reassigning an `inout` raw string (`s`) is an error, because the
callee cannot know whether the caller's old string is owned.

```nurl
@ bump inout Counter c → v { = . c n + . c n 1 }
: ~ Counter c @ Counter { 0 10 }
( bump c )                       // c.n is now 1 in the caller
```

**`sink`.** The callee owns the argument and drops it unless it moves it
on (returns it, stores it, passes it to another `sink`). Using the
caller's binding afterwards is a use-after-move.

```nurl
@ give_away sink ( Vec i ) g → v {}   // g is dropped here, by the callee
: ( Vec i ) xs ( vec_new [i] )
( give_away xs )                       // xs is consumed
```

**Inferred `sink`.** A parameter does not have to be spelled `sink` to be
one. If the body consumes it (releases it, stores it in an owner, passes
it to another `sink` position) or returns it, the parameter is a `sink`
for every caller:

```nurl
@ dispose ( Vec i ) xs → v { ( vec_free [i] xs ) }   // param 0 is a sink
( dispose xs ) ( dispose xs )                          // use-after-move at the second call
```

Inference is decided after the whole module is compiled, so the order in
which functions are defined never changes the result. A function's name
and return type are never evidence of consumption. A destructor that
releases fields or raw memory declares its consuming parameter
explicitly.

**Closure parameters** are always borrowed (§7.5).

One implementation limit remains: a raw owned string (`s`) and an owned
slice cannot be passed to an explicit `sink` parameter. Wrap them in a
`String` / `Vec`.

## 2. The ownership rules

The rules below are checked on every compile. They are a static analysis
only: they never change generated code, so an accepted program compiles
to the same IR with or without them. A violation is an `error:` that
stops the build, and every violation in a run is reported.

`--no-borrowck` is deprecated and prints a warning: a program compiled
without the checker is not held to the rules, so nothing guarantees it is
memory-safe. A correct program the rules reject is a bug worth reporting.

### 2.1 Moves — use after move

An owned value moves out of a binding when it is:

- passed to a `sink` parameter (explicit or inferred),
- stored into an aggregate literal, an Option, a container or a field,
- sent through a channel,
- returned,
- copied into another immutable binding (§2.2),
- captured by a closure that runs on another thread or fiber.

Reading the binding afterwards is an error:

```
error: use of moved value 'v' - it was consumed at line N
```

Rebinding the name (`:` or `=`) makes it usable again.

A value moved on only **some** paths is *maybe-moved*. Reading it is an
error too, because on the path that moved it the read touches released
memory:

```
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

A value with nothing to release (a struct of scalars, an enum of unit
variants) is copied, never moved.

### 2.1b Releasing what the compiler releases

Inside an `unsafe` function, `nurl_free` on a binding the compiler already
drops (an owned string, slice, `Drop` value or owning struct) would free
it twice, and is an error:

```
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

A closure that captures a `: ~` mutable multi-field struct captures it by
pointer into the enclosing frame. Such a value is a *stack reference* and
must not outlive that frame. The checker tracks the scope depth a stack
reference points into, through bindings, assignments, field stores,
aggregate and closure literals, and `?` / `??` joins. An escape is an
error when a stack reference reaches:

- a `^` return,
- a container (`vec_push`, `vec_insert`, `vec_set`) or a thread
  (`thread_spawn`),
- an assignment into a binding of a longer-lived scope.

```
error: returning a value that references a stack binding by pointer
         - it dangles after this function returns
         (move the captured data to a heap-backed handle)
```

Closures that capture by value (an immutable `:` capture, a single-handle
struct) never escape this way.

### 2.4 Exclusive access for `inout` arguments

An `inout` argument is an exclusive mutable borrow for the duration of
its call. Passing the same binding again in the same call, as another
`inout` or as an ordinary argument, is an error:

```
( swap_counters c c )    // error: 'c' is both mutably borrowed
                         //        and aliased by another argument
```

Reads of the binding inside other arguments (`( grow v ( vec_len v ) )`)
are evaluated before the call runs and are allowed.

### 2.5 Iterator invalidation

A foreach loop `~ x xs { … }` borrows `xs` for its body. Mutating `xs`
inside the body is an error:

```
~ x xs { ( vec_push xs x ) }   // error: cannot mutate 'xs'
                               //        while iterating over it
```

This covers the stdlib mutators (`vec_push`, `vec_insert`, `vec_remove`,
`vec_pop`, `vec_clear`, `vec_set`, `vec_reserve`, `vec_extend`,
`vec_free`, `vec_swap`, `vec_reverse`, …), an `inout` argument naming the
container, and any function that mutates the container passed to it,
wherever that function is defined. A counter loop (`~ < k n { … }`)
borrows nothing, so `vec_set xs k v` inside it is allowed.

### 2.6 Loop-carried moves

A loop body runs more than once. A binding that existed before the loop
and is consumed in the body, without being rebound before the next
iteration, is moved when the next iteration reads it:

```
: ( Vec i ) xs ( vec_new [i] )
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

```
@ detach ( @ v ) cb → v { ( thread_spawn cb ) }   // param 0 escapes
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

```
@ id ( @ v ) cb → ( @ v ) { ^ cb }
: ( @ v ) f \ → v { = . c n + . c n 1 }
^ ( id f )                  // error: returning a value that references
                            //        a stack binding by pointer …
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

```
: *u p ( vec_data [u] v )
( vec_push [u] v # u 1 )       // may reallocate
: i x # i . p 0                // error: pointer 'p' borrowed from 'v' is
                               //        stale: 'v' was mutated on line N
```

Fetch the view again after the mutation. The rule applies in `unsafe`
code too, because it is decided from the program text, not from the
capacity at run time. A mutation inside one `?` arm does not end a view
in the other arm, and a function that mutates the container passed to it
ends views exactly as an inline mutation does, wherever it is defined.

### 2.11 Closures hold their captures

A closure holds every value it captured for as long as it can run.
Invoking a closure reads all of its captures, so releasing a capture
through its original name and then invoking the closure is a use after
move:

```
: ( Vec i ) v ( vec_new [i] )
: ( @ i ) f \ → i { ^ ( vec_len [i] v ) }
( vec_free [i] v )
( nurl_println_int ( f ) )     // error: use of moved value 'v' …
                               //        the closure 'f' still holds 'v'
```

This holds for a direct call, for a call through a function that invokes
its closure parameter, for a closure captured by another closure, and for
a mutation inside the body as much as a read. Capturing an
already-released value is rejected at the closure literal. A closure
stored into a struct, or handed to a function that keeps it, makes that
owner depend on the captures: releasing a capture while the owner may
still run the closure is an error. Loading a closure value, and dropping
the closure's own environment at the end of its scope, is not a use.

### 2.12 A stored value belongs to its owner

A value stored into an owner (an aggregate literal, a container through
`vec_push` or `map_set`, a function that keeps its parameter) belongs to
that owner. Releasing it again through the original name is an error:

```
error: 's' is consumed here, but its value was stored into an owner at line N …
```

To hand a value on and keep one, store a copy (`string_clone`,
`vec_clone`, `mem_dup`).

## 3. Outside the rules

The rules cover all safe code. What they do not check is a stated
boundary:

- **The body of an `unsafe` function.** Raw pointers, pointer casts, the
  raw-memory primitives and foreign calls are allowed only there, and the
  function's author vouches for it (spec §3.3d).
- **Marker assertions.** `% Send`, `% Sync`, `% NotSend`, `% NotSync` and
  `% Resource` are assertions about a type the compiler cannot verify
  (§6.5, §7.7).
- **Whether a lock is held.** Mutation of shared state outside a `Mutex`
  is rejected, but whether a `mutex_lock` is held at a given point is
  counted, not proved per path (§6.5).
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
  bounds-checked and compile to the same loop as raw pointer access.
  `vec_data` + `unsafe` is not faster.
- **Share mutable state through a handle.** Between threads use `Channel`,
  `Mutex` or `Arc` (§6.5). Within a thread, to share a closure beyond the
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
| Stale view after reallocation | §2.10 |
| Releasing a value a closure still holds | §2.11 |
| Borrow used after its owner moved, ended, or was reassigned | §6.2 |
| Non-shareable value crossing a thread boundary | §6.5 |
| Shared mutation outside a lock | §6.5 |
| Cycle of thread-shared handles | §7.7 |
| Out-of-bounds element access | bounds-checked (`vec_at` panics, `vec_get` returns None) |
| Raw pointers, casts, raw memory, foreign calls | only inside `unsafe` (spec §3.3d) |

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
- **A view also ends at reallocation.** `string_data` / `vec_data` are
  views of the buffer and end at any mutation that may reallocate it
  (§2.10).
- **A container keeps what it is handed.** A view stored in a `Vec`, used
  as a map key or handed to a function that keeps its argument may live no
  longer than its source.
- **Threads and fibers.** A closure run on another thread or fiber moves
  its captures. Handles whose copy is a share of one object (`Channel`,
  `Mutex`, `Arc`, `HttpServer`) are captured as a share of their own, so
  both sides keep using them and either may end first. Shared mutable
  state goes through one of those handles (§6.5).
- **Raw memory only in `unsafe`** (spec §3.3d).

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
  leak-free for every caller. `nurlc --unsafe-report` lists those a
  program contains outside the standard library, which is the whole
  surface a reviewer of that program has to trust.
- **The standard library and the runtime.** Their raw code, the `Rc`
  cycle collector and the panic journal included, is the base every safe
  program stands on.
- **Marker assertions** (`% Send`, `% Sync`, `% NotSend`, `% NotSync`,
  `% Resource`) on types whose safety the compiler cannot see.
- **The compiler itself.** A program accepted in violation of §6.2 is a
  compiler bug (§6.6).

### 6.5 Threads, and how this compares to Rust

The model uses Rust's vocabulary (move, borrow, readers XOR writer) for
ideas that are genuinely analogous, but the mechanics differ:

- Ownership is single-owner with scope-bound drop. There are **no
  lifetimes** in types, no lifetime parameters and no lifetime syntax.
- A borrow cannot be stored in a struct or outlive the call or scope that
  produced it. Where Rust would store a reference, NURL code stores an
  owned copy, an `Rc` / `Arc`, or an index into an owning container.
- `in` / `inout` / `sink` are call conventions resolved per call, not
  reference types.
- Leaks are part of the guarantee. Safe Rust permits leaks
  (`mem::forget`, `Rc` cycles); in NURL `mem_forget` is `unsafe` and `Rc`
  cycles are collected.

**Send and Sync.** `Send` ("may move to another thread") and `Sync` ("may
be reached from two threads at once") are marker traits
(`stdlib/core/marker.nu`) that the compiler derives structurally over a
type's whole graph: struct fields, enum payloads, generic arguments,
aggregate members and closure captures. Two leaves are built in:

| | Send | Sync | why |
|---|---|---|---|
| `Rc` | ✗ | ✗ | the reference count is not atomic |
| `Cell` | ✓ | ✗ | a raw byte buffer with unsynchronised writes |
| everything else | ✓ | ✓ | unless a field says otherwise |

They are checked where a value crosses: `thread_spawn` and `spawn` (every
capture must be Send), `chan_send` (the value must be Send), and `Arc T`
(T must be Send and Sync). `[T: Send]` bounds are answered by the same
derivation.

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
handle). A negative marker outranks a positive one on the same type.

**Shared mutation.** A closure run on another thread moves its captures,
so the spawner cannot keep using a plain `Vec` a worker was handed. Only
share handles (`Channel`, `Mutex`, `Arc`) are used on both sides. A
thread that mutates the contents of an `Arc` it did not create, without
holding a lock, is rejected: `Arc` makes the reference count atomic, not
the data. Put the data behind a `Mutex`. Whether the lock is held is
counted over `mutex_lock` / `mutex_unlock` calls, not proved per path
(§3).

### 6.6 How the guarantee is checked

The guarantee is a property of the rules. The compiler's implementation
of them is tested continuously:

- **Hole probes.** Every way safe code has been shown to break the
  guarantee is kept as a program that must be rejected.
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
- On a panic, the values still recorded since the target frame's mark are
  released before the jump, while their frames are still valid.

The journal belongs to the thread outside fibers and to the fiber inside
one. The scheduler switches it with the fiber, so fibers sharing a worker,
or moving between workers, never drain each other's extents. Functions
that cannot reach a panic do not register anything and pay nothing.

### 7.3 What a panic does not reclaim

Raw memory managed by an `unsafe` function (§7.4) is never auto-dropped,
so a panic that abandons it mid-scope leaks it, exactly as omitting its
`nurl_free` would. An `unsafe` function that holds raw memory across a
call that may panic keeps it in the caller's frame (`stdlib/std/panic.nu`
shows the pattern).

### 7.4 Raw memory

The compiler does not track memory allocated as raw bytes (`nurl_alloc`
behind a `*T`) or a value given up with `mem_forget`. Both are possible
only in `unsafe` code, which releases them with `nurl_free`.

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
| a struct field | the struct, with its other fields; copying the struct copies the environment |
| a slice of closures | the slice, element by element |
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
`{ size, drop, clone }`. `nurl_closure_drop` (null-safe) is what every
owner calls. Releasing an environment by hand is a compile error.
`unsafe` code that hands an environment to C and needs it past the call
keeps a `nurl_closure_clone` and releases that with `nurl_closure_drop`.

A closure run by a thread or fiber moves the bindings it captures into its
environment (§6.2); share handles are captured as a share of their own.

**Closure parameters are always borrowed.** A call through a closure value
cannot see what the body does with its arguments, so the contract is
fixed:

- the caller keeps what it passes and drops a temporary it made for the
  call right after it;
- what the body stores or returns is a copy, and every closure result is
  owned by its caller;
- releasing a parameter inside the body is a compile error.

Accordingly, every `*_free_with` (`vec_free_with`, `box_free_with`,
`rc_free_with`, `arc_free_with`, `btree_free_with`, …) *lends* each
element to its hook and then drops the container as `*_free` does. A hook
is for teardown the element type does not do itself (counting, logging,
closing a foreign handle), never for releasing what the container owns.

A `String` or `Vec` captured by value is a snapshot the body may modify
locally: an assignment to it is discarded when the closure returns (the
compiler warns), and the assigned value is dropped then.

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
released by hand is emptied and skipped. A raw `s` field of a `Drop` type
belongs to the impl alone. A function a `Drop` impl hands its receiver to
(a disposer) never drops that parameter itself.

A `% Drop` type is dropped by its impl wherever it lives: a local, a
`Vec` element, a struct field. A struct holding one is move-only and gets
a compiler-written drop of its fields. A struct with an enum or
trait-object field is move-only in the same way. A `( dyn Trait v )` box
owns `v`: boxing an owned local moves it in, boxing a borrowed value
copies it.

**Handles.** `String`, `Vec T`, owning structs, owning enums (`Json`,
`TomlValue`), Options and results that own memory, and library handles
are dropped, moved and copied by the same rules:

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
  in the struct, so the struct's drop skips it. A field returned out of a
  struct this function owns is copied (or moved, into a returned
  literal).
- **Call results.** Whether a call returns an owned value or a borrow of
  an argument is taken from the callee's summary. A function that lends
  on some paths and returns a fresh value on others answers per call, at
  run time.
- **Values that cannot be copied.** A `% Drop` value with no clone (a
  sqlite `Database`, a `Statement`) read out of a parameter is lent.
  Where a copy would be needed (stored into an owner, handed to a keeping
  callee), compilation stops with an error naming the type.
- **Joins.** A `?` / `??` yielding an owning value hands its binding what
  the chosen arm owned; an arm that yields an outer binding lends it.
- **Returns.** A returned binding that does not own what it holds is
  copied on the way out, so the caller always owns the result.

**Ownership primitives** for library code:

| Call | Meaning |
|---|---|
| `( mem_take x )` | `x`, read out of a container by hand, owns that value from here on (`vec_pop`, `vec_remove`) |
| `( mem_put_back x )` | the next store of `x` through a pointer writes back a value read from that slot; the container keeps owning it |
| `( mem_dup x )` | an owned copy: deep for an owning value, the value itself otherwise |
| `( mem_forget x )` | gives up `x`'s value without releasing it; `unsafe` only |

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

**Raw memory reached from an `unsafe` structure.** A struct behind a
`nurl_alloc` pointer is not dropped by the compiler. A parameter stored
there only is a view, never dropped by the callee. A field of an owned
local stored there is copied. A parameter's field stored there is taken
over from the caller.

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
  `( mem_ts_cyclic [( Arc T )] )` walks the thread-shared graph. For such
  an `Arc`, `arc_get` returns a copy, and `arc_set` / `arc_ptr` are
  compile errors. The payload is built first and shared whole, a tree
  from its leaves up. `ArcWeak` (`arc_downgrade` / `arc_weak_upgrade`)
  points back without owning.
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
