// owner_given_a_forwarders_lend_of_another_owner_read_after_that_one_is_replaced: `= o ( fwd other )`, fwd handing back `( id a )`, then `= other …` and o read
// Closed in the ownership engine: eng_handover hands a replaced owner's old value only to a reader codegen links - not to one `=` gave a call's lend (__eng_call_lent_reader; agora #881). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-881: `= o ( fwd other )`, fwd handing back `( id a )`, then `= other …` and o read
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ fwd String a → String { ^ ( id a ) }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    = o ( fwd other )
    = other ( string_from `cccccccccccccccccccccccccccccc` )
    ( nurl_println ( string_data o ) )
    ^ 0
}
