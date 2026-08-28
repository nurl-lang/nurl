// The same file imported through two different-but-equivalent paths (here
// via a `..` segment; packages hit this through symlinked deps/ chains —
// a DIAMOND dependency) must compile exactly once. Before the canonical
// (realpath) dedup key this produced "invalid redefinition" at the LLVM
// stage because every function in the file was emitted twice.
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/../core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 42 )
    ( nurl_println_int ?? ( vec_get [i] v 0 ) { T x → x F _ → 0 } )
    ^ 0
}
