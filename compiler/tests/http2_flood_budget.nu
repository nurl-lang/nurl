// http2_flood_budget.nu — live regression for the HTTP/2 flood budgets
// (RFC 9113 §10.5), the CVE-2023-44487 Rapid Reset class.
//
// Before the fix a peer could send RST_STREAM (and PING / SETTINGS /
// PRIORITY / empty DATA) frames without limit: each one costs the server
// a frame read + work, and the handler even ran to completion before the
// RST was observed, so a reset stream still did full work. There was no
// GOAWAY, no ENHANCE_YOUR_CALM, no ceiling.
//
// Now three per-connection counters (streams_opened, peer_resets,
// idle_frames) each have an absolute ceiling; crossing one is answered
// with GOAWAY(ENHANCE_YOUR_CALM). This test opens one stream and then
// floods RST_STREAM on it past __h2_max_resets (1000); the server must
// respond with a GOAWAY carrying error code 11 (ENHANCE_YOUR_CALM).
// requires: live

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_frame.nu`
$ `stdlib/ext/http2_server.nu`

& `libc` @ nurl_tcp_connect s host i port → i

@ ok_handler HttpRequest req → HttpResponse { ^ ( response_text 200 `ok` ) }

// Write one frame; CONSUMES `payload`. Returns T on success.
@ wf TcpConn conn i ftype i flags i sid ( Vec u ) payload → b {
    : H2Frame f @ H2Frame { ftype flags sid payload }
    : !v H2FrameErr r ( h2_write_frame conn f 16384 )
    ( h2_frame_free f )
    ^ ?? r { T _ → T F _ → F }
}

// A minimal valid request header block for stream 1: indexed static
// entries :method GET (0x82), :scheme http (0x86), :path / (0x84) and a
// literal :authority (index 1) "x".
@ req_headers → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 0x82 )
    ( vec_push [u] b # u 0x86 )
    ( vec_push [u] b # u 0x84 )
    ( vec_push [u] b # u 0x41 )  // literal w/ incremental indexing, name idx 1
    ( vec_push [u] b # u 0x01 )  // value length 1
    ( vec_push [u] b # u 0x78 )  // 'x'
    ^ b
}

// A 4-byte RST_STREAM payload carrying error code 8 (CANCEL).
@ rst_payload → ( Vec u ) {
    : ( Vec u ) p ( vec_new [u] )
    ( vec_push [u] p # u 0 )
    ( vec_push [u] p # u 0 )
    ( vec_push [u] p # u 0 )
    ( vec_push [u] p # u 8 )
    ^ p
}

@ run → i {
    : ~ i fails 0
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18831 )
    ?? lr {
        T listener → {
            : ( @ v ) server_fn \ → v {
                : !TcpConn NetErr ar ( tcp_accept listener )
                ?? ar {
                    T conn → {
                        : !v H2ConnErr sr ( http2_serve conn \ HttpRequest req → HttpResponse { ^ ( ok_handler req ) } )
                        ?? sr { T _ → {} F _ → {} }
                        ( tcp_close_conn conn )
                    }
                    F _ → {}
                }
            }
            : !Thread ThreadErr st ( thread_spawn server_fn )
            ( sleep_ms 100 )

            : i craw ( nurl_tcp_connect `127.0.0.1` 18831 )
            ? != ( nurl_tcp_err_kind craw ) 0 {
                ( nurl_print `  FAIL connect\n` ) = fails + fails 1
            } {
                : TcpConn conn @ TcpConn { # s craw }
                ( tcp_set_timeout conn 3000 )
                : !v H2FrameErr pf ( h2_write_preface conn )
                ?? pf { T _ → {} F _ → {} }
                : b _s ( wf conn ( h2_type_settings ) 0 0 ( vec_new [u] ) )
                // Open stream 1 (END_STREAM | END_HEADERS) so RST on it is
                // a valid, silently-ignored frame — one that still counts
                // toward the reset budget.
                : b _h ( wf conn ( h2_type_headers ) 5 1 ( req_headers ) )
                // Flood RST_STREAM on stream 1 past __h2_max_resets (1000).
                : ~ i c 0
                : ~ b wok T
                ~ & wok < c 1100 {
                    = wok ( wf conn ( h2_type_rst_stream ) 0 1 ( rst_payload ) )
                    = c + c 1
                }
                // The server must GOAWAY with ENHANCE_YOUR_CALM (code 11).
                : ~ b calmed F
                : ~ b sawgoaway F
                : ~ i reads 0
                ~ & ! calmed < reads 40 {
                    : !H2Frame H2FrameErr rr ( h2_read_frame conn 16384 )
                    ?? rr {
                        T fr → {
                            ? == . fr frame_type ( h2_type_goaway ) {
                                = sawgoaway T
                                : ( Vec u ) pl . fr payload
                                ? >= ( vec_len [u] pl ) 8 {
                                    : *u pp ( vec_data [u] pl )
                                    : i code + + + << & 255 # i . pp 4 24 << & 255 # i . pp 5 16 << & 255 # i . pp 6 8 & 255 # i . pp 7
                                    ? == code 11 { = calmed T } {}
                                } {}
                            } {}
                            ( h2_frame_free fr )
                        }
                        F _ → { = reads 40 }
                    }
                    = reads + reads 1
                }
                ? calmed {
                    ( nurl_print `rapid-reset defended: GOAWAY ENHANCE_YOUR_CALM\n` )
                } {
                    ? sawgoaway {
                        ( nurl_print `  FAIL GOAWAY but not ENHANCE_YOUR_CALM\n` )
                    } {
                        ( nurl_print `  FAIL no GOAWAY on RST flood\n` )
                    }
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

@ main → i { ^ ( run ) }
