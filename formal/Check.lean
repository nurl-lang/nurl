import A1
import A2
import A3
import B
import C
import D
/-! Run by `check.sh`: the axioms the main theorems rest on. -/
#print axioms A1.memory_safe
#print axioms A1.soundness
#print axioms A2.memory_safe
#print axioms A2.soundness
#print axioms A2.no_leak_end
#print axioms A2.no_leak_panic
-- Agora #879: a Vec's control block is never a buffer of any tree the store owns (slots and
-- blocks), the fact nurlc's `nurl vec ctl` / `nurl vec elem` TBAA tags assert
#print axioms A2.ctl_ne_data
-- Agora #610: the marking sweep marks an unreached `Arc` of a destructor value (Agora #755: or of
-- a drained `Vec` of them) `dead`, and the thread whose step it ended reaps it (`Settle`) before
-- anything else runs: the invariant through both, the reaps always possible and finite, no
-- orphan left between steps
#print axioms A2.pres_reap
#print axioms A2.Inv.sweepD
#print axioms A2.MemCodes.sweepD
#print axioms A2.Mem.sweepD_empty
#print axioms A2.Mem.sweepD_keeps
#print axioms A2.Mem.sweepD_marks
#print axioms A2.CutOff.not_reached
#print axioms A2.CutOff.top
#print axioms A2.sweepBlkD_marks
#print axioms A2.Mem.sweepD_marks_cut
#print axioms A2.settle_ok
#print axioms A2.orphan_reaps
#print axioms A2.settle_total
#print axioms A2.steps_step
#print axioms A2.settle_reaps
#print axioms A2.progress_no_reap
#print axioms A2.no_orphan
-- ... a witness: an `Arc` of a destructor value, cloned, both shares dropped (A2/ArcDtorWitness.lean)
#print axioms A2.ArcDtorWitness.main_typed
#print axioms A2.ArcDtorWitness.main_safe
#print axioms A2.ArcDtorWitness.main_no_leak
#print axioms A2.ArcDtorWitness.last_drop_reaps
#print axioms A3.arcDtor_claim
-- Agora #755: ... and an `Arc` of a `Vec` of destructor values: reaped at its own type, its frame drains it
#print axioms A2.ArcDtorWitness.mainV_typed
#print axioms A2.ArcDtorWitness.mainV_safe
#print axioms A2.ArcDtorWitness.mainV_no_leak
#print axioms A2.ArcDtorWitness.last_dropV_reaps
#print axioms A2.ArcDtorWitness.reapV_drains
#print axioms A3.arcVecDtor_claim
-- Agora #790: a share whose last drop is a panic's unwinding is reaped inside the frame that
-- caught it: a panic of its destructor comes back to that frame (A2/ArcPanicWitness.lean)
#print axioms A2.ArcPanicWitness.frame_reap_inside
#print axioms A2.ArcPanicWitness.reaped_panic_runs_dtor
#print axioms A2.ArcPanicWitness.recover_reap_inside
#print axioms A2.ArcPanicWitness.recover_catches_reaped
#print axioms A2.ArcPanicWitness.catchR_no_panic
#print axioms A2.ArcPanicWitness.unwind_reap
#print axioms A2.ArcPanicWitness.recover_reap
#print axioms A2.ArcPanicWitness.last_drop_marks
#print axioms A2.ArcPanicWitness.frame_unwind
#print axioms A2.ArcPanicWitness.recover_unwind
#print axioms A2.ArcPanicWitness.main1_typed
#print axioms A2.ArcPanicWitness.main1_safe
#print axioms A2.ArcPanicWitness.main1_no_leak_panic
#print axioms A2.ArcPanicWitness.main1_no_leak
#print axioms A2.ArcPanicWitness.main1_unwind
#print axioms A2.ArcPanicWitness.main2_typed
#print axioms A2.ArcPanicWitness.main2_safe
#print axioms A2.ArcPanicWitness.main2_no_leak
#print axioms A2.ArcPanicWitness.main2_no_leak_panic
#print axioms A2.ArcPanicWitness.main2_unwind
-- ... the case nurlc runs: a destructor frame inside a `recover` (main1 has no `recover`: the
-- model's behaviour on an uncaught panic, where nurlc aborts with no drain)
#print axioms A2.ArcPanicWitness.main3_body
#print axioms A2.ArcPanicWitness.main3_typed
#print axioms A2.ArcPanicWitness.main3_safe
#print axioms A2.ArcPanicWitness.main3_no_leak
#print axioms A2.ArcPanicWitness.main3_no_leak_panic
#print axioms A2.ArcPanicWitness.main3_unwind
#print axioms A3.arcPanic_claim
-- Agora #755, `Locked D`: a lock's payload that is a destructor value holding no share; the
-- check-out gives it back at its end and on a panic, and the orphaned lock block is reaped
-- (A3/LockDtorWitness.lean)
#print axioms A3.LockDtorWitness.giveable_of
#print axioms A3.LockDtorWitness.release_puts
#print axioms A3.LockDtorWitness.scopeL_end_gives_back
#print axioms A3.LockDtorWitness.scopeL_panic_gives_back
#print axioms A3.LockDtorWitness.sendCheck_noArc
-- Agora #805, #825: a typed check-out frame, of every payload type, ends with `x` holding a `t` (owned,
-- or an integer payload's plain integer), and at every panic point `x` holds a `t` (given back) or
-- nothing (`StmtT.scopeL` asks `x` bound as `withLock` binds it, live at the end)
#print axioms A3.LockDtorWitness.scopeL_entry
#print axioms A3.LockDtorWitness.scopeL_end_entry
#print axioms A3.LockDtorWitness.frame_slot
#print axioms A3.LockDtorWitness.frame_slot_live
#print axioms A3.LockDtorWitness.scopeL_end_owns
#print axioms A3.LockDtorWitness.scopeL_typed_end_gives_back
#print axioms A3.LockDtorWitness.Step.panic_st
#print axioms A3.LockDtorWitness.release_cases
#print axioms A3.LockDtorWitness.scopeL_typed_panic
-- Agora #810: a lock block's payload is taken (`locked_take`, `Mem.taken`) or checked out (a
-- `withLock`); a restore fills only a taken block, and panics on a checked-out one or a full one
#print axioms A3.lockRestore_checked_out
#print axioms A3.lockRestore_present
-- Agora #808: the check-outs' invariant over every reached configuration (A3/LockExcl.lean): each
-- frame's block checked out (out, not taken), or gone, and the frame its only one (A3.2's mutual
-- exclusion); Agora #810: for every payload type
#print axioms A3.Step.lfr
#print axioms A3.EvalR.stay
#print axioms A3.Step.stay
#print axioms A3.EvalR.taken_stay
#print axioms A3.Step.taken_stay
#print axioms A3.LockInv.put
#print axioms A3.LockInv.settle
#print axioms A3.LockInv.spawn
#print axioms A3.LockInv.spawnFail
#print axioms A3.LockInv.tstep
#print axioms A3.reach_lockInv
#print axioms A3.Redex.frame_unique
#print axioms A3.reach_frame_out
#print axioms A3.reach_lock_excl
-- Agora #808: the check-out's root share outlives its body (A3/LockRoot.lean): a step leaves the
-- slot of a binding its statement does not name that holds a share (through calls' `frozen` lists and
-- a package's by-name captures, `inp` or a `Vec`: `PkgsOK`); each frame keeps a root on its thread
-- and its block (kept by every `TStep`); the give-back lemmas with no hypothesis on the block; a
-- thread inside a check-out through a cell share holds an owner's share of it (`CellOp`'s second case)
#print axioms A3.Step.keepSlot
#print axioms A3.TypedAt.capShr
#print axioms A3.Step.lkRoots
#print axioms A3.Redex.lkRoots
#print axioms A3.RootInv.put
#print axioms A3.RootInv.sweepD
#print axioms A3.RootInv.settle
#print axioms A3.RootInv.spawn
#print axioms A3.RootInv.spawnFail
#print axioms A3.RootInv.tstep
#print axioms A3.reach_rootInv
#print axioms A3.reach_frame_root
#print axioms A3.reach_frame_live
#print axioms A3.reach_frame_checked_out
#print axioms A3.rbOK_of
#print axioms A3.reach_frame_root_cell_owner
#print axioms A3.reach_scopeL_end_gives_back
#print axioms A3.reach_scopeL_panic
#print axioms A3.LockDtorWitness.lockRestore_dtor_typed
#print axioms A3.LockDtorWitness.main_typed
#print axioms A3.LockDtorWitness.main_safe
#print axioms A3.LockDtorWitness.main_no_leak
#print axioms A3.LockDtorWitness.main_no_leak_panic
#print axioms A3.LockDtorWitness.last_drop_reaps
#print axioms A3.lockDtor_claim
-- (A3/RwDtorWitness.lean: Agora #804, `RwLocked D` read through a guard that lends its payload)
#print axioms A3.RwDtorWitness.rwRead_dtor_typed
#print axioms A3.RwDtorWitness.rwTryRead_dtor_typed
#print axioms A3.RwDtorWitness.rwRead_view_lends
#print axioms A3.RwDtorWitness.view_keeps_lock
#print axioms A3.RwDtorWitness.view_lock_not_cand
#print axioms A3.RwDtorWitness.view_no_dtor
#print axioms A3.RwDtorWitness.main_typed
#print axioms A3.RwDtorWitness.main_safe
#print axioms A3.RwDtorWitness.main_no_leak
#print axioms A3.RwDtorWitness.main_no_leak_panic
-- (Agora #831: the guard dropped after the lock's last share; the lock block and the view cut off)
#print axioms A3.RwDtorWitness.view_cutOff
#print axioms A3.RwDtorWitness.guard_drop_reaps
#print axioms A3.RwDtorWitness.guard_drop_reaps_settle
#print axioms A3.rwDtor_claim
#print axioms A3.LockDtorWitness.mainV_typed
#print axioms A3.LockDtorWitness.mainV_safe
#print axioms A3.LockDtorWitness.mainV_no_leak
#print axioms A3.LockDtorWitness.mainV_no_leak_panic
#print axioms A3.LockDtorWitness.last_dropV_reaps
#print axioms A3.LockDtorWitness.reapV_drains
#print axioms A3.lockVecDtor_claim
-- Agora #803 (A3/LockArcDtorWitness.lean): a destructor payload may hold `arc` and lock shares (no
-- cell share, `Ty.lkPay`); its give-back's failing crossing check turns the check-out's frame into
-- the value's destructor frame (`Step.scopeLPD`), never the code-less drop (`Release.drop`): a
-- case nurlc refuses statically (the check fails only through a read guard, Agora #837), and the
-- lemmas take the failing check as a hypothesis; a witness, a `Locked` of a destructor value
-- holding an `Arc` share
#print axioms A2.pres_unwindD
#print axioms A2.Inv.scopeL_iff
#print axioms A3.LockArcDtorWitness.release_none
#print axioms A3.LockArcDtorWitness.scopeL_fail_end
#print axioms A3.LockArcDtorWitness.scopeL_fail_frame
#print axioms A3.LockArcDtorWitness.fail_frame_runs_dtor
#print axioms A3.LockArcDtorWitness.fail_end_runs_dtor
#print axioms A3.LockArcDtorWitness.lk_ok
#print axioms A3.LockArcDtorWitness.main_typed
#print axioms A3.LockArcDtorWitness.main_safe
#print axioms A3.LockArcDtorWitness.main_no_leak
#print axioms A3.LockArcDtorWitness.main_no_leak_panic
#print axioms A3.LockArcDtorWitness.last_drop_reaps
#print axioms A3.lockArcDtor_claim
-- Agora #837: a read guard is a type of its own (`Ty.rguard`), `% NotSend`: no lock's, cell's or
-- `Arc`'s payload, no global and no closure of a class that crosses holds one (`Ty.hasGuard`,
-- `Ty.ok`, `Cross.Fits`); so a typed check-out's give-back passes its crossing check, for every
-- payload type holding no cell share (every destructor payload, shares included), and
-- `Step.scopeLPD` never fires from a typed reachable configuration
#print axioms A2.Ty.ok_rguard
#print axioms A2.Ty.ok_lk_guard
#print axioms A2.Ty.ok_arc_guard
#print axioms A2.Cross.Fits.guard
#print axioms A2.ArcBlk.guard
#print axioms A2.ArcBlk.view
#print axioms A2.MInv.guard_val
#print axioms A2.MInv.lends_val
#print axioms A2.out_guard
#print axioms A2.ArcIn.guard_hasGuard
#print axioms A2.WFv.not_href
#print axioms A2.WFv.refers_noView
#print axioms A3.LockDtorWitness.noGuard_of_free
#print axioms A3.LockDtorWitness.sendCheck_free
#print axioms A3.LockDtorWitness.giveCheck_of
#print axioms A3.LockDtorWitness.checkedOut_free
#print axioms A3.LockDtorWitness.giveCheck_typed
#print axioms A3.LockDtorWitness.giveCheck_typed_dtor
#print axioms A3.LockDtorWitness.scopeL_typed_end_giveCheck
#print axioms A3.LockDtorWitness.Step.panic_blkBack
#print axioms A3.LockDtorWitness.scopeL_typed_panic_give
#print axioms A3.LockDtorWitness.scopeL_typed_panic_at
#print axioms A3.LockDtorWitness.scopeL_typed_panic_giveCheck
#print axioms A3.LockDtorWitness.scopeL_typed_no_scopeLPD
#print axioms A3.scopeL_typed_panic_of
#print axioms A3.reach_scopeL_giveCheck
#print axioms A3.reach_no_scopeLPD
#print axioms A3.RwDtorWitness.guard_refused
#print axioms A3.RwDtorWitness.arc_pair_ok
#print axioms A3.RwDtorWitness.dropd_closure_ok
-- (A3/ChanDtorWitness.lean)
#print axioms A3.ChanDtorWitness.main_typed
#print axioms A3.ChanDtorWitness.main_safe
#print axioms A3.ChanDtorWitness.main_no_leak
#print axioms A3.ChanDtorWitness.main_no_leak_panic
#print axioms A3.ChanDtorWitness.last_drop_reaps
#print axioms A3.ChanDtorWitness.reap_runs_glue
#print axioms A3.ChanDtorWitness.closed_send_parks
#print axioms A3.chanDtor_claim
-- Agora #805: every share in a configuration a typed start reaches names a key below `nid`
-- (A3/Keys.lean), so a closed channel's send parks its value in a block nothing refers to: the
-- step's marking sweep marks it and the sending thread reaps it; a witness closes a channel, then sends
#print axioms A3.Step.keys
#print axioms A3.TStep.keys
#print axioms A3.CKeys.start
#print axioms A3.reach_keys
#print axioms A3.TStep.closed_send_reaps
#print axioms A3.reach_closed_send_reaps
#print axioms A3.closed_send_core
#print axioms A3.TStep.closed_send_reaps_assign
#print axioms A3.reach_closed_send_reaps_assign
-- Agora #815: no block is named by both a lock share and a cell share (A3/Kinds.lean): a kind per
-- key that every share of the configuration agrees with, kept by every step (a constructor's fresh
-- key above every share), at a start whose globals keep the kinds apart (`GlobsOK.kinds`, which the
-- make phase leaves); so a check-out of a cell's block is through a cell share, by an owner (`CellOp`);
-- `GlobsTyped` (`GlobsOK` before #815) admits a start naming a key by both, which `GlobsOK` refuses
#print axioms A3.EvalR.kinds
#print axioms A3.Step.kinds
#print axioms A3.CSettle.kinds
#print axioms A3.TStep.kinds
#print axioms A3.Reach.kinds
#print axioms A3.CKinds.start
#print axioms A3.reach_kinds
#print axioms A3.CKinds.shareKind
#print axioms A3.reach_shareKind
#print axioms A3.reach_shareKind_made
#print axioms A3.reach_frame_cell_owner
#print axioms A3.reach_frame_cellOp
#print axioms A3.mix_globsTyped
#print axioms A3.mix_not_shareKind
#print axioms A3.mix_not_globsOK
#print axioms A3.ChanDtorWitness.mainC_typed
#print axioms A3.ChanDtorWitness.mainC_safe
#print axioms A3.ChanDtorWitness.mainC_no_leak
#print axioms A3.ChanDtorWitness.mainC_no_leak_panic
#print axioms A3.chanClosed_claim
#print axioms A3.chanClosed_reaps
-- Agora #805: a channel's glue (`GlueOK` over `prod (vec s) int`) drains the queue in index order,
-- as its frame's steps: the queue to a `letd` at `vec s`, whose frame ends by the drain
#print axioms A3.LetdChain.of_movedFirst
#print axioms A3.LetdChain.typed
#print axioms A3.unpair_body
#print axioms A3.RhsT.var_out_ty
#print axioms A3.letd_vec_nest
#print axioms A3.chanGlue_drains
#print axioms A3.ChanDtorWitness.glueV_drains
-- Agora #805: a receive of a destructor value: the option bound under its glue (`ofnR`, an
-- `EnumGlueOK` glue of `sum int DT`), whose frame's end calls the glue, which takes the payload out
#print axioms A2.DtorWitness.ofnR_ok
#print axioms A3.ChanDtorWitness.mainR_typed
#print axioms A3.ChanDtorWitness.mainR_safe
#print axioms A3.ChanDtorWitness.mainR_no_leak
#print axioms A3.ChanDtorWitness.mainR_no_leak_panic
#print axioms A3.ChanDtorWitness.recv_runs_glue
#print axioms A3.ChanDtorWitness.ofnR_takes_payload
#print axioms A3.chanRecv_claim
-- Agora #755 item 1: A3's marking sweep and eager reaps (A3/Mark.lean, A3/Reap.lean):
-- the thread that drops the last share runs the destructor
#print axioms A3.CParts.sweepD
#print axioms A3.Cfg.sweepD_reached
#print axioms A3.Cfg.sweepD_marks
#print axioms A3.Cfg.sweepD_marks_cut
#print axioms A3.CInv.thread_of
#print axioms A3.CInv.raceFree
#print axioms A3.CSettle.total
#print axioms A3.TStep.thread_total
#print axioms A3.CSettle.keeps_slot
#print axioms A3.CSettle.reaps_block
#print axioms A3.TStep.last_drop_reaps
#print axioms A3.reach_thread_total
#print axioms A3.arcDtor_reaps
#print axioms A3.arcVecDtor_reaps
#print axioms A3.lockDtor_reaps
#print axioms A3.lockVecDtor_reaps
#print axioms A3.chanDtor_reaps
#print axioms A3.glob_not_marked
-- per-call ownership, as the calculus has it (A2/DynCell.lean)
#print axioms A2.DynCell.pick_ok
#print axioms A2.DynCell.main_safe
#print axioms A2.DynCell.main_no_leak
-- Agora #826: a take out of an `inout .replace` place (A2/TakeWitness.lean)
#print axioms A2.rhs_take
#print axioms A2.TakeWitness.g_ok
#print axioms A2.TakeWitness.main_safe
#print axioms A2.TakeWitness.main_no_leak
-- AGORA-888: a pop and a remove through a borrow, as a truncation to the last
-- index (`Expr.dec`) and element sets (A2/PopWitness.lean)
#print axioms A2.PopWitness.main_safe
#print axioms A2.PopWitness.main_no_leak
-- AGORA-889: a remove of a number at a general index through a borrow, as a loop
-- (A2/RemoveLoopWitness.lean)
#print axioms A2.RemoveLoop.main_safe
#print axioms A2.RemoveLoop.main_no_leak
-- AGORA-889: an element that owns memory moved out through a borrow, kept
-- (`Stmt.takeB`; A2/TakeB.lean, A2/TakeBWitness.lean)
#print axioms A2.takeB_pres
#print axioms A2.HeapOK.editTake
#print axioms A2.MInv.editB_take
#print axioms A2.TakeBWitness.main_typed
#print axioms A2.TakeBWitness.main_safe
#print axioms A2.TakeBWitness.main_no_leak
-- AGORA-897: ... and one whose type holds views (`StmtT.takeBV`; A2/TakeB.lean,
-- A2/TakeBVWitness.lean)
#print axioms A2.takeBV_pres
#print axioms A2.MInv.editBV_take
#print axioms A2.takeB_viewsOK
#print axioms A2.takeBV_out
#print axioms A2.TakeBVWitness.main_typed
#print axioms A2.TakeBVWitness.main_safe
#print axioms A2.TakeBVWitness.main_no_leak
-- AGORA-898: ... and one whose type holds views and a closure (a closure whose
-- environment is a view, moved out; `NewSlot.editV`'s closure case)
#print axioms A2.TakeBVWitness.main2_typed
#print axioms A2.TakeBVWitness.main2_safe
#print axioms A2.TakeBVWitness.main2_no_leak
#print axioms A2.node_names_sub
-- AGORA-901: a store through a borrow of an element that holds views and a closure
-- (`StmtT.editBV`'s right disjunct: nothing captured by name; A2/EditBVFnWitness.lean)
#print axioms A2.EditBVFnWitness.main_typed
#print axioms A2.EditBVFnWitness.main_safe
#print axioms A2.EditBVFnWitness.main_no_leak
-- AGORA-900: ... and one that holds a destructor value, handed to its `letd`
-- first thing (A2/TakeBDWitness.lean; the typing's guarantee `A2.Dtor.takeB_typed`)
#print axioms A2.Dtor.takeB_typed
#print axioms A2.TakeBDWitness.main12_typed
#print axioms A2.TakeBDWitness.main12_safe
#print axioms A2.TakeBDWitness.main12_no_leak
-- AGORA-885: the by-name owner hand-over, as an encoding (A2/HandOver.lean)
#print axioms A2.HandOver.main_safe
#print axioms A2.HandOver.main_no_leak
#print axioms A2.HandOver.mainJ_safe
#print axioms A2.HandOver.mainJ_no_leak
-- A2-drop.3a: the destructor on the type (A2/DtorWitness.lean): the typing's
-- guarantee for each binder, the destructor frame's end and panic, a witness
#print axioms A2.Dtor.letv_owned_no_dtor
#print axioms A2.Dtor.letcall_hands_over
#print axioms A2.Dtor.unpair_hands_over
#print axioms A2.Dtor.letd_dtor
#print axioms A2.Dtor.fnOK_dtor_params
-- Agora #616: a struct's drop glue takes the struct apart, a frame per field
#print axioms A2.Dtor.unpair_typed
#print axioms A2.Dtor.struct_dtor_is_glue
#print axioms A2.Dtor.glue_takes_apart
#print axioms A2.DtorWitness.main7_safe
#print axioms A2.DtorWitness.main7_lent_refused
#print axioms A2.Dtor.letd_retype
#print axioms A2.Dtor.impl_glue_body
#print axioms A2.DtorWitness.main8_safe
-- Agora #633: ... and one that holds views of older bindings, moved into its glue as a `sink` argument
#print axioms A2.glueCall_typed
#print axioms A2.DtorWitness.glueS_ok
#print axioms A2.DtorWitness.main10_typed
#print axioms A2.DtorWitness.main10_safe
-- Agora #750: an enum with a destructor payload and a view payload, its view variant holding a view of an older binding
#print axioms A2.DtorWitness.ofnV_ok
#print axioms A2.DtorWitness.main12_typed
#print axioms A2.DtorWitness.main12_safe
-- ... and a view-holding struct whose glue runs its own `% Drop` impl first
#print axioms A2.DtorWitness.glueS2_ok
#print axioms A2.DtorWitness.main13_typed
#print axioms A2.DtorWitness.main13_safe
-- Agora #609: a closure whose environment is a destructor value is dropped by its glue, which calls its drop method (A2/ClosureDropWitness.lean)
#print axioms A2.ClosureDropWitness.glue_calls_drop
#print axioms A2.ClosureDropWitness.prog_ok
#print axioms A2.ClosureDropWitness.main_typed
#print axioms A2.ClosureDropWitness.main_safe
#print axioms A2.ClosureDropWitness.main_letv_refused
-- Agora #651: ... and such a closure is called through its `letd` binding, lent, then dropped by its glue
#print axioms A2.ClosureDropWitness.main2_typed
#print axioms A2.ClosureDropWitness.main2_safe
-- AGORA-395: a closure whose code changes elements through a borrow of its own local, called
-- through its package: the code implements a through-changing interface (A2/ThruClosureWitness.lean)
#print axioms A2.ThruClosureWitness.code_impl
#print axioms A2.ThruClosureWitness.prog_ok
#print axioms A2.ThruClosureWitness.main_typed
#print axioms A2.ThruClosureWitness.main_safe
#print axioms A2.ThruClosureWitness.main_no_leak
-- A destructor that changes elements through a borrow of its own local, on a type that holds no
-- views, run by its `letd` frame's end (A2/ThruDtorWitness.lean)
#print axioms A2.ThruDtorWitness.dtor_thru
#print axioms A2.ThruDtorWitness.dtor_ok
#print axioms A2.ThruDtorWitness.prog_ok
#print axioms A2.ThruDtorWitness.main_typed
#print axioms A2.ThruDtorWitness.main_safe
#print axioms A2.ThruDtorWitness.main_no_leak
-- drop glue whose struct's own `% Drop` changes elements through a borrow, on
-- a value that holds no views (A2/ThruGlueWitness.lean)
#print axioms A2.ThruGlueWitness.implT_thru
#print axioms A2.ThruGlueWitness.glue2_thru
#print axioms A2.ThruGlueWitness.glue2_implOK
#print axioms A2.ThruGlueWitness.prog_ok
#print axioms A2.ThruGlueWitness.main_typed
#print axioms A2.ThruGlueWitness.main_safe
#print axioms A2.ThruGlueWitness.main_no_leak
-- Agora #632: an enum's drop glue takes the enum owned and the payload out
#print axioms A2.Dtor.enum_dtor_is_glue
#print axioms A2.Dtor.enum_glue_body
#print axioms A2.Dtor.take_is_glue
#print axioms A2.Dtor.assign_take_is_glue
#print axioms A2.Dtor.result_frame_is_scopeD
#print axioms A2.Dtor.scopeD_end_runs_dtor
#print axioms A2.Dtor.scopeD_panic_runs_dtor
-- A2-drop.3b, the drain: a `Vec` of destructor values, bound by `letd` and drained at its
-- frame's end and on a panic; what drops elements with no code refuses one
#print axioms A2.Dtor.letd_binds
#print axioms A2.Dtor.scopeD_typed
#print axioms A2.Dtor.scopeD_frame_value
#print axioms A2.Dtor.scopeD_end_drains
#print axioms A2.Dtor.scopeD_drain_binds
#print axioms A2.Dtor.scopeD_end_empty
#print axioms A2.Dtor.scopeD_panic_drains
#print axioms A2.Dtor.free_dtor_free
#print axioms A2.Dtor.edit_drops_dtor_free
#print axioms A2.Dtor.withElem_dtor_free
-- ... and `vec_free` / `vec_clear` / `vec_truncate` / `vec_set` / `withElem` of one are typed code (A2/DropCode.lean)
#print axioms A2.Dtor.vecFreeD_typed
#print axioms A2.Dtor.vecClearD_typed
#print axioms A2.Dtor.vecTruncD_typed
#print axioms A2.Dtor.vecSetD_typed
#print axioms A2.Dtor.withElemD_typed
#print axioms A2.DtorWitness.main6_safe
#print axioms A2.DtorWitness.mainSet_safe
#print axioms A2.DtorWitness.mainElem_safe
-- Agora #607: a `Vec` of destructor values as a struct's field, drained through the struct's glue
#print axioms A2.DtorWitness.main9_safe
-- A2-drop.3c: no closure or trait-object environment holds a destructor value
#print axioms A2.Dtor.pack_env_dtor_free
#print axioms A2.WFv.pkg_env_dtor_free
#print axioms A2.Dtor.pkgs_env_dtor_free
#print axioms A2.Dtor.closure_dtor_is_glue
#print axioms A2.Dtor.drop_method_code
-- A2-drop.3d: no lock's or cell's payload owns a destructor value; an `Arc`'s is one at its top,
-- or (Agora #755) a drained `Vec` of them, or owns none
#print axioms A2.Dtor.ok_payloads_free
#print axioms A2.Dtor.ok_lockPayloads_free
#print axioms A2.Dtor.shares_dtor_free
#print axioms A2.Dtor.blocks_dtor_free
-- Agora #804: an `arc` block is never of a read guard's view type (the block-level fact
-- behind `Ty.ok_arc_dtor`; since Agora #837 a read guard is a type of its own, `Ty.rguard`)
#print axioms A2.Dtor.arc_blocks_dtor
#print axioms A2.Blk.DtorOK.arc
#print axioms A2.Blk.DtorOK.nest
#print axioms A2.Ty.ok_arc_dtor
#print axioms A2.Ty.rview_shape
#print axioms A2.viewDtorOK
#print axioms A2.Dtor.blk_pkgs_env_dtor_free
#print axioms A2.Dtor.share_new_dtor_free
#print axioms A2.Dtor.vec_elems_dtor_free
#print axioms A2.Dtor.new_dtor_free
#print axioms A2.Dtor.vecs_dtor_free
#print axioms A2.rhs_remove
#print axioms A2.Dtor.holdsDtor_deep
#print axioms A2.Dtor.letv_owned_dtor_free
#print axioms A2.DtorWitness.main_safe
#print axioms A2.DtorWitness.main2_safe
#print axioms A2.DtorWitness.main3_safe
#print axioms A2.DtorWitness.main4_safe
#print axioms A2.DtorWitness.main4_letv_refused
#print axioms A2.DtorWitness.main5_safe
#print axioms A2.DtorWitness.main5_letv_refused
#print axioms A2.DtorWitness.main11_safe
#print axioms A2.DtorWitness.main11_no_leak
-- Agora #782: a `Vec` of destructor values whose elements hold views of an older binding,
-- armed by its `letd`, typed and drained
#print axioms A2.MInv.rearm
#print axioms A2.DtorWitness.main14_typed
#print axioms A2.DtorWitness.main14_safe
#print axioms A2.DtorWitness.main14_no_leak
#print axioms A2.DtorWitness.enum_lends
#print axioms A2.DtorWitness.enum_take_refused
-- threads: moves, Arc's frozen shared payloads, Locked, RwLocked, Atomic, channels, library
-- handles and the crossing check, module globals (A3/Claim.lean)
#print axioms A3.claim
-- module globals made before main by their declarations' makes, read at their declared types
-- (A3/Make.lean)
#print axioms A3.claim_made
-- the claim in full (Agora #818): with race freedom adequate for cells, every check-out of a
-- cell's block a step on the cell (A3/ClaimFull.lean)
#print axioms A3.claim_full
#print axioms A3.made_safe_full
#print axioms A3.claim_made_full
-- Agora #909 (design e): a destructor of a type that holds views changes elements through a
-- fresh borrow of its own local, an `edit false`, and is not through-changing
-- (A2/FreshWitness.lean); no new premise removes a typing (A2/Unfresh.lean)
#print axioms A2.FreshWitness.dtor_not_thru
#print axioms A2.FreshWitness.dtor_ok
#print axioms A2.FreshWitness.prog_ok
#print axioms A2.FreshWitness.main_typed
#print axioms A2.FreshWitness.main_safe
#print axioms A2.FreshWitness.main_no_leak
#print axioms A2.FreshWitness.edit_false_fresh
#print axioms A2.FreshWitness.at_rootb_not_fresh
#print axioms A2.FreshWitness.at_bor_not_fresh
#print axioms A2.StmtT.unfresh
#print axioms A2.weaker_unfreshC
#print axioms A2.freshOK_unfreshC
#print axioms A2.unfreshC_panic
-- ... and a closure over a slice whose code does so, called through its package
-- (A2/FreshClosureWitness.lean)
#print axioms A2.FreshClosureWitness.code_impl
#print axioms A2.FreshClosureWitness.prog_ok
#print axioms A2.FreshClosureWitness.main_typed
#print axioms A2.FreshClosureWitness.main_safe
#print axioms A2.FreshClosureWitness.main_no_leak
#print axioms A2.freshOK_of_noFresh
#print axioms A2.EntryWeaker.fresh_of_not
#print axioms A2.RhsT.borrow_unfresh
#print axioms A2.RhsT.at_unfresh
-- Agora #916: a held-fresh view (a view of an owner of a type that holds no views, or of a
-- held-fresh borrow) is lifted by a call without the arguments' memory; no new premise removes a
-- typing, and no view of a borrowed parameter is held-fresh (A2/UnheldFresh.lean)
#print axioms A2.StmtT.unheld
#print axioms A2.weaker_unheldC
#print axioms A2.RhsT.view_unheld
#print axioms A2.heldSrc_not_rootb
#print axioms A2.view_rootb_not_heldFresh
#print axioms A2.view_bor_not_heldFresh
#print axioms A2.RSetup.heldSrc_lift
#print axioms A2.RSetup.heldSrc_held_lift
#print axioms A2.RSetup.memDeps_heldA
#print axioms A2.heldFresh_view_witness
-- Agora #916, option (a): a view of an owner or `inout` parameter may be fresh, never one of a
-- borrowed parameter or a borrow; a kill does not read the bits; an edit of view-holding elements
-- through a fresh borrow, storing a value the frame's own, is an `edit false`
#print axioms A2.hits_fresh_irrel
#print axioms A2.view_rootb_not_fresh
#print axioms A2.view_bor_not_fresh
#print axioms A2.derive_freshE
#print axioms A2.RSetup.pushArg_ren_held
#print axioms A2.RSetup.editBV_ren
-- ... and a destructor of a type that holds views stores a fresh, held-fresh view of its own local
-- through a fresh borrow of its own local: an `edit false`, not through-changing, run by an armed
-- `letd` handed a value that holds views (A2/StoreViewWitness.lean)
#print axioms A2.StoreViewWitness.edit_typed
#print axioms A2.StoreViewWitness.dtor_not_thru
#print axioms A2.StoreViewWitness.dtor_ok
#print axioms A2.StoreViewWitness.prog_ok
#print axioms A2.StoreViewWitness.main_typed
#print axioms A2.StoreViewWitness.main_safe
#print axioms A2.StoreViewWitness.main_no_leak
-- Agora #3932 (#909's own example): a fresh borrow that is not held-fresh may store anything, a
-- view of a borrowed parameter too: a call lifts it, and every owner of a type that holds views,
-- with all the arguments hold, and that is where the store's dependencies land (pushArg_ren_sub,
-- its borrowed-parameter case derive_lift_rootb); no `edit false` of a value that is not the
-- frame's own leaves its borrow held-fresh (A2/ParamViewWitness.lean)
#print axioms A2.RSetup.derive_lift_rootb
#print axioms A2.RSetup.pushArg_ren_sub
#print axioms A2.ParamViewWitness.edit_false_unfresh_unheld
#print axioms A2.ParamViewWitness.edit_false_unown_unheld
#print axioms A2.ParamViewWitness.heldSrc_of_weaker
#print axioms A2.ParamViewWitness.param_store_unheld
#print axioms A2.ParamViewWitness.stale_store_unheld
#print axioms A2.ParamViewWitness.edit_typed
#print axioms A2.ParamViewWitness.dtor_not_thru
#print axioms A2.ParamViewWitness.dtor_ok
#print axioms A2.ParamViewWitness.prog_ok
#print axioms A2.ParamViewWitness.main_typed
#print axioms A2.ParamViewWitness.main_safe
#print axioms A2.ParamViewWitness.main_no_leak
-- AGORA-606, AGORA-563: an argument the callee moves or may change that views its own storage
-- (a root of its own memory dependencies; a `sink` one, of any) admits no `CallT`
#print axioms A2.CallT.not_self_view
#print axioms A2.CallT.not_self_dep_sink
-- AGORA-909 (github#2041): closure code, called through its package with an argument that holds
-- views, that stores that view through a fresh borrow of its own local: an `edit false`, not
-- through-changing (A2/ClosureParamViewWitness.lean)
#print axioms A2.ClosureParamViewWitness.code_not_thru
#print axioms A2.ClosureParamViewWitness.code_impl
#print axioms A2.ClosureParamViewWitness.prog_ok
#print axioms A2.ClosureParamViewWitness.main_typed
#print axioms A2.ClosureParamViewWitness.main_safe
#print axioms A2.ClosureParamViewWitness.main_no_leak
-- AGORA-909 (github#2041), direct call: a callee that changes the elements of its `inout`
-- parameter through `vec_at`, called with an argument that holds a view, read after the call
-- (A2/InoutViewArgWitness.lean): the borrow is fresh, so the call asks nothing of the view
#print axioms A2.InoutViewArgWitness.g_not_thru
#print axioms A2.InoutViewArgWitness.call_ok
#print axioms A2.InoutViewArgWitness.main_typed
#print axioms A2.InoutViewArgWitness.main_safe
#print axioms A2.InoutViewArgWitness.main_no_leak
#print axioms A2.InoutViewArgWitness.call_refused
-- (A2/HeldViewThruWitness.lean, AGORA-933): a callee changing a Vec reached through a slice its
-- parameter holds is through-changing; a call of it is refused with `s2` live, alongside the
-- argument or after the call (`call_ok` below types `( f1 vv )` with `s2` dead)
#print axioms A2.HeldViewThruWitness.call_refused
#print axioms A2.HeldViewThruWitness.call_alone_refused
-- (A2/ThruPre.lean, AGORA-937 stage 3a): what a through-changing call that passes views of real
-- memory ends before its body runs (`thruPre`): only bindings, every binding but the arguments,
-- by a drop on each root they hold views of; it keeps the context well-formed, its domain, modes and
-- types, fresh borrows' sources and every binding a closure names
#print axioms A2.LiveLe.thruPre
#print axioms A2.CtxWF.thruPre
#print axioms A2.FreshOK.thruPre
#print axioms A2.NameWF.thruPre
#print axioms A2.DomTy.thruPre
#print axioms A2.thruPre_dead
-- ... and for AGORA-933's `( f1 vv )`: `s2`, a view of `w`'s element, is ended; `vv` and `w` are kept
#print axioms A2.HeldViewThruWitness.pre_s2_dead
#print axioms A2.HeldViewThruWitness.pre_vv_kept
#print axioms A2.HeldViewThruWitness.pre_w_kept
-- ... (AGORA-937 B4, route U) and with `s2` ended, `( f1 vv )` types: it passes a view of `w`, a
-- real memory root, which the callee changes only inside its elements (`CallThruOK`)
#print axioms A2.HeldViewThruWitness.thru_ok
#print axioms A2.HeldViewThruWitness.call_ok
-- (A2/EditB.lean, A2/DropInWitness.lean, AGORA-937): a change strictly inside the elements of a
-- Vec root (`Eff.dropIn`) keeps the root's views: its buffer keeps its address and length
#print axioms A2.vkeep_view_below
#print axioms A2.HKeep.view_of_self
#print axioms A2.MInv.edit_dropE
#print axioms A2.effAt_dropE
#print axioms A2.RSetup.Eff.kills_mono
#print axioms A2.DropInWitness.set_keeps_view
#print axioms A2.DropInWitness.drop_would_end
#print axioms A2.DropInWitness.struct_root_drops
-- (AGORA-937 item 2): a lent parameter holding views has a region; typing anchors it through
-- the region's view (RootbAnchR), and frames, which bind no region, keep RootbAnch
#print axioms A2.killE_rootbR
#print axioms A2.RootbAnchR.toAnch
#print axioms A2.sigCtx_anch
#print axioms A2.CallH.canon_param
#print axioms A2.CallH.sig_abs
#print axioms A2.RSetup.hits_lift
#print axioms A2.StmtT.ctxRel
-- (AGORA-937 item 3): a change through a borrow may reach a region (ThruOKR) when its effect ends no
-- view; the call places it exactly (ghost) or, the region standing for nothing, weakens to it
#print axioms A2.RSetup.editB_ren_facts
#print axioms A2.RSetup.editB_ren
#print axioms A2.RSetup.weaker_kill_region
#print axioms A2.RSetup.memDeps_subE_liftE_bor
#print axioms A2.RegionChangeWitness.push_typed
#print axioms A2.RegionChangeWitness.push_keeps_vv
-- (A2/SubDcKill.lean, AGORA-937 3d groundwork): the kinds-composed lift of a change through a
-- region ends at the caller exactly what the callee ends, for arguments that view `w` at `.view`
#print axioms A2.dropIn_comp_exact
#print axioms A2.dropIn_comp_exact'
#print axioms A2.subDc_hits_exact_root
#print axioms A2.subDc_hits_none_root
#print axioms A2.dropIn_comp_inner_overkills
#print axioms A2.subDc_hits_exact
-- (AGORA-937 3d): a parameter holds its region by its handle; a kill spares it where it spares a view
#print axioms A2.Eff.kills_self_of_view
-- (AGORA-937 3d): a call through a package returns its receiver's own memory deps, composed;
-- the lift of it is exact
#print axioms A2.recvDeps_root
#print axioms A2.RSetup.allKinds_recvRoots_subE
-- (AGORA-937 3d): a lent parameter's lift holds the callee's memory; placed, it is its argument's entry
#print axioms A2.CallH.canon_inp_eq
#print axioms A2.StmtT.keepKV
#print axioms A2.CallH.thruReady
#print axioms A2.CallH.held_anch
-- (AGORA-937 3d): what a call's result may hold, and what a call setting adds, is precise
#print axioms A2.mem_compAll
#print axioms A2.compAll_argMem_notName
#print axioms A2.RSetup.compAll_Rd
-- (AGORA-937 3d): frozen roots split from region-reached ones; the bounds after the substitution
#print axioms A2.RSetup.mem_subD_comp
#print axioms A2.RSetup.heldOfArgs_lift
#print axioms A2.CallH.own_param_free
-- (AGORA-937 3d): a change inside a region's elements, where the call places it, is the caller's on the root
#print axioms A2.RSetup.hits_subE_region
#print axioms A2.RSetup.canon_kill_region
#print axioms A2.RSetup.dtorSafe_region
-- (AGORA-937 3d): the rename places a change through a region whose argument views real memory
#print axioms A2.RSetup.canon_killNames_region
#print axioms A2.RSetup.editB_ren_facts_thru
#print axioms A2.RSetup.StmtT.ren
-- (AGORA-937 3d, route F): a kill that ends no lent parameter keeps the invariant, frozen root or not
#print axioms A2.MInv.kill_norootb
#print axioms A2.MInv.killNames_norootb
-- (AGORA-937 3d, route F, memory side): a frozen owner's tree changed inside, no loan in it or ended
#print axioms A2.rootKeep_frame_ne
#print axioms A2.MInv.change_ne
#print axioms A2.MInv.edit_dropE_ne
#print axioms A2.MInv.killNames_mixed
-- (AGORA-937 3d, route U, PR A): the memory lemmas allow a lent Vec's held anchors at roots changed only inside
#print axioms A2.rootb_anchor
#print axioms A2.MInv.change
#print axioms A2.HeldSpared.of_none
#print axioms A2.NoHeld.of_anchF
#print axioms A2.ThruSpared.of_anchF
-- (AGORA-937 3d, route U, PR B1): a change through a borrow ends no lent Vec's view of its root
#print axioms A2.RSetup.HeldOK.canon
#print axioms A2.ThruOK.spared
#print axioms A2.RSetup.liftE_rootb_dep
-- (AGORA-937 3d groundwork): the call's lift is precise (σ: the argument's own memory deps and
-- each root by its handle) and composes kinds; deriving commutes with it
#print axioms A2.RSetup.derive_subE
#print axioms A2.RSetup.mem_subD
#print axioms A2.CallH.σC_held
-- (A2/RegionMem.lean, AGORA-937 stage 3b): a region of buffer addresses reaches the node at one of
-- them (RootNode's view case generalised); an argument's valid views are valid through its region,
-- each address reaches one node, and derived borrows compose kinds through a region as through a root
#print axioms A2.ViewsOK.region_viewAt
#print axioms A2.ViewsOK.region_node
#print axioms A2.RegionNode.unique
#print axioms A2.RegionLanded.comp
#print axioms A2.RegionLanded.mono
-- ... and what lands through a region lands through the argument's own roots at the composed kind,
-- whose hypothesis holds of an argument's valid views at the call's entry
#print axioms A2.RegionLanded.landed
#print axioms A2.ViewsOK.region_landed
-- ... and the kinds-composed substitution (`subDc`): with each region read as its addresses, what
-- lands through a dependency, or through one of a list, lands through its substitution
#print axioms A2.LandedR.subDc
#print axioms A2.LandedR.subDc_list
#print axioms A2.LandedR.of_noPi
-- ... and deriving a borrow commutes with it (composing kinds is associative)
#print axioms A2.comp_assoc
#print axioms A2.subDc_comp
#print axioms A2.subDc_derive
-- ... and a change strictly inside a region's node keeps the node's address and length, so a view
-- of its buffer stays in bounds while the body changes the memory it points into
#print axioms A2.Repl.keeps_enclosing
#print axioms A2.DataAt.keeps_enclosing
#print axioms A2.RegionViewAt.keeps_len
-- ... and the view itself survives, well-formed; and after the entry kill no live frame binding
-- but the arguments reaches the changed roots by a kind a drop ends
#print axioms A2.Repl.keeps_enclosing'
#print axioms A2.RegionViewAt.keep_inner
#print axioms A2.killHv_live_nohit
#print axioms A2.thruPre_live_nohit
-- (A2/Rename.lean, AGORA-937 stage 3): a call setting may lift regions as ghost bindings
-- (`RSetup.ghost`), renamed rather than substituted; then no index is a region's to substitute
#print axioms A2.RSetup.AbsOK.ghost_notPi
-- ... with the region indices recorded apart from whether they are substituted (`isReg`)
#print axioms A2.RSetup.AbsOK.notRegFresh
#print axioms A2.RSetup.AbsOK.notReg_of_notPi
#print axioms A2.RSetup.AbsOK.notPi_of_notReg
#print axioms A2.callS_isReg_lt
-- ... and the renaming lemma holds whether or not the setting lifts regions as ghost bindings:
-- a lifted inner call's views are of region bindings only (substituted: none)
#print axioms A2.RSetup.callR_canon
#print axioms A2.RSetup.StmtT.ren
-- ... and any call setting made ghost (regions renamed, only part of its roots frozen) is a
-- setting, so the renaming lemma places a callee body under it
#print axioms A2.RSetup.OK.ghostify
#print axioms A2.RSetup.AbsOK.ghostify
#print axioms A2.RSetup.StmtT.ren_ghost
-- (A2/SliceCopyViewWitness.lean, AGORA-935): a copy of a slice of views, typed as A2 types a
-- copy (a call, `callRes`), holds copies of its loans and nothing of the slice: releasing the
-- temporary leaves it live, replacing what the views point into ends it, and then no read types
#print axioms A2.SliceCopyViewWitness.dupFn_not_thru
#print axioms A2.SliceCopyViewWitness.copy_call
#print axioms A2.SliceCopyViewWitness.copy_typed
#print axioms A2.SliceCopyViewWitness.copy_holds_a
#print axioms A2.SliceCopyViewWitness.copy_free_of_temp
#print axioms A2.SliceCopyViewWitness.copy_survives_temp_release
#print axioms A2.SliceCopyViewWitness.dep_on_temp_dies
#print axioms A2.SliceCopyViewWitness.copy_dead_after_replace
#print axioms A2.SliceCopyViewWitness.read_copy_refused
#print axioms A2.SliceCopyViewWitness.lit_held
#print axioms A2.SliceCopyViewWitness.lit_free_of_temp
-- (A2/ThruLiftKinds.lean, AGORA-932): what a change through a callee borrow kills, seen from
-- the caller: exact through a root's own handle, coarser through a view or an element; and a
-- kill after a `.replace` on the same root ends nothing more (A2/THRU_LIFT_DESIGN.md)
#print axioms A2.kills_comp_self
#print axioms A2.comp_view_overkills
#print axioms A2.comp_inner_overkills
#print axioms A2.comp_inner_push_overkills
#print axioms A2.replace_covers
#print axioms A2.kill_after_replace
-- (A2/Region.lean, AGORA-937): after a .replace on a root, nothing depending on it is live
#print axioms A2.kill_replace_pi_dead
#print axioms A2.mem_rdsπ
-- AGORA-937: a region is no frame binding, has no slot, and is never a (held-)fresh
-- source; a region's index is always bound, so a fresh binding is never a region
#print axioms A2.Mode.region_not_frame
#print axioms A2.pi_not_fresh
#print axioms A2.pi_not_heldSrc
#print axioms A2.RSetup.AbsOK.notPiFresh
-- AGORA-937: the substitution keeps a name on no region and drops one on a region
-- (agora #4191: no region is ever changed by name), and keeps a weakening, so the
-- lifted context of a weaker callee context is weaker
#print axioms A2.RSetup.subD_name
#print axioms A2.RSetup.name_kill_not_region
#print axioms A2.RSetup.subE_weaker
#print axioms A2.RSetup.canon_weaker_sub
-- AGORA-937: no name is on a region (NameWF), and the substitution is idempotent, so what
-- the lifted context's arguments depend on is kept by it
#print axioms A2.RSetup.no_name_on_region
#print axioms A2.RSetup.subD_idem
#print axioms A2.RSetup.callRes_lift
-- AGORA-937: the call's lift with regions: what a substituted entry depends on
-- it depended on or the arguments hold, and what the caller's context adds is kept
#print axioms A2.RSetup.mem_subE_vdeps_A
#print axioms A2.RSetup.outHeld_canon_fix
#print axioms A2.RSetup.callT_ren
-- AGORA-937 (turn-on 2): CallT's ThruFn premise asks only that the arguments' roots are
-- regions or (route U, AGORA-937 B4) meet CallThruOK; where no binding is a region
-- (MInv.noRegion), its regions-only branch is the old premise, so such a call passes no views and
-- its regions stand for nothing (`call_root_not_region` refutes that branch only); the lift
-- of a call in the body that passes views of regions passes none (A2/RegionThruWitness.lean)
#print axioms A2.thru_call
#print axioms A2.callR_regions_of_nil
#print axioms A2.callR_nil_of_regions
#print axioms A2.CallT.thru
#print axioms A2.RSetup.σ_nil_of_R
#print axioms A2.RSetup.mem_subE_held_notPi_of_R
#print axioms A2.CallH.σ_nil_of_thru
#print axioms A2.RSetup.callR_canon
#print axioms A2.callR_clean_regions
#print axioms A2.RegionThruWitness.callR_region
#print axioms A2.RegionThruWitness.call_region_ok
#print axioms A2.RegionThruWitness.call_root_not_region
-- AGORA-937 (turn-on 3): FnOK's end checks let a result or an inout parameter hold views of a
-- parameter's region (isRegionIdx); the call substitutes what the argument holds views of,
-- which the caller's result and inout argument hold (heldOfArgs: CallH.σ_held), so the
-- exits' result and inout argument stay within callRes/callPost (A2/RegionResWitness.lean)
#print axioms A2.isRegionIdx_iff
#print axioms A2.fnOK_mono
#print axioms A2.callS_isPi
#print axioms A2.RSetup.mem_subD_pi
#print axioms A2.CallH.σ_held
#print axioms A2.CallH.lift_nosink_sub
#print axioms A2.CallH.lift_sub_sub
#print axioms A2.CallH.res_at
#print axioms A2.CallH.res_props
#print axioms A2.CallH.inout_at
#print axioms A2.CallH.fin_weaker
#print axioms A2.CallH.typedIn
#print axioms A2.RegionResWitness.idv_ok
#print axioms A2.RegionResWitness.idv_not_ok0
#print axioms A2.RegionResWitness.call_ok
#print axioms A2.RegionResWitness.callRes_holds
#print axioms A2.RegionResWitness.vw_not_ok
#print axioms A2.RegionResWitness.vat_ok
#print axioms A2.RegionResWitness.fst_trunc_ok
#print axioms A2.RegionResWitness.fst_trunc_old_refused
#print axioms A2.RegionResWitness.snd_trunc_refused
#print axioms A2.RegionResWitness.sink_dep_refused
-- AGORA-937: a right-hand side lifted with regions: what it reads is on no region, a
-- fresh borrow is on no region (FreshOK), what is derived is the lift substituted
#print axioms A2.RSetup.canon_setEs
#print axioms A2.RSetup.derive_subE
#print axioms A2.RSetup.fresh_keep
#print axioms A2.RSetup.RhsT.ren
-- AGORA-909: a field or payload read of a frame binding of a view-free type that holds
-- nothing may be fresh (RhsT.fst/snd/getl/getr), so a push through `. b items` of an
-- `inout` parameter is an `edit false` (A2/FreshProjWitness.lean)
#print axioms A2.RhsT.fst_unfresh
#print axioms A2.RhsT.snd_unfresh
#print axioms A2.RhsT.getl_unfresh
#print axioms A2.RhsT.getr_unfresh
#print axioms A2.FreshProjWitness.fst_typed
#print axioms A2.FreshProjWitness.g_not_thru
#print axioms A2.FreshProjWitness.call_ok
#print axioms A2.FreshProjWitness.main_typed
#print axioms A2.FreshProjWitness.main_safe
#print axioms A2.FreshProjWitness.main_no_leak
#print axioms A2.FreshProjWitness.proj_fresh_src
#print axioms A2.FreshProjWitness.proj_not_src_not_fresh
#print axioms A2.FreshProjWitness.fst_rootb_not_fresh
#print axioms A2.FreshProjWitness.proj_stale_not_fresh
#print axioms A2.FreshProjWitness.proj_of_proj_fresh
#print axioms A2.FreshProjWitness.proj_view_not_fresh
#print axioms A2.FreshProjWitness.nested_view_not_fresh
#print axioms A2.FreshProjWitness.payload_fresh_killed
-- ... and a nested read through a fresh, held-fresh borrow: the lift adds no name to a
-- type that holds no closure (RSetup.heldA), so the renamed read is exact
#print axioms A2.WFv.names_nil_fn
#print axioms A2.RSetup.heldA_P_sub
#print axioms A2.RSetup.projSrc_lift
#print axioms A2.RSetup.projE_fresh_lift
#print axioms A2.FreshNestWitness.fst3_typed
#print axioms A2.FreshNestWitness.g_not_thru
#print axioms A2.FreshNestWitness.call_ok
#print axioms A2.FreshNestWitness.main_typed
#print axioms A2.FreshNestWitness.main_safe
#print axioms A2.FreshNestWitness.main_no_leak
-- AGORA-909: an element read through a slice may be fresh (RhsT.sat), as one through a Vec
#print axioms A2.derive_freshE_any
#print axioms A2.RhsT.sat_unfresh
#print axioms A2.FreshSatWitness.view_typed
#print axioms A2.FreshSatWitness.sat_typed
#print axioms A2.FreshSatWitness.g_not_thru
#print axioms A2.FreshSatWitness.call_ok
#print axioms A2.FreshSatWitness.main_typed
#print axioms A2.FreshSatWitness.main_safe
#print axioms A2.FreshSatWitness.main_no_leak
#print axioms A2.FreshSatWitness.sat_rootb_not_fresh
#print axioms A2.FreshSatWitness.sat_stale_not_fresh
#print axioms A2.FreshSatWitness.sat_slice_elem_not_fresh
#print axioms A2.FreshSatWitness.sat_of_view_of_rootb_not_fresh
-- Phase B1: `Vec`'s owned buffer (stdlib/core/vec.nu's raw core) meets A1's `Vec`
#print axioms B.growTo_ok
#print axioms B.push_ok
#print axioms B.push_refines
#print axioms B.get_ok
#print axioms B.set_ok
#print axioms B.setC_ok
#print axioms B.pop_ok
#print axioms B.free_ok
#print axioms B.insert_ok
#print axioms B.remove_ok
#print axioms B.truncate_ok
#print axioms B.swap_ok
#print axioms B.reserve_ok
#print axioms B.memcpy_ok
#print axioms B.vget_ok
#print axioms B.vpush_ok
#print axioms B.dropLoop_ok
#print axioms B.releaseFrom_ok
#print axioms B.memcpy_frame
#print axioms B.dropLoop_nid
#print axioms B.dropLoop_wf
#print axioms B.releaseFrom_fresh
#print axioms B.copyAt_ok
#print axioms B.append_ok
#print axioms B.rep_free_other
#print axioms B.appendFree_ok
-- Phase B2: `String` (stdlib/core/string.nu's raw core): the bytes and the NUL terminator
#print axioms B.strSeal_ok
#print axioms B.pushBytes_ok
#print axioms B.data_ok
-- Phase B3: `rcbox` (stdlib/core/rcbox.nu): the count is the handles; the last release drops once
#print axioms B.rcNew_ok
#print axioms B.rcShare_ok
#print axioms B.rcRelease_ok
-- Phase B4: `HashMap` (stdlib/std/hashmap.nu): probes in bounds, sound and total; no write over an entry
#print axioms B.mask_eq_mod
#print axioms B.probe_found
#print axioms B.probe_insert
#print axioms B.probe_total
#print axioms B.set_probe_answers
#print axioms B.mapInsert_ok
#print axioms B.mapReplace_ok
#print axioms B.mapRemove_ok
#print axioms B.entries_put_empty
#print axioms B.moveAll_ok
#print axioms B.grow_ok
#print axioms B.release_ok
-- Phase B5: `Arc` / `ArcWeak` (stdlib/std/arc.nu): counts are the handles; the value dropped at the last strong
-- release, the block freed at the last handle of either kind, an upgrade only while the value lives
#print axioms B.arcNew_ok
#print axioms B.arcClone_ok
#print axioms B.arcDowngrade_ok
#print axioms B.weakClone_ok
#print axioms B.arcDrop_ok
#print axioms B.weakDrop_ok
#print axioms B.upgrade_ok
-- Phase B6: `Channel`'s queue (stdlib/std/channel.nu): FIFO conservation, none lost, none twice
#print axioms B.conservation
#print axioms B.offered_split
#print axioms B.fresh_conservation
#print axioms B.recv_steps
-- Phase B7: the Rc cycle collector's trial-deletion criterion: a white block has no outside handle and
-- every handle on it is a white block's, so freeing them together leaves nothing dangling
#print axioms B.trial_eq
#print axioms B.white_closed
#print axioms B.collect_safe
-- Phase B8: alloc_size / alloc_count_add never hand back a wrapped size
#print axioms B.allocSize_ok
#print axioms B.countAdd_ok
#print axioms B.reserveC_overflow
#print axioms B.reserveC_room
#print axioms B.reserveC_ok
#print axioms B.growTo_cap
#print axioms B.reserveZ_room
#print axioms B.reserveZ_count_overflow
#print axioms B.reserveZ_size_overflow
#print axioms B.reserveZ_ok
#print axioms B.reserveC_size_gap
#print axioms B.doubleTo_le
#print axioms B.growCap_le
-- Phase B9: std/rc.nu's Rc / Weak / rc_take: a checked-out value is never read or dropped through the block;
-- the last strong release drops a value only when it is there; the block goes with the last Weak
#print axioms B.rcGet_ok
#print axioms B.rcTake_ok
#print axioms B.rcRestore_ok
#print axioms B.rcDrop_ok
#print axioms B.rcUpgrade_ok
#print axioms B.rcWeakDrop_ok
#print axioms B.packedPush_room
#print axioms B.packedPush_ok
#print axioms B.packedPush_release
-- Phase C0: an executable checker for A1's straight-line fragment, sound against A1's typing
#print axioms C.checkExpr_sound
#print axioms C.inferRhs_sound
#print axioms C.checkStmt_sound
#print axioms C.checked_memory_safe
-- Phase C1: the checker with ite / while joins over finite contexts, sound
#print axioms C.eq_of_agree
#print axioms C.checkS_sound
#print axioms C.checkedS_memory_safe
-- Phase C2: subsumption by certificate: Weaker decided over the finite domain
#print axioms C.weakerB_sound
#print axioms C.checkC_sound
#print axioms C.checkedC_memory_safe
-- Phase C3–C4: calls decided; whole A1 programs checked end to end
#print axioms C.callB_sound
#print axioms C.fnOKB_sound
#print axioms C.progOKB_sound
#print axioms C.progOKAux_mem
#print axioms C.checkedS_memory_safe_dedup
#print axioms C.checkedC_memory_safe_dedup
#print axioms C.checked_program_safe_dedup
#print axioms C.joinTbl_supported
#print axioms C.capOKB_held
#print axioms C.unpairTyB_some
#print axioms C.takeOKB_sound
#print axioms C.checked_program_safe
-- Phase C7w: A2's Weaker decided; joins of ite arms and loop rounds by weakening
#print axioms C.weaker2B_sound
-- Phase C8c: A3.2's lock and A3.4's channel right-hand sides, decided (AGORA-975)
#print axioms C.chanRhs_ok
#print axioms C.inferRhs2c_ok
-- Phase C8p: A2's closure literal with no captures by name, decided (AGORA-978)
#print axioms C.packRhs_ok
#print axioms C.inferRhs2p_ok
-- Phase C7x: A2's exit, decided by obligations on the exits context
#print axioms C.checkX_sound
-- Phase C11: A2 end to end - a program the checker accepts never gets stuck from the empty store
#print axioms C.checked_program_safe2
-- Phase C12: A3 end to end - a checked program's makes and run are memory-safe, race-free and leak-free
#print axioms C.checked_claim_made_full
-- Phase C13: a program's certificate claims, from the checker's one-boolean verdict (AGORA-1019)
#print axioms C.cert_safe
#print axioms C.cert_leak_end
#print axioms C.cert_leak_panic
#print axioms C.cert_witness_safe
#print axioms C.cert_witness_leak
-- Phase C5: A2's expressions decided
#print axioms C.checkExpr2_sound
-- Phase C6: A2's core right-hand sides decided
#print axioms C.noPinB_sound
#print axioms C.dtorSafeB_sound
#print axioms C.inferRhs2_sound
-- Phase C7: A2's core statements decided, for any exits
#print axioms C.endOK2B_sound
#print axioms C.pushArg2_sound
#print axioms C.checkStmt2_sound
-- Phase C8: A2's struct and enum right-hand sides decided
#print axioms C.inferRhs2d_ok
-- Phase C9: A2's calls decided; the A2 checker so far (checkA2)
#print axioms C.callB2_sound
#print axioms C.checkA2_sound
-- Phase C10: CtxWF / NameWF decided; A2's panic
#print axioms C.ctxWF2B_sound
#print axioms C.nameWFB_sound
#print axioms C.panic_self
#print axioms C.freshOKB_sound
#print axioms C.panicToB_sound
-- (A2/CapsStore.lean, AGORA-969, AGORA-963 step 3's store half): the closure-capture clause's
-- store part, kept by the store operations a step makes
#print axioms A2.heldCapsInp_iff
#print axioms A2.HeldCapsInp.of_caps
#print axioms A2.CapsInpAt.set
#print axioms A2.CapsInpAt.remove
#print axioms A2.CapsInpAt.of_st
#print axioms A2.sub_pkg_lendOf
#print axioms A2.BindParams.capsInp
#print axioms A2.Release.capsInp
#print axioms A2.EvalR.capsInp
#print axioms A2.Step.slotsCaps
-- Phase D2: an accepted drop-validation path is safe on a concrete heap
#print axioms D.validated_safe
