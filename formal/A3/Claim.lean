import A3.SpawnPres
import A3.Restrict
import A3.Lift
import A3.SpawnOld
import A3.SpawnNew

/-! A3.0 — the claim. -/

namespace A3
open A2

/-- **A3.0**: a program A2 types, whose spawned functions take only
    view-free `sink` parameters, is memory-safe, race-free and leak-free on
    every interleaving of its threads. -/
theorem claim : Claim :=
  claim_from
    (fun _ => fun h => fun hav hb hf => Step.restrict h hav hb hf)
    (fun _ => fun h => fun hd hf => Step.lift h hd hf)
    (fun _ _ hP hPc hS => fun hok => fun hR hsp hf hx hmv => spawner_ok hP hPc hS hok hR hsp hf hx hmv)
    (fun _ _ hP hS => fun hok => fun hR hsp hf hmv => spawn_args hP hS hok hR hsp hf hmv)
    (fun _ _ hP hPc hS => fun hsp hf => fun hlen hwf hnd hdisj hself hpk hcd => fun hpart => fun hlt =>
      newThread_ok hP hPc hS hsp hf hlen hwf hnd hdisj hself hpk hcd hpart hlt)

end A3
