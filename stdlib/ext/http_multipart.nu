// stdlib/ext/http_multipart.nu — multipart/form-data body parser
// (RFC 7578, the file-upload partner of `parse_form_urlencoded`).
// Pure NURL, no runtime / compiler additions.
//
// Rationale: `Phase 7` shipped `parse_form_urlencoded` for the simple
// `application/x-www-form-urlencoded` case. Real browser forms with
// `<input type=file>` elements switch to `multipart/form-data` —
// without this module, a NURL HTTP server cannot accept file uploads.
//
// API (this revision):
//
//   ( parse_multipart_form ( Vec u ) body s boundary )
//                                    → ( Vec MultipartPart )    OWNED
//   ( request_multipart_parts HttpRequest req )
//                                    → ? ( Vec MultipartPart )
//   ( multipart_part_free  MultipartPart p )            → v
//   ( multipart_parts_free ( Vec MultipartPart ) parts ) → v
//   ( multipart_find_first ( Vec MultipartPart ) parts s name ) → i
//                                                          (-1 if absent)
//   ( multipart_count      ( Vec MultipartPart ) parts )  → i
//
// `MultipartPart`:
//
//   String name           field name from Content-Disposition; never None.
//                         Parts without a `name=` parameter are dropped
//                         silently (RFC 7578 §4.2 makes the field
//                         mandatory for HTML form parts).
//   String filename       OWNED — empty String when the part is a plain
//                         field rather than a file upload. The HTML
//                         <input type=file> path always populates this.
//   String content_type   OWNED. `text/plain` when the part omits a
//                         Content-Type header (RFC 7578 §4.4 default).
//   ( Vec u ) data        OWNED part body bytes. For file uploads this
//                         is the raw file contents — may include NUL.
//
// Memory model:
//
//   * `parse_multipart_form` BORROWS both the body Vec and the boundary
//     literal. It returns an OWNED `Vec[MultipartPart]` — caller frees
//     with `multipart_parts_free`.
//   * `request_multipart_parts` does the convenience work: parses the
//     `Content-Type` header, extracts the boundary parameter, and
//     dispatches into `parse_multipart_form`. Returns Some(parts) when
//     the request claims `multipart/form-data` AND a boundary is
//     present; None otherwise. Both arms carry an OWNED Vec safe to
//     pass through `multipart_parts_free`.
//   * Per-part data is COPIED from the body into a fresh `Vec[u]` so
//     callers can keep parts alive past the request's lifetime
//     (typical pattern: stash uploaded files in storage after the
//     handler returns the response).
//
// Best-effort semantics:
//
//   * Empty boundary → returns an empty Vec (mirrors
//     `parse_form_urlencoded`'s tolerance of malformed input).
//   * Body without an opening `--BOUNDARY` marker → empty Vec.
//   * Truncated body (no final `--BOUNDARY--`) → returns whatever
//     parts were already complete; the half-parsed last part is
//     dropped.
//   * A part with no `Content-Disposition: form-data; name=...` is
//     dropped silently. Use `multipart_count` to detect "I expected
//     N parts but only got M" mismatches.
//   * Parts without a `Content-Type` get `text/plain` per RFC 7578.
//
// Limitations (all v1 — refinements possible later):
//
//   * No streaming — the full body must be in memory. The default
//     parser body cap (10 MB) thus caps upload size; tune via the
//     forthcoming configurable-parser-limits work for larger uploads.
//   * No `Content-Transfer-Encoding` decoding (RFC 7578 §4.7 says
//     "SHOULD NOT use" anyway; clients almost never set it).
//   * Quoted boundary parameters (`boundary="my bound"`) are honoured;
//     `boundary` parameters with embedded `;` or escaped quotes are not.

