// diag_send_generic_bound.nu
// `[T: Send]` is answered by the same derivation the thread boundaries
// use, not by hunting the impl registry — `i` and `s` and structs of
// them are Send because of what they ARE, and requiring an impl block
// per type would make the bound unusable. `( Rc i )` fails it, and the
// message says the bound cannot be satisfied by adding an impl.

$ `stdlib/core/marker.nu`
$ `stdlib/std/rc.nu`

@ ship [T : Send] T v → i { ^ 0 }

@ main → i {
    : ( Rc i ) r ( rc_new [i] 0 )
    ^ ( ship [( Rc i )] r )
}
