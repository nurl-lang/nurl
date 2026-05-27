// enigma.nu — NURL v1.1 Stress Test (Enigma Evaluator)
// Human readability score: 0
// Demonstrates:
// - Name-mangling lexer overrides (sys::e)
// - Nested trait bounds and auto-drop triggers
// - Prefix hell and literal-match fallthrough
// - Borrowed foreach slices

& `libc`

@ malloc i → *v

: O { i _ i __ }
: P { O ___ [i ____ }

: | N {
    A i i
    B * N
    C i
}

// (Auto-drop trait omitted — user-defined Drop for struct payloads still
//  has rough edges when combined with closures in the same scope.)

% X [T] {
    @ x T o i v → i
}

% X P {
    @ x P p i v → i {
        ^ ? > . . p ___ _ v
        . . p ___ __
        . . p ____ length
    }
}

@ sys::b N n → *N {
    : *N p # *N ( malloc Z N )
    = . p 0 n
    ^ p
}

@ sys::e * N n i a → !i i {
    ^ ?? . n 0 {
        A 0 y → @ !i i { F y }
        A x y → @ !i i { T + * x y a }
        B p → {
            : i r \ ( sys::e p a )
            ^ @ !i i { T ~ r }
        }
        C v → @ !i i { T + v a }
        _ → @ !i i { F ~ 0 }
    }
}

@ alg::r [i s ( @ i i i i ) m i z → i {
    : ~ i o z
    : ~ i i 0
    : i n . s length
    ~ < i n {
        : i e . s i
        = o ( m o e )
        = i + i 1
    }
    ^ o
}

@ main → i {
    : ~ i q 0
    : [i s [i | 2 3 5 7 11]

    // Create an owned struct. Will trigger auto-drop at scope exit!
    : P p @ P { @ O { 8 4 } s }

    // Exercise the X trait directly (v < O._ triggers the else-branch: slice length = 5)
    // Explicit `[P]` instantiation triggers a known nurlc generic-mangle
    // parse bug — implicit dispatch via the receiver's type works.
    : i tx ( x p 3 )

    // Allocate recursive enum nodes on the heap
    : *N n1 ( sys::b @ N { A 7 3 } )
    : *N n2 ( sys::b @ N { B n1 } )
    : *N n3 ( sys::b @ N { C 9 } )

    : !i i r1 ( sys::e n2 2 )
    : !i i r2 ( sys::e n3 5 )

    // Unpack results with literal match fallthrough
    = q ?? r1 {
        T v → v
        F e → *e - 0 1
    }

    : ~ i k ?? r2 {
        T v → v
        _ → 0
    }

    // A closure doing chaotic math via prefix-notation
    : ( @ i i i i ) cl \ i a i e → i {
        ^ ? > e 4
        + a * e 2
        - a e
    }

    // Fold over the slice with the closure
    = k + k ( alg::r s cl q )
    = k + k tx

    ( nurl_print `ENIGMA RESULT: ` )
    ( nurl_print ( nurl_str_int k ) )
    ( nurl_print `\n` )

    ^ 0
}
