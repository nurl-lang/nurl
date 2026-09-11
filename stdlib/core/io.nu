// stdlib/core/io.nu — Tier 0 stdin/stdout completion
//
// Thin wrappers that lift the runtime read_line / flush / eof primitives
// into NURL's owned-String model and boolean convention.
//
//   ( read_line )         → String  owned line from stdin (trailing '\n' stripped)
//                                   On EOF with no data: empty String, ( stdin_eof ) turns T.
//   ( read_stdin )        → !String IoErr  remaining stdin, preserving byte length; errors are explicit.
//   ( read_all_stdin )    → String  same data, panics on I/O failure.
//   ( read_n_bytes i n )  → ( Vec u )  exactly n bytes from stdin (or fewer on EOF).
//                                       Use for framed binary protocols (LSP, DAP,
//                                       JSON-RPC over stdio with `Content-Length` headers)
//                                       where the payload may contain '\n' or NUL bytes
//                                       and `read_line` is the wrong tool.
//   ( stdin_eof )         → b       T after read_line returned no bytes at EOF
//   ( flush )             → v       fflush(stdout)
//   ( eflush )            → v       fflush(stderr)
//
// ── When you need ( flush ) ──────────────────────────────────────────
//
// stdout is block-buffered when it is a pipe or a file, and flushed per
// print when it is a terminal — the same split C and Python make. That
// keeps a print-heavy program from paying one write(2) per fragment
// (measured: 300k printed lines went from 435 ms to 26 ms) without
// costing an interactive prompt its immediacy.
//
// The runtime already drains stdout for you at process exit, before a
// panic aborts, before every stderr write (so `2>&1` never reorders the
// two streams), and before `process`'s fork. Call ( flush ) yourself in
// the two cases it cannot see:
//
//   * before writing to fd 1 with raw `write(2)` instead of a print —
//     that path bypasses stdio's buffer entirely;
//   * when another process is *following* your redirected stdout and
//     must see a line the moment you print it (a server announcing its
//     port to a supervisor, a progress line piped into `tee`).

$ `stdlib/core/errors.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`  // buffered stdin bridge

// Reader contract: write at most room bytes, return the count, zero at EOF,
// or -1 on error. Short positive reads are data, never assumed to be EOF.
// The destination pointer is borrowed only for the duration of that call.
// The returned Vec owns its buffer and keeps one spare NUL terminator byte,
// so a text caller can adopt the same control block as a String without copying.
// At capacity the terminator slot permits one-byte lookahead: grow only when
// input actually continues, including when a regular-file size hint is stale.
@ read_to_end ( @ i * u i ) reader i hint → !( Vec u ) IoErr {
    : i initial ? > hint 0 hint 4096
    ? >= initial 9223372036854775807 { ^ @ !( Vec u ) IoErr { F @ IoErr { Other } } } {}
    : ( Vec u ) bytes ( vec_with_cap [u] + initial 1 )
    : ~ b done F
    ~ ! done {
        : i len ( vec_len [u] bytes )
        : i room - - ( vec_cap [u] bytes ) len 1
        : i want ? > room 0 room 1
        : *u dst # *u + # i ( vec_data [u] bytes ) len
        : i got ( reader dst want )
        ? | < got 0 > got want {
            ( vec_free [u] bytes )
            ^ @ !( Vec u ) IoErr { F @ IoErr { ReadFailed } }
        } {}
        : b _set ( vec_set_len [u] bytes + len got )
        ( vec_reserve [u] bytes 1 )
        = . ( vec_data [u] bytes ) + len got # u 0
        ? == got 0 { = done T } {}
    }
    ^ @ !( Vec u ) IoErr { T bytes }
}

// Shared stdio, not descriptor reads: read_line may already have prefetched
// bytes past its newline. Text retains its real byte length, including NULs.
@ read_stdin → !String IoErr {
    ?? ( read_to_end \ * u dst i room → i { ^ ( nurl_stdin_read dst room ) } 4096 ) {
        T bytes → { ^ @ !String IoErr { T @ String { . bytes ctl } } }
        F e → { ^ @ !String IoErr { F e } }
    }
}

