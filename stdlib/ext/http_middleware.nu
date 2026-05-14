// stdlib/ext/http_middleware.nu — HTTP server Phase 8 conveniences:
// access log + Prometheus-style metrics. Pure NURL — sits on top of
// Phase 6 router patterns (handler-wrapping closure combinators) and
// the existing `with_log_requests` / `with_cors_default` helpers in
// `http_router.nu`.
//
// API (this revision):
//
//   ( with_access_log ( @ HttpResponse HttpRequest ) inner )
//                         → ( @ HttpResponse HttpRequest )
//                         (logs NCSA Common Log Format to stderr —
//                          one line per request)
//
//   ( metrics_new )                                   → Metrics
//   ( metrics_free Metrics m )                        → v
//
//   ( with_metrics  Metrics m
//                   ( @ HttpResponse HttpRequest ) inner )
//                         → ( @ HttpResponse HttpRequest )
//
//   ( metrics_handler Metrics m HttpRequest req )     → HttpResponse
//                         (Prometheus text-exposition body, suitable
//                          for `router_get "/metrics"`)
//
// Design notes:
//
//   * `with_access_log` writes one NCSA Common Log Format line to
//     stderr per dispatched request. Format:
//       <method> <path> <status> <body-bytes>
//     This is a deliberate subset: there's no remote-addr in the
//     HttpRequest yet (the listener layer doesn't propagate the peer),
//     no User-Agent column, no timestamp. When `tcp_peer_addr` flows
//     through to the request, this becomes a single-line edit.
//   * `Metrics` is a fixed-shape counter bag — total requests, in-
//     flight, status-class buckets (1xx/2xx/3xx/4xx/5xx). Mutating
//     i64 fields in a struct via direct field-store works in NURL
//     today (no atomics — single-thread or per-worker counters; the
//     thread-pool path needs a Mutex around the same struct).
//   * `metrics_handler` emits Prometheus 0.0.4 text-exposition
//     payload. `# HELP` + `# TYPE` lines first, then sample lines.
//     No external libs, no labels — three counters, one gauge, one
//     histogram-ish (latency_ms_total) covers 90% of "is the server
//     alive and serving 200s" dashboards.

$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── with_access_log ───────────────────────────────────────────────────

@ __status_class i status → i {
  ? & >= status 100 < status 200 { ^ 1 } {}
  ? & >= status 200 < status 300 { ^ 2 } {}
  ? & >= status 300 < status 400 { ^ 3 } {}
  ? & >= status 400 < status 500 { ^ 4 } {}
  ? & >= status 500 < status 600 { ^ 5 } {}
  ^ 0
}

@ with_access_log ( @ HttpResponse HttpRequest ) inner → ( @ HttpResponse HttpRequest ) {
  : ( @ HttpResponse HttpRequest ) wrapped \ HttpRequest req → HttpResponse {
    : i t0 ( monotonic_ns )
    : HttpResponse resp ( inner req )
    : i dt_ns - ( monotonic_ns ) t0
    : i dt_ms / dt_ns 1000000

    ( nurl_eprint `[req] ` )
    ( nurl_eprint ( string_data . req method ) )
    ( nurl_eprint ` ` )
    ( nurl_eprint ( string_data . req path ) )
    ( nurl_eprint ` → ` )
    ( nurl_eprint ( nurl_str_int . resp status ) )
    ( nurl_eprint ` ` )
    ( nurl_eprint ( nurl_str_int ( vec_len [u] . resp body ) ) )
    ( nurl_eprint `B ` )
    ( nurl_eprint ( nurl_str_int dt_ms ) )
    ( nurl_eprint `ms\n` )

    ^ resp
  }
  ^ wrapped
}

// ── Metrics ───────────────────────────────────────────────────────────
//
// Backed by a 10-slot `Vec[i]` so the entire Metrics struct fits in
// a single pointer-handle slot (cheap to pass by value, mutations
// through the inner pointer are observed by every holder of the
// handle). Slot indices:
//
// Historical note: a plain `{ i requests, i in_flight, … }` struct
// used to be impossible because closures captured multi-field structs
// by value — `=` writes inside `with_metrics` would land on a dead
// local copy. The 2026-05-14 fix to mutable multi-field-struct
// captures (`: ~ Metrics m` is now captured by pointer, see
// docs/GOTCHAS.md §2) makes the plain-fields shape viable for new
// code. We keep the Vec[i] shape here because (a) it's already
// shipped, tested, and exposed through `metrics_render` / Prometheus
// exposition, and (b) the handle shape composes cleanly with
// `! T E` and `Vec[Metrics]` without depending on the by-ref-capture
// path.
//
//   0 requests_total       5 status_2xx
//   1 in_flight            6 status_3xx
//   2 bytes_out_total      7 status_4xx
//   3 latency_ms_total     8 status_5xx
//   4 status_1xx           9 errors_total

: Metrics { ( Vec i ) counters }

@ metrics_slot_count → i { ^ 10 }

@ metrics_new → Metrics {
  : ( Vec i ) v ( vec_with_cap [i] 10 )
  : ~ i k 0
  ~ < k 10 {
    ( vec_push [i] v 0 )
    = k + k 1
  }
  ^ @ Metrics { v }
}

@ metrics_free Metrics m → v {
  ( vec_free [i] . m counters )
}

@ __m_inc Metrics m i idx i delta → v {
  : *i data ( vec_data [i] . m counters )
  : i cur . data idx
  ( vec_set [i] . m counters idx + cur delta )
}

