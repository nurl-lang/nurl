// libh_key_locked_first.nu — a library handle that opens with a Locked.
//
// A binding read out of a field of an `inout` struct is checked, where the
// struct may have been changed meanwhile, against the field's current
// value by identity: a library handle's control-block pointer (agora
// #265). The pointer was taken from field 0, or field 0 of a `( Shared T
// )` there; a handle whose field 0 is a `( Locked T )` — a Shared of its
// own, two levels above the pointer, as gpukit's GpuKit is — handed the
// identity compare the Locked struct itself: invalid IR, and nurllama
// stopped compiling. The key follows every one-field wrapper down to the
// pointer now.

$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`

: St { i n }

// Field 0 a Locked: a handle (Kit_drop takes it `sink`).
: Kit {
    ( Locked St ) st
    ( Arc i ) info
}

@ Kit_share Kit k → Kit { ^ @ Kit { ( Locked_share [St] . k st ) ( arc_clone [i] . k info ) } }

@ Kit_drop sink Kit k → v {}

@ kit_new i n → Kit { ^ @ Kit { ( locked_new [St] @ St { n } ) ( arc_new [i] n ) } }

: Holder {
    Kit kit
    i x
    i calls
}

@ step Kit k i v inout i calls → b {
    = calls + calls 1
    ^ > + v ( arc_get [i] . k info ) 0
}

// The shape nurllama's __lm_emit has: a binding read out of the handle
// field of an `inout` struct before a loop, handed on inside it — where,
// for all the compiler knows, an earlier round may have taken the field's
// value over, so each call checks the binding still holds what the field
// does.
@ emit inout Holder h → b {
    : Kit kit . h kit
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k 3 {
        = ok & ok ( step kit . h x . h calls )
        = . h x + . h x 1
        = k + k 1
    }
    ^ ok
}

@ main → i {
    : ~ Holder h @ Holder { ( kit_new 5 ) 1 0 }
    : b ok ( emit h )
    ( nurl_println ? ok `ok` `failed` )
    ( nurl_print `calls: ` ) ( nurl_println_int . h calls )
    ( nurl_print `x: ` ) ( nurl_println_int . h x )
    ( nurl_print `info: ` ) ( nurl_println_int ( arc_get [i] . . h kit info ) )
    ^ 0
}
