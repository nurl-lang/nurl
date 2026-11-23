// map: §2.1 | A2 | rejected | - | AGORA-952 (CodeRabbit on github#2189): a closure over a value whose `% Drop` reaches an Rc and may panic, released at its block's end, in a function with no borrow, while an inout field is taken
// AGORA-952 (closed): refused - the closure's notes are `+dk=` (an Rc reached), and a scope's end is asked for them too (__bck_du_any); main 26f26b53: accepted, a SEGV after recover
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

: H { ( Rc ( Vec u ) ) a i n }

% Drop H { @ drop H h → v { ? > . h n 2 { ( panic `in drop` ) } {} ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) } }

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk i d → ( Vec u ) { ^ ( vec_new [u] ) }

@ mkf sink H h → ( @ i ) { ^ \ → i { ^ . h n } }

@ cycle inout Holder h i k → v {
    : ~ i n 0
    {
        : ( @ i ) f ( mkf @ H { ( rc_new [( Vec u )] ( vec_new [u] ) ) k } )
        = n ( take . h buf )
    }
    = . h buf ( mk n )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
