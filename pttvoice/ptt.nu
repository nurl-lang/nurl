// pttvoice/ptt.nu — Push-To-Talk voice over the NURL overlay. Captures mic
// audio, Opus-encodes it, and pushes it either to ONE chosen peer (unicast,
// p2p when the transport can punch through, relayed otherwise) or to EVERY
// member of the group (broadcast → relay multicast). A receiver decodes each
// frame and plays it back. Audio is 48 kHz mono, 20 ms Opus frames.
//
// Usage:
//   ./nurl.sh pttvoice/ptt.nu <relay_host> <relay_port> <self_id> <mode> [target_id] [frames]
//     mode = group   broadcast a talkspurt to the whole group
//          = peer    unicast a talkspurt to <target_id>
//          = listen  receive and play whatever arrives
//   frames = number of 20 ms frames to transmit (default 50 ≈ 1 s)
//
// On a host with no sound card (CI / headless) capture yields a synth tone and
// playback is a silent sink, so the network path still runs end to end.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/net/transport.nu`
$ `pttvoice/opus.nu`
$ `pttvoice/audio.nu`
$ `pttvoice/proto.nu`

@ pk_for i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + id k ) = k + k 1 } ^ v }
@ group_id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + 200 k ) = k + k 1 } ^ v }

// A synth talkspurt frame (sawtooth) for hosts with no microphone, so a
// headless sender still transmits real, decodable audio.
@ synth_frame i phase → ( Vec u ) {
    : ( Vec u ) pcm ( vec_new [u] )
    : i fs ( opus_frame_samples )
    : ~ i k 0
    ~ < k fs { ( pcm_push pcm - * % + phase k 120 160 9600 ) = k + k 1 }
    ^ pcm
}

// Drain + play every inbound voice frame currently available. Returns how many
// frames were played.
@ pump_playback *Transport tr s dec s play → i {
    : ~ i played 0
    : ~ b more T
    ~ more {
        ?? ( transport_recv tr 4000 ) {
            T m → {
                ?? ( proto_decode . m payload ) {
                    T vm → {
                        : ( Vec u ) pcm ( opus_decode_frame dec . vm opus )
                        ? > ( vec_len [u] pcm ) 0 { ( audio_play play pcm ) = played + played 1 } {}
                        ( vec_free [u] pcm )
                        ( voicemsg_free vm )
                    }
                    F → {}
                }
                ( transport_msg_free m )
            }
            F → { = more F }
        }
    }
    ^ played
}

@ main → i {
    : i argc ( env_args_count )
    : String host ? > argc 1 ( env_arg 1 ) ( string_from `127.0.0.1` )
    : i port ? > argc 2 { : String ps ( env_arg 2 ) : i p ( nurl_str_to_int ( string_data ps ) ) ( string_free ps ) p } 47700
    : i sid ? > argc 3 { : String ss ( env_arg 3 ) : i s ( nurl_str_to_int ( string_data ss ) ) ( string_free ss ) s } 1
    : String mode ? > argc 4 ( env_arg 4 ) ( string_from `group` )
    : i tid ? > argc 5 { : String ts ( env_arg 5 ) : i t ( nurl_str_to_int ( string_data ts ) ) ( string_free ts ) t } 2
    : i frames ? > argc 6 { : String fs2 ( env_arg 6 ) : i f ( nurl_str_to_int ( string_data fs2 ) ) ( string_free fs2 ) f } 50

    : b is_listen != ( nurl_str_eq ( string_data mode ) `listen` ) 0
    : b is_peer != ( nurl_str_eq ( string_data mode ) `peer` ) 0

    ?? ( relay_dial ( string_data host ) port ) {
        T rc → {
            : ( Vec u ) self_pk ( pk_for + 1 sid )
            ?? ( relay_register rc self_pk ) { T _ → {} F _ → {} }
            ( relay_set_timeout rc 200 )
            : *Transport tr # *Transport ( transport_open # s 0 rc 1 )
            : ( Vec u ) g ( group_id )
            ?? ( transport_group_join tr g ) { T _ → {} F _ → {} }
            : ( Vec u ) target ( pk_for + 1 tid )

            : s enc ( opus_enc_new )
            : s dec ( opus_dec_new )
            : s cap ( audio_capture_open )
            : s play ( audio_play_open )
            ( nurl_print `ptt node ` ) ( nurl_print_int sid )
            ( nurl_print ` mode=` ) ( nurl_print ( string_data mode ) )
            ( nurl_print ? == # i cap 0 ` (no mic → synth)` `` )
            ( nurl_print ? == # i play 0 ` (no speaker → silent)` `` ) ( nurl_print `\n` )

            : ~ i sent 0
            : ~ i recvd 0

            ? is_listen {
                // receive-only: pump playback for ~frames*20 ms
                : ~ i r 0
                ~ < r frames { = recvd + recvd ( pump_playback tr dec play ) ( sleep_ms 20 ) = r + r 1 }
            } {
                // transmit a talkspurt; also play anything that arrives (duplex)
                : ~ i seq 0
                ~ < seq frames {
                    : ( Vec u ) pcm ? == # i cap 0 ( synth_frame * seq 7 ) ( audio_capture cap ( opus_frame_samples ) )
                    : ( Vec u ) use ? > ( vec_len [u] pcm ) 0 pcm ( synth_frame * seq 7 )
                    : ( Vec u ) opus ( opus_encode_frame enc use )
                    ? > ( vec_len [u] opus ) 0 {
                        : ( Vec u ) wire ( proto_voice_encode seq opus )
                        ? is_peer {
                            ?? ( transport_send tr target wire ) { T _ → { = sent + sent 1 } F _ → {} }
                        } {
                            ?? ( transport_broadcast tr g wire ) { T _ → { = sent + sent 1 } F _ → {} }
                        }
                        ( vec_free [u] wire )
                    } {}
                    ( vec_free [u] opus )
                    // `use` aliases `pcm` unless a synth frame replaced an empty
                    // capture; free once when aliased, both when distinct.
                    ? == # i use # i pcm { ( vec_free [u] pcm ) } { ( vec_free [u] use ) ( vec_free [u] pcm ) }
                    = recvd + recvd ( pump_playback tr dec play )
                    ( sleep_ms 20 )
                    = seq + seq 1
                }
            }

            ( nurl_print `frames sent=` ) ( nurl_print_int sent )
            ( nurl_print ` frames played=` ) ( nurl_print_int recvd ) ( nurl_print `\n` )

            ( opus_enc_free enc ) ( opus_dec_free dec )
            ( audio_close cap ) ( audio_close play )
            ( vec_free [u] self_pk ) ( vec_free [u] g ) ( vec_free [u] target )
            ( transport_free tr ) ( relay_close rc )
        }
        F _ → { ( nurl_print `could not reach relay at ` ) ( nurl_print ( string_data host ) ) ( nurl_print `\n` ) }
    }
    ( string_free host ) ( string_free mode )
    ^ 0
}
