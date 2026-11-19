// own_drop_hook_reads_a_view_of_an_older_binding_runs_clean: AGORA-384 guard — a program's own `H_drop` hook reads a view field whose source is declared before the holder: the source outlives the hook, accepted
// map: §7.6 | A2 | runs-clean | - | AGORA-384 guard: a hook reading a view of an older binding
$ `stdlib/core/string.nu`

: H { s v }

@ H_drop sink H h → v { ( nurl_println . h v ) }

@ main → i {
    : String b ( string_from `a string older than the holder, alive when its hook runs` )
    : ~ H h @ H { `literal` }
    = h @ H { ( string_data b ) }
    ^ 0
}
