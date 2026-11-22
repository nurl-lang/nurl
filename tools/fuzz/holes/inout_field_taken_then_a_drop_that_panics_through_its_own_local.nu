// map: §2.1 | A2 | rejected | - | AGORA-942: an inout parameter's field a sink took, then a value released whose destructor may panic only through a local of its own whose destructor may
// AGORA-942 (closed): refused - `A`'s drop releases a `D` whose drop may panic; releasing `t` before the refill may unwind (CodeRabbit on github#2183: ncore's panic graph counted no release; main 3f08626b: accepted, a SEGV after recover)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: D { i n }

% Drop D { @ drop D c → v { ? > . c n 2 { ( panic `in drop` ) } {} } }

: A { i n }

% Drop A { @ drop A c → v { : D inner @ D { . c n } } }

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ mk i d → ( Vec u ) { ^ ( vec_new [u] ) }

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    { : A t @ A { k } }
    = . h buf ( mk n )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
