// Test: stdlib/std/log.nu — leveled logging with fmt-based variants.
//
// All log output goes to stderr; stdout stays clean. The test is
// deterministic: no timestamps, fixed messages, default + tweaked
// thresholds. The test_runner captures stdout+stderr together so the
// baseline pins both streams.

$ `stdlib/std/log.nu`

@ main → i {
    // Default level is Info(1) — Debug suppressed, Info..Error printed.
    ( nurl_print `=== default level (Info) ===\n` )
    ( log_debug `should be hidden` )
    ( log_info `info ok` )
    ( log_warn `warn ok` )
    ( log_error `error ok` )

    // Bump threshold to Warn — Info now hidden too.
    ( log_set_level ( log_level_warn ) )
    ( nurl_print `=== threshold = Warn ===\n` )
    ( log_info `should be hidden too` )
    ( log_warnf1 `disk {} full` `/var` )
    ( log_errorf2 `oops {}: code {}` `db` `42` )

    // Off silences everything.
    ( log_set_level ( log_level_off ) )
    ( nurl_print `=== threshold = Off ===\n` )
    ( log_debug `silent` )
    ( log_info `silent` )
    ( log_warn `silent` )
    ( log_error `silent` )

    // Back to Debug — exercise all f-variants.
    ( log_set_level ( log_level_debug ) )
    ( nurl_print `=== threshold = Debug ===\n` )
    ( log_debugf3 `{}-{}-{}` `a` `b` `c` )
    ( log_infof2 `req {} took {}ms` `GET /` `12` )
    ( log_warnf3 `slow query {} ({} rows in {}ms)` `users` `1234` `560` )
    ( log_errorf1 `crash: {}` `null deref` )

    // get/set round-trip
    ( log_set_level ( log_level_info ) )
    ( nurl_print `cur_level=` )
    ( nurl_print ( nurl_str_int ( log_get_level ) ) )
    ( nurl_print `\n` )

    // Owned String + integer arg.
    : String who ( string_from `Bob` )
    ( log_infof2 `{} just turned {}` ( string_data who ) ( nurl_str_int 42 ) )
    ( string_free who )

    ( nurl_print `done\n` )
    ^ 0
}
