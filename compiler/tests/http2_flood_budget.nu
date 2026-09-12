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
// with GOAWAY(ENHANCE_YOUR_CALM). This test opens one stream and drives
// the reset counter to the ceiling and then one past it:
//
//   phase 1 — exactly `_h2_max_resets` RST_STREAMs, then a PING. The
//             PING ACK proves the connection is still being served, so
//             the ceiling is not tripped EARLY.
//   phase 2 — one more RST_STREAM. The server must answer with GOAWAY
//             carrying error code 11 (ENHANCE_YOUR_CALM).
//
// Why exactly the ceiling, and not "some number comfortably past it"
// (this test flooded 1100 before 2026-09-12): the client must not leave
// bytes the server will never read. The server stops reading the instant
// the budget trips, so an overshooting client's surplus frames sit
// unread in the server's receive queue — and closing a socket with
// unread data is a TCP RESET, not a FIN. Linux hands an application the
// bytes already queued before it reports that reset, so the overshooting
// client here still read its GOAWAY; Winsock discards them and fails the
// recv outright. That is the shape of the flakiness this test carried on
// Windows — ten of the last eighty-seven windows-tests runs red, every
// one of them this test, every one of them "FAIL no GOAWAY on RST
// flood", every re-run green.
//
// Sending exactly what the server will consume makes the close a FIN on
// every platform, and a FIN never destroys data already in flight. The
// count comes from the stdlib ceiling itself (`_h2_max_resets`) so the
// two can never drift apart. The FIN is asserted, not assumed, at the
// end of the run; and every other exit names its own step, so if the
// diagnosis above were wrong the next failure would say which step
// actually broke instead of blaming the GOAWAY.
// requires: live

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
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

