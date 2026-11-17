// vec_owner_given_a_calls_lend_of_another_read_after_that_one_is_replaced: `= o ( id other )` of two `( Vec i )` owners, then `= other …` and an element of o read
// Closed in the ownership engine: eng_handover hands a replaced owner's old value only to a reader codegen links - not to one `=` gave a call's lend (__eng_call_lent_reader; agora #881). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-881: `= o ( id other )` of two `( Vec i )` owners, then `= other …` and an element of o read
$ `stdlib/core/string.nu`

@ id ( Vec i ) a → ( Vec i ) { ^ a }

@ main → i {
    : ~ ( Vec i ) other ( vec_new [i] )
    ( vec_push [i] other 1 ) ( vec_push [i] other 2 )
    : ~ ( Vec i ) o ( vec_new [i] )
    ( vec_push [i] o 7 )
    = o ( id other )
    = other ( vec_new [i] )
    ( vec_push [i] other 3 )
    ( nurl_println_int ( vec_at [i] o 1 ) )
    ^ 0
}
