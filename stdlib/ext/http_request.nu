// stdlib/ext/http_request.nu — HTTP/1.1 request parser (Phase 2 of
// HTTP_SERVER_PLAN.md). Pure NURL — no socket dependency in the parser
// proper; the body reader (`read_body`) layers on top of `std/net.nu`
// once a TcpConn is available.
//
// The parser operates on a `( Vec u )` byte buffer that the caller
// fills incrementally from the network. `parse_request_head` looks
// for the `\r\n\r\n` separator and either yields a `ParsedHead`
// containing the request line + headers + bytes_consumed, or asks
// for more bytes via `HttpReqIncomplete`.
//
// API (this revision):
//
//   ( percent_decode s in )                 → String        "%20"→" "
//   ( percent_encode s in )                 → String        " "→"%20"
//   ( parse_url s url )                     → UrlSplit     path + query
//                                                          (frees: free
//                                                          path + query)
//   ( parse_query s qs )                    → ( Vec QueryPair )
//   ( query_pairs_free ( Vec QueryPair ) v ) → v
//
// Note on shape: query parameters use a dedicated `QueryPair { String
// key, String value }` struct rather than the generic `Pair[String,
// String]`. This is because the NURL compiler currently doesn't accept
// compound type-args in the `( Vec ( Pair K V ) )` form (return /
// declaration positions invoke `parse_type_paren`, which reads
// type-args one token at a time and never recurses into a nested
// paren). The slice form `[( Pair K V )]` works because
// `parse_type_slice` recurses through `parse_type`. See
// HTTP_SERVER_PLAN.md "Cross-cutting prerequisites" for the
// language-side follow-up.
//
//   ( header_get ( Vec Header ) hs s name ) → ? String     case-insens
//                                                          owned copy
//   ( headers_free ( Vec Header ) hs )      → v            cascades
//
//   ( request_new )                         → HttpRequest  fully empty
//   ( request_free HttpRequest req )        → v            cascades
//   ( parse_request_head ( Vec u ) buf )    → ParsedHead   tagged
//                                                          struct: read
//                                                          .ok, then
//                                                          .head/.consumed
//                                                          or .err.
//   ( parsed_head_free ParsedHead p )       → v
//   ( http_req_err_name HttpReqErr e )      → s            diagnostic
//
//   ( read_body  TcpConn HttpRequest )      → ! ( Vec u ) HttpReqErr
//   ( read_body_to TcpConn HttpRequest i max ) → ! ( Vec u ) HttpReqErr
//
// Memory model:
//
//   * `parse_request_head` BORROWS its input buffer. It allocates a
//     fresh `HttpRequest` (inside ParsedHead) whose String fields and
//     `( Vec Header )` headers are all OWNED — the caller must call
//     `parsed_head_free` (or `request_free` after extracting `.head`)
//     exactly once on the Result-Ok path. The Err arms produced by
//     this parser carry NO live allocation.
//   * `parse_url` returns an OWNED `UrlSplit` whose `path` and `query`
//     are independent owned strings. Free both with `string_free`,
//     or use `url_split_free` for the cascade.
//   * `parse_query` returns an OWNED `( Vec QueryPair )`. Use
//     `query_pairs_free` for the cascade-free.
//   * `percent_*` return OWNED String — caller frees.
//   * `header_get` returns an OWNED String inside the Some arm; free
//     it on the Some path.
//   * `read_body` reads from the socket into a fresh OWNED `( Vec u )`.
//     Caller frees with `( vec_free [u] body )`.
//
// Errors — `HttpReqErr` tags:
//
//   HttpReqMalformed           1   syntax violation in head/body
//   HttpReqTooLarge            2   head > 8 KiB / body > limit /
//                                  too many headers
//   HttpReqUnsupportedVersion  3   not "HTTP/1.0" or "HTTP/1.1"
//   HttpReqIncomplete          4   buffer doesn't yet contain a full head
//   HttpReqIo                  5   transport failure on body read
//
// Limits (constant accessors — adjust at the call site if a downstream
// needs more headroom):
//
//   http_req_head_max_bytes      → 8192
//   http_req_header_max_count    → 100
//   http_req_body_default_max    → 10 MiB

