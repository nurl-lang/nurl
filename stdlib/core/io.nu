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

// Binary stdin reader: returns exactly `n` bytes as an OWNED Vec[u].
// On short reads (EOF mid-stream) the result is shorter than `n` and
// ( stdin_eof ) turns T. Used by framed protocols (LSP / DAP /
// raw JSON-RPC over stdio) where the body length is announced by a
// `Content-Length: N` header and the body is opaque bytes — possibly
// containing newlines or even NULs — so `read_line` would corrupt it.
//
// Memory: the runtime allocates an `n+1`-byte buffer (trailing NUL),
// the actual byte count rides the `nurl_last_bytes_len` side-channel.
// This function copies into an OWNED Vec[u] and frees the runtime
// buffer; caller must `( vec_free [u] v )` when done.
@ read_n_bytes i n → ( Vec u ) {
    ? <= n 0 { ^ ( vec_new [u] ) } {}
    // `raw` is auto-dropped at scope exit because nurl_read_n_bytes
    // is registered as `__ret_owned=str`; no manual nurl_free needed.
    : s raw ( nurl_read_n_bytes n )
    : i got ( nurl_last_bytes_len )
    : ( Vec u ) out ( vec_with_cap [u] got )
    : ~ i k 0
    ~ < k got {
        ( vec_push [u] out # u ( nurl_str_get raw k ) )
        = k + k 1
    }
    ^ out
}

@ stdin_eof → b {
    ^ != 0 ( nurl_stdin_eof )
}

@ flush → v {
    ( nurl_flush_stdout )
}

@ eflush → v {
    ( nurl_flush_stderr )
}
