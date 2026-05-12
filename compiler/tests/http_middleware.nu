// http_middleware.nu — Phase 8 acceptance test for stdlib/ext/http_middleware.nu.
// Pure offline: no socket, no real timing — Metrics counters are
// driven by hand-built HttpRequest/HttpResponse pairs.
//
// Coverage:
//   * metrics_new initial state (all zero, render emits 6 metric blocks).
//   * with_metrics increments requests_total, status-class buckets,
//     bytes_out_total, errors_total (5xx). in_flight wraps to zero
//     after the inner handler returns.
//   * metrics_handler returns the rendered text body verbatim.
//   * with_access_log composes — wraps inner handler, response passes
//     through unchanged. Stderr goes to a separate stream so stdout
//     stays deterministic.
//
// Notes:
//   * Latency-related metrics are masked to "non-zero or zero" because
//     they depend on `monotonic_ns` which isn't deterministic.
//   * Status counts in the rendered output are exact — they're driven
//     by status codes the test sets.

$ `stdlib/ext/http_middleware.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http.nu`

@ println_str s prefix s value → v {
  ( nurl_print prefix )
  ( nurl_print value )
  ( nurl_print `\n` )
}

@ println_int s prefix i n → v {
  ( nurl_print prefix )
  ( nurl_print ( nurl_str_int n ) )
  ( nurl_print `\n` )
}

@ make_req s method s path → HttpRequest {
  : HttpRequest req ( request_new )
  ( string_push_str . req method method )
  ( string_push_str . req path   path   )
  ^ req
}

@ __is_digit i c → b {
  ^ & >= c 48 <= c 57
}

// Synthetic handler: returns response with status from path's last segment
// (e.g. "/200" → 200, "/404" → 404, "/500" → 500). Body is a static text.
@ canned_handler HttpRequest req → HttpResponse {
  : i n ( string_len . req path )
  : ~ i status 200
  ? >= n 4 {
    : i d2 ( string_get . req path - n 3 )
    : i d1 ( string_get . req path - n 2 )
    : i d0 ( string_get . req path - n 1 )
    ? & ( __is_digit d2 ) & ( __is_digit d1 ) ( __is_digit d0 ) {
      = status + + * - d2 48 100 * - d1 48 10 - d0 48
    } {}
  } {}
  ^ ( response_text status `body bytes here\n` )
}

// ── Initial state of Metrics + render ────────────────────────────────

@ run_metrics_initial → v {
  ( nurl_print `── metrics initial ──\n` )
  : Metrics m ( metrics_new )
  ( println_int `  requests_total=`  ( metrics_requests_total  m ) )
  ( println_int `  in_flight=`       ( metrics_in_flight       m ) )
  ( println_int `  bytes_out_total=` ( metrics_bytes_out_total m ) )
  ( println_int `  errors_total=`    ( metrics_errors_total    m ) )

  : String body ( metrics_render m )
  ( nurl_print ( string_data body ) )
  ( string_free body )
  ( metrics_free m )
}

// ── with_metrics dispatch round ──────────────────────────────────────

@ run_metrics_dispatch → v {
  ( nurl_print `── metrics dispatch ──\n` )
  : Metrics m ( metrics_new )
  : ( @ HttpResponse HttpRequest ) wrapped ( with_metrics m \ HttpRequest req → HttpResponse { ^ ( canned_handler req ) } )

  // Drive 4 dispatches: 200, 200, 404, 500.
  : HttpRequest r1 ( make_req `GET` `/200` )
  : HttpResponse a ( wrapped r1 )
  ( println_int `  a.status=` . a status )
  ( http_response_free a )
  ( request_free r1 )

  : HttpRequest r2 ( make_req `GET` `/200` )
  : HttpResponse b ( wrapped r2 )
  ( http_response_free b )
  ( request_free r2 )

  : HttpRequest r3 ( make_req `GET` `/404` )
  : HttpResponse c ( wrapped r3 )
  ( println_int `  c.status=` . c status )
  ( http_response_free c )
  ( request_free r3 )

  : HttpRequest r4 ( make_req `GET` `/500` )
  : HttpResponse d ( wrapped r4 )
  ( println_int `  d.status=` . d status )
  ( http_response_free d )
  ( request_free r4 )

  ( println_int `  requests_total=`  ( metrics_requests_total  m ) )
  ( println_int `  in_flight=`       ( metrics_in_flight       m ) )
  ( println_int `  errors_total=`    ( metrics_errors_total    m ) )
  ( println_int `  bytes_out_total=` ( metrics_bytes_out_total m ) )
  // Latency depends on monotonic_ns and is non-deterministic — print
  // only "zero or non-zero" so the snapshot is stable on slow CI hosts.
  : i lat ( metrics_latency_ms_total m )
  ? > lat 0 { ( nurl_print `  latency_ms_total>0\n` ) } { ( nurl_print `  latency_ms_total=0\n` ) }
  ( metrics_free m )
}

// ── metrics_handler — single endpoint that wraps render ──────────────

@ run_metrics_handler → v {
  ( nurl_print `── metrics_handler ──\n` )
  : Metrics m ( metrics_new )
  : HttpRequest req ( make_req `GET` `/metrics` )
  : HttpResponse r ( metrics_handler m req )
  ( println_int `  status=` . r status )
  : ? String ct ( header_get . r headers `Content-Type` )
  ?? ct {
    T v → { ( println_str `  content-type=` ( string_data v ) ) ( string_free v ) }
    F e → { ( nurl_print `  content-type missing\n` ) ( string_free e ) }
  }
  ( println_int `  body-bytes=` ( vec_len [u] . r body ) )
  ( http_response_free r )
  ( request_free req )
  ( metrics_free m )
}

// ── with_access_log composition ─────────────────────────────────────

@ run_access_log → v {
  ( nurl_print `── access_log ──\n` )
  : ( @ HttpResponse HttpRequest ) wrapped ( with_access_log \ HttpRequest req → HttpResponse { ^ ( canned_handler req ) } )

  : HttpRequest r1 ( make_req `GET` `/200` )
  : HttpResponse a ( wrapped r1 )
  ( println_int `  a.status=` . a status )
  ( println_int `  a.body=` ( vec_len [u] . a body ) )
  ( http_response_free a )
  ( request_free r1 )

  // Compose: log + metrics in same chain.
  : Metrics m ( metrics_new )
  : ( @ HttpResponse HttpRequest ) chained
        ( with_access_log
            ( with_metrics m
                \ HttpRequest req → HttpResponse { ^ ( canned_handler req ) } ) )
  : HttpRequest r2 ( make_req `POST` `/201` )
  : HttpResponse b ( chained r2 )
  ( println_int `  b.status=` . b status )
  ( http_response_free b )
  ( request_free r2 )
  ( println_int `  m.requests_total=` ( metrics_requests_total m ) )
  ( metrics_free m )
}

// ── main ─────────────────────────────────────────────────────────────

@ main → i {
  ( run_metrics_initial )
  ( run_metrics_dispatch )
  ( run_metrics_handler )
  ( run_access_log )
  ^ 0
}
