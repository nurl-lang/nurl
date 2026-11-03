// string_global_given_literals_directly_runs_clean: the form packages/image's error slot takes now — each failure assigns its literal straight to the `s` global (`= __img_err `not a PPM``), as MEMORY.md §1 asks of safe code, instead of handing a setter a view parameter (view_param_kept_in_a_string_global).
// main 4f15689: accepted; ran clean.
// map: §1 | A2 | runs-clean | - | an s global given literals directly in safe code
$ `stdlib/core/string.nu`

: ~ s g_err ``

@ parse s text → b {
    ? == 0 ( nurl_str_len text ) { = g_err `empty input` ^ F } {}
    ? != 80 ( nurl_str_get text 0 ) { = g_err `not a PPM` ^ F } {}
    ^ T
}

@ main → i {
    : String bad ( string_from `X5 a heap string, long enough` )
    ? ( parse ( string_data bad ) ) {} { ( nurl_print g_err ) ( nurl_print `\n` ) }
    ? ( parse `` ) {} { ( nurl_print g_err ) ( nurl_print `\n` ) }
    ^ 0
}
