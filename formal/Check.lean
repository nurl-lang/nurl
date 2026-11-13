import A1
import A2
import A3
/-! Run by `check.sh`: the axioms the main theorems rest on. -/
#print axioms A1.memory_safe
#print axioms A1.soundness
#print axioms A2.memory_safe
#print axioms A2.soundness
#print axioms A2.no_leak_end
#print axioms A2.no_leak_panic
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
#print axioms A3.LockDtorWitness.release_puts
#print axioms A3.LockDtorWitness.scopeL_end_gives_back
#print axioms A3.LockDtorWitness.scopeL_panic_gives_back
#print axioms A3.LockDtorWitness.sendCheck_noArc
-- Agora #805: a typed check-out frame of a destructor payload ends with `x` owning a `t`, and at every
-- panic point `x` owns a `t` (given back) or nothing (`StmtT.scopeL` asks `x` an owner, live at the end)
#print axioms A3.LockDtorWitness.scopeL_end_entry
#print axioms A3.LockDtorWitness.scopeL_end_owns
#print axioms A3.LockDtorWitness.scopeL_typed_end_gives_back
#print axioms A3.LockDtorWitness.Step.panic_st
#print axioms A3.LockDtorWitness.scopeL_entry
#print axioms A3.LockDtorWitness.scopeL_typed_panic
-- Agora #808: the check-outs' invariant over every reached configuration (A3/LockExcl.lean): each
-- frame's block a lock block of its type, or gone; a frame of a payload that holds a destructor value
-- has its block checked out and is its only frame (A3.2's mutual exclusion)
#print axioms A3.Step.lfr
#print axioms A3.EvalR.stay
#print axioms A3.Step.stay
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
#print axioms A3.LockDtorWitness.rwRead_dtor_refused
#print axioms A3.LockDtorWitness.lockRestore_dtor_refused
#print axioms A3.LockDtorWitness.main_typed
#print axioms A3.LockDtorWitness.main_safe
#print axioms A3.LockDtorWitness.main_no_leak
#print axioms A3.LockDtorWitness.main_no_leak_panic
#print axioms A3.LockDtorWitness.last_drop_reaps
#print axioms A3.lockDtor_claim
#print axioms A3.LockDtorWitness.mainV_typed
#print axioms A3.LockDtorWitness.mainV_safe
#print axioms A3.LockDtorWitness.mainV_no_leak
#print axioms A3.LockDtorWitness.mainV_no_leak_panic
#print axioms A3.LockDtorWitness.last_dropV_reaps
#print axioms A3.LockDtorWitness.reapV_drains
#print axioms A3.lockVecDtor_claim
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
-- key above every share), at a start whose globals keep the kinds apart (which the make phase
-- leaves); so a check-out of a cell's block is through a cell share, by an owner (`CellOp`); `GlobsOK`
-- alone admits a start naming a key by both kinds
#print axioms A3.EvalR.kinds
#print axioms A3.Step.kinds
#print axioms A3.CSettle.kinds
#print axioms A3.TStep.kinds
#print axioms A3.Reach.kinds
#print axioms A3.CKinds.start
#print axioms A3.reach_kinds
#print axioms A3.CKinds.shareKind
#print axioms A3.reach_shareKind
#print axioms A3.made_kinds
#print axioms A3.reach_shareKind_made
#print axioms A3.reach_frame_cell_owner
#print axioms A3.reach_frame_cellOp
#print axioms A3.mix_globsOK
#print axioms A3.mix_not_shareKind
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
