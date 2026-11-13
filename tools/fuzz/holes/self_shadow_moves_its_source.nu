// self_shadow_moves_its_source: `? T { : String s s  ( eat s ) } {}`: the walk took the new s for the moved one and refused the sink ("use of moved value 's'") though the inner s takes the value over, as `: String u s` does (agora #792).
// Closed: `: T s s` names as its source the binding the new s shadows — in codegen its slot, read before the new s is defined (gen_let_or_struct, g_let_self_src), and for the walk `^s`, the spelling visible before the newest declaration (bck_xl_resolve). The flag moves as for `: T u s` (agora #792).
// main (before this PR): refused.
// map: §7.6 | A2 | runs-clean | - | agora #792: a self-shadow handover sunk in an arm
$ `stdlib/core/string.nu`

@ eat sink String x → v { ( nurl_println ( string_data x ) ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    ? T { : String s s ( eat s ) } {}
    ^ 0
}
