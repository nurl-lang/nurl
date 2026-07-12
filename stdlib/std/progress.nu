// stdlib/std/progress.nu — a terminal progress bar for long transfers.
//
// The display layer for streamed work (a model download writing through
// file_write_chunk, a hash of a huge file): counts bytes, renders a
// throttled single-line bar on stderr, and stays COMPLETELY SILENT when
// stderr is not a tty — CI logs never fill with carriage returns.
//
//   ( progress_new label total )   → *Progress   total ≤ 0: indeterminate
//   ( progress_add p n )           → v           advance by n units
//   ( progress_set p cur )         → v           set absolute position
//   ( progress_done p )            → v           final render + newline; FREES p
//   ( progress_human n )           → String      "3.4 MB" (pure; unit-testable)
//
// Rendering: at most every 100 ms (monotonic clock), width-fitted to
// term_width, with a rate derived from the elapsed wall time:
//
//   fetch [==========>          ]  42.5 MB / 118.2 MB  17.3 MB/s
//
// Units are whatever the caller counts — the human formatter assumes
// bytes, which is the overwhelmingly common case.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/term.nu`

: Progress {
    String label
    i total
    i cur
    i started_ns
    i last_ns
    b tty
}

// "1023 B" · "3.4 KB" · "42.5 MB" · "1.2 GB" — one decimal above bytes.
@ progress_human i n → String {
    : String out ( string_new )
    ? < n 0 {
        ( string_push_str out `0 B` )
        ^ out
    } {}
    ? < n 1024 {
        ( string_push_int out n )
        ( string_push_str out ` B` )
        ^ out
    } {}
    : ~ i unit 0
    : ~ i scaled * n 10
    = scaled / scaled 1024
    ~ & >= scaled 10240 < unit 3 {
        = scaled / scaled 1024
        = unit + unit 1
    }
    ( string_push_int out / scaled 10 )
    ( string_push_char out 46 )
    ( string_push_int out % scaled 10 )
    ( string_push_char out 32 )
    ? == unit 0 { ( string_push_str out `KB` ) } {
        ? == unit 1 { ( string_push_str out `MB` ) } {
            ? == unit 2 { ( string_push_str out `GB` ) } { ( string_push_str out `TB` ) }
        }
    }
    ^ out
}

@ progress_new s label i total → *Progress {
    : *Progress p # *Progress ( nurl_alloc Z Progress )
    = . p label ( string_from label )
    = . p total total
    = . p cur 0
    = . p started_ns ( monotonic_ns )
    = . p last_ns 0
    = . p tty ( term_is_tty 2 )
    ^ p
}

@ __pg_write s raw → v {
    : i n ( nurl_str_len raw )
    ? > n 0 { : i _w ( write 2 # *u raw n ) } {}
}

@ __pg_render * Progress p b final → v {
    : String ln ( string_new )
    ( string_push_char ln 13 )
    ( string_push_str ln ( string_data . p label ) )
    ( string_push_char ln 32 )
    : String curh ( progress_human . p cur )
    ? > . p total 0 {
        // width-fitted bar: label + [bar] + "cur / total  rate"
        : String toth ( progress_human . p total )
        : ~ i pct 0
        ? > . p total 0 { = pct / * . p cur 100 . p total } {}
        ? > pct 100 { = pct 100 } {}
        : i tw ( term_width )
        : ~ i barw - - - tw ( string_len . p label ) ( string_len curh ) ( string_len toth )
        = barw - barw 30
        ? > barw 40 { = barw 40 } {}
        ? >= barw 8 {
            ( string_push_char ln 91 )
            : i fill / * barw pct 100
            : ~ i k 0
            ~ < k barw {
                ? < k fill { ( string_push_char ln 61 ) } {
                    ? == k fill { ( string_push_char ln 62 ) } { ( string_push_char ln 32 ) }
                }
                = k + k 1
            }
            ( string_push_str ln `] ` )
        } {}
        ( string_push_int ln pct )
        ( string_push_str ln `% ` )
        ( string_push_str ln ( string_data curh ) )
        ( string_push_str ln ` / ` )
        ( string_push_str ln ( string_data toth ) )
        ( string_free toth )
    } {
        ( string_push_str ln ( string_data curh ) )
    }
    // rate over the whole transfer — smooth and honest
    : i el - ( monotonic_ns ) . p started_ns
    ? > el 100000000 {
        : i per_s / * . p cur 1000000000 el
        : String rh ( progress_human per_s )
        ( string_push_str ln `  ` )
        ( string_push_str ln ( string_data rh ) )
        ( string_push_str ln `/s` )
        ( string_free rh )
    } {}
    ( string_push_str ln `    ` )
    ? final { ( string_push_char ln 10 ) } {}
    ( __pg_write ( string_data ln ) )
    ( string_free ln )
    ( string_free curh )
}

@ __pg_tick * Progress p → v {
    ? . p tty {} { ^ v }
    : i now ( monotonic_ns )
    ? > - now . p last_ns 100000000 {
        = . p last_ns now
        ( __pg_render p F )
    } {}
}

@ progress_add * Progress p i n → v {
    = . p cur + . p cur n
    ( __pg_tick p )
}

@ progress_set * Progress p i cur → v {
    = . p cur cur
    ( __pg_tick p )
}

// Final render (100 % state) + newline, then FREES p — the handle is
// dead after this. Still silent when stderr is not a tty.
@ progress_done * Progress p → v {
    ? . p tty { ( __pg_render p T ) } {}
    ( string_free . p label )
    ( nurl_free # s p )
}
