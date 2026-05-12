// http_multipart.nu — Phase 9 acceptance test for
// stdlib/ext/http_multipart.nu. Builds synthetic multipart bodies
// in-memory, parses them, and prints structured snapshots for
// golden-baseline diffing. No socket, no curl, no fs — runs
// unconditionally (matches `http_*` exemption alongside
// http_request_parser / http_response_builder).

$ `stdlib/ext/http_multipart.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// Append a raw `s` literal to `out` byte-for-byte. (`bytes_extend_str`
// from std/bytes.nu does exactly this — keeping the alias here for
// readability inside body builders.)
@ push_str ( Vec u ) out s text → v {
  ( bytes_extend_str out text )
}

// Print a Vec[u] as ASCII with non-printable bytes shown as `[NN]`
// hex pairs — the part-data field can contain arbitrary binary, so
// we need a deterministic snapshot format.
@ dump_data ( Vec u ) bytes → v {
  : i n ( vec_len [u] bytes )
  : *u data ( vec_data [u] bytes )
  : ~ i k 0
  ~ < k n {
    : u byte . data k
    : i ib # i byte
    ? & >= ib 32 < ib 127 {
      : String tmp ( string_with_cap 1 )
      ( string_push_char tmp ib )
      ( nurl_print ( string_data tmp ) )
      ( string_free tmp )
    } {
      ( nurl_print `[` )
      ( nurl_print ( nurl_str_int ib ) )
      ( nurl_print `]` )
    }
    = k + k 1
  }
}

@ dump_part ( Vec MultipartPart ) parts i k → v {
  : *MultipartPart data ( vec_data [MultipartPart] parts )
  : MultipartPart p . data k
  ( nurl_print `  [` )
  ( nurl_print ( nurl_str_int k ) )
  ( nurl_print `] name=` )
  ( nurl_print ( string_data . p name ) )
  ( nurl_print ` filename=` )
  : i fnlen ( string_len . p filename )
  ? > fnlen 0 {
    ( nurl_print ( string_data . p filename ) )
  } {
    ( nurl_print `<none>` )
  }
  ( nurl_print ` ct=` )
  ( nurl_print ( string_data . p content_type ) )
  ( nurl_print ` data=` )
  ( dump_data . p data )
  ( nurl_print `\n` )
}

@ run_case s label ( Vec u ) body s boundary → v {
  ( nurl_print `── ` ) ( nurl_print label ) ( nurl_print ` ──\n` )
  : ( Vec MultipartPart ) parts ( parse_multipart_form body boundary )
  : i n ( multipart_count parts )
  ( nurl_print `  count=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
  : ~ i k 0
  ~ < k n {
    ( dump_part parts k )
    = k + k 1
  }
  ( multipart_parts_free parts )
}

// ── Body builders ────────────────────────────────────────────────────

// A canonical two-text-field form:
//
//     ------B
//     Content-Disposition: form-data; name="username"
//
//     alice
//     ------B
//     Content-Disposition: form-data; name="role"
//
//     admin
//     ------B--
@ build_two_text_fields → ( Vec u ) {
  : ( Vec u ) b ( vec_with_cap [u] 256 )
  ( push_str b `------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="username"\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `alice` )
  ( push_str b `\r\n------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="role"\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `admin` )
  ( push_str b `\r\n------B--\r\n` )
  ^ b
}

// A file-upload mix: text field + binary file with explicit MIME.
//
//     ------B
//     Content-Disposition: form-data; name="title"
//
//     hello
//     ------B
//     Content-Disposition: form-data; name="upload"; filename="hi.bin"
//     Content-Type: application/octet-stream
//
//     <bytes 0..3>
//     ------B--
@ build_file_upload → ( Vec u ) {
  : ( Vec u ) b ( vec_with_cap [u] 256 )
  ( push_str b `------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="title"\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `hello` )
  ( push_str b `\r\n------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="upload"; filename="hi.bin"\r\n` )
  ( push_str b `Content-Type: application/octet-stream\r\n` )
  ( push_str b `\r\n` )
  ( vec_push [u] b # u 0 )
  ( vec_push [u] b # u 1 )
  ( vec_push [u] b # u 2 )
  ( vec_push [u] b # u 3 )
  ( push_str b `\r\n------B--\r\n` )
  ^ b
}

// Header with junk preamble before the first boundary — RFC 2046
// says we ignore the preamble.
@ build_with_preamble → ( Vec u ) {
  : ( Vec u ) b ( vec_with_cap [u] 256 )
  ( push_str b `This is the preamble — should be ignored.\r\n` )
  ( push_str b `------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="x"\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `42` )
  ( push_str b `\r\n------B--\r\n` )
  ^ b
}

// Truncated body — no final closing boundary. Best-effort returns
// whatever was parsed before the cut.
@ build_truncated → ( Vec u ) {
  : ( Vec u ) b ( vec_with_cap [u] 256 )
  ( push_str b `------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="ok"\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `parsed` )
  ( push_str b `\r\n------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="dropped"\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `never reached` )
  // No closing "\r\n------B--\r\n".
  ^ b
}

// Part that omits Content-Disposition entirely — should be dropped
// silently.
@ build_no_disposition → ( Vec u ) {
  : ( Vec u ) b ( vec_with_cap [u] 256 )
  ( push_str b `------B\r\n` )
  ( push_str b `X-Custom: nothing useful\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `bogus` )
  ( push_str b `\r\n------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="kept"\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `survives` )
  ( push_str b `\r\n------B--\r\n` )
  ^ b
}

