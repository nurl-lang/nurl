// Regression: `^ ?? owned { … }` returning a SCALAR must still drop the
// owned scrutinee. gen_ret's escape analysis used the lingering
// `__last_ident_name__` (the match scrutinee) to skip the returned
// value's auto-drop — but the value returned is the match RESULT (an
// int), not the scrutinee, so the owned binding leaked. A scalar match
// result cannot alias the scrutinee's storage, so gen_match now clears
// the ident name and the scrutinee drops normally.
//
// Builds via ./build.sh; the leak proof is under ASan/LSan.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Elem { String tag ( Vec Node ) kids }
: | Node { NText String  NElem Elem }

@ mk_text s t → Node { ^ @ Node { NText ( string_from t ) } }

// The repro: an owned local matched in RETURN position, yielding an int.
// `owned` is not the returned value, so it must be reclaimed here.
@ classify_owned → i {
    : Node owned ( mk_text `owned-then-returned-as-scalar` )
    ^ ?? owned { NText _ → 0  NElem _ → 1 }
}

@ main → i {
    : ~ i fails 0
    ? != ( classify_owned ) 0 { ( nurl_print `  FAIL classify\n` ) = fails + fails 1 } {}
    ? == fails 0 { ( nurl_print `ret_match_scalar_drop: PASS\n` ) } {
        ( nurl_print `ret_match_scalar_drop: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
