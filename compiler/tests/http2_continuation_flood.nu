// http2_continuation_flood.nu — live regression for the HTTP/2
// CONTINUATION-flood DoS (CVE-2024-27316 class), gated NURL_NET_TESTS=1.
//
// A peer opens a HEADERS frame WITHOUT END_HEADERS, then sends a stream
// of CONTINUATION frames that also never set END_HEADERS. Before the fix
// the server appended every CONTINUATION payload to the stream's
// header_block with no cap → unbounded memory growth. Now the
// accumulation is bounded by __h2_max_header_block_bytes (64 KiB); past
// it the server raises a connection error → GOAWAY + close.
//
// We craft the raw frames with h2_write_frame and assert the server
// answers the flood with a GOAWAY (or closes) rather than swallowing an
// unbounded block. main returns the failure count.

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_frame.nu`
$ `stdlib/ext/http2_server.nu`

& `libc` @ nurl_tcp_connect s host i port → i

@ flood_handler HttpRequest req → HttpResponse {
    ^ ( response_text 200 `ok` )
}

@ filler i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] v # u 0 )
        = k + k 1
    }
    ^ v
}

// Write one frame; returns T on success. CONSUMES `payload`.
@ wf TcpConn conn i ftype i flags i sid ( Vec u ) payload → b {
    : H2Frame f @ H2Frame { ftype flags sid payload }
    : !v H2FrameErr r ( h2_write_frame conn f 16384 )
    ( h2_frame_free f )
    ^ ?? r { T _ → T F _ → F }
}

@ run → i {
    : ~ i fails 0
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18824 )
    ?? lr {
        T listener → {
            : ( @ v ) server_fn \ → v {
                : !TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → {
                        : !v H2ConnErr sr ( http2_serve conn \ HttpRequest req → HttpResponse { ^ ( flood_handler req ) } )
                        ?? sr { T _ → {} F _ → {} }
                        ( tcp_close_conn conn )
                    }
                    F _ → {}
                }
            }
            : !Thread ThreadErr st ( thread_spawn server_fn )
            ( sleep_ms 100 )

            : i craw ( nurl_tcp_connect `127.0.0.1` 18824 )
            : i cek ( nurl_tcp_err_kind craw )
            ? != cek 0 {
                ( nurl_print `  FAIL connect\n` ) = fails + fails 1
            } {
                : TcpConn conn @ TcpConn { # s craw }
                ( tcp_set_timeout conn 3000 )
                : !v H2FrameErr pf ( h2_write_preface conn )
                ?? pf { T _ → {} F _ → {} }
                // Client SETTINGS (empty) — required first frame (§3.4).
                : b _s ( wf conn ( h2_type_settings ) 0 0 ( vec_new [u] ) )
                // HEADERS on stream 1, NO END_HEADERS → opens an
                // accumulation the CONTINUATION flood feeds.
                : b _h ( wf conn ( h2_type_headers ) 0 1 ( filler 16000 ) )
                // 5 × 16000 + 16000 = 96 KiB > the 64 KiB cap.
                : ~ i c 0
                : ~ b wok T
                ~ & wok < c 5 {
                    = wok ( wf conn ( h2_type_continuation ) 0 1 ( filler 16000 ) )
                    = c + c 1
                }
                // The server must answer with GOAWAY (or close) — it must
                // NOT keep accepting an unbounded block. Read frames,
                // skipping the server's own SETTINGS etc., until GOAWAY or
                // the connection drops.
                : ~ b defended F
                : ~ i reads 0
                ~ & ! defended < reads 20 {
                    : !H2Frame H2FrameErr rr ( h2_read_frame conn 16384 )
                    ?? rr {
                        T fr → {
                            ? == . fr frame_type ( h2_type_goaway ) { = defended T } {}
                            ( h2_frame_free fr )
                        }
                        F _ → { = defended T }
                    }
                    = reads + reads 1
                }
                ? defended {} {
                    ( nurl_print `  FAIL no GOAWAY/close on CONTINUATION flood\n` )
                    = fails + fails 1
                }
                ( tcp_close_conn conn )
            }
            : i _sj ?? st { T th → ( thread_join th ) F _ → 0 }
            ( tcp_close_listener listener )
        }
        F _ → { ( nurl_print `  FAIL listen\n` ) = fails + fails 1 }
    }
    ^ fails
}

@ main → i {
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            : i f ( run )
            ? == f 0 { ( nurl_print `continuation-flood defended\n` ) } {}
            ^ f
        }
        F → { ( nurl_print `http2_continuation_flood skipped (NURL_NET_TESTS != 1)\n` ) ^ 0 }
    }
}
