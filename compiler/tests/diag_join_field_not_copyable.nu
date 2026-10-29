// diag_join_field_not_copyable.nu — a `?` that hands back, on one of its
// paths, a field of a value this function releases on the way out (agora
// #178). The field is copied when it can be. A `% Drop` value cannot be
// copied, so the return is refused: under the caller, the field would be
// released with its owner.

$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part i n b c → D {
    : H h @ H { @ D { ( mk ) } n }
    ^ ? c . h d @ D { ( mk ) }
}

@ main → i {
    : D t ( part 1 T )
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
