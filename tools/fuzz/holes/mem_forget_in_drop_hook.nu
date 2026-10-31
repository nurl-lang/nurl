// mem_forget_in_drop_hook: a library-handle drop hook (`<Type>_drop`) in safe code may call mem_forget, and leaks.
// Closed: the ownership primitives (mem_forget, mem_take, mem_put_back) are `unsafe`-only (bck_check_raw_call).
// Note_drop forgets its receiver and releases nothing — the old handle convention, which used mem_forget
// so the hook would not drop its own receiver — so the String field leaks on every drop. mem_forget is
// `unsafe`-only (§3.3d), but no check rejects it in 0.72.0 (mem_forget_owned_vec); this is one context
// a fix must cover.
// LSan: detected memory leaks — the String `text` (24-byte control block from string_from, and its buffer).
// map: §3 | B | rejected | h151 | mem_forget in safe library drop hook leaks fields
$ `stdlib/core/string.nu`

: Note { String text }

@ Note_drop sink Note h → v { ( mem_forget h ) }

@ main → i {
    : Note n @ Note { ( string_from `x` ) }
    ( nurl_println `ran` )
    ^ 0
}
