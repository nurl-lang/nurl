// OPEN in 0.72.0 — a view of a local stored into a raw string field of an `inout` struct: the caller reads freed memory.
// `setl` builds a fresh string `x`, stores it into `. r name` of its `inout Rec r`, and releases `x` when
// it returns; main then prints `. r name`. The same store into a local struct runs clean; through an
// `inout` parameter the field keeps only a view of the released string.
// ASan: heap-use-after-free in fputs <- nurl_println (main), reading `. r name`.
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ setl inout Rec r → v { : s x ( nurl_str_cat `ef` `gh` ) = . r name x }

@ main → i {
    : ~ Rec r @ Rec { `init` 1 }
    ( setl r )
    ( nurl_println . r name )
    ( nurl_println `P48B-MARK` )
    ^ 0
}
