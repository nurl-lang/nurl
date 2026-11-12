// checked_out_value_dropped_once.nu — a `Locked D` or `Rc D` whose value
// was checked out (locked_take / rc_take) and never put back: the value is
// its taker's, and the last share drops only the empty slot — D's
// destructor runs once, on the taker's binding (Agora #795). Before, the
// last share's drop ran D's destructor again on the zero bytes the take
// left (`7` then `0`; a destructor writing a Vec field faulted). Also: a
// value taken and restored is dropped once by the last share; one never
// taken likewise; a second share kept while the value is out; an Rc whose
// value holds handles (the runtime's release path); and a Vec value with
// no destructor of its own.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`

: D { i id }

% Drop D { @ drop D r → v { ( nurl_println_int . r id ) } }

: Logged { ( Vec i ) seen i id }

% Drop Logged { @ drop Logged r → v { : ~ ( Vec i ) s . r seen ( vec_push [i] s . r id ) ( nurl_println_int + 100 ( vec_len [i] s ) ) } }

: Holder { ( Rc i ) inner D d }

@ main → i {
    ( nurl_println `locked: taken, never restored` )
    : ( Locked D ) l1 ( locked_new [D] @ D { 1 } )
    { : D c ( locked_take [D] l1 ) }

    ( nurl_println `locked: taken and restored` )
    : ( Locked D ) l2 ( locked_new [D] @ D { 2 } )
    : D c2 ( locked_take [D] l2 )
    ( locked_restore [D] l2 c2 )

    ( nurl_println `locked: never taken` )
    { : ( Locked D ) l3 ( locked_new [D] @ D { 3 } ) }

    ( nurl_println `locked: a second share while out` )
    : ( Locked D ) l4 ( locked_new [D] @ D { 4 } )
    { : ( Locked D ) l4b ( Locked_share [D] l4 ) : D c4 ( locked_take [D] l4b ) }

    ( nurl_println `locked: a destructor that writes a Vec field` )
    : ( Locked Logged ) l5 ( locked_new [Logged] @ Logged { ( vec_new [i] ) 5 } )
    { : Logged c5 ( locked_take [Logged] l5 ) }

    ( nurl_println `rc: taken, never restored` )
    : ( Rc D ) r1 ( rc_new [D] @ D { 6 } )
    { : D c6 ( rc_take [D] r1 ) }

    ( nurl_println `rc: taken and restored` )
    : ( Rc D ) r2 ( rc_new [D] @ D { 7 } )
    : D c7 ( rc_take [D] r2 )
    ( rc_restore [D] r2 c7 )

    ( nurl_println `rc: a value holding handles, taken` )
    : ( Rc Holder ) r3 ( rc_new [Holder] @ Holder { ( rc_new [i] 9 ) @ D { 8 } } )
    { : Holder c8 ( rc_take [Holder] r3 ) }

    ( nurl_println `locked: a Vec, taken` )
    : ( Locked ( Vec i ) ) l6 ( locked_new [( Vec i )] ( vec_new [i] ) )
    { : ( Vec i ) v6 ( locked_take [( Vec i )] l6 ) ( vec_push [i] v6 1 ) }

    ( nurl_println `end of main` )
    ^ 0
}
