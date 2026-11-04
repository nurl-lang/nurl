// closure_local_releases_an_option_capture_never_run: agora #463 — `: ( @ i ) c \ → i { ^ ( eato x ) }`, `x` a `?String`, `c` never called
// Closed: a capture the body takes over is the environment's: released by it when the body never ran; the body empties the slot when it takes it (agora #463).
// main: ran clean (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `: ( @ i ) c \ → i { ^ ( eato x ) }`, `x` a `?String`, `c` never called
$ `stdlib/core/string.nu`

@ eato sink ? String o → i { ?? o { T s → { ^ ( string_len s ) } F → { ^ 0 } } }

@ main → i {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    : ( @ i ) c \ → i { ^ ( eato x ) }
    ( nurl_println `not called` )
    ^ 0
}