@ read_line → String {
    : s raw ( nurl_read_line )
    : String out ( string_from raw )
    ^ out
}

// Convenience form for callers that cannot recover from an input failure.
// Errors panic; returning an empty String would make truncated input look valid.
@ read_all_stdin → String {
    ?? ( read_stdin ) {
        T text → { ^ text }
        F _ → { ( nurl_panic `read_all_stdin: input read failed` ) ^ ( string_new ) }
    }
}

// Binary stdin reader: returns up to `n` bytes as an OWNED Vec[u].
// On short reads (EOF mid-stream) the result is shorter than `n`;
// callers detect EOF by comparing `vec_len out` against `n`. Used by
// framed protocols (LSP / DAP / raw JSON-RPC over stdio) where the
// body length is announced by a `Content-Length: N` header and the
// body is opaque bytes — possibly containing newlines or even NULs —
// so `read_line` would corrupt it.
//
// PURIFY (2026-05-24): reads stdin in a retry loop until `n` bytes are
// accumulated or a read returns 0 (EOF). No more runtime-side sideband —
// the byte count is the returned Vec's length. Caller frees via
// `vec_free [u]`. Read failures panic instead of looking like early EOF.
//
// Reads through `nurl_stdin_read` (a buffered `fread(stdin)`) rather
// than a raw `read(2)` on fd 0 so that it stays coherent with
// `read_line`'s buffered `fgetc`: a framed protocol that reads the
// header line with `read_line` and the body with this must share one
// stdio buffer, or the header read silently swallows body bytes the raw
// descriptor read would then miss (LSP/DAP body truncation).
@ read_n_bytes i n → ( Vec u ) {
    ? <= n 0 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) out ( vec_with_cap [u] n )
    : *u dst ( vec_data [u] out )
    : ~ i got 0
    : ~ b done F
    ~ ! done {
        : i room - n got
        ? <= room 0 { = done T } {
            : *u at # *u + # i dst got
            : i r ( nurl_stdin_read at room )
            ? < r 0 { ( vec_free [u] out ) ( nurl_panic `read_n_bytes: input read failed` ) ^ ( vec_new [u] ) } {}
            ? == r 0 { = done T } {
                = got + got r
            }
        }
    }
    : b _ok ( vec_set_len [u] out got )
    ^ out
}

@ stdin_eof → b {
    ^ != 0 ( nurl_stdin_eof )
}

// Everything on stdin as bytes, paired with write_bytes for binary filters.
// Both this function and read_stdin retain NUL bytes; converting String data
// to a raw `s` for C-string APIs still loses the explicit byte length.
//
// Shares read_to_end's geometric buffer growth and explicit error handling.
@ read_all_stdin_bytes → ( Vec u ) {
    ?? ( read_to_end \ * u dst i room → i { ^ ( nurl_stdin_read dst room ) } 4096 ) {
        T bytes → { ^ bytes }
        F _ → { ( nurl_panic `read_all_stdin_bytes: input read failed` ) ^ ( vec_new [u] ) }
    }
}

// ── Binary stdout ───────────────────────────────────────────────────
//
// The write-side dual of read_n_bytes. Every print in the language takes
// a NUL-terminated string, so a program holding arbitrary bytes — a value
// read out of a database, a decoded image, a response body being
// proxied — could not emit them: output stopped at the first zero byte,
// silently. write_bytes writes the buffer exactly, NULs and all.
//
// It shares stdout's stdio buffer and tty-flush rule with the ordinary
// prints, so mixing the two never reorders output (unlike a raw write(2)
// on fd 1, which would need an explicit ( flush ) first).
& `c` @ nurl_print_bytes s p i n → v

@ write_bytes ( Vec u ) v → v {
    : i n ( vec_len [u] v )
    ? > n 0 { ( nurl_print_bytes # s ( vec_data [u] v ) n ) } {}
}

@ flush → v {
    ( nurl_flush_stdout )
}

@ eflush → v {
    ( nurl_flush_stderr )
}
