// diag_elem_index_not_int.nu — an element index that is not an integer.
//
// The READ side has always said so: `. xs 1.5` is "expected a field name
// or an index after '.'". The five index-STORE paths never asked, so
// `= . xs 1.5 7` emitted `getelementptr i64, i64* %p, double 1.5` and
// clang answered "getelementptr index must be an integer" — about
// generated IR, with no NURL location.
//
// The spelling that reaches it is a MISSING index, not a wrong one: this
// file is diag_elem_store_clash.nu with the `0` of `= . xs 0 1.5`
// deleted, which leaves the value standing where the position belongs.
// That is what the diagnostic says, because that is what it almost
// always is.

@ main → i {
    : [i xs [i | 1 2 3]
    = . xs 1.5
    ^ 0
}
