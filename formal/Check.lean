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
#print axioms A2.Dtor.scopeD_end_runs_dtor
#print axioms A2.Dtor.scopeD_panic_runs_dtor
#print axioms A2.DtorWitness.main_safe
#print axioms A2.DtorWitness.main2_safe
#print axioms A2.DtorWitness.lock_checkout_assign
-- threads: moves, Arc's frozen shared payloads, Locked, RwLocked, Atomic, channels, library
-- handles and the crossing check, module globals (A3/Claim.lean)
#print axioms A3.claim
-- module globals made before main by their declarations' makes, read at their declared types
-- (A3/Make.lean)
#print axioms A3.claim_made
