// diag_join_assigned_outward_not_copyable.nu — a `?` assigned to a binding
// of an outer block hands it, on one path, a field of a value declared in
// the inner block (agora #179). That value dies first, so the field is
// copied. A `% Drop` value cannot be copied, so the assignment is refused.

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
