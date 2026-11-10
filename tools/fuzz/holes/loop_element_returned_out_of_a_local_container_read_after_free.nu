// loop_element_returned_out_of_a_local_container_read_after_free: agora #545 — `~ x ss { ? … { ^ x } {} }`, ss a local slice the function drops on the way out: the element went back as lent while the frame dropped the container it was read out of, so the caller read freed memory (or, copied by the caller and dropped by the frame, was freed twice).
// Closed: a loop element returned out of a container the frame drops is the caller's own value: taken out of its slot, or copied where it cannot be taken (a struct element, under a `;` defer); out of a parameter it is still a lend the caller copies.
// main (before this PR): AddressSanitizer, heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #545: a loop element returned out of a local slice went back lent while the frame dropped the slice (UAF, double free)
$ `stdlib/core/string.nu`

: Rec { String name i n }

@ pick_slice i n → [i {
    : [[i nest [[i | [i | 1] [i | 2 3] [i | 4 5 6]]
    : ~ i k 0
    ~ r nest { ? == k n { ^ r } {} = k + k 1 }
    ^ [i | 0]
}

@ pick_str i n → String {
    : [String ss [String | ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two` )]
    : ~ i k 0
    ~ x ss { ? == k n { ^ x } {} = k + k 1 }
    ^ ( string_from `none of them, in a string long enough for the heap` )
}

@ pick_rec i n → Rec {
    : [Rec rs [Rec | @ Rec { ( string_from `a long enough string to be on the heap, rec one` ) 1 } @ Rec { ( string_from `a long enough string to be on the heap, rec two` ) 2 }]
    ~ r rs { ? == . r n n { ^ r } {} }
    ^ @ Rec { ( string_from `no such record, in a string long enough for the heap` ) 0 }
}

@ main → i {
    : [i a ( pick_slice 1 )
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    : [i a9 ( pick_slice 9 )
    ~ x a9 { ( nurl_println ( nurl_str_int x ) ) }
    : String t ( pick_str 1 )
    ( nurl_println ( string_data t ) )
    : String t9 ( pick_str 9 )
    ( nurl_println ( string_data t9 ) )
    : Rec u ( pick_rec 2 )
    ( nurl_println ( string_data . u name ) )
    ^ 0
}
