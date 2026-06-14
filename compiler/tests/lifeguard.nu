// lifeguard.nu — offline test for stdlib/std/lifeguard.nu. Deterministic:
// checks the Local Health Multiplier (penalize/award/cap/floor/scale) and
// the confirmation-scaled suspicion timeout (max at 0 confirmations, min at
// k, monotone decrease, expiry).

$ `stdlib/std/lifeguard.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }
@ pi s label i v → v { ( nurl_print label ) ( nurl_print_int v ) }

@ main → i {
    // ── Local Health Multiplier ──────────────────────────────────
    : LocalHealth h0 ( local_health_new 8 )
    ( pb `LHM starts healthy (0): ` == ( lh_value h0 ) 0 )
    ( pb `award at floor stays 0: ` == ( lh_value ( lh_award h0 ) ) 0 )

    : LocalHealth h1 ( lh_penalize h0 )
    : LocalHealth h2 ( lh_penalize h1 )
    ( pb `two penalties → 2: ` == ( lh_value h2 ) 2 )
    ( pb `scale base 1000 by (1+2) = 3000: ` == ( lh_scale h2 1000 ) 3000 )
    ( pb `award recovers to 1: ` == ( lh_value ( lh_award h2 ) ) 1 )

    // penalize past the cap (10× on a max-8 health) clamps at 8
    : ~ LocalHealth hc ( local_health_new 8 )
    : ~ i k 0 ~ < k 10 { = hc ( lh_penalize hc ) = k + k 1 }
    ( pb `penalty capped at max (8): ` == ( lh_value hc ) 8 )

    // ── confirmation-scaled suspicion timeout ────────────────────
    // min 1000, max 5000, k 3, start at t=0.
    : Suspicion s0 ( suspicion_new 1000 5000 3 0 )
    : i t0 ( suspicion_timeout_ns s0 )
    ( pi `timeout @ 0 confirms: ` t0 ) ( nurl_print `\n` )
    ( pb `0 confirms → max (5000): ` == t0 5000 )

    // one confirmation: log(2)/log(4) = 0.5 → 5000 - 4000*0.5 = 3000
    : Suspicion s1 ( suspicion_confirm s0 )
    : i t1 ( suspicion_timeout_ns s1 )
    ( pi `timeout @ 1 confirm: ` t1 ) ( nurl_print `\n` )
    ( pb `1 confirm → 3000: ` == t1 3000 )

    // two confirmations: strictly between t1 and the floor
    : Suspicion s2 ( suspicion_confirm s1 )
    : i t2 ( suspicion_timeout_ns s2 )
    ( pb `2 confirms strictly between: ` & < t2 t1 > t2 1000 )

    // three (== k) confirmations: floor (1000); further confirms clamp
    : Suspicion s3 ( suspicion_confirm s2 )
    : i t3 ( suspicion_timeout_ns s3 )
    ( pb `k confirms → min (1000): ` == t3 1000 )
    ( pb `confirms clamp at k: ` == ( suspicion_confirms ( suspicion_confirm s3 ) ) 3 )

    // ── expiry ───────────────────────────────────────────────────
    // lone suspicion (timeout 5000): not expired at 4000, expired at 6000.
    ( pb `lone suspicion alive at t=4000: ` ! ( suspicion_expired s0 4000 ) )
    ( pb `lone suspicion expired at t=6000: ` ( suspicion_expired s0 6000 ) )
    // corroborated (timeout 1000): already expired at t=4000.
    ( pb `corroborated expires fast (t=4000): ` ( suspicion_expired s3 4000 ) )

    ^ 0
}
