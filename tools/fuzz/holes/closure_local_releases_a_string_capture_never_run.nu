// closure_local_releases_a_string_capture_never_run: agora #463 — `: ( @ i ) c \ → i { ^ ( eat x ) }`, `x` a String, `c` never called
// Closed: the same for a String capture (agora #463).
// main: detected memory leaks (base 8a2afbc3).
// map: §7.5 | A2 | runs-clean | - | agora #463: `: ( @ i ) c \ → i { ^ ( eat x ) }`, `x` a String, `c` never called
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String x ( string_from `a String local long enough for the heap` )
    : ( @ i ) c \ → i { ^ ( eat x ) }
    ( nurl_println `not called` )
    ^ 0
}