$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`

// ── MultipartPart struct + lifecycle ─────────────────────────────────

: MultipartPart {
  String name
  String filename
  String content_type
  ( Vec u ) data
}

@ multipart_part_free MultipartPart p → v {
  ( string_free . p name )
  ( string_free . p filename )
  ( string_free . p content_type )
  ( vec_free [u] . p data )
}

@ multipart_parts_free ( Vec MultipartPart ) parts → v {
  ( vec_free_with [MultipartPart] parts \ MultipartPart p → v { ( multipart_part_free p ) } )
}

@ multipart_count ( Vec MultipartPart ) parts → i {
  ^ ( vec_len [MultipartPart] parts )
}

// Linear scan returning the first index where the part's `name`
// matches `target` (case-sensitive — form fields keep their wire
// casing). -1 when no part matches. Caller pulls the part out via
// `vec_data [MultipartPart]` + pointer indexing (the multi-field
// `vec_get [MultipartPart]` default-construction path miscompiles —
// see GOTCHAS.md item 4).
@ multipart_find_first ( Vec MultipartPart ) parts s target → i {
  : i n ( vec_len [MultipartPart] parts )
  : *MultipartPart data ( vec_data [MultipartPart] parts )
  : ~ i k 0
  ~ < k n {
    : MultipartPart p . data k
    ? != 0 ( nurl_str_eq ( string_data . p name ) target ) { ^ k } {}
    = k + k 1
  }
  ^ -1
}

// ── Internal byte helpers ────────────────────────────────────────────
//
// We intentionally don't import `__bbyte` / `__bsubstr` from
// http_request.nu — they're already exposed by the `$`-include above,
// no shadowing needed. The helpers below add buffer-substring search
// and bounded CRLF-CRLF detection on top of the existing primitives.

// Find the first byte index `i ∈ [start, vec_len(buf))` where the
// `nlen` bytes at `(needle, nlen)` match `buf[i..i+nlen]`. Returns
// -1 if the needle never occurs at-or-after `start`. Naive O(n*m) —
// fine for the boundary-search workload (boundaries are 30–60 bytes
// and bodies are bounded by the parser's body cap).
@ __find_in_buf ( Vec u ) buf s needle i nlen i start → i {
  ? <= nlen 0 { ^ -1 } {}
  : i n ( vec_len [u] buf )
  ? < start 0 { ^ -1 } {}
  ? > + start nlen n { ^ -1 } {}
  : ~ i i start
  : i stop - n nlen
  ~ <= i stop {
    : ~ b match T
    : ~ i j 0
    ~ & match < j nlen {
      ? != ( __bbyte buf + i j ) ( nurl_str_get needle j ) { = match F } {}
      = j + j 1
    }
    ? match { ^ i } {}
    = i + i 1
  }
  ^ -1
}

// Bounded variant of `__find_head_end`: search for `\r\n\r\n` only
// within `[start, end)`. Nested `?`s avoid the binary-`&` arity
// trap (chaining four conditions through `&` only binds two args
// per operator, see GOTCHAS.md item 1).
@ __find_crlf_crlf_bounded ( Vec u ) buf i start i end → i {
  : i stop - end 3
  : ~ i i start
  ~ <= i stop {
    : i b0 ( __bbyte buf i )
    ? == b0 13 {
      : i b1 ( __bbyte buf + i 1 )
      ? == b1 10 {
        : i b2 ( __bbyte buf + i 2 )
        ? == b2 13 {
          : i b3 ( __bbyte buf + i 3 )
          ? == b3 10 { ^ i } {}
        } {}
      } {}
    } {}
    = i + i 1
  }
  ^ -1
}

// Walk a semicolon-separated parameter list (e.g. the value of
// Content-Type or Content-Disposition) and append the value of the
// parameter named `key` (case-insensitive) into `out`. If the
// parameter is absent, `out` is left untouched. Quoted values
// (`key="value with spaces"`) have their surrounding double-quotes
// stripped — escapes inside the quoted string are NOT honoured
// (acceptable for filenames in practice; pathological clients that
// embed `\"` would need RFC 6266 / 5987 decoding).
@ __extract_param s text s key String out → v {
  : i n ( nurl_str_len text )
  : i klen ( nurl_str_len key )
  : ~ i seg_start 0
  : ~ i k 0
  : ~ b found F
  ~ & ! found <= k n {
    : ~ b at_end F
    ? == k n { = at_end T } {
      ? == ( nurl_str_get text k ) 59 { = at_end T } {}
    }
    ? at_end {
      // Trim leading whitespace from segment.
      : ~ i sp seg_start
      : ~ b sp_done F
      ~ & ! sp_done < sp k {
        : i c ( nurl_str_get text sp )
        ? | == c 32 == c 9 { = sp + sp 1 } { = sp_done T }
      }
      // Locate '=' inside [sp, k).
      : ~ i eq -1
      : ~ i j sp
      ~ & == eq -1 < j k {
        ? == ( nurl_str_get text j ) 61 { = eq j } {}
        = j + j 1
      }
      ? >= eq 0 {
        : i name_len - eq sp
        ? == name_len klen {
          // Case-insensitive name compare.
          : ~ b match T
          : ~ i ci 0
          ~ & match < ci klen {
            : i a ( nurl_str_get text + sp ci )
            : i b ( nurl_str_get key ci )
            ? & >= a 65 <= a 90 { = a + a 32 } {}
            ? & >= b 65 <= b 90 { = b + b 32 } {}
            ? != a b { = match F } {}
            = ci + ci 1
          }
          ? match {
            : ~ i v_start + eq 1
            : ~ i v_end k
            // Strip surrounding double quotes.
            ? & < v_start v_end == ( nurl_str_get text v_start ) 34 {
              = v_start + v_start 1
              ? & < v_start v_end == ( nurl_str_get text - v_end 1 ) 34 {
                = v_end - v_end 1
              } {}
            } {}
            : ~ i copy_i v_start
            ~ < copy_i v_end {
              ( string_push_char out ( nurl_str_get text copy_i ) )
              = copy_i + copy_i 1
            }
            = found T
          } {}
        } {}
      } {}
      = seg_start + k 1
    } {}
    = k + k 1
  }
}

