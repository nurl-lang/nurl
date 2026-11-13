// mut_self_shadow_sunk: `{ : ~ String s s  ( eat s ) }`: a `: ~` copy is a borrow of the outer s, but the walk read its source as the copy itself, so handing it to a sink was accepted and the outer s freed it again (agora #792).
// Closed: `: T s s` names as its source the binding the new s shadows — in codegen its slot, read before the new s is defined (gen_let_or_struct, g_let_self_src), and for the walk `^s`, the spelling visible before the newest declaration (bck_xl_resolve). The flag moves as for `: T u s` (agora #792).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #792: a mutable self-shadow copy handed to a sink (UAF on main)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String t i n }

% Drop R { @ drop R r → v { ( nurl_println_int . r n ) } }

@ eat sink String x → v { ( nurl_println ( string_data x ) ) }

@ eatr sink R x → v { ( nurl_println_int . x n ) }

@ eatv sink ( Vec i ) x → v { ( nurl_println_int ( vec_len [i] x ) ) }

@ main → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    { : ~ String s s ( eat s ) }
    ^ 0
}
