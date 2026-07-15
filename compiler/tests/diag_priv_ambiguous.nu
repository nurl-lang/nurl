// diag_priv_ambiguous.nu — a cross-file reference to a private defined in
// SEVERAL files has no right answer, and guessing one silently would be the
// flat namespace's bug wearing a new hat. The error names every owner.
$ `compiler/tests/diag_priv_ambiguous_mod.nu`
$ `compiler/tests/diag_priv_ambiguous_second_mod.nu`

@ main → i {
    ^ ( __amb )
}
