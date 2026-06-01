// recover_basic.nu — exercises stdlib/std/panic.nu's `panic` /
// `recover` round trip.
//
// Three cases:
//
//   1. recover wrapping a closure that completes normally → Ok arm.
//   2. recover wrapping a closure that calls `panic` → Err arm, the
//      message round-trips through the runtime's thread-local slot.
//   3. Typed-return shape: a `: ~ HttpResponse`-style byref-capture
//      receives the closure's intended value when no panic fires;
//      keeps its pre-call default when a panic fires.
//
// Captures the panic-recovery contract: control returns to the
// caller, the program keeps running, owned allocations made inside
// the recover scope LEAK (documented cost — see panic.nu header).

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Counter { i n i max }

@ noisy → v {
    ( nurl_print `noisy: before panic\n` )
    ( panic `simulated handler crash` )
    ( nurl_print `noisy: after panic (should NOT print)\n` )
}

@ produce_42 → i { ^ 42 }

@ main → i {
    // Case 1 — closure completes normally.
    : !v PanicInfo r1 ( recover \ → v { ( nurl_print `c1: closure body\n` ) } )
    ?? r1 {
        T _ → ( nurl_print `c1: ok\n` )
        F p → { ( nurl_print `c1: unexpected panic\n` ) ( panic_info_free p ) }
    }

    // Case 2 — closure panics; control returns, message captured.
    : !v PanicInfo r2 ( recover \ → v { ( noisy ) } )
    ?? r2 {
        T _ → ( nurl_print `c2: ok (unexpected!)\n` )
        F p → {
            ( nurl_print `c2: caught msg=` )
            ( nurl_print ( string_data . p msg ) )
            ( nurl_print `\n` )
            ( panic_info_free p )
        }
    }

    // Case 3 — typed-return via byref-capture. The mutable slot is a
    // multi-field struct (Counter) — these flow through the closure's
    // env block as POINTERS (the `: ~`-byref-capture path) so writes
    // inside the closure reach the outer alloca. Scalars + single-
    // handle structs are captured by VALUE, so this idiom only works
    // for multi-field structs (mirrors docs/MEMORY.md §2.3).
    //
    // Non-panicking call: the assignment reaches the outer alloca →
    // out_a.n is 42 after recover returns.
    : ~ Counter out_a @ Counter { 0 0 }
    : !v PanicInfo r3a ( recover \ → v { = out_a @ Counter { 42 0 } } )
    ?? r3a {
        T _ → { ( nurl_print `c3a: out_a.n=` ) ( nurl_print ( nurl_str_int . out_a n ) ) ( nurl_print `\n` ) }
        F p → { ( nurl_print `c3a: unexpected panic\n` ) ( panic_info_free p ) }
    }

    // Panicking call: panic fires BEFORE the assignment → out_b keeps
    // its pre-call default (99 / 0).
    : ~ Counter out_b @ Counter { 99 0 }
    : !v PanicInfo r3b ( recover \ → v { ( noisy ) = out_b @ Counter { 42 0 } } )
    ?? r3b {
        T _ → ( nurl_print `c3b: ok (unexpected!)\n` )
        F p → {
            ( nurl_print `c3b: out_b.n=` ) ( nurl_print ( nurl_str_int . out_b n ) ) ( nurl_print `\n` )
            ( panic_info_free p )
        }
    }

    // Case 4 — program continues normally past the recover boundary.
    ( nurl_print `c4: program still alive\n` )
    ^ 0
}
