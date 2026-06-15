// pttvoice/test_pipeline.nu — the full send→receive payload pipeline minus the
// network: synth PCM → Opus encode → proto VOICE frame → proto decode → Opus
// decode → PCM. Confirms a frame survives the wire framing with its sequence
// intact and still carries audio energy. Headless (pure codec + framing).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `pttvoice/opus.nu`
$ `pttvoice/proto.nu`

@ yn s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ make_frame i phase0 → ( Vec u ) {
    : ( Vec u ) pcm ( vec_new [u] )
    : i fs ( opus_frame_samples )
    : ~ i k 0
    ~ < k fs { ( pcm_push pcm - * % + phase0 k 100 200 10000 ) = k + k 1 }
    ^ pcm
}

@ main → i {
    : s enc ( opus_enc_new )
    : s dec ( opus_dec_new )

    : ~ b all_ok T
    : ~ i frames_ok 0
    : ~ i f 0
    ~ < f 5 {
        // sender side: capture → encode → frame
        : ( Vec u ) pcm ( make_frame * f 11 )
        : ( Vec u ) opus ( opus_encode_frame enc pcm )
        : ( Vec u ) wire ( proto_voice_encode + 1000 f opus )
        // receiver side: parse frame → decode → play
        ?? ( proto_decode wire ) {
            T vm → {
                : b seq_ok == . vm seq + 1000 f
                : ( Vec u ) out ( opus_decode_frame dec . vm opus )
                : b frame_ok & & seq_ok == ( pcm_samples out ) ( opus_frame_samples ) > ( pcm_energy out ) 0
                ? frame_ok { = frames_ok + frames_ok 1 } { = all_ok F }
                ( vec_free [u] out )
                ( voicemsg_free vm )
            }
            F → { = all_ok F }
        }
        ( vec_free [u] pcm ) ( vec_free [u] opus ) ( vec_free [u] wire )
        = f + f 1
    }

    : ( Vec u ) empty ( vec_new [u] )
    ( yn `non-voice payload rejected by proto_decode: ` ?? ( proto_decode empty ) { T vm → { ( voicemsg_free vm ) F } F → T } )
    ( vec_free [u] empty )
    ( nurl_print `frames that survived encode→frame→decode→pcm: ` ) ( nurl_print_int frames_ok )
    ( yn `all 5 frames round-tripped (seq + energy): ` & all_ok == frames_ok 5 )

    ( opus_enc_free enc ) ( opus_dec_free dec )
    ^ 0
}
