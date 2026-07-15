// ws_permessage_deflate.nu — RFC 7692 permessage-deflate for
// stdlib/ext/websocket.nu. All offline:
//   §A  Extension-header negotiation (offer / parse / response / clamp)
//   §B  Decline cases (no permessage-deflate offered)
//   §C  Cross-context message round-trip (client compresses, server
//       decompresses) incl. context takeover across messages
//   §D  Text UTF-8 validated AFTER inflation; decompression-bomb cap

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/websocket.nu`

@ pl s tag s v → v {
    ( nurl_print tag ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ pb s tag b v → v { ( pl tag ? v `T` `F` ) }

@ vec_eq ( Vec u ) a ( Vec u ) b → b {
    : i na ( vec_len [u] a )
    ? != na ( vec_len [u] b ) { ^ F } {}
    : *u pa ( vec_data [u] a )
    : *u pb ( vec_data [u] b )
    : ~ i k 0
    ~ < k na {
        ? != # i . pa k # i . pb k { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ make_text s sample i reps → ( Vec u ) {
    : ( Vec u ) buf ( vec_with_cap [u] 256 )
    : ~ i k 0
    ~ < k reps { ( bytes_extend_str buf sample ) = k + k 1 }
    ^ buf
}

// Mirror the sender: compress through a context's deflater, strip the
// Z_SYNC_FLUSH tail (and reset if no-context-takeover).
@ compress_msg WsDeflate d ( Vec u ) payload → ( Vec u ) {
    : !( Vec u ) CompressErr cr ( raw_deflate_block . d deflater payload )
    ^ ?? cr {
        T comp → {
            ? . d deflate_no_takeover { ( raw_deflate_reset . d deflater ) } {}
            ( _ws_strip_deflate_tail comp )
            comp
        }
        F _ → ( vec_new [u] )
    }
}

@ section_a → v {
    ( nurl_print `--- A negotiation ---\n` )
    // Default offer is the bare extension token.
    : String o1 ( ws_deflate_offer_header ( ws_deflate_default_config ) )
    ( pl `offer_default` ( string_data o1 ) )
    ( string_free o1 )

    // Offer with params.
    : WsDeflateConfig c2 @ WsDeflateConfig { T F T 10 15 }
    : String o2 ( ws_deflate_offer_header c2 )
    ( pl `offer_params` ( string_data o2 ) )
    ( string_free o2 )

    // Parse a client offer (browser-style).
    : ?WsDeflateConfig p1 ( ws_deflate_parse_extensions `permessage-deflate; client_max_window_bits=12; server_no_context_takeover` )
    ?? p1 {
        T c → {
            ( pb `parse_enabled` . c enabled )
            ( pb `parse_snto` . c server_no_context_takeover )
            ( pb `parse_cnto` . c client_no_context_takeover )
            ( pl `parse_cwb` ( nurl_str_int . c client_max_window_bits ) )
            ( pl `parse_swb` ( nurl_str_int . c server_max_window_bits ) )
        }
        F _ → ( nurl_print `parse_offer_none\n` )
    }

    // window_bits = 8 clamps to 9 (libz raw constraint).
    : ?WsDeflateConfig p2 ( ws_deflate_parse_extensions `permessage-deflate; server_max_window_bits=8` )
    ?? p2 {
        T c → ( pl `clamp_swb8` ( nurl_str_int . c server_max_window_bits ) )
        F _ → ( nurl_print `clamp_none\n` )
    }

    // Server response header echoes agreed params.
    : WsDeflateConfig agreed @ WsDeflateConfig { T T F 15 15 }
    : String resp ( ws_deflate_response_header agreed )
    ( pl `response` ( string_data resp ) )
    ( string_free resp )
}

@ section_b → v {
    ( nurl_print `--- B decline ---\n` )
    : ?WsDeflateConfig p ( ws_deflate_parse_extensions `x-custom-ext; q=1` )
    ?? p {
        T c → { ( nurl_print `unexpected_some\n` ) }
        F _ → ( nurl_print `no_pmce=T\n` )
    }
    // Empty header → None.
    : ?WsDeflateConfig p2 ( ws_deflate_parse_extensions `` )
    ?? p2 {
        T c → { ( nurl_print `unexpected_some2\n` ) }
        F _ → ( nurl_print `empty_none=T\n` )
    }
}

@ section_c → v {
    ( nurl_print `--- C round-trip ---\n` )
    : WsDeflateConfig cfg ( ws_deflate_default_config )
    : !WsDeflate WsErr cm ( ws_deflate_make cfg F )  // client side
    : !WsDeflate WsErr sm ( ws_deflate_make cfg T )  // server side
    ?? cm {
        F _ → ( nurl_print `client_ctx_fail\n` )
        T client → {
            ?? sm {
                F _ → { ( nurl_print `server_ctx_fail\n` ) ( ws_deflate_free client ) }
                T server → {
                    ( pb `client_active` ( ws_deflate_active client ) )

                    : WsLimits lim ( ws_default_limits )
                    : ( Vec u ) m1 ( make_text `permessage-deflate compresses repetitive frames well. ` 8 )
                    : ( Vec u ) m2 ( make_text `permessage-deflate compresses repetitive frames well. ` 8 )

                    // Client compresses; server decompresses.
                    : ( Vec u ) c1 ( compress_msg client m1 )
                    : i c1len ( vec_len [u] c1 )
                    : WsMessage msg1 @ WsMessage { 1 T c1 }
                    : !WsMessage WsErr r1 ( _ws_inflate_message server lim msg1 )
                    ?? r1 {
                        T out → {
                            ( pb `m1_round_trip` ( vec_eq m1 . out payload ) )
                            ( pb `m1_smaller` < c1len ( vec_len [u] m1 ) )
                            ( ws_message_free out )
                        }
                        F e → ( pl `m1_err` ( ws_err_name e ) )
                    }

                    // Second identical message: context takeover means the
                    // server inflater must keep state to decode it.
                    : ( Vec u ) c2 ( compress_msg client m2 )
                    : i c2len ( vec_len [u] c2 )
                    : WsMessage msg2 @ WsMessage { 1 T c2 }
                    : !WsMessage WsErr r2 ( _ws_inflate_message server lim msg2 )
                    ?? r2 {
                        T out → {
                            ( pb `m2_round_trip` ( vec_eq m2 . out payload ) )
                            ( pb `m2_takeover_shrinks` < c2len c1len )
                            ( ws_message_free out )
                        }
                        F e → ( pl `m2_err` ( ws_err_name e ) )
                    }

                    ( vec_free [u] m1 ) ( vec_free [u] m2 )
                    ( ws_deflate_free server )
                }
            }
            ( ws_deflate_free client )
        }
    }
}

@ section_d → v {
    ( nurl_print `--- D validation ---\n` )
    : WsDeflateConfig cfg ( ws_deflate_default_config )
    : !WsDeflate WsErr cm ( ws_deflate_make cfg F )
    : !WsDeflate WsErr sm ( ws_deflate_make cfg T )
    ?? cm {
        F _ → ( nurl_print `ctx_fail\n` )
        T client → {
            ?? sm {
                F _ → { ( nurl_print `ctx_fail2\n` ) ( ws_deflate_free client ) }
                T server → {
                    // Invalid UTF-8 in a TEXT message must be rejected
                    // AFTER inflation.
                    : ( Vec u ) bad ( vec_new [u] )
                    ( vec_push [u] bad # u 255 )  // lone 0xFF = invalid UTF-8
                    ( vec_push [u] bad # u 254 )
                    : ( Vec u ) cbad ( compress_msg client bad )
                    : WsLimits lim ( ws_default_limits )
                    : WsMessage mb @ WsMessage { 1 T cbad }
                    : !WsMessage WsErr rb ( _ws_inflate_message server lim mb )
                    ?? rb {
                        T out → { ( nurl_print `utf8_not_rejected\n` ) ( ws_message_free out ) }
                        F e → ( pl `utf8_text_err` ( ws_err_name e ) )
                    }
                    ( vec_free [u] bad )

                    // The same bytes as BINARY (opcode 2) are fine.
                    : ( Vec u ) bin ( vec_new [u] )
                    ( vec_push [u] bin # u 255 )
                    ( vec_push [u] bin # u 254 )
                    : ( Vec u ) cbin ( compress_msg client bin )
                    : WsMessage mn @ WsMessage { 2 T cbin }
                    : !WsMessage WsErr rn ( _ws_inflate_message server lim mn )
                    ?? rn {
                        T out → {
                            ( pb `binary_ok` ( vec_eq bin . out payload ) )
                            ( ws_message_free out )
                        }
                        F e → ( pl `binary_err` ( ws_err_name e ) )
                    }
                    ( vec_free [u] bin )

                    // Decompression-bomb cap: a large payload with a tiny
                    // max_message_bytes must fail WsMessageTooLarge.
                    : ( Vec u ) big ( make_text `AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA` 4096 )
                    : ( Vec u ) cbig ( compress_msg client big )
                    : WsLimits tiny @ WsLimits { 16777216 1024 60000 128 }
                    : WsMessage mg @ WsMessage { 2 T cbig }
                    : !WsMessage WsErr rg ( _ws_inflate_message server tiny mg )
                    ?? rg {
                        T out → { ( nurl_print `bomb_not_capped\n` ) ( ws_message_free out ) }
                        F e → ( pl `bomb_capped` ( ws_err_name e ) )
                    }
                    ( vec_free [u] big )

                    ( ws_deflate_free server )
                }
            }
            ( ws_deflate_free client )
        }
    }
}

@ main → i {
    ( section_a )
    ( section_b )
    ( section_c )
    ( section_d )
    ^ 0
}
