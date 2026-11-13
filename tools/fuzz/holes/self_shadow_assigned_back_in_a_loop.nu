// self_shadow_assigned_back_in_a_loop: `= s { : String s s  s }` in a loop: no flag moved — the inner s, resolved by name, was taken for the new binding itself, so the outer s kept its flag and `= s <inner>` released the buffer it stored back (agora #792).
// Closed: `: T s s` names as its source the binding the new s shadows — in codegen its slot, read before the new s is defined (gen_let_or_struct, g_let_self_src), and for the walk `^s`, the spelling visible before the newest declaration (bck_xl_resolve). The flag moves as for `: T u s` (agora #792), and the block's tail, the inner s spelled like the target, is handed over by its slot (agora #806).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #792: the self-shadow alias assigned back to the outer s in a loop (UAF on main)
$ `stdlib/core/string.nu`

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 2 { = s { : String s s s } = k + k 1 }
    ( nurl_println ( string_data s ) )
    ^ 0
}
