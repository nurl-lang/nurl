// http2_continuation_flood.nu — live regression for the HTTP/2
// CONTINUATION-flood DoS (CVE-2024-27316 class), over a loopback socket.
//
// A peer opens a HEADERS frame WITHOUT END_HEADERS, then sends a stream
// of CONTINUATION frames that also never set END_HEADERS. Before the fix
// the server appended every CONTINUATION payload to the stream's
// header_block with no cap → unbounded memory growth. Now the
// accumulation is bounded by __h2_max_header_block_bytes (64 KiB); past
// it the server raises a connection error → GOAWAY + close.
//
// We craft the raw frames with h2_write_frame and assert the server
// answers the flood with a GOAWAY rather than swallowing an unbounded
// block. main returns the failure count.
//
// Two things this test used to be loose about, both fixed 2026-09-12:
//
//   * it accepted a read FAILURE as "defended", so a regression that
//     dropped the connection without ever sending a GOAWAY would have
//     passed. A dropped connection is now a failure with its own name.
//   * it sent one CONTINUATION more than the ceiling needs. The server
//     stops reading the moment the block is over budget, so the surplus
//     frame stayed unread in its receive queue — and a close over unread
//     data is a TCP RESET, not a FIN. Linux still hands the application
//     the bytes queued ahead of that reset, Winsock throws them away;
//     that is exactly what made http2_flood_budget.nu flaky on Windows
//     CI, and only the lenient assertion above kept it from surfacing
//     here too. The flood now stops at the first frame that crosses the
//     ceiling, taken from the stdlib constant, and the clean EOF that
//     proves nothing was left behind is asserted rather than assumed.
// requires: live

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
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
                // accumulation the CONTINUATION flood feeds. Keep adding
                // 16000-byte CONTINUATIONs until the accumulated block is
                // over the ceiling — and then stop, so every byte written
                // is a byte the server reads before it bails.
                : i chunk 16000
                : i cap ( _h2_max_header_block_bytes )
                : b _h ( wf conn ( h2_type_headers ) 0 1 ( filler chunk ) )
                : ~ i acc chunk
                : ~ b wok T
                ~ & wok <= acc cap {
                    = wok ( wf conn ( h2_type_continuation ) 0 1 ( filler chunk ) )
                    = acc + acc chunk
                }
                ? wok {} {
                    ( nurl_print `  FAIL CONTINUATION write failed mid-flood\n` )
                    = fails + fails 1
                }
                // The server must answer with a GOAWAY — dropping the
                // connection silently is NOT a defence, it is the outcome
                // a crash would produce too. Read frames, skipping the
                // server's own SETTINGS etc., until the GOAWAY arrives.
                : ~ b defended F
                : ~ b dead F
                : ~ i reads 0
                ~ & ! defended & ! dead < reads 20 {
                    : !H2Frame H2FrameErr rr ( h2_read_frame conn 16384 )
                    ?? rr {
                        T fr → {
                            ? == . fr frame_type ( h2_type_goaway ) { = defended T } {}
                            ( h2_frame_free fr )
                        }
                        F fe → {
                            ( nurl_print `  FAIL connection dropped without GOAWAY: ` )
                            ( nurl_print ( h2_frame_err_name fe ) )
                            ( nurl_print `\n` )
                            = dead T
                        }
                    }
                    = reads + reads 1
                }
                ? dead { = fails + fails 1 } {}
                ? | defended dead {} {
                    ( nurl_print `  FAIL no GOAWAY on CONTINUATION flood\n` )
                    = fails + fails 1
                }
                // Nothing was left unread, so the peer's close must reach
                // us as a clean end-of-stream. A reset here would mean the
                // flood overshot again (see the header).
                ? defended {
                    : !H2Frame H2FrameErr er ( h2_read_frame conn 16384 )
                    ?? er {
                        T fr2 → {
                            ( nurl_print `  FAIL frame after GOAWAY where EOF was due\n` )
                            ( h2_frame_free fr2 )
                            = fails + fails 1
                        }
                        F fe2 → {
                            ?? fe2 {
                                H2FrameReadShort → {}
                                _ → {
                                    ( nurl_print `  FAIL close was a RESET, not a FIN: ` )
                                    ( nurl_print ( h2_frame_err_name fe2 ) )
                                    ( nurl_print `\n` )
                                    = fails + fails 1
                                }
                            }
                        }
                    }
                } {}
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
    : i f ( run )
    ? == f 0 { ( nurl_print `continuation-flood defended\n` ) } {}
    ^ f
}
