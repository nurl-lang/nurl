// pttvoice/test_opus_roundtrip.nu — exercises the libopus FFI offline: synth a
// sawtooth PCM signal, encode each 20 ms frame, decode it back, and confirm the
// codec produced a non-empty packet and a full lossy-but-energetic frame. No
// audio hardware needed — this is pure codec, so it runs headless.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `pttvoice/opus.nu`

// one 960-sample frame of a sawtooth (period 100 samples, ±10000)
@ make_frame i phase0 → ( Vec u ) {
    : ( Vec u ) pcm ( vec_new [u] )
    : i fs ( opus_frame_samples )
    : ~ i k 0
    ~ < k fs {
        : i ph % + phase0 k 100
        : i saw - * ph 200 10000
        ( pcm_push pcm saw )
        = k + k 1
    }
    ^ pcm
}

@ yn s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ main → i {
    : s enc ( opus_enc_new )
    : s dec ( opus_dec_new )
    ( yn `encoder created: ` != # i enc 0 )
    ( yn `decoder created: ` != # i dec 0 )

    : ~ i last_samples 0
    : ~ i last_energy 0
    : ~ i last_pkt 0
    : ~ i f 0
    ~ < f 6 {
        : ( Vec u ) pcm ( make_frame * f 7 )
        : ( Vec u ) pkt ( opus_encode_frame enc pcm )
        : ( Vec u ) out ( opus_decode_frame dec pkt )
        = last_pkt ( vec_len [u] pkt )
        = last_samples ( pcm_samples out )
        = last_energy ( pcm_energy out )
        ( vec_free [u] pcm ) ( vec_free [u] pkt ) ( vec_free [u] out )
        = f + f 1
    }

    ( yn `encoded packet is non-empty: ` > last_pkt 0 )
    ( yn `decoded a full 960-sample frame: ` == last_samples 960 )
    ( yn `decoded frame carries energy (lossy roundtrip): ` > last_energy 0 )

    ( opus_enc_free enc ) ( opus_dec_free dec )
    ^ 0
}
