// unsafe_prefix_skipped_fn.nu — an `unsafe @` function that lazy
// compilation skips (nothing calls it) must not lend its prefix to the
// next declaration. The flag that marks `unsafe & …` foreign functions
// raw was cleared only when the function was compiled, so the foreign
// function after an unreached `unsafe @` became raw, and a safe caller
// of it was rejected: stdlib/std/fs.nu declares `unlink` right after
// `unsafe @ __fd_write_all`, and ply's viewer, calling `unlink` and not
// `fd_write_all`, stopped compiling.
$ `stdlib/core/io.nu`
$ `stdlib/std/fs.nu`

@ main → i {
    ( nurl_println_int # i ( unlink `/nonexistent-dir-for-this-test/x` ) )
    ^ 0
}
