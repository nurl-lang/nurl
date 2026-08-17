// stdlib/core/io.nu — Tier 0 stdin/stdout completion
//
// Thin wrappers that lift the runtime read_line / flush / eof primitives
// into NURL's owned-String model and boolean convention.
//
//   ( read_line )         → String  owned line from stdin (trailing '\n' stripped)
//                                   On EOF with no data: empty String, ( stdin_eof ) turns T.
//   ( read_all_stdin )    → String  slurp stdin to EOF; empty String when no data.
//   ( read_n_bytes i n )  → ( Vec u )  exactly n bytes from stdin (or fewer on EOF).
//                                       Use for framed binary protocols (LSP, DAP,
//                                       JSON-RPC over stdio with `Content-Length` headers)
//                                       where the payload may contain '\n' or NUL bytes
//                                       and `read_line` is the wrong tool.
//   ( stdin_eof )         → b       T iff a previous read hit EOF
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

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`  // read(2) for the pure-NURL stdin slurp

// ── Pure-NURL stdin slurp ───────────────────────────────────────────
//
// PURIFY §13 batch 2 (2026-05-24): `nurl_read_all_stdin` is now a NURL
// @-function reading fd 0 via `read(2)` (declared in `stdlib/core/posix.nu`)
// in a 4 KB-stepped grow-and-retry loop. Both libc flavours we target
// (Linux/macOS, mingw-w64 libmingwex `read = _read`) accept fd 0 with
// blocking semantics for the controlling terminal / piped stdin. WASI
// routes the read through wasi-libc's POSIX shim.
//
// Returns a malloc'd NUL-terminated buffer (caller frees) or `0` on
// failure. The trailing NUL is written at `len`; the malloc'd region
// is sized `cap` (>= len + 1). The wrapper `read_all_stdin` below
// translates to an owned String for normal callers.
@ __read_all_stdin_pure → s {
    : ~ i cap 4096
    : ~ i len 0
    : ~ s buf ( nurl_alloc cap )
    ? == # i buf 0 { ^ # s 0 } {}
    : ~ b done F
    : ~ b ok F
    ~ ! done {
        // Ensure room for at least 1 byte read + NUL.
        ? <= - cap len 1 {
            : i ncap * cap 2
            : s nb ( nurl_realloc buf ncap )
            ? == # i nb 0 {
                // realloc failed; the original buf is still valid —
                // free it explicitly so the failure path doesn't leak.
                ( nurl_free buf )
                = buf # s 0
                = done T
            } {
                = buf nb
                = cap ncap
            }
        } {}
        ? ! done {
            : i room - cap - len 1
            : *u dst # *u + # i buf len
            : i got ( read # i32 0 dst room )
            ? > got 0 {
                = len + len got
            } {
                ? == got 0 {
                    // EOF — clean completion
                    = ok T
                    = done T
                } {
                    // -1 read error
                    = done T
                }
            }
        } {}
    }
    ? ok {
        : *u p # *u + # i buf len
        = . p 0 # u 0
        ^ buf
    } {
        ? != # i buf 0 { ( nurl_free buf ) } {}
        ^ # s 0
    }
}

@ read_line → String {
    : s raw ( nurl_read_line )
    : String out ( string_from raw )
    ^ out
}

// Read everything from stdin until EOF and return it as a single owned
// String. CLI tools that consume stdin (e.g. `cat`, `wc`, JSON formatters)
// use this when line-at-a-time iteration isn't required. Returns an empty
// String on allocation failure too — the runtime falls back to NULL which
// `string_from` turns into "" rather than crashing.
@ read_all_stdin → String {
    : s raw ( __read_all_stdin_pure )
    : i p # i raw
    ? == p 0 {
        ^ ( string_new )
    } {}
    : String out ( string_from raw )
    ( nurl_free raw )
    ^ out
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
// `vec_free [u]` or auto-drop.
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
            ? <= r 0 { = done T } {
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

// Everything on stdin, as BYTES. `read_all_stdin` returns a String, and
// a String stops at its first NUL — so a program in the middle of a
// pipe (`cat a.zst | zst d | wc -c`) could read a text stream whole but
// not a binary one, with the truncation silent. This is the dual of
// `write_bytes`, and the pair makes a byte-clean filter possible.
//
// Grows in 64 KiB steps and stops at the first zero-length read, so an
// input of unknown length costs O(size) copies and no length header.
@ read_all_stdin_bytes → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : ~ b done F
    ~ ! done {
        ( vec_reserve [u] out 65536 )
        : i len ( vec_len [u] out )
        : *u dst # *u + # i ( vec_data [u] out ) len
        : i r ( nurl_stdin_read dst 65536 )
        ? <= r 0 { = done T } {
            : b _ok ( vec_set_len [u] out + len r )
        }
    }
    ^ out
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
