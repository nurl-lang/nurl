// t952_taken_field_past_a_closure_release_whose_env_drop_panics: AGORA-952 (open; filed from AGORA-942) — a sink took `. h buf` of an `inout` parameter; before the refill, `= f g` releases a closure whose environment took over a `D` whose `% Drop` may panic
// AGORA-952 (open): accepted by nurlc, refused by ncore; a `recover`ing caller gets `h` back with `buf` empty and its next push reads a null handle (tools/fuzz/holes/open/t952.md)
// map: §3.3d | A2 | rejected | - | AGORA-952: a taken inout field, then a closure released whose environment's destructor may panic
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk i d → ( Vec u ) { ^ ( vec_new [u] ) }

@ mkf sink D d → ( @ i ) { ^ \ → i { ^ . d n } }

@ cycle inout Holder h i k → v {
    : ~ ( @ i ) f ( mkf @ D { k } )
    : ( @ i ) g ( mkf @ D { 1 } )
    : i n ( take . h buf )
    = f g
    = . h buf ( mk n )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
