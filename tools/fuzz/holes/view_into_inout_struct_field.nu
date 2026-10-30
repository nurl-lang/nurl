// view_into_inout_struct_field: a view of a local stored into a raw string field of an `inout` struct: the caller reads freed memory.
// Closed: storage the caller holds (a parameter, an alias of one, an `inout` struct) may not keep a view of a binding released here (bck_param_view_check, bck_caller_view_diag); a field store records the view (gen_field_rhs).
// `setl` builds a fresh string `x`, stores it into `. r name` of its `inout Rec r`, and releases `x` when
// it returns; main then prints `. r name`. The same store into a local struct runs clean; through an
// `inout` parameter the field keeps only a view of the released string.
// ASan: heap-use-after-free in fputs <- nurl_println (main), reading `. r name`.
// map: §2.13 | A2 | rejected | h172 | view of local stored into s field of inout struct; caller reads
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
