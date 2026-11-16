// map: §7.6 | A2 | rejected | - | agora #242: elaborated twin: a value block whose tail is a raw view of its own local, bound by `:` then handed back
// AGORA-869: heap-use-after-free under ASan with the walk alone; the ownership engine refuses it (codegen makes no copy here, unlike the unbound spelling).
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
