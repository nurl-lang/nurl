// benchmark-contract: dynamic-method-mix;objects=64;impls=4(adder,mixer,shifter,lookup16);kind=(r>>8)%4;steps=10000000;lcg=mmix(seed=1);draw=state>>33;obj=r&63;chain=v=apply(o,v^r)+weight(o);fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// dynamic_method_mix — 10M steps over 64 trait objects of one dynamic
// interface, `%Op` (two methods, `apply` and `weight`), implemented by
// four struct types of different shapes: one field, two, three, and one
// owning a Vec of sixteen u64s. The objects' kinds are drawn from an
// MMIX LCG when the pool is built, and each step draws the object to use
// from the same generator, so neither the callee nor the receiver's type
// is predictable. Every result feeds the next step.
//
// What this row adds: dynamic dispatch — a vtable load, then an
// indirect call per method, on a receiver whose concrete type the call
// site does not know. `captured_closure_queue` is the nearest row: a
// closure is one function pointer beside its environment, a trait
// object is a pointer to a table of them (and here two calls a step).
//
// C carries each object as a { data pointer, vtable pointer } pair with
// a hand-written vtable of function pointers per type (the shape NURL's
// and Rust's trait objects lower to); Rust a `Vec<Box<dyn Op>>`.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

$ `stdlib/core/vec.nu`

% Op [T] {
    @ apply T self u64 x → u64
    @ weight T self → u64
}

: Adder { u64 c }

: Mixer { u64 m u64 s }

: Shifter { u64 a u64 b u64 c }

: Lookup { ( Vec u64 ) t }

% Op Adder {
    @ apply Adder o u64 x → u64 { ^ + x . o c }
    @ weight Adder o → u64 { ^ & . o c 7 }
}

% Op Mixer {
    @ apply Mixer o u64 x → u64 { ^ ^^ * x . o m . o s }
    @ weight Mixer o → u64 { ^ & . o s 7 }
}

% Op Shifter {
    @ apply Shifter o u64 x → u64 { ^ + ^^ >> x . o a << x . o b . o c }
    @ weight Shifter o → u64 { ^ . o a }
}

% Op Lookup {
    @ apply Lookup o u64 x → u64 { ^ ^^ x ( vec_at [u64] . o t # i & x 15 ) }
    @ weight Lookup o → u64 { ^ & ( vec_at [u64] . o t 0 ) 7 }
}

@ lookup_table u64 seed → ( Vec u64 ) {
    : ( Vec u64 ) t ( vec_with_cap [u64] 16 )
    : ~ u64 j 0
    ~ < j 16 {
        ( vec_push [u64] t + * ^^ seed j 2654435761 j )
        = j + j 1
    }
    ^ t
}

// An object of kind 0..3, its fields drawn from `r`.
@ make u64 kind u64 r → %Op {
    ? == kind 0 { ^ ( dyn Op @ Adder { r } ) } {}
    ? == kind 1 { ^ ( dyn Op @ Mixer { | r 1 >> r 5 } ) } {}
    ? == kind 2 { ^ ( dyn Op @ Shifter { + & r 31 1 + & >> r 5 31 1 * r 3 } ) } {}
    ^ ( dyn Op @ Lookup { ( lookup_table r ) } )
}

@ fnv u64 h u64 v → u64 { ^ * ^^ h v 1099511628211 }

@ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : u64 steps * 10000000 BENCH_SCALE

    : ~ u64 x 1
    : ( Vec % Op ) objs ( vec_with_cap [% Op] 64 )
    : ~ u64 z 0
    ~ < z 64 {
        = x + * x 6364136223846793005 1442695040888963407
        : u64 r >> x 33
        ( vec_push [% Op] objs ( make % >> r 8 4 r ) )
        = z + z 1
    }

    : ~ u64 v 0
    : ~ u64 k 0
    ~ < k steps {
        = x + * x 6364136223846793005 1442695040888963407
        : u64 r >> x 33
        : %Op o ( vec_at [% Op] objs # i & r 63 )
        = v + ( apply o ^^ v r ) ( weight o )
        = k + k 1
    }

    : ~ u64 h 1469598103934665603
    = h ( fnv h v )
    : ~ i s 0
    ~ < s 64 {
        : %Op g ( vec_at [% Op] objs s )
        = h ( fnv h + ( apply g 12345 ) ( weight g ) )
        = s + s 1
    }
    = h ( fnv h x )
    ( nurl_println_int # i & h 0x7fffffffffffffff )
    ^ 0
}