$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/ext/http.nu`

: | HttpReqErr {
    HttpReqMalformed
    HttpReqTooLarge
    HttpReqUnsupportedVersion
    HttpReqIncomplete
    HttpReqIo
}

@ http_req_err_name HttpReqErr e → s {
    ^ ?? e {
        HttpReqMalformed → `HttpReqMalformed`
        HttpReqTooLarge → `HttpReqTooLarge`
        HttpReqUnsupportedVersion → `HttpReqUnsupportedVersion`
        HttpReqIncomplete → `HttpReqIncomplete`
        HttpReqIo → `HttpReqIo`
    }
}

: HttpRequest {
    String method
    String path
    String query
    String version
    ( Vec Header ) headers
    ( Vec u ) body
}

// `parse_request_head` would naturally return `! ParsedHead HttpReqErr`,
// but the NURL `! T E` encoding (`{ i1, i64 }`) only carries `T` values
// that fit in an i64. Multi-field structs like `ParsedHead` can't be
// boxed inline, and the compiler currently emits a wrong `extractvalue`
// for them. The workaround is the tagged-struct pattern below: callers
// branch on `.ok`, then read either `.head` + `.consumed` or `.err`.
// The `head` field is ALWAYS initialised (with empty String / Vec
// handles on the failure path) so a single `parsed_head_free` is safe
// regardless of `ok`. See HTTP_SERVER_PLAN.md "Cross-cutting
// prerequisites" for the language-side follow-up.
: ParsedHead {
    HttpRequest head
    i consumed
    b ok
    HttpReqErr err
}

// Result of `parse_url`: a path/query split. Both fields are owned
// Strings. Use the dedicated struct (rather than `Pair[String,String]`)
// because struct-field types of the form `( Pair String String )` work
// fine but `( Vec ( Pair String String ) )` doesn't parse (see
// HTTP_SERVER_PLAN.md). Keeping a dedicated struct keeps the surface
// uniform with `QueryPair` below.
: UrlSplit {
    String path
    String query
}

@ url_split_free UrlSplit u → v {
    ( string_free . u path )
    ( string_free . u query )
}

// Owned (key, value) pair for query-string parsing. See the module
// header note about why this isn't `Pair[String,String]`.
: QueryPair {
    String key
    String value
}

@ query_pair_free QueryPair p → v {
    ( string_free . p key )
    ( string_free . p value )
}

// ── Internal byte-buffer helpers ──────────────────────────────────────

@ __bbyte ( Vec u ) buf i k → i {
    : ?u got ( vec_get [u] buf k )
    ?? got {
        T b → { ^ # i b }
        F _ → { ^ -1 }
    }
}

// First index in [start..len-3] at which buf contains \r\n\r\n.
@ __find_head_end ( Vec u ) buf i start → i {
    : i n ( vec_len [u] buf )
    ? < n + start 4 { ^ -1 } {}
    : ~ i i start
    : i stop - n 3
    ~ <= i stop {
        : i b0 ( __bbyte buf i )
        ? == b0 13 {
            : i b1 ( __bbyte buf + i 1 )
            : i b2 ( __bbyte buf + i 2 )
            : i b3 ( __bbyte buf + i 3 )
            ? & & == b1 10 == b2 13 == b3 10 { ^ i } {}
        } {}
        = i + i 1
    }
    ^ -1
}

// Copy bytes [from..to) of `buf` into a fresh owned String.
@ __bsubstr ( Vec u ) buf i from i to → String {
    : i n ( vec_len [u] buf )
    : i a ? < from 0 0 from
    : i b ? > to n n to
    ? > a b { = a b } {}
    : i out_n - b a
    : String out ( string_with_cap out_n )
    : ~ i k a
    ~ < k b {
        : i bb ( __bbyte buf k )
        ? >= bb 0 { ( string_push_char out bb ) } {}
        = k + k 1
    }
    ^ out
}

// First index in [from..to) at which `buf` contains the byte `target`.
@ __bindex_byte ( Vec u ) buf i from i to i target → i {
    : ~ i k from
    ~ < k to {
        ? == ( __bbyte buf k ) target { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// First index in [from..to) at which `buf` contains the two-byte
// CRLF sequence. Returns -1 if absent.
@ __bindex_crlf ( Vec u ) buf i from i to → i {
    : i stop - to 1
    : ~ i k from
    ~ < k stop {
        ? == ( __bbyte buf k ) 13 {
            ? == ( __bbyte buf + k 1 ) 10 { ^ k } {}
        } {}
        = k + k 1
    }
    ^ -1
}

// Skip leading OWS (SP=32 / HTAB=9). Returns position of first non-OWS
// byte in [from..to), or `to` if everything was OWS.
@ __skip_ows ( Vec u ) buf i from i to → i {
    : ~ i k from
    ~ < k to {
        : i b ( __bbyte buf k )
        ? & != b 32 != b 9 { ^ k } {}
        = k + k 1
    }
    ^ to
}

// Trim trailing OWS. Returns largest k <= to such that bytes [from..k)
// ends in a non-OWS byte (or `from` if every byte was OWS).
@ __trim_ows_end ( Vec u ) buf i from i to → i {
    : ~ i k to
    ~ > k from {
        : i b ( __bbyte buf - k 1 )
        ? & != b 32 != b 9 { ^ k } {}
        = k - k 1
    }
    ^ from
}

@ __ascii_lower i c → i {
    ? & >= c 65 <= c 90 { ^ + c 32 } {}
    ^ c
}

// Case-insensitive equality between an owned String and a NUL-terminated
// raw `s`. Used by header_get for case-insensitive name lookup.
@ __string_eq_ci String s s raw → b {
    : i la ( string_len s )
    : i lb ( nurl_str_len raw )
    ? != la lb { ^ F } {}
    : ~ i k 0
    ~ < k la {
        : i ca ( __ascii_lower ( string_get s k ) )
        : i cb ( __ascii_lower ( nurl_str_get raw k ) )
        ? != ca cb { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── Limits ────────────────────────────────────────────────────────────

@ http_req_head_max_bytes → i { ^ 8192 }

@ http_req_header_max_count → i { ^ 100 }

@ http_req_body_default_max → i { ^ 10485760 }

// ── Headers helpers ───────────────────────────────────────────────────

@ headers_free ( Vec Header ) hs → v {
    ( vec_free_with [Header] hs \ Header h → v { ( header_free h ) } )
}

// Direct-pointer iteration via `vec_data` + `*Header`. The shorter
// `vec_get [Header]` form would be cleaner but currently miscompiles
// (`# Header 0` default-construction emits `i64 0` into a `%String`
// field). See HTTP_SERVER_PLAN.md "Cross-cutting prerequisites".
@ header_get ( Vec Header ) hs s name → ?String {
    : i n ( vec_len [Header] hs )
    : *Header data ( vec_data [Header] hs )
    : ~ i k 0
    ~ < k n {
        : Header h . data k
        ? ( __string_eq_ci . h name name ) {
            : String copy ( string_from ( string_data . h value ) )
            ^ @ ?String { T copy }
        } {}
        = k + k 1
    }
    ^ @ ?String { F ( string_new ) }
}

