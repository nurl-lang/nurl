// should_warn_priv_cross_file.nu — calling ANOTHER file's `__` function
// still works when the definition is unique, but it is deprecated and says
// so: the flat-namespace era wrote a lot of cross-file private calls (a
// package's sibling files cannot import each other, so the consumer glues
// them into one unit), and breaking them all at once would break every
// published package. The warning is the migration path — ONE underscore is
// the shared-internal convention; two is compiler-enforced file-private.
$ `compiler/tests/should_warn_priv_cross_file_mod.nu`

@ main → i {
    ^ - ( __only_here 3 ) 30
}
