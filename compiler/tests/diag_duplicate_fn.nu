// diag_duplicate_fn.nu — two files, one function name, one program.
//
// A NURL compilation unit is one flat namespace: a `__`-prefixed helper is
// private by convention, not by scoping. Before the duplicate check this
// program survived the front end and died inside LLVM as
//
//   error: invalid redefinition of function '__shared_helper'
//
// — an error with no NURL source location, pointing into a generated .ll
// file tens of thousands of lines long. It is a real failure shape: two
// packages each grew a private `__get`-style helper, and the collision
// appeared only in whichever consumer imported both (packages/audio's
// `__vget` against stdlib/std/x25519.nu's, found by whisper serve).
//
// The check lives in the signature scan, where both locations are still
// known — and the SAME location seen twice stays legal, because a file
// imported by several importers is scanned once per importer.
$ `compiler/tests/diag_duplicate_fn_mod.nu`

@ __shared_helper i x → i {
    ^ + x 2
}

@ main → i {
    ^ ( __shared_helper 1 )
}
