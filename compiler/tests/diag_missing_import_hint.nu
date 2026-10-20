// diag_missing_import_hint.nu — a type the program never imported: the
// diagnostic names the stdlib module that defines it and the exact line
// to add, `$ `stdlib/core/vec.nu``, instead of asking whether an import
// is missing. The module is found on the way to the error only, so a
// program that compiles never pays for the scan.

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ^ 0
}
