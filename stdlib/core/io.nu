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
    : s raw ( nurl_read_all_stdin )
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