// Part with a filename but no Content-Type — should default to
// text/plain per RFC 7578 §4.4.
@ build_default_ct → ( Vec u ) {
  : ( Vec u ) b ( vec_with_cap [u] 256 )
  ( push_str b `------B\r\n` )
  ( push_str b `Content-Disposition: form-data; name="readme"; filename="readme.txt"\r\n` )
  ( push_str b `\r\n` )
  ( push_str b `txt body` )
  ( push_str b `\r\n------B--\r\n` )
  ^ b
}

// ── request_multipart_parts ─ build a synthetic HttpRequest and run ──

@ make_multipart_req s ct ( Vec u ) body → HttpRequest {
  : HttpRequest req ( request_new )
  ( vec_push [Header] . req headers ( header_new `Content-Type` ct ) )
  ( vec_extend [u] . req body body )
  ^ req
}

@ run_request_case s label s ct ( Vec u ) body → v {
  ( nurl_print `── request: ` ) ( nurl_print label ) ( nurl_print ` ──\n` )
  : HttpRequest req ( make_multipart_req ct body )
  : ? ( Vec MultipartPart ) opt ( request_multipart_parts req )
  ?? opt {
    T parts → {
      ( nurl_print `  some=T count=` ) ( nurl_print ( nurl_str_int ( multipart_count parts ) ) ) ( nurl_print `\n` )
      : i n ( multipart_count parts )
      : ~ i k 0
      ~ < k n {
        ( dump_part parts k )
        = k + k 1
      }
      ( multipart_parts_free parts )
    }
    F empty → {
      ( nurl_print `  some=F\n` )
      ( multipart_parts_free empty )
    }
  }
  ( request_free req )
}

// ── multipart_find_first ─────────────────────────────────────────────

@ run_find_first → v {
  ( nurl_print `── multipart_find_first ──\n` )
  : ( Vec u ) body ( build_two_text_fields )
  : ( Vec MultipartPart ) parts ( parse_multipart_form body `----B` )
  ( vec_free [u] body )
  ( nurl_print `  username=` ) ( nurl_print ( nurl_str_int ( multipart_find_first parts `username` ) ) ) ( nurl_print `\n` )
  ( nurl_print `  role=`     ) ( nurl_print ( nurl_str_int ( multipart_find_first parts `role`     ) ) ) ( nurl_print `\n` )
  ( nurl_print `  missing=`  ) ( nurl_print ( nurl_str_int ( multipart_find_first parts `missing`  ) ) ) ( nurl_print `\n` )
  ( multipart_parts_free parts )
}

@ main → i {
  : ( Vec u ) b1 ( build_two_text_fields )
  ( run_case `two_text_fields` b1 `----B` )
  ( vec_free [u] b1 )

  : ( Vec u ) b2 ( build_file_upload )
  ( run_case `file_upload` b2 `----B` )
  ( vec_free [u] b2 )

  : ( Vec u ) b3 ( build_with_preamble )
  ( run_case `with_preamble` b3 `----B` )
  ( vec_free [u] b3 )

  : ( Vec u ) b4 ( build_truncated )
  ( run_case `truncated` b4 `----B` )
  ( vec_free [u] b4 )

  : ( Vec u ) b5 ( build_no_disposition )
  ( run_case `no_disposition` b5 `----B` )
  ( vec_free [u] b5 )

  : ( Vec u ) b6 ( build_default_ct )
  ( run_case `default_ct` b6 `----B` )
  ( vec_free [u] b6 )

  // Empty boundary
  : ( Vec u ) b7 ( vec_new [u] )
  ( push_str b7 `whatever` )
  ( run_case `empty_boundary` b7 `` )
  ( vec_free [u] b7 )

  // Bogus body without any boundary marker
  : ( Vec u ) b8 ( vec_new [u] )
  ( push_str b8 `not multipart at all\r\n` )
  ( run_case `no_marker` b8 `----B` )
  ( vec_free [u] b8 )

  // request_multipart_parts cases
  : ( Vec u ) bb ( build_two_text_fields )
  ( run_request_case `match` `multipart/form-data; boundary=----B` bb )
  ( vec_free [u] bb )

  : ( Vec u ) bb2 ( build_two_text_fields )
  ( run_request_case `quoted` `multipart/form-data; boundary="----B"` bb2 )
  ( vec_free [u] bb2 )

  : ( Vec u ) bb3 ( build_two_text_fields )
  ( run_request_case `case` `Multipart/Form-Data; Boundary=----B` bb3 )
  ( vec_free [u] bb3 )

  : ( Vec u ) bb4 ( build_two_text_fields )
  ( run_request_case `with_charset` `multipart/form-data; charset=utf-8; boundary=----B` bb4 )
  ( vec_free [u] bb4 )

  : ( Vec u ) bb5 ( build_two_text_fields )
  ( run_request_case `wrong_ct` `application/json` bb5 )
  ( vec_free [u] bb5 )

  : ( Vec u ) bb6 ( build_two_text_fields )
  ( run_request_case `no_boundary` `multipart/form-data` bb6 )
  ( vec_free [u] bb6 )

  ( run_find_first )

  ^ 0
}
