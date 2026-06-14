// stdlib/std/lifeguard.nu — Lifeguard failure-detector resilience (§7.4
// Phase 5). The SWIM "Lifeguard" extensions cut false-positive failure
// detections — the dominant problem when members run over flaky mobile /
// NAT'd links (net/transport), where a slow or roaming node looks "dead"
// when it is merely temporarily unreachable.
//
// Two pure mechanisms (no I/O — they parametrise a failure detector's
// timers and accusations; wiring onto std/swim over net/transport is the
// remaining Phase 5 step):
//
//   1. Local Health Multiplier (LHM). A node measures ITS OWN health: a
//      probe that gets no ack (direct or indirect) is evidence that the
//      LOCAL node's network is degraded as much as the remote's, so the
//      node penalises itself, and a successful probe rewards it. Probe
//      intervals AND suspicion timeouts are scaled by (1 + LHM): an
//      unhealthy node both probes less aggressively and is slower to
//      accuse others — so a node on a bad link stops generating false
//      positives about everyone else.
//
//   2. Confirmation-scaled suspicion timeout (the "dogpile"). A suspected
//      member is given a LONG timeout to refute the suspicion; each
//      INDEPENDENT confirmation from another node shortens it, down to a
//      floor once enough peers agree. Lone suspicions wait long (mobile
//      blip); corroborated ones converge fast (genuine failure).
//      timeout(c) = max - (max-min) · log(c+1)/log(k+1).

$ `stdlib/std/float.nu`

// ── Local Health Multiplier ──────────────────────────────────────

: LocalHealth {
    i lhm     // current multiplier, 0 (healthy) .. max
    i max     // cap (memberlist uses 8)
}

@ local_health_new i max → LocalHealth { ^ @ LocalHealth { 0 max } }
@ lh_value LocalHealth h → i { ^ . h lhm }

// Successful probe → improve local health (decrement toward 0).
@ lh_award LocalHealth h → LocalHealth {
    : i nv ? > . h lhm 0 - . h lhm 1 0
    ^ @ LocalHealth { nv . h max }
}

// Failed probe / self was suspected → worsen local health (increment, capped).
@ lh_penalize LocalHealth h → LocalHealth {
    : i nv ? < . h lhm . h max + . h lhm 1 . h max
    ^ @ LocalHealth { nv . h max }
}

// Scale a base interval / timeout by (1 + LHM). An unhealthy node backs off.
@ lh_scale LocalHealth h i base → i { ^ * base + 1 . h lhm }

// ── confirmation-scaled suspicion timeout ────────────────────────

: Suspicion {
    i min_ns      // floor timeout once k confirmations are in
    i max_ns      // initial timeout with zero confirmations
    i k           // independent confirmations needed to reach the floor
    i confirms    // confirmations received so far (0..k)
    i start_ns    // monotonic time the suspicion began
}

@ suspicion_new i min_ns i max_ns i k i now_ns → Suspicion {
    ^ @ Suspicion { min_ns max_ns k 0 now_ns }
}
@ suspicion_confirms Suspicion s → i { ^ . s confirms }

// Register one independent confirmation from a distinct peer (capped at k).
@ suspicion_confirm Suspicion s → Suspicion {
    : i nc ? < . s confirms . s k + . s confirms 1 . s confirms
    ^ @ Suspicion { . s min_ns . s max_ns . s k nc . s start_ns }
}

// Current timeout for the suspicion given confirmations received:
//   max - (max-min) · log(c+1)/log(k+1)      (== max at c=0, == min at c=k)
@ suspicion_timeout_ns Suspicion s → i {
    ? <= . s k 0 { ^ . s min_ns } {}
    : i c ? > . s confirms . s k . s k . s confirms
    : i c1 + c 1
    : i k1 + . s k 1
    : f frac / ( log # f c1 ) ( log # f k1 )
    : i diff - . s max_ns . s min_ns
    : f prod * # f diff frac
    : i delta # i prod
    : i to - . s max_ns delta
    ^ ? < to . s min_ns . s min_ns to
}

// Has the suspicion timed out at now_ns (→ declare the member dead)?
@ suspicion_expired Suspicion s i now_ns → b {
    ^ >= - now_ns . s start_ns ( suspicion_timeout_ns s )
}
