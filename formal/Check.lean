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
#print axioms A3.LockDtorWitness.rwRead_dtor_refused
#print axioms A3.LockDtorWitness.lockRestore_dtor_refused
#print axioms A3.LockDtorWitness.main_typed
#print axioms A3.LockDtorWitness.main_safe
#print axioms A3.LockDtorWitness.main_no_leak
#print axioms A3.LockDtorWitness.main_no_leak_panic
#print axioms A3.LockDtorWitness.last_drop_reaps
#print axioms A3.lockDtor_claim
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
