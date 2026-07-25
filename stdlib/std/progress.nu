// stdlib/std/progress.nu — a terminal progress bar for long transfers.
//
// The display layer for streamed work (a model download writing through
// file_write_chunk, a hash of a huge file): counts bytes, renders a
// throttled single-line bar on stderr, and stays COMPLETELY SILENT when
// stderr is not a tty — CI logs never fill with carriage returns.
//
//   ( progress_new label total )   → *Progress   total ≤ 0: indeterminate
//   ( progress_add p n )           → v           advance by n units
//   ( progress_set p cur )         → v           set absolute position AND
//                                                rebase the rate (resume)
//   ( progress_done p )            → v           final render + newline; FREES p
//   ( progress_human n )           → String      "3.4 MB" (pure; unit-testable)
//
// Rendering: at most every 100 ms (monotonic clock), width-fitted to
// term_width, with a CURRENT rate — the recent throughput, the number
// curl and wget show — not a cumulative average:
//
//   fetch [==========>          ]  42.5 MB / 118.2 MB  17.3 MB/s
//
// Units are whatever the caller counts — the human formatter assumes
// bytes, which is the overwhelmingly common case.
//
// Why a windowed rate: the rate used to be `cur / (now - started)`, an
// average over the whole transfer. Two things made that misleading on a
// long download. It cannot react — a transfer that settles at 1 MB/s
// after a fast first second spends minutes crawling down toward the
// truth, which reads as "the download is slowing down" when it is not.
// And on a RESUME the caller sets the already-downloaded bytes with
// `progress_set`, so the first render divided (say) 400 MB by 0.2 s and
// printed gigabytes per second, then decayed continuously from there.
// The rate is now an exponential moving average over the last ~1 s of
// samples, measured from the resume point, and `progress_done` reports
// the average over THIS session's bytes.

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
    // Rate state. `base_*` is the point the rate is measured from —
    // reset by progress_set so resumed bytes never count as throughput.
    // `w_*` is the previous sample; `rate` the smoothed bytes/s.
    i base_cur
    i base_ns
    i w_cur
    i w_ns
    i rate
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
    : i now ( monotonic_ns )
    = . p started_ns now
    = . p last_ns 0
    = . p tty ( term_is_tty 2 )
    = . p base_cur 0
    = . p base_ns now
    = . p w_cur 0
    = . p w_ns now
    = . p rate 0
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
    // Current rate: the smoothed recent throughput. Before the first
    // sample lands, fall back to this session's average (bytes since the
    // resume point over the time since it) so the field is never blank.
    // `final` reports that session average — the summary wget prints.
    : i el - ( monotonic_ns ) . p base_ns
    : ~ i per_s 0
    ? final {
        ? > el 100000000 { = per_s / * - . p cur . p base_cur 1000000000 el } {}
    } {
        ? > . p rate 0 { = per_s . p rate } {
            ? > el 100000000 { = per_s / * - . p cur . p base_cur 1000000000 el } {}
        }
    }
    ? > per_s 0 {
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

// Fold one sample into the moving average. alpha = 1/8 over the 100 ms
// render cadence ≈ a 0.8 s time constant: responsive enough to show a
// stall, smooth enough not to jitter on chunk boundaries.
@ __pg_sample * Progress p i now → v {
    : i dt - now . p w_ns
    ? <= dt 0 { ^ v } {}
    : i db - . p cur . p w_cur
    : i inst / * db 1000000000 dt
    ? <= . p rate 0 { = . p rate inst } { = . p rate / + * . p rate 7 inst 8 }
    = . p w_cur . p cur
    = . p w_ns now
}

@ __pg_tick * Progress p → v {
    ? . p tty {} { ^ v }
    : i now ( monotonic_ns )
    ? > - now . p last_ns 100000000 {
        = . p last_ns now
        ( __pg_sample p now )
        ( __pg_render p F )
    } {}
}

@ progress_add * Progress p i n → v {
    = . p cur + . p cur n
    ( __pg_tick p )
}

// Absolute position — and the rate's new zero. The caller that uses
// this is resuming a partial transfer: those bytes came off the disk,
// not the network, so counting them as throughput is what produced the
// "starts at gigabytes per second, then falls forever" display.
@ progress_set * Progress p i cur → v {
    : i now ( monotonic_ns )
    = . p cur cur
    = . p base_cur cur
    = . p base_ns now
    = . p w_cur cur
    = . p w_ns now
    = . p rate 0
    ( __pg_tick p )
}

// Final render (100 % state) + newline, then FREES p — the handle is
// dead after this. Still silent when stderr is not a tty.
@ progress_done * Progress p → v {
    ? . p tty { ( __pg_render p T ) } {}
    ( string_free . p label )
    ( nurl_free # s p )
}
