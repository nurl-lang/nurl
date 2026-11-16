// option_owner_given_a_calls_lend_of_another_read_after_that_one_is_replaced: `= o ( id other )` of two `?String` owners, then `= other …` and o's payload read
// Closed in the ownership engine: eng_handover hands a replaced owner's old value only to a reader codegen links - not to one `=` gave a call's lend (__eng_call_lent_reader; agora #881). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-881: `= o ( id other )` of two `?String` owners, then `= other …` and o's payload read
$ `stdlib/core/string.nu`

@ id ? String a → ?String { ^ a }

@ mk s s → ?String { ^ @ ?String { T ( string_from s ) } }

@ main → i {
    : ~ ? String other ( mk `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ ? String o ( mk `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o ( id other )
    = other ( mk `cccccccccccccccccccccccccccccc` )
    ?? o { T q → { ( nurl_println ( string_data q ) ) } F → {} }
    ^ 0
}
