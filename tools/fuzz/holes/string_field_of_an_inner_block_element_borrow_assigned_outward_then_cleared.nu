// string_field_of_an_inner_block_element_borrow_assigned_outward_then_cleared: the same with a String field, `= w . x name`.
// Closed: a field read out of a struct of an inner scope "moves out" with that struct's drop flag (mem_udrop_field_move); where the struct is itself a borrow (`vec_at`) the binding owns nothing on that path, and its borrow row (mode `t`, bck_note_moved_field) now begins from the field there, flattened to what the struct borrows (agora #533). It was marked as owning, so the block's end retired its only tie.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #533: a String field of an inner block's element borrow assigned outward, its container cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: E { ( Vec E ) kids String name }

@ mk String s → E { ^ @ E { ( vec_new [E] ) s } }

@ main → i {
    : ( Vec E ) top ( vec_new [E] )
    ( vec_push [E] top ( mk ( string_from `a parent name long enough for the heap` ) ) )
    : ~ String w ( string_from `w` )
    {
        : E x ( vec_at [E] top 0 )
        = w . x name
    }
    ( vec_clear [E] top )
    ( nurl_println_int # i ( string_len w ) )
    ^ 0
}
