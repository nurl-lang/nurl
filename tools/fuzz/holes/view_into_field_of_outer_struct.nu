// view_into_field_of_outer_struct: a view of a loop-body string stored into a field of a struct declared outside the loop: the string was released at the end of each iteration, and the read of the field after the loop read freed memory (a field store did not record what the stored view points into).
// Closed: a value that may hold views stored into a field makes the field's binding depend on what they point into (gen_field_rhs, a `vpass` row kept in the binding), so reading the struct after the string ended is an error.
// ASan: heap-use-after-free in fputs <- nurl_println (main), reading `. r name`.
// map: §2.13 | A2 | rejected | h179 | loop-body raw string view stored into outer struct field, read after string freed
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ main → i {
    : ~ Rec r @ Rec { `init` 1 }
    : ~ i k 0
    ~ < k 2 { : s x ( nurl_str_cat `ef` `gh` ) = . r name x = k + k 1 }
    ( nurl_println . r name )
    ^ 0
}
