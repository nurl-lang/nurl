// raw_param_in_local_literal.nu — a raw string parameter placed in a literal
// the function keeps to itself does not make the function its keeper.
//
// `@ f_struct s p → i { : P q @ P { p … } ^ . q n }` was summarised as
// keeping `p`, so a temporary argument (`( f_struct ( nurl_argv_get 0 ) )`,
// examples/find_clone's `( regex_compile ( nurl_argv_get 2 ) )`) was never
// freed. The parameter is kept only once the literal's binding leaves whole
// — stored (`( vec_push all q )`), returned, handed on — and then the
// temporary still stays alive, as before.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: P { s text i n }

@ f_struct s p → i {
    : P q @ P { p ( nurl_str_len p ) }
    ^ . q n
}

@ keep_it s p ( Vec P ) all → v {
    : P q @ P { p 1 }
    ( vec_push [P] all q )
}

unsafe @ main → i {
    : ( Vec P ) all ( vec_new [P] )
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 { = acc + acc ( f_struct ( nurl_str_cat `ab` `cd` ) ) = k + k 1 }
    ( nurl_print `view only, live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ( keep_it ( nurl_str_cat `xy` `zw` ) all )
    // The kept string is the Vec's now: a raw `s` field has no drop, so it is
    // released by hand (were it freed at the call, this would read freed memory).
    ?? ( vec_get [P] all 0 ) { T x → { ( nurl_print . x text ) ( nurl_print `\n` ) ( nurl_free . x text ) } F → {} }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ^ 0
}
