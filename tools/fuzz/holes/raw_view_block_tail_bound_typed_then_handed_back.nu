// map: §7.6 | A2 | runs-clean | - | AGORA-953: `: s e { : String x … ( string_data x ) }  ^ e`, the type written: the typed let path gives the binding a copy of its own, as the inferred one does
// Was a heap-use-after-free under ASan on main 4525fc8.
// twin of tools/fuzz/holes/raw_view_block_tail.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`

@ pick → s {
    : s __el {
        : String x ( string_from `element string long enough for a heap buffer` )
        ( string_data x )
    }
    ^ __el
}

@ main → i {
    : s a ( pick )
    ( nurl_println a )
    ^ 0
}
