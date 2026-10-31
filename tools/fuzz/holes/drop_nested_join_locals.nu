// drop_nested_join_locals: agora #186 — `^ ? c ? d l1 l2 @ D { … }`: two locals through a nested join (drop_nested_join_locals).
// Closed: `^` of a `?` / `??` hands the join to the caller at receiver depth 0 (g_join_rdepth): a local an arm selects moves out on its path, and what stays lent is the caller's, answered per call (agora #186).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h802 | agora #186: `^ ? c ? d l1 l2 @ D { … }`: two locals through a nested join
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ pick b c b d → D {
    : D l1 @ D { ( string_from `first local string long enough for a heap buffer` ) }
    : D l2 @ D { ( string_from `second local string long enough for a heap buffer` ) }
    ^ ? c ? d l1 l2 @ D { ( string_from `fresh string long enough for a heap buffer` ) }
}

@ main → i {
    : D a ( pick T T )
    : D b ( pick T F )
    : D e ( pick F T )
    ( nurl_println_int + + ( string_len . a s ) ( string_len . b s ) ( string_len . e s ) )
    ^ 0
}
