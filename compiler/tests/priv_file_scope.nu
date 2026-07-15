// priv_file_scope.nu — `__`-prefixed functions are FILE-SCOPED.
//
// Both this file and the imported mod define `@ __pick`. Under the flat
// namespace that was an instant duplicate; now each file's definition is
// mangled with its file id and each file's CALLS bind to its own:
//
//   * mod_pick (defined in the mod) returns the MOD's __pick → 1
//   * our own call returns OURS → 2
//
// Nobody can shadow anybody's private, and the LLVM-redefinition collision
// class (__vget vs __vget, found the hard way) is structurally gone.
//
// Expected output:
//   1
//   2
$ `compiler/tests/priv_file_scope_mod.nu`
$ `stdlib/core/string.nu`

@ __pick → i {
    ^ 2
}

@ p i v → v {
    : String m ( string_new )
    ( string_push_int m v )
    ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
    ( string_free m )
}

@ main → i {
    ( p ( mod_pick ) )
    ( p ( __pick ) )
    ^ 0
}