// ── Per-part header parsing ──────────────────────────────────────────
//
// Walks `body[start..end)` line by line (each line ends with CRLF)
// and pulls out:
//   * Content-Disposition's `name`     → name
//   * Content-Disposition's `filename` → filename
//   * Content-Type                     → content_type
// All three String parameters are mutated in place. Lines that don't
// parse are skipped silently (matches the best-effort posture).
@ __parse_part_headers ( Vec u ) body i start i end String name String filename String content_type → v {
  : ~ i line_start start
  : ~ b done F
  ~ ! done {
    ? >= line_start end { = done T } {
      // Find next CRLF in [line_start, end).
      : ~ i nl -1
      : ~ i k line_start
      ~ & == nl -1 < k - end 1 {
        : i b0 ( __bbyte body k )
        ? == b0 13 {
          : i b1 ( __bbyte body + k 1 )
          ? == b1 10 { = nl k } {}
        } {}
        = k + k 1
      }
      ? < nl 0 { = done T } {
        // Empty line ⇒ end of header section (caller bounds prevent
        // running into part data, but be safe).
        ? == nl line_start { = done T } {
          : ~ i colon -1
          : ~ i j line_start
          ~ & == colon -1 < j nl {
            ? == ( __bbyte body j ) 58 { = colon j } {}
            = j + j 1
          }
          ? >= colon 0 {
            : String fname  ( __bsubstr body line_start colon )
            : String fvalue_raw ( __bsubstr body + colon 1 nl )
            : String fvalue ( string_trim fvalue_raw )
            ( string_free fvalue_raw )
            : String fname_lc ( string_to_lower fname )
            : s fname_lc_raw ( string_data fname_lc )
            ? != 0 ( nurl_str_eq fname_lc_raw `content-disposition` ) {
              ( __extract_param ( string_data fvalue ) `name`     name     )
              ( __extract_param ( string_data fvalue ) `filename` filename )
            } {}
            ? != 0 ( nurl_str_eq fname_lc_raw `content-type` ) {
              ( string_push_str content_type ( string_data fvalue ) )
            } {}
            ( string_free fname    )
            ( string_free fname_lc )
            ( string_free fvalue   )
          } {}
          = line_start + nl 2
        }
      }
    }
  }
}

