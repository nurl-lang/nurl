// diag_duplicate_fn.nu — two files, one SHARED function name, one program.
//
// `__`-prefixed functions are file-scoped now (see priv_file_scope.nu), so
// two files' private helpers coexist by design. A SHARED name — anything not
// `__`-prefixed — still lives in the one flat namespace, and a second
// definition used to survive the front end and die inside LLVM as
//
//   error: invalid redefinition of function 'shared_helper'
//
// — an error with no NURL source location, pointing into a generated .ll
// tens of thousands of lines long. The check lives in the signature scan,
// where both locations are still known; the SAME location seen twice stays
// legal (a file imported by several importers is scanned once per importer).
$ `compiler/tests/diag_duplicate_fn_mod.nu`

@ shared_helper i x → i {
    ^ + x 2
}

@ main → i {
    ^ ( shared_helper 1 )
}
