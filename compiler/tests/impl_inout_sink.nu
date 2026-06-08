// impl_inout_sink.nu — regression for `inout` / `sink` parameter
// conventions on TRAIT IMPL METHODS (grammar v2 borrow-checker, §1).
//
// Bug (pre-fix): an `inout`/`sink` parameter on an impl method silently
// miscompiled. gen_fn_decl_concrete recorded the convention under the
// MANGLED method name (`bump__Counter`) but the call site dispatches by
// the BARE name (`( bump c )` → `bump`) and looked the convention up
// there — finding nothing, it passed the receiver BY VALUE into a `%T*`
// parameter → memory corruption / segfault. Fixing that surfaced a
// second bug: applying `inout` pointerises the first arg to `%T*`, which
// missed the impl-dispatch key (`bump##%Counter`), emitting an undefined
// bare `@bump`. Both are fixed: the bare-name convention is mirrored at
// emission, and the impl-dispatch key retries with the receiver pointer
// stripped.
//
// main returns the number of failed checks (0 = all pass).

$ `stdlib/core/vec.nu`

: Counter { i n }
: Tally { i hits }
: Holder { ( Vec i ) v }

% Bumpable [T] {
    @ bump inout T x → v
    @ bump_by inout T x i d → v
}

% Bumpable ( Counter ) {
    @ bump inout Counter c → v { = . c n + . c n 1 }
    @ bump_by inout Counter c i d → v { = . c n + . c n d }
}

// A second implementing type for the same trait method names — proves
// the type-mangled dispatch still distinguishes them once inout is on.
% Bumpable ( Tally ) {
    @ bump inout Tally t → v { = . t hits + . t hits 10 }
    @ bump_by inout Tally t i d → v { = . t hits + . t hits d }
}

% Consumable [T] {
    @ consume sink T x → i
}

% Consumable ( Holder ) {
    @ consume sink Holder h → i {
        : i n ( vec_len [i] . h v )
        ( vec_free [i] . h v )
        ^ n
    }
}

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : ~ i f 0

    // Struct inout (the former segfault): the impl mutates the caller's
    // binding in place through the address.
    : ~ Counter c @ Counter { 10 }
    ( bump c )
    ( bump c )
    = f + f ( chk . c n 12 `struct_inout` )

    // inout beside an ordinary by-value parameter.
    ( bump_by c 5 )
    = f + f ( chk . c n 17 `inout_plus_byval` )

    // Same method names on a second type → distinct type-mangled impls.
    : ~ Tally t @ Tally { 0 }
    ( bump t )
    ( bump_by t 3 )
    = f + f ( chk . t hits 13 `second_impl_distinct` )

    // sink impl method: the receiver is moved into the method, which
    // frees its Vec exactly once — no double free with the binding's
    // own auto-drop.
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ( vec_push [i] v 8 )
    : Holder h @ Holder { v }
    = f + f ( chk ( consume h ) 2 `sink_impl` )

    ^ f
}
