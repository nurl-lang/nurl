// lent_element_bound_then_handed_back_runs_clean: agora #462 — `: Conn c ( vec_at [Conn] cs 0 ) ^ c`, Conn a `% Drop` type: the binding's flag is the per-call answer, so the caller holds the result as a lend (claude-holes j12)
// main 0b124982: double drop (heap-use-after-free): the function answered "owned" statically and both the caller's binding and cs dropped the element.
// map: §2.10 | A2 | runs-clean | - | agora #462: `: Conn c ( vec_at [Conn] cs 0 ) ^ c`, Conn a `% Drop` type: the binding's flag is the per-call answer, so the caller holds the result as a lend (claude-holes j12)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ g ( Vec Conn ) cs → Conn { : Conn c ( vec_at [Conn] cs 0 ) ^ c }

@ main → i {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `the first connection, a heap name` ) 3 } )
    : Conn a ( g cs )
    ( nurl_println ( string_data . a name ) )
    ^ 0
}
