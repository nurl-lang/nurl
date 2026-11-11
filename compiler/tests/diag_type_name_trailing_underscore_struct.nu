// diag_type_name_trailing_underscore_struct.nu — a struct's name does not
// end in `_`. The compiler writes `__` after a type's name where its type
// arguments start, so the name's last `_` would run into that separator:
// `( Holder_ i )` is spelled `Holder___i64`, which reads as a `Holder` of
// `_i64` — another type, with other fields or none, to every rule that
// walks a type by its name (agora #639).

$ `stdlib/std/rc.nu`

: Holder_ [A] { ( Rc A ) r }

@ main → i {
    : ( Holder_ i ) h @ ( Holder_ i ) { ( rc_new [i] 5 ) }
    ^ - ( rc_strong [i] . h r ) 1
}
