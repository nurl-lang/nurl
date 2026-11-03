// string_global_given_its_own_copy_in_an_unsafe_setter_runs_clean: the form the packages' configuration setters take now (registry, pki-server, anomaly, nurlbox) — an `unsafe` setter, set once before serving, gives the `s` global a copy of its own (`( nurl_str_cat root `` )`), released by the next assignment, so the caller's String may go first (view_param_kept_in_a_string_global).
// main 4f15689: accepted; ran clean.
// map: §1 | A2 | runs-clean | - | an unsafe setter giving an s global its own copy; the caller's String freed first
$ `stdlib/core/string.nu`

: ~ s g_root `.`

unsafe @ set_root s r → v { = g_root ( nurl_str_cat r `` ) }

@ configure → v {
    : String m ( string_from `/var/lib/some/long/configured/root/path` )
    ( set_root ( string_data m ) )
}

@ main → i {
    ( configure )
    ( nurl_print g_root ) ( nurl_print `\n` )
    ( configure )
    ( set_root `literal` )
    ( nurl_print g_root ) ( nurl_print `\n` )
    ^ 0
}
