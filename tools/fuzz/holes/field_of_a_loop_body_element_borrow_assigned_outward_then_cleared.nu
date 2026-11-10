// field_of_a_loop_body_element_borrow_assigned_outward_then_cleared: the same as field_of_an_inner_block_element_borrow_assigned_outward_then_cleared in a `~ < k 1` loop body.
// Closed: a field read out of a struct of an inner scope "moves out" with that struct's drop flag (mem_udrop_field_move); where the struct is itself a borrow (`vec_at`) the binding owns nothing on that path, and its borrow row (mode `t`, bck_note_moved_field) now begins from the field there, flattened to what the struct borrows (agora #533). It was marked as owning, so the block's end retired its only tie.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #533: a field of a loop body's element borrow assigned outward, its container cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: E { ( Vec E ) kids String name }

@ mk String s → E { ^ @ E { ( vec_new [E] ) s } }

@ main → i {
    : ( Vec E ) top ( vec_new [E] )
    : ~ E p ( mk ( string_from `parent` ) )
    ( vec_push [E] . p kids ( mk ( string_from `a child name long enough for the heap` ) ) )
    ( vec_push [E] top p )
    : ~ ( Vec E ) w ( vec_new [E] )
    : ~ i k 0
    ~ < k 1 {
        : E x ( vec_at [E] top 0 )
        = w . x kids
        = k + k 1
    }
    ( vec_clear [E] top )
    ( nurl_println_int ( vec_len [E] w ) )
    ^ 0
}
