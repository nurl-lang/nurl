// inner_drop_field_through_a_cond_assigned_outward: agora #179 — an inner block's `% Drop` field handed through a `?` to a binding of an outer block: it cannot be copied (inner_drop_field_through_a_cond_assigned_outward).
// Closed: a `?` / `??` assigned to a binding of an outer block measures its arms against that binding's scope: a binding of an inner block moves out, a view or a field of one is copied (g_join_rdepth, mem_arm_copy_out; agora #179).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h745 | agora #179: an inner block's `% Drop` field handed through a `?` to a binding of an outer block: it cannot be copied
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d i n }

@ main → i {
    : ~ D t @ D { ( mk ) }
    ? > ( string_len . t s ) 0 {
        : H h @ H { @ D { ( mk ) } 1 }
        = t ? T . h d @ D { ( mk ) }
    } {}
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
