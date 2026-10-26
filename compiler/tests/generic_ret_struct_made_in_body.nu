// A generic function's return type that applies generic structs no
// top-level code names: the instance is first needed in a body, where the
// call's result is read (`. ( mk_opt [i] 5 ) k`). It is made there at
// module scope, so the layout is in place for that body, for the bodies
// after it and for the generic's own instance. Made in the body's scope,
// its fields went with the scope while its `__done` mark stayed ("has no
// field 'k'"), and the outer instance had no layout at all (Agora #73).
//
// A type argument made of a type parameter — `?A`, `( Pair A i )`,
// `?( Slot A )`, a closure over A — is abstract, as A is: the template's
// own signature no longer instantiates `%Wrap__opt_A = type { { i1, %A },
// i64 }`, a type naming one nothing defines (invalid IR, status 0).

: Slot [A] {
    A val
    i n
}

: Pair [A B] {
    A a
    B b
}

: Wrap [A] {
    A inner
    i k
}

@ mk_opt [A] A x → ( Wrap ? ( Slot A ) ) {
    ^ @ ( Wrap ? ( Slot A ) ) { @ ?( Slot A ) { T @ ( Slot A ) { x 1 } } 3 }
}

@ mk_pair [A] A x → ( Wrap ( Pair A i ) ) {
    ^ @ ( Wrap ( Pair A i ) ) { @ ( Pair A i ) { x 2 } 4 }
}

@ mk_bare_opt [A] A x → ( Wrap ? A ) {
    ^ @ ( Wrap ? A ) { @ ?A { T x } 5 }
}

@ mk_clo [A] A x → ( Wrap ( @ A i ) ) {
    ^ @ ( Wrap ( @ A i ) ) { \ i y → A { ^ x } 6 }
}

// A generic body reading the result of another generic's call.
@ slot_val [A] A x → i {
    ?? . ( mk_opt [A] x ) inner {
        T s → { ^ . s n }
        F → { ^ -1 }
    }
}

// First made inside a nested block, then read after it, in this body…
@ first → i {
    : ~ i r 0
    ? T { = r . ( mk_opt [i] 5 ) k } {}
    = r + r . ( mk_opt [i] 6 ) k
    ^ r
}

// …and in a body compiled later.
@ second → i {
    : i p . . ( mk_pair [i] 7 ) inner a
    : i q . ( mk_bare_opt [i] 8 ) k
    : i c . ( mk_clo [i] 9 ) k
    : ( @ i i ) f . ( mk_clo [i] 9 ) inner
    ^ + + + p q c ( f 0 )
}

@ main → i {
    ( nurl_println ( nurl_str_int ( first ) ) )
    ( nurl_println ( nurl_str_int ( second ) ) )
    ( nurl_println ( nurl_str_int ( slot_val [i] 10 ) ) )
    ^ 0
}
