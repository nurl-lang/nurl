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
-- ... and `vec_free` / `vec_clear` / `vec_truncate` of one are typed code (A2/DropCode.lean)
#print axioms A2.Dtor.vecFreeD_typed
#print axioms A2.Dtor.vecClearD_typed
#print axioms A2.Dtor.vecTruncD_typed
#print axioms A2.DtorWitness.main6_safe
-- Agora #607: a `Vec` of destructor values as a struct's field, drained through the struct's glue
#print axioms A2.DtorWitness.main9_safe
-- A2-drop.3c: no closure or trait-object environment holds a destructor value
#print axioms A2.Dtor.pack_env_dtor_free
#print axioms A2.WFv.pkg_env_dtor_free
#print axioms A2.Dtor.pkgs_env_dtor_free
#print axioms A2.Dtor.closure_dtor_is_glue
#print axioms A2.Dtor.drop_method_code
-- A2-drop.3d: no share's payload owns a destructor value
#print axioms A2.Dtor.ok_payloads_free
#print axioms A2.Dtor.shares_dtor_free
#print axioms A2.Dtor.blocks_dtor_free
#print axioms A2.Dtor.blk_pkgs_env_dtor_free
#print axioms A2.Dtor.share_new_dtor_free
#print axioms A2.Dtor.vec_elems_dtor_free
#print axioms A2.Dtor.new_dtor_free
#print axioms A2.Dtor.vecs_dtor_free
#print axioms A2.rhs_popFront
#print axioms A2.Dtor.holdsDtor_deep
#print axioms A2.Dtor.letv_owned_dtor_free
#print axioms A2.DtorWitness.main_safe
#print axioms A2.DtorWitness.main2_safe
#print axioms A2.DtorWitness.main3_safe
#print axioms A2.DtorWitness.main4_safe
#print axioms A2.DtorWitness.main4_letv_refused
#print axioms A2.DtorWitness.main5_safe
#print axioms A2.DtorWitness.main5_letv_refused
#print axioms A2.DtorWitness.enum_lends
#print axioms A2.DtorWitness.enum_take_refused
-- threads: moves, Arc's frozen shared payloads, Locked, RwLocked, Atomic, channels, library
-- handles and the crossing check, module globals (A3/Claim.lean)
#print axioms A3.claim
-- module globals made before main by their declarations' makes, read at their declared types
-- (A3/Make.lean)
#print axioms A3.claim_made
