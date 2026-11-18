// map: §2.10 | A2 | rejected | - | AGORA-811: `~ w ws { ( wipe_it w ) }` over a parameter's Vec, a static trait method clearing the payload of `w`'s share
// AGORA-811 (closed with AGORA-495): refused - a loop element of a parameter, a struct handed to a callee that clears through it, makes a drop edge on the parameter (main fd008190: accepted, heap-use-after-free)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

% Wiper [T] { @ wipe_it T self → i }

: G { ( Rc ( Vec String ) ) r }

% Wiper G { @ wipe_it G g → i { ( vec_clear [String] ( rc_get [( Vec String )] . g r ) ) ^ 0 } }

@ each ( Vec G ) ws → v { ~ w ws { : i z ( wipe_it w ) } }

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : ( Vec G ) ws ( vec_new [G] )
    ( vec_push [G] ws @ G { r } )
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( each ws )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
