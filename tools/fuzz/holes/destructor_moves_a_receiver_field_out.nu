// destructor_moves_a_receiver_field_out: a destructor (a library handle's drop hook, or a `% Drop` impl) that stored a field of its receiver into a literal, a container or another field moved it there without emptying the field, so its drop glue released it a second time.
// Closed: a value that cannot be copied, read out of a field, is lent — here out of the value a destructor is dropping, whose drop glue still releases the field (mem_lent_cond) — so storing it is rejected; a `sink` function's parameter was already rejected the same way.
// v0.78.0: accepted; ASan reported heap-use-after-free in Res's drop (std/pool.nu's Pooled guard had this shape, reported in Agora #73).
// map: §7.6 | A2 | rejected | h322 | a drop hook stored a non-copyable field of its receiver into a generic struct literal; the field was not emptied and the receiver's drop glue released it again; a destructor receiver's field is now lent, as a parameter's is
$ `stdlib/core/string.nu`

: Res { String name }

% Drop Res { @ drop sink Res r → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . r name ) ) ) } }

: Slot [A] { A val i n }

: Guard [A] { A val i k }

@ Guard_drop [A] sink ( Guard A ) g → v {
    : ( Slot A ) s @ ( Slot A ) { . g val 1 }
    ( nurl_println `hook` )
}

@ main → i {
    : ( Guard Res ) g @ ( Guard Res ) { @ Res { ( string_from `r1` ) } 7 }
    ( nurl_println `ran` )
    ^ 0
}
