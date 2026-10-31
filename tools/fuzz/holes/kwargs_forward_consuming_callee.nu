// kwargs_forward_consuming_callee: a keyword-argument call to a function defined later that hands its argument on to a `sink`: the kwargs path skipped the consumption summary, so the caller dropped the String again (double free).
// map: CallT.summary | A1 | runs-clean | h142 | kwargs call to later fn that forwards arg to sink; caller drops again
$ `stdlib/core/string.nu`

@ main → i {
    : String raw ( string_from `abc` )
    ( nurl_println_int ( retain value : raw ) )
    ( nurl_println `KWARGS-MARK` )
    ^ 0
}

@ retain String value → i { ^ ( consume value ) }

@ consume sink String v → i { ^ ( string_len v ) }
