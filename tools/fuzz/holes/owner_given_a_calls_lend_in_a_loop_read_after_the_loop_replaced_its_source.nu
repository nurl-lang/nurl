// owner_given_a_calls_lend_in_a_loop_read_after_the_loop_replaced_its_source: `= o ( id other )  = other …` in each round of a loop, o read after it
// Closed in the ownership engine: eng_handover hands a replaced owner's old value only to a reader codegen links - not to one `=` gave a call's lend (__eng_call_lent_reader; agora #881). The walk refused it already.
// main 22183195 (--no-borrowck): AddressSanitizer: heap-use-after-free; `nurlc --engine`: runs-clean.
// map: §7.6 | A2 | rejected | - | AGORA-881: `= o ( id other )  = other …` in each round of a loop, o read after it
$ `stdlib/core/string.nu`

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ main → i {
    : ~ String other ( string_from `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` )
    : ~ String o ( string_from `bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` )
    : i k ( nurl_str_len `x` )
    : ~ i n 0
    ~ < n 2 {
        = o ( id other )
        = other ( string_from `cccccccccccccccccccccccccccccc` )
        = n + n 1
    }
    ( nurl_println ( string_data o ) )
    ^ 0
}