// ── HttpRequest lifecycle ─────────────────────────────────────────────

@ request_new → HttpRequest {
    ^ @ HttpRequest {
        ( string_new )
        ( string_new )
        ( string_new )
        ( string_new )
        ( vec_new [Header] )
        ( vec_new [u] )
    }
}

@ request_free HttpRequest req → v {
    ( string_free . req method )
    ( string_free . req path )
    ( string_free . req query )
    ( string_free . req version )
    ( headers_free . req headers )
    ( vec_free [u] . req body )
}

@ parsed_head_free ParsedHead p → v {
    ( request_free . p head )
}

// Convenience constructor for the failure path. Allocates an empty
// HttpRequest so the `head` field is always safely freeable, sets the
// HttpReqErr discriminant, and zeroes `consumed`.
@ __parsed_head_err HttpReqErr e → ParsedHead {
    ^ @ ParsedHead { ( request_new ) 0 F e }
}

// ── Percent codec (RFC 3986 §2.1) ─────────────────────────────────────

@ __hex_val i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}
    ? & >= c 65 <= c 70 { ^ - c 55 } {}
    ? & >= c 97 <= c 102 { ^ - c 87 } {}
    ^ -1
}

@ __hex_digit_lo i n → i {
    : i v & n 15
    ? < v 10 { ^ + 48 v } {}
    ^ + 87 v
}

@ __hex_digit_hi i n → i {
    : i v & 15 / n 16
    ? < v 10 { ^ + 48 v } {}
    ^ + 87 v
}

// Decode `%xx` escapes and `+` -> ' ' substitutions (the form-urlencoded
// convention). Invalid `%xx` sequences are passed through verbatim.
@ percent_decode s in → String {
    : i n ( nurl_str_len in )
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get in k )
        ? == c 37 {
            ? <= + k 2 - n 1 {
                : i hi ( __hex_val ( nurl_str_get in + k 1 ) )
                : i lo ( __hex_val ( nurl_str_get in + k 2 ) )
                ? & >= hi 0 >= lo 0 {
                    ( string_push_char out + * hi 16 lo )
                    = k + k 3
                } {
                    ( string_push_char out c )
                    = k + k 1
                }
            } {
                ( string_push_char out c )
                = k + k 1
            }
        } {
            ? == c 43 {
                ( string_push_char out 32 )
                = k + k 1
            } {
                ( string_push_char out c )
                = k + k 1
            }
        }
    }
    ^ out
}

@ __is_unreserved i c → b {
    ? & >= c 65 <= c 90 { ^ T } {}
    ? & >= c 97 <= c 122 { ^ T } {}
    ? & >= c 48 <= c 57 { ^ T } {}
    ? | | == c 45 == c 95 == c 46 { ^ T } {}
    ? == c 126 { ^ T } {}
    ^ F
}

