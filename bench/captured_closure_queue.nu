// benchmark-contract: captured-closure-queue;slots=16;kinds=5(add,mulxor,rotadd,table16,pair);steps=10000000;lcg=mmix(seed=1);draw=state>>33;slot=r&15;refill=every256th(slot=(r>>8)&15,kind=((r>>12)&65535)%5);chain=v=f(v^r);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// captured_closure_queue — 10M calls through a queue of 16 closures of
// one type, `( @ u64 u64 )`, made by five constructors whose captured
// environments differ in shape: one u64, two u64s, three u64s, a Vec of
// sixteen u64s (a table the body indexes by its argument) and a two-field
// record. Each step draws a slot from an MMIX LCG and calls that closure
// on the running value xor the draw, so the callee is unpredictable and
// every result feeds the next call. Every 256th step a fresh closure of
// an input-chosen kind replaces an input-chosen slot, dropping the old
// one's environment and allocating the new one's.
//
// What this row adds: the closure ABI — an indirect call through a
// function pointer with an environment pointer, the loads of captures
// laid out in a heap environment, and a closure's environment built and
// dropped as the queue churns. `fib` measures a direct call; nothing
// else in the roster calls through a pointer.
//
// C carries each closure as a { function pointer, malloc'd environment }
// pair (the table kind's environment points at a malloc'd table, as a
// Vec's buffer is separate from its handle); Rust a `Vec<Box<dyn
// Fn(u64) -> u64>>` whose table kind captures a `Vec<u64>`.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

$ `stdlib/core/vec.nu`

: Pair { u64 lo u64 hi }

@ mk_add u64 c → ( @ u64 u64 ) { ^ \ u64 x → u64 { ^ + x c } }

@ mk_mulxor u64 m u64 s → ( @ u64 u64 ) { ^ \ u64 x → u64 { ^ ^^ * x m s } }

@ mk_rotadd u64 rot u64 a u64 b → ( @ u64 u64 ) {
    ^ \ u64 x → u64 { ^ ^^ + | >> x rot << x - 64 rot a b }
}

@ mk_table u64 seed → ( @ u64 u64 ) {
    : ( Vec u64 ) t ( vec_with_cap [u64] 16 )
    : ~ u64 j 0
    ~ < j 16 {
        ( vec_push [u64] t + * ^^ seed j 2654435761 j )
        = j + j 1
    }
    ^ \ u64 x → u64 { ^ ^^ x ( vec_at [u64] t # i & x 15 ) }
}

@ mk_pair Pair p → ( @ u64 u64 ) { ^ \ u64 x → u64 { ^ ^^ + x . p lo . p hi } }

// A closure of kind 0..4, its captures drawn from `r`.
@ make u64 kind u64 r → ( @ u64 u64 ) {
    ? == kind 0 { ^ ( mk_add r ) } {}
    ? == kind 1 { ^ ( mk_mulxor | r 1 >> r 5 ) } {}
    ? == kind 2 { ^ ( mk_rotadd + & r 31 1 >> r 7 * r 3 ) } {}
    ? == kind 3 { ^ ( mk_table r ) } {}
    ^ ( mk_pair @ Pair { r << r 17 } )
}

@ fnv u64 h u64 v → u64 { ^ * ^^ h v 1099511628211 }

@ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : u64 steps * 10000000 BENCH_SCALE

    : ~ u64 x 1
    : ( Vec ( @ u64 u64 ) ) q ( vec_with_cap [( @ u64 u64 )] 16 )
    : ~ u64 z 0
    ~ < z 16 {
        = x + * x 6364136223846793005 1442695040888963407
        ( vec_push [( @ u64 u64 )] q ( make % z 5 >> x 33 ) )
        = z + z 1
    }

    : ~ u64 v 0
    : ~ u64 k 0
    ~ < k steps {
        = x + * x 6364136223846793005 1442695040888963407
        : u64 r >> x 33
        ? == & k 255 255 {
            ( vec_put [( @ u64 u64 )] q # i & >> r 8 15 ( make % & >> r 12 65535 5 r ) )
        } {}
        : ( @ u64 u64 ) f ( vec_at [( @ u64 u64 )] q # i & r 15 )
        = v ( f ^^ v r )
        = k + k 1
    }

    : ~ u64 h 1469598103934665603
    = h ( fnv h v )
    : ~ i s 0
    ~ < s 16 {
        : ( @ u64 u64 ) g ( vec_at [( @ u64 u64 )] q s )
        = h ( fnv h ( g 12345 ) )
        = s + s 1
    }
    = h ( fnv h x )
    ( nurl_println_int # i & h 0x7fffffffffffffff )
    ^ 0
}
