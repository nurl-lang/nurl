// map: §7.6 | A2 | runs-clean | - | AGORA-953 (agora #242 twin): `: s e { : String x … ( string_data x ) }  ^ e`: the binding gets a copy of its own
// twin of tools/fuzz/holes/raw_view_block_tail.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`

@ pick → s {
    : __el {
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
