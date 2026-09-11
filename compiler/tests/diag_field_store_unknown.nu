// diag_field_store_unknown.nu — writing a field the struct does not
// have. gen_member rejects this on the READ side and says why: an empty
// index lookup becomes `nurl_str_to_int ""` = 0, so the access silently
// uses field 0. The WRITE side kept the bug — `= . p nofield 5` stored
// into field 'x', a struct-corrupting miscompile, and the empty field
// type printed `store  5, * %r` with no types at all: emitted with
// status 0, rejected only by clang, against generated IR.

: Pt { i x i y }

@ main → i {
    : ~ Pt p @ Pt { 1 2 }
    = . p nofield 5
    ^ 0
}