// PING opaque data — exactly 8 bytes (§6.7); the server echoes it back.
@ ping_payload → ( Vec u ) {
    : ( Vec u ) p ( vec_new [u] )
    : ~ i k 0
    ~ < k 8 {
        ( vec_push [u] p # u 0x5a )
        = k + k 1
    }
    ^ p
}

// Read the 32-bit error code out of a GOAWAY payload (last_stream_id
// then error_code, §6.8); -1 when the payload is too short to carry one.
@ goaway_code ( Vec u ) pl → i {
    ? < ( vec_len [u] pl ) 8 { ^ - 0 1 } {}
    : *u pp ( vec_data [u] pl )
    ^ + + + << & 255 # i . pp 4 24 << & 255 # i . pp 5 16 << & 255 # i . pp 6 8 & 255 # i . pp 7
}

// Drive the flood on an already-connected socket. Returns the number of
// failures, having printed which step failed and why — every exit names
// itself, so a broken budget is never reported as a lost frame and a
// lost frame is never reported as a broken budget.
@ flood_client TcpConn conn → i {
    : ~ i fails 0
    : !v H2FrameErr pf ( h2_write_preface conn )
    ?? pf { T _ → {} F _ → {} }
    : b _s ( wf conn ( h2_type_settings ) 0 0 ( vec_new [u] ) )
    // Open stream 1 (END_STREAM | END_HEADERS) so RST on it is a valid,
    // silently-ignored frame — one that still counts toward the budget.
    : b _h ( wf conn ( h2_type_headers ) 5 1 ( req_headers ) )

    : i budget ( _h2_max_resets )
    // ── Phase 1: resets UP TO the ceiling must not trip it ──────────
    : ~ i c 0
    : ~ i badwrite - 0 1
    ~ & < badwrite 0 < c budget {
        ? ( wf conn ( h2_type_rst_stream ) 0 1 ( rst_payload ) ) {} { = badwrite c }
        = c + c 1
    }
    ? >= badwrite 0 {
        ( nurl_print `  FAIL RST_STREAM write failed at ` )
        ( nurl_print ( nurl_str_int badwrite ) )
        ( nurl_print `\n` )
        ^ + fails 1
    } {}
    ? ( wf conn ( h2_type_ping ) 0 0 ( ping_payload ) ) {} {
        ( nurl_print `  FAIL PING write failed\n` )
        ^ + fails 1
    }
    : ~ b alive F
    : ~ b sank F
    : ~ i reads 0
    ~ & ! alive & ! sank < reads 40 {
        : !H2Frame H2FrameErr rr ( h2_read_frame conn 16384 )
        ?? rr {
            T fr → {
                ? == . fr frame_type ( h2_type_ping ) {
                    ? != 0 & . fr flags ( h2_flag_ack ) { = alive T } {}
                } {}
                ? == . fr frame_type ( h2_type_goaway ) {
                    ( nurl_print `  FAIL budget tripped EARLY, at or below ` )
                    ( nurl_print ( nurl_str_int budget ) )
                    ( nurl_print ` resets\n` )
                    = sank T
                } {}
                ( h2_frame_free fr )
            }
            F fe → {
                ( nurl_print `  FAIL no PING ACK below the ceiling: ` )
                ( nurl_print ( h2_frame_err_name fe ) )
                ( nurl_print `\n` )
                = sank T
            }
        }
        = reads + reads 1
    }
    ? sank { ^ + fails 1 } {}
    ? ! alive {
        ( nurl_print `  FAIL no PING ACK below the ceiling: 40 frames read\n` )
        ^ + fails 1
    } {}
    ( nurl_print `budget holds to the ceiling: PING ACK\n` )

    // ── Phase 2: one more reset CROSSES it ──────────────────────────
    ? ( wf conn ( h2_type_rst_stream ) 0 1 ( rst_payload ) ) {} {
        ( nurl_print `  FAIL ceiling-crossing RST_STREAM write failed\n` )
        ^ + fails 1
    }
    : ~ b calmed F
    : ~ b stop F
    : ~ i reads2 0
    ~ & ! calmed & ! stop < reads2 40 {
        : !H2Frame H2FrameErr rr ( h2_read_frame conn 16384 )
        ?? rr {
            T fr → {
                ? == . fr frame_type ( h2_type_goaway ) {
                    : i code ( goaway_code . fr payload )
                    ? == code 11 {
                        = calmed T
                    } {
                        ( nurl_print `  FAIL GOAWAY error code ` )
                        ( nurl_print ( nurl_str_int code ) )
                        ( nurl_print ` not 11 (ENHANCE_YOUR_CALM)\n` )
                        = stop T
                    }
                } {}
                ( h2_frame_free fr )
            }
            F fe → {
                ( nurl_print `  FAIL connection died before GOAWAY: ` )
                ( nurl_print ( h2_frame_err_name fe ) )
                ( nurl_print `\n` )
                = stop T
            }
        }
        = reads2 + reads2 1
    }
    ? stop { ^ + fails 1 } {}
    ? ! calmed {
        ( nurl_print `  FAIL no GOAWAY on RST flood\n` )
        ^ + fails 1
    } {}
    // ── The close must be a FIN, not a RESET ────────────────────────
    // This is the invariant the whole shape of the test rests on, so
    // assert it rather than assume it: one more read has to end in a
    // CLEAN end-of-stream. A reset surfaces as H2FrameReadIo instead,
    // and a reset is what discards the GOAWAY on Winsock — so if a
    // future edit starts overshooting the ceiling again, this line
    // fails on Linux too, where the flakiness would otherwise be
    // invisible.
    : !H2Frame H2FrameErr er ( h2_read_frame conn 16384 )
    ?? er {
        T fr2 → {
            ( nurl_print `  FAIL frame after GOAWAY where EOF was due\n` )
            ( h2_frame_free fr2 )
            = fails + fails 1
        }
        F fe2 → {
            ?? fe2 {
                H2FrameReadShort → {
                    ( nurl_print `rapid-reset defended: GOAWAY ENHANCE_YOUR_CALM\n` )
                }
                _ → {
                    ( nurl_print `  FAIL close was a RESET, not a FIN: ` )
                    ( nurl_print ( h2_frame_err_name fe2 ) )
                    ( nurl_print `\n` )
                    = fails + fails 1
                }
            }
        }
    }
    ^ fails
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
                = fails + fails ( flood_client conn )
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