@ percent_encode s in → String {
    : i n ( nurl_str_len in )
    : String out ( string_with_cap n )
    : ~ i k 0
    ~ < k n {
        : i c & 255 ( nurl_str_get in k )
        ? ( __is_unreserved c ) {
            ( string_push_char out c )
        } {
            ( string_push_char out 37 )
            : i hi ( __hex_digit_hi c )
            : i lo ( __hex_digit_lo c )
            // Switch lowercase hex from __hex_digit_* to uppercase
            // (RFC 3986 §2.1 RECOMMENDED for percent-encoding output).
            ? & >= hi 97 <= hi 102 { = hi - hi 32 } {}
            ? & >= lo 97 <= lo 102 { = lo - lo 32 } {}
            ( string_push_char out hi )
            ( string_push_char out lo )
        }
        = k + k 1
    }
    ^ out
}

// ── URL splitter ──────────────────────────────────────────────────────

@ parse_url s url → UrlSplit {
    : i n ( nurl_str_len url )
    : i q ( nurl_str_find url `?` )
    ? < q 0 {
        : String path ( string_from url )
        : String empty ( string_new )
        ^ @ UrlSplit { path empty }
    } {}
    : String path ( string_with_cap q )
    : ~ i k 0
    ~ < k q {
        ( string_push_char path ( nurl_str_get url k ) )
        = k + k 1
    }
    : i qrest - n - q 1
    : String query ( string_with_cap qrest )
    = k + q 1
    ~ < k n {
        ( string_push_char query ( nurl_str_get url k ) )
        = k + k 1
    }
    ^ @ UrlSplit { path query }
}

// Split a query string into QueryPair entries. Both sides are
// percent-decoded. Empty input → empty Vec. A bare key (`foo&bar=1`)
// yields `QueryPair { "foo", "" }`.
@ parse_query s qs → ( Vec QueryPair ) {
    : ( Vec QueryPair ) out ( vec_new [QueryPair] )
    : i n ( nurl_str_len qs )
    ? == n 0 { ^ out } {}
    : ~ i seg_start 0
    : ~ i k 0
    ~ <= k n {
        : ~ b boundary F
        ? >= k n { = boundary T } {}
        ? & ! boundary == ( nurl_str_get qs k ) 38 { = boundary T } {}
        ? boundary {
            : i seg_len - k seg_start
            ? > seg_len 0 {
                : ~ i eq -1
                : ~ i j seg_start
                ~ < j k {
                    ? == ( nurl_str_get qs j ) 61 { = eq j = j k } {}
                    = j + j 1
                }
                : i key_end ? < eq 0 k eq
                : String key_raw ( string_with_cap - key_end seg_start )
                : String val_raw ( string_with_cap seg_len )
                : ~ i kk seg_start
                ~ < kk key_end {
                    ( string_push_char key_raw ( nurl_str_get qs kk ) )
                    = kk + kk 1
                }
                ? >= eq 0 {
                    = kk + eq 1
                    ~ < kk k {
                        ( string_push_char val_raw ( nurl_str_get qs kk ) )
                        = kk + kk 1
                    }
                } {}
                : String key ( percent_decode ( string_data key_raw ) )
                : String val ( percent_decode ( string_data val_raw ) )
                ( string_free key_raw )
                ( string_free val_raw )
                : QueryPair p @ QueryPair { key val }
                ( vec_push [QueryPair] out p )
            } {}
            = seg_start + k 1
        } {}
        = k + k 1
    }
    ^ out
}

@ query_pairs_free ( Vec QueryPair ) v → v {
    ( vec_free_with [QueryPair] v \ QueryPair p → v { ( query_pair_free p ) } )
}

// ── Internal request-line parts ───────────────────────────────────────
//
// Carried as a plain struct between __parse_request_line and
// parse_request_head so the latter can build a single fresh
// HttpRequest atomically. `ok = F` flags a malformed line; the four
// String fields are still allocated (possibly empty) so the caller
// frees them uniformly.

: ReqLineParts {
    String method
    String path
    String query
    String version
    b ok
}

@ __req_line_parts_free ReqLineParts r → v {
    ( string_free . r method )
    ( string_free . r path )
    ( string_free . r query )
    ( string_free . r version )
}

