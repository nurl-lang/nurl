// pttvoice/audio.nu — ALSA capture/playback for 48 kHz mono signed-16 PCM, the
// raw audio the Opus codec consumes/produces. Thin FFI over snd_pcm_*; every
// op is a no-op (or silence) when the handle is 0, so a host with no sound
// device (CI, a headless server) still runs the app — it just hears/sends
// silence. The app substitutes a synth source there.
//
// Self-contained for the future standalone project; nurl.sh auto-links
// -lasound when these symbols appear.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── ALSA FFI ─────────────────────────────────────────────────────
// snd_pcm_open's first arg is snd_pcm_t** (out); name is a C string; format/
// access are enums; writei/readi take a frame count and return frames or -errno.
& `asound` @ snd_pcm_open *u pcmp s name i stream i mode → i
& `asound` @ snd_pcm_set_params s pcm i format i access i channels i rate i soft_resample i latency → i
& `asound` @ snd_pcm_writei s pcm *u buffer i size → i
& `asound` @ snd_pcm_readi s pcm *u buffer i size → i
& `asound` @ snd_pcm_recover s pcm i err i silent → i
& `asound` @ snd_pcm_prepare s pcm → i
& `asound` @ snd_pcm_drain s pcm → i
& `asound` @ snd_pcm_close s pcm → i

@ __snd_stream_playback → i { ^ 0 }
@ __snd_stream_capture  → i { ^ 1 }
@ __snd_format_s16_le   → i { ^ 2 }    // SND_PCM_FORMAT_S16_LE
@ __snd_access_rw_inter → i { ^ 3 }    // SND_PCM_ACCESS_RW_INTERLEAVED
@ audio_rate            → i { ^ 48000 }
@ audio_channels        → i { ^ 1 }

@ __aud_open i stream → s {
    : ( Vec u ) hp ( vec_with_cap [u] 8 )
    : ~ i z 0 ~ < z 8 { ( vec_push [u] hp # u 0 ) = z + z 1 }
    : i rc ( snd_pcm_open ( vec_data [u] hp ) `default` stream 0 )
    ? < rc 0 { ( vec_free [u] hp ) ^ # s 0 } {}
    : s pcm # s ( nurl_peek # s ( vec_data [u] hp ) 0 )
    ( vec_free [u] hp )
    ? == # i pcm 0 { ^ # s 0 } {}
    // 100 ms target latency, soft-resample on
    ? < ( snd_pcm_set_params pcm ( __snd_format_s16_le ) ( __snd_access_rw_inter ) ( audio_channels ) ( audio_rate ) 1 100000 ) 0 {
        ( snd_pcm_close pcm ) ^ # s 0
    } {}
    ^ pcm
}

// Open the default playback / capture device, or 0 if none (headless).
@ audio_play_open    → s { ^ ( __aud_open ( __snd_stream_playback ) ) }
@ audio_capture_open → s { ^ ( __aud_open ( __snd_stream_capture ) ) }

@ audio_close s pcm → v { ? != # i pcm 0 { ( snd_pcm_drain pcm ) ( snd_pcm_close pcm ) } {} }

// Play one PCM frame (Vec u of LE int16). No-op on a null handle.
@ audio_play s pcm ( Vec u ) frame → v {
    ? == # i pcm 0 { ^ v } {}
    : i frames / ( vec_len [u] frame ) 2
    ? <= frames 0 { ^ v } {}
    : i n ( snd_pcm_writei pcm ( vec_data [u] frame ) frames )
    ? < n 0 { ( snd_pcm_recover pcm n 1 ) } {}
}

// Capture `frames` samples → PCM (Vec u, 2*frames bytes). Empty on null handle
// (the app fills synth audio in that case) or on a short read.
@ audio_capture s pcm i frames → ( Vec u ) {
    ? == # i pcm 0 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) buf ( vec_with_cap [u] * frames 2 )
    : ~ i z 0 ~ < z * frames 2 { ( vec_push [u] buf # u 0 ) = z + z 1 }
    : i n ( snd_pcm_readi pcm ( vec_data [u] buf ) frames )
    ? < n 0 { ( snd_pcm_recover pcm n 1 ) ( vec_free [u] buf ) ^ ( vec_new [u] ) } {}
    : b _ok ( vec_set_len [u] buf * n 2 )
    ^ buf
}
