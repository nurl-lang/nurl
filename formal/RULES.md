# Rules → formal rules

Every ownership rule of [`docs/MEMORY.md`](../docs/MEMORY.md) and the
phase that formalizes it. A rule is **done** when its typing rule is
stated, used in the soundness proof, and every hole probe it is meant to
reject is mapped to it in [`corpus/map.tsv`](corpus/map.tsv).

Formal rules are Lean names in [`A1/`](A1/) and [`A2/`](A2/) (the same
names, extended): typing rules are constructors of `StmtT`, `RhsT`,
`PushArg` and the call check `CallT`; `kill`, `exitScope` and `derive`
are the context operations they use. A1's calculus has owned `Vec` trees
(a `String` is a `Vec` of bytes); A2 adds structs, enums, closures and
trait objects, panics and the drop journal; threads are A3.

| MEMORY.md | Rule | Phase | Formal rule | Status |
|---|---|---|---|---|
| §1, §7.6 | Single owner, drop flags, auto-drop | A1 | an owner's slot is `⟨own, some tree⟩`, a released or moved one `⟨own, none⟩` (the drop flag); `HeapOK` (one owner per allocation); `Step.scopeSkip` + `DropSlot`; `exitScope` | done |
| §2.1 | Moves — use after move | A1 | `RhsT.moveOwn`, `PushArg.move`, `CallT` (`sink`): the moved binding is dead (`live := false`) and every read needs a live entry; a moved argument is passed nowhere else in the call and reached from no other argument | done |
| §2.1b | Releasing what the compiler releases | A1 / B | `StmtT.free` releases only a live owner and kills it; inside `unsafe` is B | done for safe code |
| §2.2 | Second names | A1 | `RhsT.moveOwn` (an owner moves), `RhsT.copyBor`, `RhsT.copyRoot`, `RhsT.borrow` (a borrow is copied and depends on the root, `derive`) | done |
| §2.3 | Stack references must not escape | A1 / A2 | for borrows and views: `exitScope` ends them with their root, `FnOK` lets a result depend only on parameters; a closure's captures by handle are what it depends on (`RhsT.pack`: `D`), by name what it holds (`capDeps`), ended with their binding (`exitScope`, `kill`) | done |
| §2.4 | Exclusive access for `inout` arguments | A1 | `CallT`: an argument that moves or may change is not lent out (`F`), is passed once, and is reached from no other argument; `paramOK`, `canDo` (the `inout` bound) | done |
| §2.5 | Iterator invalidation | A1 | a borrow of `xs` depends on `xs`: `StmtT.push` (`kill .realloc`), `RhsT.pop` (`kill .drop`), `StmtT.assign` and `StmtT.free` (`kill .replace`) end it | done |
| §2.6 | Loop-carried moves | A1 | `StmtT.while`: the body ends in the context it starts in | done |
| §2.7 | Escape through a callee | A1 / A2 / A3 | `CallT` against the callee's summary: what the result borrows (`lends`) and holds (`rholds`), what the callee stores into `inout` arguments (`outHolds`), its effect bound on each; `FnOK` checks the body against it; a closure handed to a callee is held by its result (`heldOfArgs`) and run as the callee may (`NamesFree`, `mutNames`); threads are A3 | done |
| §2.8 | Escape through a return | A1 / A2 | `FnOK` (the result depends only on what `lends` / `rholds` name), `callRes` at the call; a call through a package lends from the receiver too (`recvRes`) | done |
| §2.10 | Views end when their source may reallocate | A1 | `RhsT.view`, `RhsT.sat`; `StmtT.push` (`Eff.realloc` ends views, and element borrows when elements hold views); `PushArg` / `held` (a view in a container is still a view); `outHolds` (a callee storing a view into an argument) | done |
| §2.12 | A stored value belongs to its owner | A1 / A2 | `PushArg.move`, `CallT` (`sink`); aggregate literals (`RhsT.pair`, `RhsT.inl`, `RhsT.inr`) move or copy what they store, a field taken out (`takel`, `taker`, `unpair`) moves | done |
| §2.13 | A raw string in a value is a view | A1 / A2 | a string view is a `slice` entry (`RhsT.view`) depending on its owner; a view stored in an aggregate or a package makes that value depend on what it views (`ViewsOK`, `held`) | done |
| §2.11, §7.5 | Closures hold their captures | A2 | `RhsT.pack` (`CapsOK`: captures by handle are depended on, by name held, each read or changed within its bound); `StmtT.callc` (the call through a package: `CallT` on the code with the captures as `inout` arguments of their own, `NamesFree` — a binding a closure may change is changed by the call and reached from no argument but by a closure that changes it the same way — and no argument is such a binding); `sigCtx` / `symNames` (a closure a callee is handed may change the callee's `inout` parameters); `ValOK.pkg` / `envDeps` (the environment); `A2/CAPTURES_DESIGN.md` | done |
| §7.2, §7.3 | Panics and the drop journal | A2 | the panic steps unwind to `StmtT.catchR` (`recover`: `StmtT.letrec`, `recStmt`) through the journal, dropping what each scope owns (`A2/Panic.lean`); `no_leak_end` (`A2/Leak.lean`) | done |
| §7.7 | Reference-count cycles | B | `Rc` and its collector are the standard library's `unsafe` base | not started |
| §6.5 | Threads: `Send`, `Sync`, `Arc`, `Mutex`, `Locked`, `RwLocked` and `% Frozen`, `Atomic`, `PFile`, channels | A3 | — | not started |
| §3, §6.4 | `unsafe` boundary and the trusted base | B | — | not started |

## Changes to MEMORY.md and what they do to the proof

Every change to the rules of `docs/MEMORY.md` is recorded here with its
effect on the formal rules: whether it touches a rule that is proven
(**done** above), and whether it **extends** the calculus (a new rule, or
a rule made to reject more: every existing proof still holds) or
**breaks** a proof (a rule made to accept more, which reopens its lemmas).

| Change | MEMORY.md | Touches a proven rule? | Effect |
|---|---|---|---|
| A positive `% Send` / `% Sync` outside the standard library is `unsafe % Send T { }`; `% NotSend`, `% NotSync`, `% Frozen` and `% Resource` stay safe (they only add checks); the `in` / `sync` / `nocapture` claims and the standard library's own markers are in the trusted base, and `--unsafe-report` lists the program's | §3, §6.4, §6.5 | no: threads are A3 and the trusted base is B, neither started | extension: safe code is rejected more. A1 and A2 have no markers and no threads, so no lemma moves; A3 takes an `unsafe % Send` / `unsafe % Sync` as a hypothesis of the base, as B takes an `unsafe` body |
| `dist/heartbeat.nu`'s thread holds the node's liveness (an `Atomic` and a copy), not the table; `PkMemberTable` is `% NotSend`; `mqtt_listen` takes its client (`sink`); one open hole listed: a library handle's copies on two threads | §6.2, §6.5 | no: threads are A3 | standard library only (no rule changes) and a stated exception to the guarantee; A3 must model library handles' sharing copies (a copy is a second owner of one state), where the open hole sits |
