// Test: Phase 2D#2 arm-local fall-through drop. `:` bindings made inside
// a `?` / match / loop arm that does NOT `^ ret` must have their owned
// strings AND owned struct-fields dropped at arm end, not leaked to the
// caller's owned list (which would produce invalid IR) and not left
// allocated (which ASan would flag as a leak).

$ `stdlib/core/string.nu`

: Boxed {
    s msg
    i n
}

@ main → i {
    // Arm-local owned string — falls through.
    ? 1
    { : s s1 ( nurl_str_cat `arm ` `string` )
        ( nurl_print s1 ) ( nurl_print `\n` )
    }
    {}

    // Arm-local struct with owned field — falls through.
    ? 1
    { : Boxed b @ Boxed { ( nurl_str_cat3 `x ` `y ` `z` ) 5 }
        ( nurl_print . b msg ) ( nurl_print `\n` )
    }
    {}

    // Loop body owned string — dropped per iteration.
    : ~ i i 0
    ~ < i 2 {
        : s ls ( nurl_str_cat `loop ` ( nurl_str_int i ) )
        ( nurl_print ls ) ( nurl_print `\n` )
        = i + i 1
    }

    ( nurl_print `done\n` )
    ^ 0
}
