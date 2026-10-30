// ret_struct_owned_branch.nu — a struct with fresh-owned fields handed back
// from inside a block (agora #214). The owned-field list the caller
// re-registers was written into the block's scope and popped with it, so
// the caller registered nothing and the field leaked (LeakSanitizer, in the
// sanitizer corpus). See ret_struct_owned_transfer for the other shapes.
// The raw-string field owns a fresh string only in `unsafe` code, as there.

$ `stdlib/core/string.nu`

: Inner { s name i n }

unsafe @ mk_direct → Inner {
    ^ @ Inner { ( nurl_str_cat `direct-` `owned` ) 1 }
}

@ mk_branch b c → Inner {
    ? c { ^ ( mk_direct ) } { ^ ( mk_direct ) }
}

@ main → i {
    : Inner a ( mk_branch T )
    ( nurl_print . a name ) ( nurl_print `\n` )
    ^ 0
}
