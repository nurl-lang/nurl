// sink_param_into_literal.nu — a `sink` parameter placed in a literal moves
// in, as a local does; it is not copied.
//
// `@ pair_of sink ( Vec i ) a sink ( Vec i ) b → Pair { ^ @ Pair { # s (
// rcbox_new [PairImpl] @ PairImpl { a b } ) } }`: a parameter in a literal
// the function keeps to itself was copied, because a caller still owns a
// borrowed parameter — but a `sink` one is the function's own. Every
// library-handle constructor copied each Vec it was handed and then dropped
// the original. Where the literal goes to a call that only reads it, the
// parameter keeps its value and drops it as before.

$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ allocs → i { ^ ( nurl_alloc_count ) }

@ report s what i d → v { ( nurl_print what ) ( nurl_print_int d ) ( nurl_print `\n` ) }

: PairImpl { ( Vec i ) v0 ( Vec i ) v1 }
: Pair { s ctl }

@ Pair_share Pair h → Pair { ^ @ Pair { # s ( rcbox_share # i . h ctl ) } }

@ Pair_drop sink Pair h → v { ( mem_forget h ) ( rcbox_release [PairImpl] # i . h ctl ) }

@ mk i n → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v k ) = k + k 1 }
    ^ v
}

@ pair_of sink ( Vec i ) a sink ( Vec i ) b → Pair { ^ @ Pair { # s ( rcbox_new [PairImpl] @ PairImpl { a b } ) } }

@ pair_len Pair p → i {
    : *PairImpl q ( rcbox_ptr [PairImpl] # i . p ctl )
    ^ + ( vec_len [i] . q v0 ) ( vec_len [i] . q v1 )
}

@ keep sink PairImpl x → i { ^ + ( vec_len [i] . x v0 ) ( vec_len [i] . x v1 ) }

@ peek PairImpl x → i { ^ ( vec_len [i] . x v0 ) }

// bound, then handed on
@ bound sink ( Vec i ) a sink ( Vec i ) b → i {
    : PairImpl t @ PairImpl { a b }
    ^ ( keep t )
}

// to a call that only reads it: the parameters still own their values
@ read_only sink ( Vec i ) a sink ( Vec i ) b → i { ^ ( peek @ PairImpl { a b } ) }

// in one branch only
@ branchy b c sink ( Vec i ) a sink ( Vec i ) b → i {
    ? c { ^ ( keep @ PairImpl { a b } ) } {}
    ^ + ( vec_len [i] a ) ( vec_len [i] b )
}

@ main → i {
    : ~ i k 0
    : ~ i acc 0
    : ~ i l0 ( live )
    : ~ i a0 ( allocs )
    = k 0 ~ < k 20 { : Pair p ( pair_of ( mk 100 ) ( mk 1 ) ) = acc + acc ( pair_len p ) = k + k 1 }
    ( report `constructor, live: ` - ( live ) l0 )
    // 20 × (two Vecs from mk + the box): no copies of the Vecs
    ( report `constructor, allocations per round: ` / - ( allocs ) a0 20 )
    = l0 ( live )
    = k 0 ~ < k 20 { = acc + acc ( bound ( mk 3 ) ( mk 4 ) ) = k + k 1 }
    ( report `bound, live: ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { = acc + acc ( read_only ( mk 3 ) ( mk 4 ) ) = k + k 1 }
    ( report `read-only call, live: ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { = acc + acc ( branchy == % k 2 0 ( mk 3 ) ( mk 4 ) ) = k + k 1 }
    ( report `one branch, live: ` - ( live ) l0 )
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ^ 0
}
