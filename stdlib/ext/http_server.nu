// stdlib/ext/http_server.nu — HTTP/1.1 server with keep-alive
// (Phases 4 + 5 + 5.4 of HTTP_SERVER_PLAN.md).
//
// Layering:
//
//     Caller code  ─┐
//                   │   ( @ HttpResponse HttpRequest )  handler
//                   │
//                   ▼
//             ( server_run s )           ← blocks until listener errors
//                   │
//                   ▼
//             ( server_run_once s )      ← one accept + serve, returns
//                   │
//                   ▼
//      tcp_accept → __serve_keepalive_loop → close
//                       │
//                       ▼   loops while connection alive
//      __read_request_head → handler → __write_response
//
// API (this revision):
//
//   ( server_new TcpListener listener
//                ( @ HttpResponse HttpRequest ) handler ) → HttpServer
//   ( server_new_with_timeout    listener handler i idle_ms )                      → HttpServer
//   ( server_new_full            listener handler i idle_ms i max_keepalive_reqs ) → HttpServer
//   ( server_default_idle_timeout_ms )       → i      30000 ms
//   ( server_default_max_keepalive_requests ) → i     1000
//   ( server_run_once HttpServer s )                     → ! v NetErr
//   ( server_run      HttpServer s )                     → ! v NetErr
//   ( server_run_pool HttpServer s i n_workers )         → ! v NetErr
//   ( server_stop     HttpServer s )                     → v
//
// Memory model:
//
//   * `server_new` MOVES `listener` into the HttpServer. Caller must
//     NOT call `tcp_close_listener` after handing the listener over;
//     the server owns the lifecycle and `server_stop` closes it.
//   * `server_run_once` accepts ONE connection, then serves zero or
//     more HTTP/1.1 requests on it (keep-alive), and closes. Returns
//     Ok(0) on every clean drain, Err(NetClosed) when the listener
//     was stopped, Err(other) on accept-level failures only —
//     per-request write errors close the connection but do not
//     bubble out.
//   * `server_run` repeatedly calls `server_run_once` until any Err.
//     A NetClosed Err (the normal shutdown signal) maps to Ok-return
//     so caller code can distinguish "stopped cleanly" from
//     "infrastructure failed".
//   * Per-request: malformed requests trigger a stock 4xx response
//     and the connection is closed; the listener loop survives.
//   * The handler receives an HttpRequest BORROWED. It must NOT free
//     fields of the request — the server frees the whole request
//     after the handler returns. The handler's returned HttpResponse
//     is OWNED by the server, freed after serialise+write.
//
// Keep-alive policy (Phase 5.4):
//
//   * HTTP/1.1 + no `Connection: close` → connection is reused.
//   * HTTP/1.1 + `Connection: close` (request OR response)  → close.
//   * HTTP/1.0  → close (we do not honour `Connection: keep-alive`
//     opt-in for HTTP/1.0; clients that need keep-alive must speak
//     HTTP/1.1).
//   * After `max_keepalive_requests` reuses on one connection
//     (default 1000), the server forces close — a defence-in-depth
//     cap against a single client monopolising a worker.
//   * The per-conn idle timeout (`tcp_set_timeout`, default 30 s)
//     applies to EVERY recv on the connection — including the wait
//     for the next request between calls. So a connection that
//     idles past the deadline auto-closes, freeing the worker.
//
// Limitations (all addressed in later phases):
//
//   * Pipelining is NOT supported. The buffer used by
//     `__read_request_head` is fresh per request; bytes belonging
//     to a pipelined req2 that already arrived during req1's read
//     are still safely in the kernel socket buffer and are picked
//     up on the next iteration — UNLESS req1's read pulled them
//     into the same Vec[u] chunk, in which case they are silently
//     dropped (rare; nearly all clients wait for req1's response).
//   * Single-threaded per accept loop — concurrency comes from
//     `server_run_pool`'s worker count, which is fixed at startup.
//   * No HTTP/2, no TLS — Phase 9.

