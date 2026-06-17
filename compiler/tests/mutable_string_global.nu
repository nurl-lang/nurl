// mutable_string_global.nu — regression for mutable STRING globals.
//
// Bug: `: ~ s g …` declared a mutable string global, but gen_const_decl's
// TT_STR branch never recorded the `<name>__mutable` flag (the i / u / f / b
// branches all did). So a later `= g …` was wrongly rejected with
// "cannot assign to immutable global", even though the grammar explicitly
// lists `s` as an updatable mutable-global type and the storage is emitted as
// a writable `global i8*`. `: ~ i/u/f/b` globals were unaffected.
//
// Fix: the TT_STR branch now sets `<name>__mutable` when `is_mutable`, exactly
// like the other scalar branches. Verified: reassignment to another constant
// string and to a heap-allocated (`nurl_str_cat`) string both work.

$ `stdlib/core/string.nu`

: ~ s g_msg `start`

@ main → i {
    ( nurl_print g_msg ) ( nurl_print `\n` )

    = g_msg `middle`
    ( nurl_print g_msg ) ( nurl_print `\n` )

    // Reassign to a heap-allocated string. The global keeps it reachable for
    // the rest of the run (globals are not auto-dropped), so it stays
    // LeakSanitizer-clean (still reachable, not lost).
    = g_msg ( nurl_str_cat g_msg `-end` )
    ( nurl_print g_msg ) ( nurl_print `\n` )
    ^ 0
}
