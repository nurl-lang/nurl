// map: §2.1 | A2 | rejected | - | AGORA-939: an inout parameter's field taken by one call of a statement while a later call of it may panic
// AGORA-939 (closed): refused - `take` has the field from the moment it starts, so a panic in `mayp`, later in the same statement, hands `h` back empty (github#2110 head 9e025429: accepted)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mayp i k → i { ? > k 2 { ( panic `later` ) } {} ^ k }

@ add i a i b → i { ^ + a b }

@ cycle inout Holder h i k → v {
    : i n ( add ( take . h buf ) ( mayp k ) )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
