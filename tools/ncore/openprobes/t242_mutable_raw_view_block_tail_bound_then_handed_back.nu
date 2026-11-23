// map: §7.6 | A2 | rejected | - | agora #242: `: ~ s e { : String x … ( string_data x ) }  ^ e`: a mutable raw string binding of a value block whose tail views the block's own local, handed back
// Heap-use-after-free under ASan on main 3f08626 and on github#2189: the `: ~ s` let path is not the `:` one AGORA-953 copies in.
// twin of tools/fuzz/holes/raw_view_block_tail.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`

@ pick → s {
    : ~ s __el {
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
