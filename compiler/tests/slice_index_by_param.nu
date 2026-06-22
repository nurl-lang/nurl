// slice_index_by_param.nu — slice element access `. slice k` where the index
// `k` is a bare function PARAMETER.
//
// Regression for the empty-pointer `load i64, i64*` codegen bug: the slice
// variable-index path used to load the index from a `<name>__ptr` alloca that
// a parameter never has, leaving the load's pointer operand blank — invalid IR
// nurlc accepted (rc 0) and only clang rejected. gen_member now resolves the
// index exactly like gen_ident (param → %name, local → load __ptr, const →
// load @name).
@ at [i xs i k → i { ^ . xs k }

@ main → i {
    : [i xs [i | 10 20 30]
    ( nurl_print ( nurl_str_int ( at xs 0 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( at xs 2 ) ) ) ( nurl_print `\n` )
    ^ 0
}
