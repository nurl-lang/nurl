// view_param_kept_in_a_string_global: a setter gives an `s` global its view parameter; the caller's String is freed and the global read.
// Closed: a view parameter stands for itself as a source in its function's walk (`pv_`, bck_sx_name), so the rules for a view of a local apply to it: a string global may not be given one (bck_global_view_check), and what runs on another thread may not hold one (Family 2, agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §1 | A2 | rejected | - | a view parameter kept in a string global, read after the caller's String is freed
$ `stdlib/core/string.nu`

: ~ s g_err ``

@ set_err s msg → v { = g_err msg }

@ fail → v {
    : String m ( string_from `a message built on the heap, long enough` )
    ( set_err ( string_data m ) )
}

@ main → i {
    ( fail )
    ( nurl_print g_err ) ( nurl_print `\n` )
    ^ 0
}
