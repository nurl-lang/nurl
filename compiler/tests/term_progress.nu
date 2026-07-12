// Test: term_width/term_height env fallback + the progress widget.
// The test runner pipes stdout/stderr (not a tty), so TIOCGWINSZ fails
// and the $COLUMNS/$LINES path must answer; the progress bar must stay
// completely silent on a non-tty stderr while its counters and the
// human formatter keep working.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/term.nu`
$ `stdlib/std/progress.nu`

@ ck b ok s name → v {
    ? ok { ( nurl_print `PASS ` ) } { ( nurl_print `FAIL ` ) }
    ( nurl_print name )
    ( nurl_print `\n` )
}

@ human_is i n s want → b {
    : String hh ( progress_human n )
    : b r ? ( nurl_str_eq ( string_data hh ) want ) T F
    ( string_free hh )
    ^ r
}

@ main → i {
    // non-tty: ioctl fails → env → default
    ( env_set `COLUMNS` `123` )
    ( env_set `LINES` `45` )
    ( ck == ( term_width ) 123 `term_width honours $COLUMNS off-tty` )
    ( ck == ( term_height ) 45 `term_height honours $LINES off-tty` )
    ( env_set `COLUMNS` `garbage` )
    ( ck == ( term_width ) 80 `unparseable $COLUMNS falls back to 80` )

    // human formatter
    : ~ b hf T
    ? ( human_is 0 `0 B` ) {} { = hf F }
    ? ( human_is 1023 `1023 B` ) {} { = hf F }
    ? ( human_is 1024 `1.0 KB` ) {} { = hf F }
    ? ( human_is 1536 `1.5 KB` ) {} { = hf F }
    ? ( human_is 1048576 `1.0 MB` ) {} { = hf F }
    ? ( human_is 44564480 `42.5 MB` ) {} { = hf F }
    ? ( human_is 1288490188 `1.1 GB` ) {} { = hf F }
    ( ck hf `progress_human: B/KB/MB/GB with one decimal` )

    // progress on a non-tty: counters advance, zero terminal noise
    : *Progress p ( progress_new `fetch` 1000 )
    ( progress_add p 400 )
    ( progress_set p 900 )
    ( progress_add p 100 )
    ( ck == . p cur 1000 `progress counters advance` )
    ( ck ! . p tty `non-tty detected (renders suppressed)` )
    ( progress_done p )
    ( nurl_print `done\n` )
    ^ 0
}
