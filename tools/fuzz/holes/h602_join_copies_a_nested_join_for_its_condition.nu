// H602: a `?` value join whose arm is itself a `?` join (the else arm) copied that arm when the last identifier loaded was a tracked owned string — one the inner join's CONDITION read — and the owner the inner join published through its guard was never released: one leak per evaluation.
// Closed: a nested `?` arm is not copied (its own join settled its arms), and a copy of any guarded arm — a call, a `?` / `??` join, a block — releases that guard's owner (gen_cond, __tt_guarded).
// v0.80.0: accepted; LeakSanitizer, one string per evaluation.
$ `stdlib/core/string.nu`

@ vw s t → s { ^ t }

@ isc s t → b { ^ == ( nurl_str_get t 0 ) 40 }

@ go b x b sh s nm0 s p s q → i {
    : s nm ( nurl_str_cat nm0 `` )
    : ~ s rp ( vw p )
    : ~ s ra ( vw q )
    : s pos ? ! x `` ? & ! sh ( isc ( vw nm ) ) ( wj rp ra ) ( nurl_str_cat rp `` )
    ^ ( nurl_str_len pos )
}

@ wj s a s b → s {
    ? == 0 ( nurl_str_len a ) { ^ ( nurl_str_cat b `` ) } {}
    ^ ( nurl_str_cat3 a ` ` b )
}

@ main → i {
    : ~ i n 0
    : ~ i acc 0
    ~ < n 20 {
        = acc + acc ( go T F `(x` `0` `1` )
        = acc + acc ( go T F `x` `0` `1` )
        = acc + acc ( go F F `(x` `0` `1` )
        = n + n 1
    }
    ( nurl_println_int acc )
    ^ 0
}