$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`

// ── HttpServer struct + lifecycle ─────────────────────────────────────

: HttpServer {
  TcpListener listener
  ( @ HttpResponse HttpRequest ) handler
  i idle_timeout_ms
  i max_keepalive_requests
}

// Default 30 s recv/send timeout per accepted connection — slowloris
// defence comes for free (a client that withholds bytes past the
// deadline triggers tcp_read_chunk → NetClosed → server emits its
// canned 400 / closes the connection). Pass 0 to disable.
@ server_default_idle_timeout_ms → i { ^ 30000 }

// Default cap on keep-alive request reuse per connection. After this
// many requests on a single conn, the server forces `Connection:
// close` and drops the conn. Defence-in-depth — a single misbehaving
// client cannot monopolise one worker forever. Pass 0 to disable
// keep-alive entirely (every connection serves exactly one request,
// matching pre-Phase-5.4 behaviour).
@ server_default_max_keepalive_requests → i { ^ 1000 }

@ server_new TcpListener listener ( @ HttpResponse HttpRequest ) handler → HttpServer {
  ^ @ HttpServer { listener handler ( server_default_idle_timeout_ms ) ( server_default_max_keepalive_requests ) }
}

@ server_new_with_timeout TcpListener listener ( @ HttpResponse HttpRequest ) handler i idle_timeout_ms → HttpServer {
  ^ @ HttpServer { listener handler idle_timeout_ms ( server_default_max_keepalive_requests ) }
}

@ server_new_full TcpListener listener ( @ HttpResponse HttpRequest ) handler i idle_timeout_ms i max_keepalive_requests → HttpServer {
  ^ @ HttpServer { listener handler idle_timeout_ms max_keepalive_requests }
}

@ server_stop HttpServer s → v {
  ( tcp_close_listener . s listener )
}

// ── Read the full request head off the socket ─────────────────────────
//
// Reads in a loop, accumulating bytes in a buffer, until
// `parse_request_head` succeeds or returns a non-Incomplete error.
// On success: any bytes already past the head are transferred into
// the request's body field (so the body reader only needs to top up
// from Content-Length). On socket error or unrecoverable parse error:
// the returned ParsedHead has .ok = F.

