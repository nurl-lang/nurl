// diag_missing_import_hint_fn.nu — a stdlib function called without its
// module: the cure is the exact `$` line, ahead of any near-miss spelling
// (which would point at the wrong function).

@ main → i {
    : i n ( bytes_find_byte 0 0 )
    ^ n
}
