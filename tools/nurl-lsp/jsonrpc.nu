// tools/nurl-lsp/jsonrpc.nu — LSP-style framed JSON-RPC over stdio.
//
// The wire format used by the Language Server Protocol (and the
// related Debug Adapter Protocol):
//
//   Content-Length: 123\r\n
//   Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n  (optional)
//   \r\n
//   <exactly 123 bytes of JSON body>
//
// The header section is line-delimited ASCII; the body is opaque
// bytes whose exact length is announced by `Content-Length`. The body
// MAY contain embedded `\n` or even raw NUL bytes (JSON escapes hide
// most of these in practice, but the protocol doesn't promise it), so
// reading the body requires `read_n_bytes` rather than `read_line`.
//
// Surface:
//
//   ( read_message )            → ?Json    None on EOF / malformed framing
//   ( write_message Json j )    → v        serialise + Content-Length + flush
//
// Both routines own their I/O: `read_message` consumes the runtime's
// borrowed line slot and returns an owned Json tree on Some; the
// caller frees the Json with `json_free`. `write_message` flushes
// stdout after each write so the editor sees the message immediately.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`

// ── Header parsing ────────────────────────────────────────────────
//
// LSP headers are case-INSENSITIVE per spec; in practice every client
// sends `Content-Length:` with that exact capitalisation. We accept
// both and ignore other header names.

@ __header_is_content_length s line → b {
    : i n ( nurl_str_len line )
    ? < n 15 { ^ F } {}
    // case-insensitive match against "content-length:"
    : ~ i k 0
    : s want `content-length:`
    ~ < k 15 {
        : i lc ( nurl_str_get line k )
        : i wc ( nurl_str_get want k )
        // upper → lower on the line byte for comparison
        ? & >= lc 65 <= lc 90 { = lc + lc 32 } {}
        ? != lc wc { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Strip leading whitespace then parse the rest as a decimal int.
// Returns -1 on parse error so the caller knows to drop the frame.
@ __header_value_int s line → i {
    : i n ( nurl_str_len line )
    : ~ i k 15  // skip "Content-Length:"
    // skip ASCII whitespace
    ~ & < k n | | == ( nurl_str_get line k ) 32 == ( nurl_str_get line k ) 9 == ( nurl_str_get line k ) 13 {
        = k + k 1
    }
    : ~ i v 0
    : ~ b saw_digit F
    ~ & < k n & >= ( nurl_str_get line k ) 48 <= ( nurl_str_get line k ) 57 {
        = v + * v 10 - ( nurl_str_get line k ) 48
        = saw_digit T
        = k + k 1
    }
    ? saw_digit { ^ v } { ^ - 0 1 }
}

// ── read_message ──────────────────────────────────────────────────
//
// Reads exactly one framed JSON-RPC message from stdin. Returns
// Some(Json) on success, None on EOF or unrecoverable framing error.
// On parse error inside the JSON body, also returns None — the LSP
// spec lets the server reply with a JSON-RPC Parse Error, but for the
// MVP a clean drop + best-effort log to stderr is enough.

@ read_message → ?Json {
    : ~ i clen 0
    : ~ b have_clen F
    : ~ b done F
    // Header loop: read lines until the blank `\r\n\r\n` separator.
    // `read_line` strips the trailing '\n'; per LSP the line then
    // ends with `\r`, which we leave for the matcher to ignore.
    ~ ! done {
        : String line ( read_line )
        : i ll ( string_len line )
        ? ( stdin_eof ) {
            ( string_free line )
            ^ @ ?Json { F ( json_null ) }
        } {}
        // Blank line (or pure "\r") terminates the header block.
        : b is_blank | == ll 0 & == ll 1 == ( string_get line 0 ) 13
        ? is_blank {
            ( string_free line )
            = done T
        } {
            ? ( __header_is_content_length ( string_data line ) ) {
                : i parsed ( __header_value_int ( string_data line ) )
                ? >= parsed 0 {
                    = clen parsed
                    = have_clen T
                } {}
            } {}
            ( string_free line )
        }
    }
    ? ! have_clen {
        ( nurl_eprintln `[lsp] malformed header: Content-Length missing or unparseable` )
        ^ @ ?Json { F ( json_null ) }
    } {}
    // Read the body as exactly `clen` bytes.
    : ( Vec u ) body ( read_n_bytes clen )
    : i got ( vec_len [u] body )
    ? < got clen {
        ( nurl_eprintln `[lsp] short read: body truncated by EOF` )
        ( vec_free [u] body )
        ^ @ ?Json { F ( json_null ) }
    } {}
    // The body bytes are UTF-8 JSON; copy into a NUL-terminated String
    // for the json_parse entry point. JSON itself can't contain a raw
    // NUL outside of strings, and strings with embedded NULs are not
    // valid LSP payloads, so a plain string copy is safe.
    : String src ( string_with_cap got )
    : ~ i k 0
    : *u data ( vec_data [u] body )
    ~ < k got {
        ( string_push_char src # i . data k )
        = k + k 1
    }
    ( vec_free [u] body )
    : !Json ParseErr pr ( json_parse ( string_data src ) )
    ( string_free src )
    ?? pr {
        T j → ^ @ ?Json { T j }
        F _ → {
            ( nurl_eprintln `[lsp] body is not valid JSON` )
            ^ @ ?Json { F ( json_null ) }
        }
    }
}

// ── write_message ─────────────────────────────────────────────────
//
// Serialise `j` to a JSON string, count its bytes, and emit a framed
// message on stdout. Flushes after each frame so the editor sees the
// reply without buffering delay. The caller retains ownership of `j`
// and frees it after this call returns (write_message borrows).

@ write_message Json j → v {
    : String body ( json_stringify j )
    : i n ( string_len body )
    : String hdr ( string_with_cap 32 )
    ( string_push_str hdr `Content-Length: ` )
    ( string_push_str hdr ( nurl_str_int n ) )
    ( string_push_str hdr `\r\n\r\n` )
    ( nurl_print ( string_data hdr ) )
    ( nurl_print ( string_data body ) )
    ( flush )
    ( string_free hdr )
    ( string_free body )
}
