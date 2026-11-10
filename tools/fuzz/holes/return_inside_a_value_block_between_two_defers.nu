// return_inside_a_value_block_between_two_defers: a defer, `: String e { : String t … ? c { ^ 1 } {} t }`, a second defer that reads `e`.
// Closed: the `^` inside the block releases the block's `t` itself, and `e` was never bound on that path; both were kept back by the second defer, compiled later, and fn_cleanup released them all the same. It now releases each only under its "left to the cleanup" flag (mem_dkeep_mark, agora #630).
// main d96ebfa: accepted; AddressSanitizer: heap-use-after-free in the epilogue.
// map: §7.1 | A2 | runs-clean | - | agora #630: a `^` inside a value block with `;` defers armed before and after the statement
$ `stdlib/core/string.nu`

@ pr String x → v { ( nurl_println ( string_data x ) ) }

@ f i c → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    ; { ( pr s ) }
    : String e { : String t ( string_from `inner string long enough for a heap buffer` ) ? == c 1 { ^ 1 } {} t }
    ; { ( pr e ) }
    ^ 0
}

@ main → i {
    ( nurl_println_int ( f 1 ) )
    ( nurl_println_int ( f 0 ) )
    ^ 0
}
