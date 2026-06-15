// pttvoice/opus.nu — minimal libopus binding for the PTT voice app. Mono VoIP
// at 48 kHz, 20 ms frames (960 samples). PCM is carried as a (Vec u) of
// little-endian signed 16-bit samples; an encoded frame is an opaque (Vec u).
//
// This folder is self-contained so it can move to its own project later; it
// FFIs libopus directly (nurl.sh auto-links -lopus when these symbols appear).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── libopus FFI ──────────────────────────────────────────────────
// int* error / opus_int16* pcm / unsigned char* data are all passed as raw
// buffer pointers (*u); opus reads them at the right width.
& `opus` @ opus_encoder_create i Fs i channels i application *u error → s
& `opus` @ opus_encoder_destroy s st → v
& `opus` @ opus_encode s st *u pcm i frame_size *u data i max_data_bytes → i
& `opus` @ opus_decoder_create i Fs i channels *u error → s
& `opus` @ opus_decoder_destroy s st → v
& `opus` @ opus_decode s st *u data i len *u pcm i frame_size i decode_fec → i

@ opus_rate          → i { ^ 48000 }   // VoIP sample rate (Hz)
@ opus_channels      → i { ^ 1 }       // mono
@ opus_frame_samples → i { ^ 960 }     // 20 ms @ 48 kHz
@ __opus_app_voip    → i { ^ 2048 }    // OPUS_APPLICATION_VOIP
@ __opus_max_packet  → i { ^ 4000 }    // generous per-frame ceiling

// a zero-filled byte buffer of length n (n>=1)
@ __obuf i n → ( Vec u ) {
    : ( Vec u ) b ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0 ~ < k n { ( vec_push [u] b # u 0 ) = k + k 1 }
    ^ b
}

// ── encoder ──────────────────────────────────────────────────────
@ opus_enc_new → s {
    : ( Vec u ) err ( __obuf 8 )
    : s enc ( opus_encoder_create ( opus_rate ) ( opus_channels ) ( __opus_app_voip ) ( vec_data [u] err ) )
    ( vec_free [u] err )
    ^ enc
}
@ opus_enc_free s enc → v { ? != # i enc 0 { ( opus_encoder_destroy enc ) } {} }

// Encode one frame of PCM (2*frame_samples bytes) → opaque packet bytes.
// Empty (Vec u) on failure.
@ opus_encode_frame s enc ( Vec u ) pcm → ( Vec u ) {
    : ( Vec u ) out ( __obuf ( __opus_max_packet ) )
    : i n ( opus_encode enc ( vec_data [u] pcm ) ( opus_frame_samples ) ( vec_data [u] out ) ( __opus_max_packet ) )
    ? < n 1 { ( vec_free [u] out ) ^ ( vec_new [u] ) } {}
    : b _ok ( vec_set_len [u] out n )
    ^ out
}

// ── decoder ──────────────────────────────────────────────────────
@ opus_dec_new → s {
    : ( Vec u ) err ( __obuf 8 )
    : s dec ( opus_decoder_create ( opus_rate ) ( opus_channels ) ( vec_data [u] err ) )
    ( vec_free [u] err )
    ^ dec
}
@ opus_dec_free s dec → v { ? != # i dec 0 { ( opus_decoder_destroy dec ) } {} }

// Decode one packet → PCM (2*samples bytes). Empty (Vec u) on failure.
@ opus_decode_frame s dec ( Vec u ) packet → ( Vec u ) {
    : i fs ( opus_frame_samples )
    : ( Vec u ) pcm ( __obuf * fs 2 )
    : i ns ( opus_decode dec ( vec_data [u] packet ) ( vec_len [u] packet ) ( vec_data [u] pcm ) fs 0 )
    ? < ns 0 { ( vec_free [u] pcm ) ^ ( vec_new [u] ) } {}
    : b _ok ( vec_set_len [u] pcm * ns 2 )
    ^ pcm
}

// ── PCM helpers (signed 16-bit LE in a Vec u) ────────────────────
// push one signed sample (two's-complement, no shift ops needed)
@ pcm_push ( Vec u ) buf i sample → v {
    : i vm & sample 0xffff
    ( vec_push [u] buf # u % vm 256 )
    ( vec_push [u] buf # u / vm 256 )
}
// read sample k (signed) from a PCM buffer
@ pcm_get ( Vec u ) buf i k → i {
    : i lo ?? ( vec_get [u] buf * k 2 ) { T x → # i x F → 0 }
    : i hi ?? ( vec_get [u] buf + * k 2 1 ) { T x → # i x F → 0 }
    : i v + lo * hi 256
    ^ ? >= v 32768 - v 65536 v
}
@ pcm_samples ( Vec u ) buf → i { ^ / ( vec_len [u] buf ) 2 }
// total absolute energy (0 for silence) — used by tests
@ pcm_energy ( Vec u ) buf → i {
    : i n ( pcm_samples buf )
    : ~ i e 0 : ~ i k 0
    ~ < k n { : i v ( pcm_get buf k ) = e + e ? < v 0 - 0 v v = k + k 1 }
    ^ e
}
