// stdlib/ext/http_full.nu — batteries-included HTTP stack aggregator.
//
// Single-line entry point for callers who want every HTTP module
// shipped through Phases 1–9 in scope at once:
//
//     $ `stdlib/ext/http_full.nu`
//
// After that one include, the following surfaces are available
// without further `$`-directives:
//
//   * Phase 1 / 5 sockets      ─ tcp_listen, tcp_accept, tcp_*    (std/net)
//   * Phase 1 signals          ─ signal_install_shutdown          (std/signal)
//   * Phase 2 request parser   ─ HttpRequest, parse_request_head,
//                                parse_url, parse_query, parse_form_urlencoded,
//                                request_form_pairs               (ext/http_request)
//   * Phase 3 response builder ─ HttpResponse, response_new,
//                                response_text, response_json,
//                                response_set_header (case-insens dedup),
//                                response_add_header (Set-Cookie),
//                                chunked-streaming primitives     (ext/http_response)
//   * Phase 4/5/5.4 server     ─ HttpServer, server_new,
//                                server_run, server_run_pool,
//                                keep-alive loop                  (ext/http_server)
//   * Phase 6 router           ─ Router, router_get/post/...,
//                                router_handle, params_get,
//                                with_log_requests, with_cors_default
//                                                                 (ext/http_router)
//   * Phase 7 static + auth    ─ serve_static, mime_for_ext,
//                                parse_basic_auth, parse_bearer_auth,
//                                request_cookie, response_set_cookie
//                                                                 (ext/http_static, ext/http_auth)
//   * Phase 8 middleware       ─ with_access_log, with_metrics,
//                                metrics_handler, Metrics counters
//                                                                 (ext/http_middleware)
//   * Phase 9 multipart        ─ MultipartPart, parse_multipart_form,
//                                request_multipart_parts          (ext/http_multipart)
//   * Phase 9 WebSocket        ─ ws_is_upgrade, ws_accept_key,
//                                ws_perform_handshake,
//                                ws_read_frame / ws_write_frame,
//                                ws_send_text / _binary / _ping /
//                                _pong / _close,
//                                ws_read_message, ws_serve_messages,
//                                ws_validate_utf8                 (ext/websocket)
//   * HTTP client + JSON       ─ http_get, http_post, http_post_json,
//                                http_put_json                    (ext/http, ext/http_json)
//
// Cost model:
//
//   * Mere PRESENCE of this file in the repo costs ZERO. The compiler
//     never reads it for programs that don't write
//     `$ \`stdlib/ext/http_full.nu\`` — no symbols, no IR, no impact
//     on binary size or build time for unrelated programs.
//
//   * INCLUDING this file pulls every HTTP module's `@`-functions
//     into the program's LLVM IR. LLVM removes some unreferenced
//     functions at -O2 link-time, but NURL emits `@`-functions with
//     `external` linkage so the optimiser cannot aggressively strip
//     across the boundary. Empirically, the canonical `static_server`
//     example built with `http_full.nu` is ~14 KB / ~3.6% larger
//     than the same program built with explicit per-module includes
//     (json.nu + auth + multipart pulled in transitively but unused).
//
// Use the lean per-module includes (e.g. just `$ \`stdlib/ext/http_server.nu\``)
// when:
//   * the binary-size delta matters (e.g. embedded targets,
//     WASM payloads served over the network)
//   * you want a minimal include surface for documentation reasons
//   * the project's style guide pins explicit dependencies per file
//
// Use this aggregator when:
//   * you're prototyping and don't yet know which subsystems you need
//   * you're writing an example or demo where one-line setup is the
//     point
//   * the ~14 KB overhead is irrelevant for the deployment target

$ `stdlib/std/net.nu`
$ `stdlib/std/signal.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_router.nu`
$ `stdlib/ext/http_static.nu`
$ `stdlib/ext/http_auth.nu`
$ `stdlib/ext/http_middleware.nu`
$ `stdlib/ext/http_multipart.nu`
$ `stdlib/ext/websocket.nu`