@ __read_request_head TcpConn conn → ParsedHead {
  : ( Vec u ) buf ( vec_with_cap [u] 4096 )
  // `result` is a mutable tagged-struct slot. Each assignment must
  // free the previous placeholder first (the ParsedHead returned by
  // `__parsed_head_err` always carries a fresh-empty HttpRequest
  // allocation, so dropping the slot drops a real allocation). The
  // explicit free-before-reassign discipline below keeps ASan clean.
  : ~ ParsedHead result ( __parsed_head_err # HttpReqErr HttpReqIo )
  : ~ b done F

  ~ ! done {
    : ! ( Vec u ) NetErr r ( tcp_read_chunk conn 4096 )
    ?? r {
      T chunk → {
        : i got ( vec_len [u] chunk )
        ( vec_extend [u] buf chunk )
        ( vec_free [u] chunk )
        ? <= got 0 {
          // 0 bytes can't happen (NetClosed is returned as Err) but
          // guard against runtime bugs by exiting.
          ( parsed_head_free result )
          = result ( __parsed_head_err # HttpReqErr HttpReqIo )
          = done T
        } {
          : ParsedHead ph ( parse_request_head buf )
          ? . ph ok {
            // Transfer overlapping body bytes into ph.head.body so
            // read_body's Content-Length path sees them.
            : i used . ph consumed
            : i bn ( vec_len [u] buf )
            ? > bn used {
              : *u bdata ( vec_data [u] buf )
              : HttpRequest req . ph head
              : ~ i k used
              ~ < k bn {
                ( vec_push [u] . req body . bdata k )
                = k + k 1
              }
            } {}
            ( parsed_head_free result )
            = result ph
            = done T
          } {
            // Incomplete = keep reading (drop ph + keep result's
            // current placeholder). Anything else = surface ph and
            // close. We map via the diagnostic name (no enum
            // wildcard support yet).
            : s nm ( http_req_err_name . ph err )
            ? != 0 ( nurl_str_eq nm `HttpReqIncomplete` ) {
              ( parsed_head_free ph )
            } {
              ( parsed_head_free result )
              = result ph
              = done T
            }
          }
        }
      }
      F _ → {
        // NetClosed mid-head OR any transport error → io. The
        // current placeholder is already an HttpReqIo result;
        // re-stamping it via __parsed_head_err would just churn an
        // allocation. Just exit the loop.
        = done T
      }
    }
  }
  ( vec_free [u] buf )
  ^ result
}

// ── Top up body from Content-Length, accounting for pre-loaded bytes ─
//
// `req.body` may already contain bytes that arrived in the same TCP
// segment as the head. Read just the remainder (Content-Length - existing
// length). Returns T on success, F on transport / format error.

@ __finish_body TcpConn conn HttpRequest req → b {
  : ? String cl ( header_get . req headers `Content-Length` )
  ?? cl {
    T clv → {
      : ! i ParseErr nr ( string_to_int clv )
      ( string_free clv )
      ?? nr {
        T clen → {
          ? < clen 0 { ^ F } {}
          : i have ( vec_len [u] . req body )
          ? >= have clen { ^ T } {}
          : i need - clen have
          : ! ( Vec u ) HttpReqErr more ( read_body_to conn req need )
          ?? more {
            T extra → {
              ( vec_extend [u] . req body extra )
              ( vec_free [u] extra )
              ^ T
            }
            F _ → ^ F
          }
        }
        F _ → ^ F
      }
    }
    F _ → ^ T   // No Content-Length: nothing more to read.
  }
}

// ── Write a complete HttpResponse back to the connection ──────────────
//
// When `force_close` is T, ensures `Connection: close` rides on the
// wire (replacing any caller-set value via `response_set_header`'s
// dedup semantics). When F, the Connection header is left untouched —
// HTTP/1.1's keep-alive default applies and the caller may continue
// reading further requests on the same socket.
//
// Frees `r` after serialise+write regardless of outcome.

@ __write_response TcpConn conn HttpResponse r b force_close → ! v NetErr {
  ? force_close {
    ( response_set_header r `Connection` `close` )
  } {}
  : ( Vec u ) wire ( response_serialize r )
  : ! v NetErr wr ( tcp_write_all conn wire )
  ( vec_free [u] wire )
  ( http_response_free r )
  ^ wr
}

// Build a stock 4xx error response for parse failures.
@ __parse_err_response HttpReqErr e → HttpResponse {
  : s nm ( http_req_err_name e )
  ? != 0 ( nurl_str_eq nm `HttpReqTooLarge` ) {
    ^ ( response_text 413 `request entity too large\n` )
  } {}
  ? != 0 ( nurl_str_eq nm `HttpReqUnsupportedVersion` ) {
    ^ ( response_text 505 `HTTP version not supported\n` )
  } {}
  ^ ( response_text 400 `bad request\n` )
}

// ── Connection-header parsing ─────────────────────────────────────────
//
// Case-insensitive ASCII compare between an OWNED String value (as
// returned by header_get) and a NUL-terminated raw `s` literal.
// Lengths must match exactly — `__header_value_eq_ci v "close"`
// returns F for "Close, Upgrade" and any other multi-token value.
// Multi-token Connection headers fall through to "keep-alive" by
// default; this is acceptable for v1 — clients that genuinely want
// a close on a 1.1 connection send the bare token.

@ __header_value_eq_ci String value s lit → b {
  : i la ( string_len value )
  : i lb ( nurl_str_len lit )
  ? != la lb { ^ F } {}
  : ~ i k 0
  ~ < k la {
    : i ca ( string_get value k )
    : i cb ( nurl_str_get lit k )
    ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
    ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
    ? != ca cb { ^ F } {}
    = k + k 1
  }
  ^ T
}

// Returns T if the request asks for the connection to be closed
// after this response. Policy:
//   * non-HTTP/1.1 (any version other than the literal string
//     "HTTP/1.1") → close. We deliberately do not honour
//     `Connection: keep-alive` opt-in for HTTP/1.0 — clients that
//     need persistent connections must speak 1.1.
//   * HTTP/1.1 + bare `Connection: close` value → close.
//   * HTTP/1.1 + missing or other Connection header → keep-alive.
@ __request_says_close HttpRequest req → b {
  : s ver ( string_data . req version )
  ? == 0 ( nurl_str_eq ver `HTTP/1.1` ) { ^ T } {}
  : ? String hv ( header_get . req headers `Connection` )
  ?? hv {
    T value → {
      : b says_close ( __header_value_eq_ci value `close` )
      ( string_free value )
      ^ says_close
    }
    F empty → { ( string_free empty ) ^ F }
  }
}

// Returns T if the response carries `Connection: close`. The handler
// can opt this connection out of keep-alive by setting that header
// explicitly.
@ __response_says_close HttpResponse r → b {
  : ? String hv ( header_get . r headers `Connection` )
  ?? hv {
    T value → {
      : b says_close ( __header_value_eq_ci value `close` )
      ( string_free value )
      ^ says_close
    }
    F empty → { ( string_free empty ) ^ F }
  }
}

// ── server_run_once ──────────────────────────────────────────────────
//
// Single connection lifecycle: accept, then drive the keep-alive
// loop until the conn drains (peer close, idle timeout, explicit
// `Connection: close`, or the per-conn request cap fires). Returns
// Ok(0) for every cleanly-drained connection. Returns Err only when
// `tcp_accept` itself fails — per-request write/parse errors close
// the connection but do not bubble out.

@ server_run_once HttpServer s → ! v NetErr {
  : ! TcpConn NetErr ar ( tcp_accept . s listener )
  ?? ar {
    T conn → {
      : i ito . s idle_timeout_ms
      ? > ito 0 { ( tcp_set_timeout conn ito ) } {}
      ( __serve_keepalive_loop s conn )
      ( tcp_close_conn conn )
      ^ @ ! v NetErr { T 0 }
    }
    F e → ^ @ ! v NetErr { F e }
  }
}

// The per-connection request loop. Walks request → handler →
// response → repeat until any of the following happens:
//
//   * `__read_request_head` fails with HttpReqIo (peer closed
//     cleanly between requests, or the recv timeout fired). No
//     response is written — connection dies silently.
//   * `__read_request_head` fails with any other parse error. We
//     write the canned 4xx response, then close.
//   * `__finish_body` fails. We write a 400, then close.
//   * The request OR response carries `Connection: close`. We write
//     the response (forcing `Connection: close`), then close.
//   * `n_served` reaches `max_keepalive_requests`. Same as the
//     close-after-response path — the cap is defence-in-depth, not
//     a polished policy.
//   * Any `__write_response` returns Err. We close.
//
// The function returns `v` rather than `! v NetErr` because none of
// these per-request errors are interesting at the listener level —
// they all just mean "this connection is done, accept the next one".

@ __serve_keepalive_loop HttpServer s TcpConn conn → v {
  : i max_req . s max_keepalive_requests
  : ~ b done F
  : ~ i n_served 0
  ~ ! done {
    : ParsedHead ph ( __read_request_head conn )
    ? . ph ok {
      : HttpRequest req . ph head
      : b body_ok ( __finish_body conn req )
      ? body_ok {
        : b req_close ( __request_says_close req )
        : ( @ HttpResponse HttpRequest ) f . s handler
        : HttpResponse resp ( f req )
        : b resp_close ( __response_says_close resp )
        = n_served + n_served 1
        : b at_cap ? > max_req 0 >= n_served max_req T
        : b should_close | | req_close resp_close at_cap
        : ! v NetErr wr ( __write_response conn resp should_close )
        ( request_free req )
        ?? wr {
          T _ → {
            ? should_close { = done T } {}
          }
          F _ → { = done T }
        }
      } {
        : HttpResponse er ( response_text 400 `malformed body\n` )
        : ! v NetErr _wr ( __write_response conn er T )
        ( request_free req )
        = done T
      }
    } {
      // Distinguish "peer closed cleanly with no request bytes" from
      // "got bytes but they didn't parse". The former is normal
      // (browser closing an idle keep-alive), the latter deserves a
      // 4xx so the client knows we rejected the syntax.
      : s nm ( http_req_err_name . ph err )
      ? != 0 ( nurl_str_eq nm `HttpReqIo` ) {
        ( parsed_head_free ph )
      } {
        : HttpResponse er ( __parse_err_response . ph err )
        : ! v NetErr _wr ( __write_response conn er T )
        ( parsed_head_free ph )
      }
      = done T
    }
  }
}

// ── server_run ───────────────────────────────────────────────────────
//
// Drive `server_run_once` in a tight loop until the listener stops.
// Returns Ok on a clean stop (NetClosed / NetAccept after
// server_stop), Err on infrastructure failure mid-flight.

@ server_run HttpServer s → ! v NetErr {
  // Loop forever (until either a clean stop or a real error). One
  // NURL compiler quirk still shapes this implementation:
  //   * Multiple early-`^`-returns inside `?? r { T → … F → … }` arms
  //     leave a phi-with-only-undef-incomings dangling before the
  //     loop_exit branch (terminator missing).
  // The structure below works around it: stash a `done` boolean plus
  // a mutable `last_err` enum (now legal after the 2026-05-14 fix to
  // mutable enum bindings) and emit a single Result construction past
  // the loop.
  : ~ b done F
  : ~ b had_err F
  : ~ NetErr last_err NetClosed
  ~ ! done {
    : ! v NetErr r ( server_run_once s )
    ?? r {
      T _ → {}
      F e → {
        : s nm ( net_err_name e )
        ? | != 0 ( nurl_str_eq nm `NetClosed` ) != 0 ( nurl_str_eq nm `NetAccept` ) {
          = done T
        } {
          = last_err e
          = had_err T
          = done T
        }
      }
    }
  }
  ? had_err
    { ^ @ ! v NetErr { F last_err } }
    {}
  ^ @ ! v NetErr { T 0 }
}

// ── server_run_pool — thread-per-worker model ─────────────────────────
//
// Spawn `n_workers` threads, each looping `server_run_once` against the
// shared listener. Both POSIX accept(2) and Win32 accept are thread-
// safe — the kernel hands at most one accepted connection to a single
// caller, so workers do not need a userland mutex around accept.
//
// Shutdown: caller invokes `server_stop s` (typically from another
// thread, e.g. a signal handler or a control endpoint registered as a
// regular route). Closing the listener causes every worker's
// `tcp_accept` to fail with NetClosed / NetAccept; each worker then
// exits its loop. `server_run_pool` joins all workers and returns Ok.
//
// `n_workers <= 1` short-circuits to plain `server_run` (no threads
// spawned, useful when the caller wants a uniform entry-point but
// flips the worker count via config).
//
// Memory model: each worker captures `s` by value. HttpServer is
// `{ TcpListener, ( @ ... ) handler }` — the listener handle is a
// shared kernel FD via the `s raw` pointer; the handler closure is
// shared via the captured (fn_ptr, env_ptr) pair. Concurrent handler
// invocations must guard their own shared state (this layer guarantees
// at-most-N concurrent calls but no synchronisation around them).
//
// Limitations (Phase 5 MVP — addressed in Phase 7/8):
//   * No per-worker idle timeout (slowloris can pin one worker).
//   * Worker pool size is fixed; no backpressure if all workers are
//     stuck on slow handlers (new connections sit in the kernel's
//     accept queue until backlog fills).
//   * No graceful drain — `server_stop` makes accept() fail
//     immediately; a worker mid-request finishes that request, then
//     exits. That's fine but observable as a small lag.
@ server_run_pool HttpServer s i n_workers → ! v NetErr {
  ? <= n_workers 1 { ^ ( server_run s ) } {}

  // Storage for n thread handles, indexed by worker number.
  : s thandles ( nurl_alloc * n_workers 8 )

  // Worker body: identical to server_run's loop, just inlined here so
  // we don't have to make `s` a parameter (closure capture is the
  // simpler shape than a top-level @-fn + manual env build).
  : ( @ v ) worker \ → v {
    : ~ b done F
    ~ ! done {
      : ! v NetErr r ( server_run_once s )
      ?? r {
        T _ → {}
        F e → {
          : s nm ( net_err_name e )
          ? | != 0 ( nurl_str_eq nm `NetClosed` ) != 0 ( nurl_str_eq nm `NetAccept` ) {
            = done T
          } {
            // Any other NetErr is treated as a fatal worker-level
            // failure. Phase 8 will replace this with a per-error
            // policy (continue on transient, exit on listener-level).
            = done T
          }
        }
      }
    }
  }

  : ~ i j 0
  ~ < j n_workers {
    : ! Thread ThreadErr tr ( thread_spawn worker )
    ?? tr {
      T t → {
        : s tp . t raw
        : i traw # i tp
        ( nurl_poke thandles * j 8 traw )
      }
      F _ → {
        // Spawn failure → leave a NULL slot so the join phase skips it.
        ( nurl_poke thandles * j 8 0 )
      }
    }
    = j + j 1
  }

  // Block until every worker exits (i.e. listener was closed by
  // caller via server_stop, or every accept hit a fatal NetErr).
  = j 0
  ~ < j n_workers {
    : i traw ( nurl_peek thandles * j 8 )
    ? != traw 0 {
      : s tp #s traw
      : Thread t @ Thread { tp }
      ( thread_join t )
    } {}
    = j + j 1
  }
  ( nurl_free thandles )
  ^ @ ! v NetErr { T 0 }
}