@ __parse_request_line ( Vec u ) buf i from i line_end → ReqLineParts {
    : i sp1 ( __bindex_byte buf from line_end 32 )
    ? < sp1 0 {
        ^ @ ReqLineParts { ( string_new ) ( string_new ) ( string_new ) ( string_new ) F }
    } {}
    : i sp2 ( __bindex_byte buf + sp1 1 line_end 32 )
    ? < sp2 0 {
        ^ @ ReqLineParts { ( string_new ) ( string_new ) ( string_new ) ( string_new ) F }
    } {}
    ? | | <= sp1 from <= sp2 + sp1 1 <= line_end + sp2 1 {
        ^ @ ReqLineParts { ( string_new ) ( string_new ) ( string_new ) ( string_new ) F }
    } {}

    : String method ( __bsubstr buf from sp1 )
    : String target ( __bsubstr buf + sp1 1 sp2 )
    : String version ( __bsubstr buf + sp2 1 line_end )

    : UrlSplit us ( parse_url ( string_data target ) )
    ( string_free target )

    ^ @ ReqLineParts {
        method
        . us path
        . us query
        version
        T
    }
}

// Walk header lines [from..head_end). Each line is "name: value\r\n".
// On success, returns an owned Vec[Header] and `status = 1`. On
// malformed input → `status = 0`. Too-many headers → `status = 2`.
// Header folding (RFC 7230 §3.2.2) is implemented by appending
// ", " + value to any existing entry with the same case-insensitive
// name. Pair[(Vec Header) i] would be the natural shape but compound
// `[ ( Vec Header ) i ]` type-args aren't supported by the generic
// instantiator (only `[(Pair K V)]` is) — so a small struct.
: ParsedHeaders {
    ( Vec Header ) headers
    i status
}

@ __parse_headers ( Vec u ) buf i from i head_end → ParsedHeaders {
    : ( Vec Header ) hs ( vec_new [Header] )
    : ~ i pos from
    : ~ i status 1  // 1 = ok, 0 = malformed, 2 = too-large
    : ~ b done F
    ~ & ! done == status 1 {
        ? >= pos head_end { = done T } {
            : i nl ( __bindex_crlf buf pos head_end )
            ? < nl 0 { = status 0 = done T } {
                : i name_end ( __bindex_byte buf pos nl 58 )
                ? < name_end 0 { = status 0 = done T } {
                    // Header name: bytes [pos..name_end). Must be non-empty.
                    ? <= name_end pos { = status 0 = done T } {
                        // OWS handling around value: skip leading ws after ':',
                        // trim trailing ws before CRLF.
                        : i v_start ( __skip_ows buf + name_end 1 nl )
                        : i v_end ( __trim_ows_end buf v_start nl )
                        ? > ( vec_len [Header] hs ) ( http_req_header_max_count ) {
                            = status 2 = done T
                        } {
                            : String name ( __bsubstr buf pos name_end )
                            : String value ( __bsubstr buf v_start v_end )
                            // Folding: if a prior header has the same case-insens
                            // name, append ", " + value to its value field. Direct
                            // *Header iteration — see header_get's note re. the
                            // `vec_get [Header]` miscompile.
                            : ~ b folded F
                            : i hcount ( vec_len [Header] hs )
                            : *Header hdata ( vec_data [Header] hs )
                            : ~ i fk 0
                            ~ & ! folded < fk hcount {
                                : Header h . hdata fk
                                ? ( __string_eq_ci . h name ( string_data name ) ) {
                                    ( string_push_str . h value `, ` )
                                    ( string_push_str . h value ( string_data value ) )
                                    = folded T
                                } {}
                                = fk + fk 1
                            }
                            ? folded {
                                ( string_free name )
                                ( string_free value )
                            } {
                                : Header newh @ Header { name value }
                                ( vec_push [Header] hs newh )
                            }
                            = pos + nl 2
                        }
                    }
                }
            }
        }
    }
    ^ @ ParsedHeaders { hs status }
}

// ── parse_request_head ────────────────────────────────────────────────