@ __m_get Metrics m i idx → i {
  : *i data ( vec_data [i] . m counters )
  ^ . data idx
}

@ metrics_requests_total  Metrics m → i { ^ ( __m_get m 0 ) }
@ metrics_in_flight       Metrics m → i { ^ ( __m_get m 1 ) }
@ metrics_bytes_out_total Metrics m → i { ^ ( __m_get m 2 ) }
@ metrics_latency_ms_total Metrics m → i { ^ ( __m_get m 3 ) }
@ metrics_errors_total    Metrics m → i { ^ ( __m_get m 9 ) }

@ __metrics_record Metrics m i status i bytes i dt_ms → v {
  ( __m_inc m 0 1 )
  ( __m_inc m 2 bytes )
  ( __m_inc m 3 dt_ms )
  : i cls ( __status_class status )
  ? == cls 1 { ( __m_inc m 4 1 ) } {}
  ? == cls 2 { ( __m_inc m 5 1 ) } {}
  ? == cls 3 { ( __m_inc m 6 1 ) } {}
  ? == cls 4 { ( __m_inc m 7 1 ) } {}
  ? == cls 5 { ( __m_inc m 8 1 ) } {}
  ? >= status 500 { ( __m_inc m 9 1 ) } {}
}

@ with_metrics Metrics m ( @ HttpResponse HttpRequest ) inner → ( @ HttpResponse HttpRequest ) {
  : ( @ HttpResponse HttpRequest ) wrapped \ HttpRequest req → HttpResponse {
    ( __m_inc m 1 1 )
    : i t0 ( monotonic_ns )
    : HttpResponse resp ( inner req )
    : i dt_ms / - ( monotonic_ns ) t0 1000000
    ( __m_inc m 1 -1 )
    ( __metrics_record m . resp status ( vec_len [u] . resp body ) dt_ms )
    ^ resp
  }
  ^ wrapped
}

// ── Prometheus text-exposition rendering ──────────────────────────────

@ __push_metric String out s name s help s ty i value → v {
  ( string_push_str out `# HELP ` )
  ( string_push_str out name )
  ( string_push_str out ` ` )
  ( string_push_str out help )
  ( string_push_char out 10 )
  ( string_push_str out `# TYPE ` )
  ( string_push_str out name )
  ( string_push_str out ` ` )
  ( string_push_str out ty )
  ( string_push_char out 10 )
  ( string_push_str out name )
  ( string_push_char out 32 )
  ( string_push_int out value )
  ( string_push_char out 10 )
}

@ __push_status_bucket String out s name s help s code i value → v {
  ( string_push_str out `# HELP ` )
  ( string_push_str out name )
  ( string_push_str out ` ` )
  ( string_push_str out help )
  ( string_push_char out 10 )
  ( string_push_str out `# TYPE ` )
  ( string_push_str out name )
  ( string_push_str out ` counter\n` )
  ( string_push_str out name )
  ( string_push_str out `{class="` )
  ( string_push_str out code )
  ( string_push_str out `"} ` )
  ( string_push_int out value )
  ( string_push_char out 10 )
}

@ metrics_render Metrics m → String {
  : String out ( string_with_cap 1024 )
  ( __push_metric out `nurl_http_requests_total`
                  `Total HTTP requests dispatched` `counter`
                  ( __m_get m 0 ) )
  ( __push_metric out `nurl_http_in_flight`
                  `Currently in-flight HTTP requests` `gauge`
                  ( __m_get m 1 ) )
  ( __push_metric out `nurl_http_bytes_out_total`
                  `Total bytes written to response bodies` `counter`
                  ( __m_get m 2 ) )
  ( __push_metric out `nurl_http_latency_ms_total`
                  `Cumulative dispatcher latency in ms` `counter`
                  ( __m_get m 3 ) )
  ( __push_metric out `nurl_http_errors_total`
                  `Total responses with status >= 500` `counter`
                  ( __m_get m 9 ) )

  // Status-class breakdown — labelled, single metric.
  ( string_push_str out `# HELP nurl_http_responses_class Total responses by status class\n` )
  ( string_push_str out `# TYPE nurl_http_responses_class counter\n` )
  ( string_push_str out `nurl_http_responses_class{class="1xx"} ` )
  ( string_push_int out ( __m_get m 4 ) )
  ( string_push_char out 10 )
  ( string_push_str out `nurl_http_responses_class{class="2xx"} ` )
  ( string_push_int out ( __m_get m 5 ) )
  ( string_push_char out 10 )
  ( string_push_str out `nurl_http_responses_class{class="3xx"} ` )
  ( string_push_int out ( __m_get m 6 ) )
  ( string_push_char out 10 )
  ( string_push_str out `nurl_http_responses_class{class="4xx"} ` )
  ( string_push_int out ( __m_get m 7 ) )
  ( string_push_char out 10 )
  ( string_push_str out `nurl_http_responses_class{class="5xx"} ` )
  ( string_push_int out ( __m_get m 8 ) )
  ( string_push_char out 10 )
  ^ out
}

@ metrics_handler Metrics m HttpRequest req → HttpResponse {
  : String body ( metrics_render m )
  : HttpResponse r ( response_new 200 )
  ( response_set_header r `Content-Type` `text/plain; version=0.0.4; charset=utf-8` )
  ( response_set_body_str r ( string_data body ) )
  ( string_free body )
  ^ r
}
