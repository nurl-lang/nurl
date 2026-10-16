# Rules → formal rules

Every ownership rule of [`docs/MEMORY.md`](../docs/MEMORY.md) and the
phase that formalizes it. A rule is **done** when its typing rule is
stated, used in the soundness proof, and every hole probe it is meant to
reject is mapped to it in [`corpus/map.tsv`](corpus/map.tsv).

Formal rules are Lean names in [`A1/`](A1/): typing rules are
constructors of `StmtT`, `RhsT`, `PushArg` and the call check `CallT`;
`kill`, `exitScope` and `derive` are the context operations they use.
A1's calculus has owned `Vec` trees (a `String` is a `Vec` of bytes);
where a rule also speaks of structs, closures or threads, that part is
in a later phase.

| MEMORY.md | Rule | Phase | Formal rule | Status |
|---|---|---|---|---|
| §1, §7.6 | Single owner, drop flags, auto-drop | A1 | an owner's slot is `⟨own, some tree⟩`, a released or moved one `⟨own, none⟩` (the drop flag); `HeapOK` (one owner per allocation); `Step.scopeSkip` + `DropSlot`; `exitScope` | done |
| §2.1 | Moves — use after move | A1 | `RhsT.moveOwn`, `PushArg.move`, `CallT` (`sink`): the moved binding is dead (`live := false`) and every read needs a live entry; a moved argument is passed nowhere else in the call and reached from no other argument | done |
| §2.1b | Releasing what the compiler releases | A1 / B | `StmtT.free` releases only a live owner and kills it; inside `unsafe` is B | done for safe code |
| §2.2 | Second names | A1 | `RhsT.moveOwn` (an owner moves), `RhsT.copyBor`, `RhsT.copyRoot`, `RhsT.borrow` (a borrow is copied and depends on the root, `derive`) | done |
| §2.3 | Stack references must not escape | A1 / A2 | for borrows and views: `exitScope` ends them with their root, `FnOK` lets a result depend only on parameters; closures' stack references are A2 | done for borrows |
| §2.4 | Exclusive access for `inout` arguments | A1 | `CallT`: an argument that moves or may change is not lent out (`F`), is passed once, and is reached from no other argument; `paramOK`, `canDo` (the `inout` bound) | done |
| §2.5 | Iterator invalidation | A1 | a borrow of `xs` depends on `xs`: `StmtT.push` (`kill .realloc`), `RhsT.pop` (`kill .drop`), `StmtT.assign` and `StmtT.free` (`kill .replace`) end it | done |
| §2.6 | Loop-carried moves | A1 | `StmtT.while`: the body ends in the context it starts in | done |
| §2.7 | Escape through a callee | A1 / A2 | `CallT` against the callee's summary: what the result borrows (`lends`) and holds (`rholds`), what the callee stores into `inout` arguments (`outHolds`), its effect bound on each; `FnOK` checks the body against it; threads and closures are A2/A3 | done for borrows and views |
| §2.8 | Escape through a return | A1 / A2 | `FnOK` (the result depends only on what `lends` / `rholds` name), `callRes` at the call | done for borrows and views |
| §2.10 | Views end when their source may reallocate | A1 | `RhsT.view`, `RhsT.sat`; `StmtT.push` (`Eff.realloc` ends views, and element borrows when elements hold views); `PushArg` / `held` (a view in a container is still a view); `outHolds` (a callee storing a view into an argument) | done |
| §2.12 | A stored value belongs to its owner | A1 / A2 | `PushArg.move`, `CallT` (`sink`); aggregate literals and fields are A2 | done for containers |
| §2.13 | A raw string in a value is a view | A1 / A2 | a string view is a `slice` entry (`RhsT.view`) depending on its owner; values other than containers are A2 | done for containers |
| §2.11, §7.5 | Closures hold their captures | A2 | — | not started |
| §7.2, §7.3 | Panics and the drop journal | A2 | — | not started |
| §7.7 | Reference-count cycles | A2 | — | not started |
| §6.5 | Threads: `Send`, `Sync`, `Arc`, `Mutex`, `Locked`, channels | A3 | — | not started |
| §3, §6.4 | `unsafe` boundary and the trusted base | B | — | not started |