@ parse_request_head ( Vec u ) buf → ParsedHead {
    : i blen ( vec_len [u] buf )
    : i head_end ( __find_head_end buf 0 )
    ? < head_end 0 {
        ? > blen ( http_req_head_max_bytes ) {
            ^ ( __parsed_head_err # HttpReqErr HttpReqTooLarge )
        } {}
        ^ ( __parsed_head_err # HttpReqErr HttpReqIncomplete )
    } {}
    ? > + head_end 4 ( http_req_head_max_bytes ) {
        ^ ( __parsed_head_err # HttpReqErr HttpReqTooLarge )
    } {}

    : i line_end ( __bindex_crlf buf 0 head_end )
    ? < line_end 0 {
        ^ ( __parsed_head_err # HttpReqErr HttpReqMalformed )
    } {}

    : ReqLineParts rl ( __parse_request_line buf 0 line_end )
    ? ! . rl ok {
        ( __req_line_parts_free rl )
        ^ ( __parsed_head_err # HttpReqErr HttpReqMalformed )
    } {}

    : s vraw ( string_data . rl version )
    : b v10 != 0 ( nurl_str_eq vraw `HTTP/1.0` )
    : b v11 != 0 ( nurl_str_eq vraw `HTTP/1.1` )
    ? ! | v10 v11 {
        ( __req_line_parts_free rl )
        ^ ( __parsed_head_err # HttpReqErr HttpReqUnsupportedVersion )
    } {}

    // `head_end` is the position of the FIRST CRLF in the closing
    // \r\n\r\n — i.e., the trailing CRLF of the last header line. The
    // header parser scans up to (but not including) the empty CRLF,
    // which starts at `head_end + 2`.
    : ParsedHeaders hr ( __parse_headers buf + line_end 2 + head_end 2 )
    : i hstatus . hr status
    ? != hstatus 1 {
        ( __req_line_parts_free rl )
        ( headers_free . hr headers )
        ? == hstatus 2 {
            ^ ( __parsed_head_err # HttpReqErr HttpReqTooLarge )
        } {}
        ^ ( __parsed_head_err # HttpReqErr HttpReqMalformed )
    } {}

    : HttpRequest req @ HttpRequest {
        . rl method
        . rl path
        . rl query
        . rl version
        . hr headers
        ( vec_new [u] )
    }
    ^ @ ParsedHead { req + head_end 4 T # HttpReqErr HttpReqMalformed }
}

// ── Body reader (Phase 2.3) ───────────────────────────────────────────

// Read the request body off `conn` according to the headers already
// captured on `req`. Honours Content-Length and Transfer-Encoding:
// chunked. Caller frees the returned Vec[u] on the Ok arm.
@ read_body TcpConn conn HttpRequest req → !( Vec u ) HttpReqErr {
    ^ ( read_body_to conn req ( http_req_body_default_max ) )
}

@ read_body_to TcpConn conn HttpRequest req i max_bytes → !( Vec u ) HttpReqErr {
    // Transfer-Encoding takes precedence over Content-Length per
    // RFC 7230 §3.3.3 rule 3.
    : ?String te ( header_get . req headers `Transfer-Encoding` )
    ?? te {
        T tev → {
            : String tev_lc ( string_to_lower tev )
            : b is_chunked != 0 ( nurl_str_eq ( string_data tev_lc ) `chunked` )
            ( string_free tev_lc )
            ( string_free tev )
            ? is_chunked {
                ^ ( __read_body_chunked conn max_bytes )
            } {}
            // Anything other than `chunked` is unsupported here — return
            // Malformed so the caller can answer 501. Identity-encoded
            // bodies still need a Content-Length (handled below).
            ^ @ !( Vec u ) HttpReqErr { F # HttpReqErr HttpReqMalformed }
        }
        F _ → {}
    }

    : ?String cl ( header_get . req headers `Content-Length` )
    ?? cl {
        T clv → {
            : !i ParseErr nr ( string_to_int clv )
            ( string_free clv )
            ?? nr {
                T clen → {
                    ? < clen 0 {
                        ^ @ !( Vec u ) HttpReqErr { F # HttpReqErr HttpReqMalformed }
                    } {}
                    ? > clen max_bytes {
                        ^ @ !( Vec u ) HttpReqErr { F # HttpReqErr HttpReqTooLarge }
                    } {}
                    ^ ( __read_n_bytes conn clen )
                }
                F _ → ^ @ !( Vec u ) HttpReqErr { F # HttpReqErr HttpReqMalformed }
            }
        }
        F _ → {}
    }

    // No Content-Length, no Transfer-Encoding: empty body per RFC 7230
    // §3.3.3 rule 6 (request bodies require an explicit length).
    : ( Vec u ) empty ( vec_new [u] )
    ^ @ !( Vec u ) HttpReqErr { T empty }
}

// Drain exactly `n` bytes from `conn` into a fresh Vec[u]. Surfaces
// HttpReqIo on transport failure (caller can inspect the conn's
// err_kind via tcp_set_timeout's recovery path), HttpReqMalformed
// on premature EOF.
@ __read_n_bytes TcpConn conn i n → !( Vec u ) HttpReqErr {
    : ( Vec u ) buf ( vec_with_cap [u] n )
    : ~ i remaining n
    : ~ i status 1  // 1 = ok, 0 = io, 2 = malformed (eof)
    ~ & == status 1 > remaining 0 {
        : i want ? > remaining 4096 4096 remaining
        : !( Vec u ) NetErr r ( tcp_read_chunk conn want )
        ?? r {
            T chunk → {
                : i got ( vec_len [u] chunk )
                ( vec_extend [u] buf chunk )
                ( vec_free [u] chunk )
                = remaining - remaining got
            }
            F e → {
                // NetClosed = clean EOF mid-body → premature truncation
                // (Malformed); anything else (including NetTimeout, which
                // would otherwise spin) → IO error. We map via the diagnostic
                // name to avoid an exhaustive enum match here.
                : s nm ( net_err_name e )
                ? != 0 ( nurl_str_eq nm `NetClosed` ) { = status 2 } { = status 0 }
            }
        }
    }
    ? == status 0 {
        ( vec_free [u] buf )
        ^ @ !( Vec u ) HttpReqErr { F # HttpReqErr HttpReqIo }
    } {}
    ? == status 2 {
        ( vec_free [u] buf )
        ^ @ !( Vec u ) HttpReqErr { F # HttpReqErr HttpReqMalformed }
    } {}
    ^ @ !( Vec u ) HttpReqErr { T buf }
}

// Read a chunked-encoded body off `conn`. We accumulate bytes into a
// scratch Vec[u] and parse chunk headers by scanning for CRLFs. The
// implementation is intentionally simple — every chunk-size line is
// fetched via repeated 1-byte reads, which is fine for low-volume
// request bodies. Streaming bulk uploads should switch to a buffered
// reader once Phase 5 brings in concurrency.
@ __read_body_chunked TcpConn conn i max_bytes → !( Vec u ) HttpReqErr {
    : ( Vec u ) body ( vec_new [u] )
    : ~ i status 1
    : ~ b done F
    ~ & ! done == status 1 {
        : !String HttpReqErr line_r ( __read_crlf_line conn 32 )
        ?? line_r {
            T line → {
                : !i ParseErr sz ( __parse_hex_size line )
                ( string_free line )
                ?? sz {
                    T n → {
                        ? < n 0 { = status 0 = done T } {}
                        ? == n 0 {
                            // Trailer-headers terminator: read an empty line.
                            : !String HttpReqErr trailer ( __read_crlf_line conn 0 )
                            ?? trailer {
                                T t → ( string_free t )
                                F _ → = status 0
                            }
                            = done T
                        } {
                            ? > + ( vec_len [u] body ) n max_bytes {
                                = status 2 = done T
                            } {
                                : !( Vec u ) HttpReqErr cr ( __read_n_bytes conn n )
                                ?? cr {
                                    T chunk → {
                                        ( vec_extend [u] body chunk )
                                        ( vec_free [u] chunk )
                                        // Trailing CRLF after the chunk data.
                                        : !String HttpReqErr eolr ( __read_crlf_line conn 0 )
                                        ?? eolr {
                                            T eol → ( string_free eol )
                                            F _ → = status 0
                                        }
                                    }
                                    F _ → = status 0
                                }
                            }
                        }
                    }
                    F _ → = status 0
                }
            }
            F _ → = status 0
        }
    }
    ? == status 0 {
        ( vec_free [u] body )
        ^ @ !( Vec u ) HttpReqErr { F # HttpReqErr HttpReqMalformed }
    } {}
    ? == status 2 {
        ( vec_free [u] body )
        ^ @ !( Vec u ) HttpReqErr { F # HttpReqErr HttpReqTooLarge }
    } {}
    ^ @ !( Vec u ) HttpReqErr { T body }
}

// Read bytes from `conn` until the next CRLF, returning the line
// without its terminator. `expect_min` is informational — if the
// resulting line is shorter than expect_min, no error is raised
// (the parser handles that). Cap line length at 8192 to defend
// against pathological clients sending an unbounded chunk-size line.
@ __read_crlf_line TcpConn conn i expect_min → !String HttpReqErr {
    : String line ( string_with_cap ? > expect_min 0 expect_min 16 )
    : ~ i status 1
    : ~ b done F
    : ~ i seen 0
    : ~ i prev -1
    ~ & ! done == status 1 {
        ? > seen 8192 { = status 0 = done T } {
            : !( Vec u ) NetErr r ( tcp_read_chunk conn 1 )
            ?? r {
                T chunk → {
                    : i got ( vec_len [u] chunk )
                    ? == got 0 {
                        ( vec_free [u] chunk )
                        = status 0 = done T
                    } {
                        : i b ( __bbyte chunk 0 )
                        ( vec_free [u] chunk )
                        = seen + seen 1
                        ? & == prev 13 == b 10 {
                            // Trim the trailing CR we already pushed.
                            : i ll ( string_len line )
                            ? > ll 0 {
                                : String trimmed ( string_substr line 0 - ll 1 )
                                ( string_free line )
                                = line trimmed
                            } {}
                            = done T
                        } {
                            ( string_push_char line b )
                            = prev b
                        }
                    }
                }
                F _ → = status 0
            }
        }
    }
    ? == status 0 {
        ( string_free line )
        ^ @ !String HttpReqErr { F # HttpReqErr HttpReqIo }
    } {}
    ^ @ !String HttpReqErr { T line }
}

// Parse a chunk-size line: "<hex>[;extension]". Returns the size as
// an i. Negative size or trailing junk → BadFormat.
@ __parse_hex_size String line → !i ParseErr {
    : i n ( string_len line )
    ? == n 0 { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}
    : ~ i acc 0
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        : i c ( string_get line k )
        ? == c 59 { = k n } {
            : i v ( __hex_val c )
            ? < v 0 { = ok F } {
                = acc + * acc 16 v
                = k + k 1
            }
        }
    }
    ? ! ok { ^ @ !i ParseErr { F @ ParseErr { BadFormat } } } {}
    ^ @ !i ParseErr { T acc }
}

// ── Form parsing (application/x-www-form-urlencoded) ─────────────────
//
// Decode a form body in `application/x-www-form-urlencoded` shape. The
// wire syntax is identical to a URL query string ("k1=v1&k2=v2") with
// percent-decoding and `+` → space substitution. We scan the byte buffer
// directly (rather than going via String) so embedded NUL bytes — which
// are technically invalid in form data but might still appear in
// adversarial input — pass through to the decoder verbatim.
//
// Empty input yields an empty `Vec[QueryPair]`. A bare key like
// `foo&bar=1` produces `QueryPair { "foo", "" }`. Caller frees with
// `query_pairs_free`.
@ parse_form_urlencoded ( Vec u ) buf → ( Vec QueryPair ) {
    : ( Vec QueryPair ) out ( vec_new [QueryPair] )
    : i n ( vec_len [u] buf )
    ? == n 0 { ^ out } {}
    : ~ i seg_start 0
    : ~ i k 0
    ~ <= k n {
        : ~ b boundary F
        ? >= k n { = boundary T } {}
        ? & ! boundary == ( __bbyte buf k ) 38 { = boundary T } {}
        ? boundary {
            : i seg_len - k seg_start
            ? > seg_len 0 {
                : ~ i eq -1
                : ~ i j seg_start
                ~ < j k {
                    ? == ( __bbyte buf j ) 61 { = eq j = j k } {}
                    = j + j 1
                }
                : i key_end ? < eq 0 k eq
                : i val_start ? < eq 0 k + eq 1
                : String key_raw ( __bsubstr buf seg_start key_end )
                : String val_raw ( __bsubstr buf val_start k )
                : String key ( percent_decode ( string_data key_raw ) )
                : String val ( percent_decode ( string_data val_raw ) )
                ( string_free key_raw )
                ( string_free val_raw )
                : QueryPair p @ QueryPair { key val }
                ( vec_push [QueryPair] out p )
            } {}
            = seg_start + k 1
        } {}
        = k + k 1
    }
    ^ out
}

// Case-insensitively match a Content-Type media-type prefix. `lc` is
// already lowered; `target` is a NUL-terminated raw-`s` literal in
// canonical lowercase form. Returns T iff `lc` equals `target` exactly
// or starts with `target` followed by `;` or whitespace (so optional
// parameters like `; charset=utf-8` are tolerated).
@ __ct_prefix_eq String lc s target → b {
    : i n ( string_len lc )
    : i tn ( nurl_str_len target )
    ? < n tn { ^ F } {}
    : ~ i k 0
    ~ < k tn {
        ? != ( string_get lc k ) ( nurl_str_get target k ) { ^ F } {}
        = k + k 1
    }
    ? == n tn { ^ T } {}
    : i ch ( string_get lc tn )
    ? | | == ch 59 == ch 32 == ch 9 { ^ T } {}
    ^ F
}

// Convenience: parse the request body as application/x-www-form-urlencoded
// IFF the Content-Type header agrees. Returns Some(pairs) on a match,
// None when the header is missing or names a different media type.
// Caller frees the Some payload with `query_pairs_free`. The None arm
// carries an empty Vec[QueryPair] handle that's safe to free as well —
// pattern-match callers don't need to discriminate the arms when they
// route the result through `query_pairs_free`.
@ request_form_pairs HttpRequest req → ?( Vec QueryPair ) {
    : ?String ct ( header_get . req headers `Content-Type` )
    ?? ct {
        T ctv → {
            : String ctv_lc ( string_to_lower ctv )
            : b is_form ( __ct_prefix_eq ctv_lc `application/x-www-form-urlencoded` )
            ( string_free ctv_lc )
            ( string_free ctv )
            ? is_form {
                : ( Vec QueryPair ) pairs ( parse_form_urlencoded . req body )
                ^ @ ?( Vec QueryPair ) { T pairs }
            } {}
            ^ @ ?( Vec QueryPair ) { F ( vec_new [QueryPair] ) }
        }
        F miss → {
            ( string_free miss )
            ^ @ ?( Vec QueryPair ) { F ( vec_new [QueryPair] ) }
        }
    }
}
