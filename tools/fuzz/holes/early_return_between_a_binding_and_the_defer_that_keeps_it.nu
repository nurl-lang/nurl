// early_return_between_a_binding_and_the_defer_that_keeps_it: `: String g …`, an early `^`, then a defer that reads `g`.
// Closed: the early return, compiled before the defer kept anything back, releases `g` itself and leaves its "left to the cleanup" flag clear, so fn_cleanup — which that exit runs too — does not release it again (mem_dkeep_mark, agora #630).
// main d96ebfa: accepted; AddressSanitizer: heap-use-after-free (the String freed at the `^` and again in fn_cleanup).
// map: §7.1 | A2 | runs-clean | - | agora #630: an early return between a binding and the `;` defer that keeps it — released at the return and again by the cleanup
$ `stdlib/core/string.nu`

@ f i n → i {
    : String e ( string_from `e: a string long enough for a heap buffer, yes` )
    ; { ( nurl_println `first defer` ) }
    : String g ( string_concat e e )
    ? > n 1 { ^ ( string_len g ) } {}
    ; { ( nurl_println_int ( string_len g ) ) }
    ^ + n ( string_len e )
}

@ main → i {
    ( nurl_println_int ( f 1 ) )
    ( nurl_println_int ( f 2 ) )
    ^ 0
}
