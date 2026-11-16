// map: §7.5 | A2 | rejected | - | agora #242: elaborated twin: a `??` whose arms are closures capturing a payload of a local `??String`, bound by `:` then handed back
// AGORA-869: heap-use-after-free under ASan with the walk alone; the ownership engine refuses it (codegen makes no copy here, unlike the unbound spelling).
// twin of tools/fuzz/holes/closure_returned_from_an_arm_over_a_payload.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`

@ cap → ( @ i ) {
    : ?? String oo @ ?? String { T @ ?String { T ( string_from `an inner option value long enough for the heap` ) } }
    : __el ?? oo { T inner → \ → i { ?? inner { T s → { ^ ( string_len s ) } F → { ^ 1 } } } F → \ → i { ^ 0 } }
    ^ __el
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
