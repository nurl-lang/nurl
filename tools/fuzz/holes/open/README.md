# tools/fuzz/holes/open — soundness holes known open

**None.** The last classes, agora #145 and #144, are closed and
graduated as `h389`–`h407`, found by a hunt along one shape — a field
handed to a callee that takes it — in every context:

| Probes | What happened | How it is closed |
|---|---|---|
| `h389`–`h393`, `h396`, `h397` | A function that handed a field of its by-value parameter to a consumer owned the parameter and dropped the rest, but its caller's binding was not moved: the caller read the struct after the call (directly, through a field viewer, a forward callee, a method; a `vec_at` copy handed to it) | The parameter is an inferred `sink` (`__param_field_taken`) |
| `h394`, `h395`, `h398` | A field of a `vec_at` copy or of a field viewer, handed to a taker, was emptied only in that copy; its owner released it again | Rejected: gen_call's `pendfx` row, decided on the callee's final summary |
| `h399`, `h400` | A closure handed a field of its capture to a taker | Rejected: a `pendfc` row |
| `h401`–`h404` | A closure or a view over a struct outlived a field of it handed to a `sink` | The borrow sweep ends them as at a field replaced |
| `h405`–`h407` | A field assigned through a by-reference capture leaked what it held (agora #144) | Released under the binding's drop flag; a borrowed binding's field cannot be assigned there |

Before them, agora #141, closed and graduated as
`h384`–`h388`: a closure a function returns over a parameter it did not
take over — bound to a local first, joined, given a new value, or over a
local view of the parameter — was not recorded as a view of the caller's
argument (the function's `retclo` summary saw only a literal written in
the `^`), and the caller freed the argument under it. What a returned
value that may hold a closure lends is now read off its source
expression, through the frame's closures, views and borrows.

Before it, two classes closed and graduated as `h378`–`h383`:

| Probes | What happened | How it is closed |
|---|---|---|
| `h378`–`h381` | A view of a call's temporary argument kept past its statement — a binding of it (`: s v ( first ( string_from … ) )`), a closure over the temporary, the view returned, or handed to a callee that keeps it — left the temporary owned by nothing: it leaked (agora #138) | A temporary a call's result may view waits for a call further out that consumes the view; one that no call consumes is rejected once the module-end summaries say the caller owned it (`resolve_view_temps`): bind the argument to a name first |
| `h382`, `h383` | A `UdpSocket` was the runtime record's address with no drop: read after `udp_close` it read freed memory, and one never closed leaked its record and fd (agora #139) | A shared handle with a drop (`UdpSocketImpl`); `udp_close` only stops the socket, and its last owner releases it. Handing one to a fiber as its only owner needed the payload of an option binding to move with the closure (agora #140) |

Before them: `h371`–`h377` (agora #132, #131): an assignment's value
dropped by the `?` statement it ended, a binding given its own value back
through a join, and closure envs a panic skipped. Before them `h367`–`h370`
(agora #135), an `inout` argument whose
binding does not own its value — a cursor over another binding, a field
read, a value `arc_get` lends — handed to a callee that gives the
parameter, or a field of it, a new value: the callee released what the
other owner held (and `h370`, the local a copy took the drop of, read after
such a call). The rule that refused the shape (`h295`) had covered only a
`: ~` copy of a parameter.

Before them, found reading a trait object out of an `Arc` (agora
#128): `h364`–`h366`, a method called through a trait object did less to
its arguments than its impls do — an `inout` receiver writing the box a
read guard lends, a field it replaced leaving a view of it reading freed
memory, and both through a helper that hands its parameter on.

Before them, the last open one, `library_handle_copy_on_two_threads.nu` — a
share of a library handle made before the handle moved to a thread, kept
by the spawner while both threads changed one state — is closed and
graduated as `h349` (agora #121), with the rest of its class: a literal
storing `. h c` (`h350`), a share in a `Vec` (`h351`), a channel
(`h352`), a `Locked`'s value going in, changed under the lock and copied
out (`h353`–`h355`), a field read taken by a thread (`h356`), an
`RwLocked` (`h357`), an `Rc` in a `Locked` in an `Arc` (`h358`) and a
trait object's box (`h360`). A crossing to another thread now checks at
run time that it leaves no owner of a handle whose copies are one state
behind (`mem_send_check`, docs/MEMORY.md §6.5); the `RwLocked` and `Arc`
cases are rejected at compile time. Found on the way and closed with them:
`h345`–`h348`, an `inout` parameter given a binding it does not own (a
field read, a closure's capture) or a fresh value in a closure, and a
library handle field read after the binding read out of it was consumed;
`h359`, an index panic that skipped the journal's registrations; and
`h361`–`h363`, a trait object moved into a literal, a `sink` parameter
or a closure, dropped once more by a later panic.
The rest of the class closed before: `h254` (SymTab, `% NotSync`), `h319`
(the membership table dist/heartbeat.nu's thread read, `% NotSend`),
`h333` (a binding read out of a struct's field, a borrow the thread's
move of the struct ends), and `h336`–`h340` (agora #66): a thread's
capture of a handle not asserted `% Sync` moves it, a parameter of one
may not be captured, it is not Sync (an `Arc` of one, a closure capturing
one kept in an `Arc`), and a closure carrying one onto a channel takes it
along; `h342`, a closure several threads run changing what it captured.
`h341`, found on the way, is a listener accepted on after its close.

Every probe this directory held is closed and graduated to the CI
gate in the parent directory. Before `h345`–`h363` came `h344` — a trait
object (`%Churn`) boxing an `Rc` crossed to a thread, because the
Send/Sync derivation saw no field inside one (agora #127); before it
`h343` — an MCP task
handle (`s`, from `mcp_task_create`) kept past its task, which the
store's eviction at its cap or a sweep past the TTL freed (agora #124);
before it `h316` — a call returning
a SIMD vector kept its temporary argument alive for a consumer a binding
never is (leak) — and before it `h311`–`h315`: lends
returned through a join (`lru_get`) and a match's scrutinee taking effect
late — and before them `h299`–`h310`: closures
that outlived what they read (a closure a call returned over its argument,
the standard library's iterators, a by-value capture whose binding was
given a new value or replaced through `inout`) and `map_keys` leaking owned
keys. Before them, `h288`–`h298`, found
building a multi-threaded database (`packages/nurldb`): a helper lending an
`Arc`'s payload unfrozen through a struct, a foreign write into a frozen
view, a lock guard held in a struct never released, drops a panic skipped
or kept registered, a temporary or a thread's message a panic leaked, and a
parameter's copy passed `inout` to a function that replaces one of its
fields, and a closure replaced through an `inout` parameter or handed a
captured binding to one.

A probe here is **safe code** (no `unsafe` function of its own, no raw
memory or FFI of its own) that the compiler still **accepts** and that then
leaks, frees memory it does not own, frees memory twice or reads freed
memory under ASan/LSan/UBSan: a known issue of the release, listed in
[`docs/MEMORY.md` §6.2](../../../../docs/MEMORY.md) beside the guarantee
until it is closed. Each file's header starts with `// OPEN in <version> —
…` and says what the program does, why it is unsound and what the sanitizer
reports.

Probes here are kept **out of the CI gate**: `../check.sh` with no arguments
runs only `h*.nu` (and `stdlib/h*.nu`) in the parent directory, where every
probe must be REJECTED or run clean. Run these by hand:

```sh
cd tools/fuzz/holes
./check.sh open/*.nu        # reports each as HOLE
```

A probe that prints REJECTED or ACCEPTED (ran clean) here has been closed —
graduate it (below).

## Closed

The 34 probes the 0.72.0 release review left open are closed and graduated
as h145–h178 (h178 under `stdlib/`: it must sit in a directory named
`stdlib`); h142–h144 were closed before them, and h179, a view stored into a
field of a struct that outlives it, was found and closed on the way:

| Class | Probes | How it is closed |
|---|---|---|
| raw string handed to `string_adopt` / a `sink s` | h161–h170 | In safe code only a declared `sink` takes a raw string over, and its callee releases it like a local; a caller hands over its own string, or a copy of anything else (MEMORY.md §1) |
| a view leaving through a call's result | h174–h177 | A returned call result that may lend a released string is the caller's own (the callee's string, or a copy); a call's result holds views of what the callee lends, stores or hands back inside it |
| a view stored into what the caller holds | h171–h173 | Storage the caller holds (a parameter, an alias of one, an `inout` struct) may not keep a view of a binding released here; a field store records the view |
| `mem_forget` / `mem_take` / `rcbox_*` in safe code | h151–h160 | `unsafe` only (spec §3.3d) |
| destructors | h146–h150 | A disposer's parameter drops by its drop glue; a value leaves the journal before its destructor runs, which journals its receiver's glue; a replaced receiver field is released; a closure in an impl has no destructor context |
| closure call with a fresh string | h145 | Released after the call |
| trust by `/stdlib/` path | stdlib/h178 | Only a file inside the real standard-library tree is trusted |

## Graduating a probe

When a fix makes a probe REJECTED, or makes it run clean under the
sanitizers, move it to `tools/fuzz/holes/` as the next free number
(`ls ../h*.nu` for the highest in use), with a one-line `// H<NNN>: …`
header in the style of the others. The CI step "Soundness hole probes"
(`./tools/fuzz/holes/check.sh`) then holds it: a later change that reopens
the hole fails the build. Then update this README and the open-hole lists in
`docs/MEMORY.md` §6.2 and `docs/LIMITATIONS.md`.