// Build a single MultipartPart from `body[start..end)`. The bytes
// are: header lines (CRLF-terminated), an empty CRLF line, then the
// raw part data. On any parse failure (no CRLF-CRLF separator, no
// `name=` parameter), returns a part with an empty `name` String —
// the high-level walker filters those out.
@ __build_part ( Vec u ) body i start i end → MultipartPart {
  : i hsep ( __find_crlf_crlf_bounded body start end )
  : String name         ( string_new )
  : String filename     ( string_new )
  : String content_type ( string_new )

  ? < hsep 0 {
    // No header separator within the part bytes. Return a sentinel
    // empty-name part with empty data so the caller's free path is
    // uniform. RFC 7578 says "SHOULD" have a Content-Disposition;
    // missing the entire header block is malformed enough to drop.
    : ( Vec u ) empty_data ( vec_new [u] )
    ^ @ MultipartPart { name filename content_type empty_data }
  } {}

  // Pass `hsep + 2` so the parser sees the CRLF that terminates the
  // LAST header line — without it, that line has no CRLF inside the
  // sliced range and the line-based scan misses it entirely.
  ( __parse_part_headers body start + hsep 2 name filename content_type )

  // Default content type per RFC 7578 §4.4.
  ? == 0 ( string_len content_type ) {
    ( string_push_str content_type `text/plain` )
  } {}

  // Part data spans [hsep+4, end).
  : i data_start + hsep 4
  : i data_len ? > end data_start - end data_start 0
  : ( Vec u ) data ( vec_with_cap [u] data_len )
  : ~ i k data_start
  ~ < k end {
    : i bb ( __bbyte body k )
    ? >= bb 0 { ( vec_push [u] data # u bb ) } {}
    = k + k 1
  }

  ^ @ MultipartPart { name filename content_type data }
}

// ── parse_multipart_form ─────────────────────────────────────────────

@ parse_multipart_form ( Vec u ) body s boundary → ( Vec MultipartPart ) {
  : ( Vec MultipartPart ) parts ( vec_new [MultipartPart] )
  : i blen ( nurl_str_len boundary )
  ? <= blen 0 { ^ parts } {}
  : i n ( vec_len [u] body )
  ? <= n 0 { ^ parts } {}

  // Marker = "--" + boundary; inner = "\r\n" + marker.
  : String marker ( string_with_cap + 2 blen )
  ( string_push_str marker `--` )
  ( string_push_str marker boundary )
  : i mlen ( string_len marker )

  : String inner ( string_with_cap + 4 blen )
  ( string_push_str inner `\r\n--` )
  ( string_push_str inner boundary )
  : i ilen ( string_len inner )

  // Find the opening boundary marker. Per RFC 2046, the body MAY have
  // a "preamble" before this — anything up to (and not including) the
  // first `--BOUNDARY` is ignored.
  : i first ( __find_in_buf body ( string_data marker ) mlen 0 )
  ? < first 0 {
    ( string_free marker )
    ( string_free inner )
    ^ parts
  } {}

  : ~ i pos + first mlen
  : ~ b done F

  ~ ! done {
    // Two bytes immediately after the boundary identify what's next:
    //   * "--"   ⇒ closing terminator, stop.
    //   * "\r\n" ⇒ part headers + data follow.
    ? > + pos 1 - n 1 { = done T } {
      : i a ( __bbyte body pos )
      : i b ( __bbyte body + pos 1 )
      ? & == a 45 == b 45 {
        // Final boundary "--BOUNDARY--" — graceful termination.
        = done T
      } {
        ? & == a 13 == b 10 {
          = pos + pos 2
          : i next_b ( __find_in_buf body ( string_data inner ) ilen pos )
          ? < next_b 0 {
            // Truncated body: no closing boundary. Drop the half-
            // parsed tail and stop.
            = done T
          } {
            : MultipartPart p ( __build_part body pos next_b )
            ? > ( string_len . p name ) 0 {
              ( vec_push [MultipartPart] parts p )
            } {
              ( multipart_part_free p )
            }
            = pos + next_b ilen
          }
        } {
          // Junk after the boundary marker (not "--", not "\r\n").
          // Bail without raising — best-effort posture.
          = done T
        }
      }
    }
  }

  ( string_free marker )
  ( string_free inner )
  ^ parts
}

// ── request_multipart_parts ──────────────────────────────────────────

// Extract the `boundary` parameter from a Content-Type header value.
// Returns an OWNED String — empty when the header doesn't claim
// `multipart/form-data` or doesn't carry a `boundary=` parameter.
@ __extract_boundary s ct → String {
  : String out ( string_new )
  : i n ( nurl_str_len ct )
  ? <= n 0 { ^ out } {}

  // Locate the first ';' — everything before it is the media type.
  : ~ i semi -1
  : ~ i k 0
  ~ & == semi -1 < k n {
    ? == ( nurl_str_get ct k ) 59 { = semi k } {}
    = k + k 1
  }

  : i mt_end ? < semi 0 n semi
  : String mt_raw ( __subraw_trim ct 0 mt_end )
  : String mt_lc ( string_to_lower mt_raw )
  ( string_free mt_raw )
  : b is_mp != 0 ( nurl_str_eq ( string_data mt_lc ) `multipart/form-data` )
  ( string_free mt_lc )
  ? ! is_mp { ^ out } {}
  ? < semi 0 { ^ out } {}

  : String params_raw ( __subraw_trim ct + semi 1 n )
  ( __extract_param ( string_data params_raw ) `boundary` out )
  ( string_free params_raw )
  ^ out
}

// Trim ASCII spaces / tabs from a slice of a raw `s`. Used for the
// media-type and parameter halves of a Content-Type header.
@ __subraw_trim s text i from i to → String {
  : i a ? < from 0 0 from
  : i b ? > to ( nurl_str_len text ) ( nurl_str_len text ) to
  ~ < a b {
    : i c ( nurl_str_get text a )
    ? | == c 32 == c 9 { = a + a 1 } { ^ ( __subraw_copy text a b ) }
  }
  ^ ( __subraw_copy text a b )
}

@ __subraw_copy s text i from i to → String {
  : i a ? < from 0 0 from
  : i b ? > to ( nurl_str_len text ) ( nurl_str_len text ) to
  : i len ? > b a - b a 0
  : String out ( string_with_cap len )
  : ~ i k a
  ~ < k b {
    : i c ( nurl_str_get text k )
    // Trim trailing whitespace by stopping early when k is past last
    // non-space char. Cheap second pass: re-check tail per char.
    ? & == k - b 1 | == c 32 == c 9 { = k b } {
      ( string_push_char out c )
    }
    = k + k 1
  }
  ^ out
}

@ request_multipart_parts HttpRequest req → ? ( Vec MultipartPart ) {
  : ? String ct ( header_get . req headers `Content-Type` )
  ?? ct {
    T ctv → {
      : String boundary ( __extract_boundary ( string_data ctv ) )
      ( string_free ctv )
      ? > ( string_len boundary ) 0 {
        : ( Vec MultipartPart ) parts ( parse_multipart_form . req body ( string_data boundary ) )
        ( string_free boundary )
        ^ @ ? ( Vec MultipartPart ) { T parts }
      } {}
      ( string_free boundary )
      ^ @ ? ( Vec MultipartPart ) { F ( vec_new [MultipartPart] ) }
    }
    F miss → {
      ( string_free miss )
      ^ @ ? ( Vec MultipartPart ) { F ( vec_new [MultipartPart] ) }
    }
  }
}
