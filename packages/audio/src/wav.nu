// packages/audio/src/wav.nu — RIFF/WAVE, read and write.
//
// The chunk layout is the whole format, and it is also the whole attack
// surface: every chunk announces its own size, and a file is free to lie about
// it. So the reader walks the chunks with a bounded cursor — a size that runs
// past the end of the file, a `data` chunk longer than the bytes that follow, a
// zero or absurd sample rate, a channel count of 0, a bit depth nobody has ever
// used: all of them are a clean error, none of them are an allocation sized by
// what the header claimed.
//
//   ( wav_read path )                  → !Wav String      f32 samples, interleaved
//   ( wav_read_mono_16k path )         → !( Vec f ) String  what speech models want
//   ( wav_write path samples rate ch ) → !v String        16-bit PCM
//   ( wav_free w )                     → v
//
// Samples come back as f32 in [-1, 1], whatever the file stored them as:
// 8-bit unsigned, 16/24/32-bit signed PCM, or 32/64-bit IEEE float.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/float.nu`

: i WAV_PCM 1
: i WAV_FLOAT 3
: i WAV_EXTENSIBLE 65534

: Wav {
    ( Vec f ) samples  // interleaved
    i channels
    i rate
    i bits  // as stored in the file (informational)
}

@ wav_free Wav w → v {
    ( vec_free [f] . w samples )
}

@ __wav_err s msg → !Wav String {
    ^ @ !Wav String { F ( string_from msg ) }
}

// A bounded cursor over the file bytes. Every read checks the budget against
// what is LEFT, never by forming off + k (which a hostile size would wrap).
: WCur {
    ( Vec u ) d
    i n
    i off
    b fail
}

@ __wc_need inout WCur c i k → b {
    ? . c fail { ^ F } {}
    ? | < k 0 > k - . c n . c off { = . c fail T ^ F } {}
    ^ T
}

@ __wc_u8 inout WCur c → i {
    ? ( __wc_need c 1 ) {} { ^ 0 }
    : i v ( __wbyte . c d . c off )
    = . c off + . c off 1
    ^ v
}

@ __wbyte ( Vec u ) d i k → i {
    ?? ( vec_get [u] d k ) { T b → { ^ # i b } F → { ^ 0 } }
}

@ __wc_u16 inout WCur c → i {
    ? ( __wc_need c 2 ) {} { ^ 0 }
    : i o . c off
    = . c off + o 2
    ^ | ( __wbyte . c d o ) << ( __wbyte . c d + o 1 ) 8
}

@ __wc_u32 inout WCur c → i {
    ? ( __wc_need c 4 ) {} { ^ 0 }
    : i o . c off
    = . c off + o 4
    ^ | ( __wbyte . c d o ) | << ( __wbyte . c d + o 1 ) 8
    | << ( __wbyte . c d + o 2 ) 16 << ( __wbyte . c d + o 3 ) 24
}

@ __wc_tag inout WCur c → i {
    ? ( __wc_need c 4 ) {} { ^ 0 }
    : i o . c off
    = . c off + o 4
    // big-endian so a tag compares as the four ASCII bytes in order
    ^ | << ( __wbyte . c d o ) 24 | << ( __wbyte . c d + o 1 ) 16
    | << ( __wbyte . c d + o 2 ) 8 ( __wbyte . c d + o 3 )
}

// 'RIFF' 'WAVE' 'fmt ' 'data' as big-endian 32-bit constants
@ __tag s four → i {
    ^ | << ( nurl_str_get four 0 ) 24 | << ( nurl_str_get four 1 ) 16
    | << ( nurl_str_get four 2 ) 8 ( nurl_str_get four 3 )
}

// Sign-extend a little-endian integer of `bytes` width read from the data.
@ __wav_int ( Vec u ) d i off i bytes → i {
    : ~ i v 0
    : ~ i k 0
    ~ < k bytes {
        = v | v << ( __wbyte d + off k ) * 8 k
        = k + k 1
    }
    : i bits * 8 bytes
    : i half << 1 - bits 1
    ^ ? >= v half - v << 1 bits v
}

@ wav_read s path → !Wav String {
    ?? ( read_file_bytes path ) {
        T data → {
            : !Wav String r ( __wav_parse data )
            ( vec_free [u] data )
            ^ r
        }
        F _ → {
            : String m ( string_from `wav: cannot read ` )
            ( string_push_str m path )
            ^ @ !Wav String { F m }
        }
    }
}

@ __wav_parse ( Vec u ) data → !Wav String {
    : i n ( vec_len [u] data )
    ? < n 12 { ^ ( __wav_err `wav: file too small to be RIFF` ) } {}
    : ~ WCur c @ WCur { data n 0 F }
    ? != ( __wc_tag c ) ( __tag `RIFF` ) { ^ ( __wav_err `wav: not a RIFF file` ) } {}
    : i _riff_size ( __wc_u32 c )
    ? != ( __wc_tag c ) ( __tag `WAVE` ) { ^ ( __wav_err `wav: RIFF file is not WAVE` ) } {}

    : ~ i fmt -1
    : ~ i ch 0
    : ~ i rate 0
    : ~ i bits 0
    : ~ i data_off -1
    : ~ i data_len 0

    // Walk the chunks. A chunk whose size runs past the end of the file is a
    // truncated (or lying) file — stop, do not read what is not there.
    ~ & ! . c fail <= + . c off 8 n {
        : i tag ( __wc_tag c )
        : i sz ( __wc_u32 c )
        ? . c fail {} {}
        ? | < sz 0 > sz - n . c off {
            ^ ( __wav_err `wav: a chunk claims more bytes than the file holds` )
        } {}
        ? == tag ( __tag `fmt ` ) {
            ? < sz 16 { ^ ( __wav_err `wav: fmt chunk is too short` ) } {}
            : i base . c off
            = fmt ( __wc_u16 c )
            = ch ( __wc_u16 c )
            = rate ( __wc_u32 c )
            : i _byterate ( __wc_u32 c )
            : i _align ( __wc_u16 c )
            = bits ( __wc_u16 c )
            // WAVE_FORMAT_EXTENSIBLE hides the real format in its GUID's first
            // two bytes; everything else about the fmt chunk is the same.
            ? & == fmt WAV_EXTENSIBLE >= sz 40 {
                = . c off + base 24
                = fmt ( __wc_u16 c )
            } {}
            = . c off + base sz
        } {
            ? == tag ( __tag `data` ) {
                = data_off . c off
                = data_len sz
                = . c off + . c off sz
            } {
                = . c off + . c off sz
            }
        }
        // chunks are word-aligned: an odd size carries one pad byte
        ? & == 1 % sz 2 < . c off n { = . c off + . c off 1 } {}
    }
    ? . c fail { ^ ( __wav_err `wav: truncated chunk header` ) } {}
    ? < fmt 0 { ^ ( __wav_err `wav: no fmt chunk` ) } {}
    ? < data_off 0 { ^ ( __wav_err `wav: no data chunk` ) } {}
    ? | < ch 1 > ch 64 { ^ ( __wav_err `wav: channel count out of range` ) } {}
    ? | < rate 1 > rate 4000000 { ^ ( __wav_err `wav: sample rate out of range` ) } {}
    ? & != fmt WAV_PCM != fmt WAV_FLOAT {
        ^ ( __wav_err `wav: not PCM or IEEE-float (compressed WAV is not supported)` )
    } {}
    : i bps / bits 8
    ? | | == bps 0 > bps 8 != 0 % bits 8 {
        ^ ( __wav_err `wav: unsupported bit depth` )
    } {}
    ? & == fmt WAV_FLOAT & != bits 32 != bits 64 {
        ^ ( __wav_err `wav: float WAV must be 32- or 64-bit` )
    } {}

    : i frame * bps ch
    : i nframes / data_len frame
    : ( Vec f ) out ( vec_with_cap [f] * nframes ch )
    : f scale ? == bits 8 128.0 ? == bits 16 32768.0 ? == bits 24 8388608.0 2147483648.0
    : ~ i k 0
    ~ < k * nframes ch {
        : i off + data_off * k bps
        : ~ f v 0.0
        ? == fmt WAV_FLOAT {
            ? == bits 32 {
                : i b32 ( __wav_uint data off 4 )
                = v # f ( bits_to_f32 b32 )
            } {
                = v ( bits_to_f64 ( __wav_uint data off 8 ) )
            }
        } {
            ? == bits 8 {
                // 8-bit WAV is UNSIGNED, alone among the PCM depths
                = v / - # f ( __wbyte data off ) 128.0 128.0
            } {
                = v / # f ( __wav_int data off bps ) scale
            }
        }
        ( vec_push [f] out v )
        = k + k 1
    }
    ^ @ !Wav String { T @ Wav { out ch rate bits } }
}

// Unsigned little-endian read of `bytes` bytes (for the float bit patterns).
@ __wav_uint ( Vec u ) d i off i bytes → i {
    : ~ i v 0
    : ~ i k 0
    ~ < k bytes {
        = v | v << ( __wbyte d + off k ) * 8 k
        = k + k 1
    }
    ^ v
}

// ── mono ────────────────────────────────────────────────────────────

// Average the channels. (Speech models want one channel; picking the left one
// throws away half of a stereo recording's information.)
@ wav_mono Wav w → ( Vec f ) {
    : i ch . w channels
    : i n / ( vec_len [f] . w samples ) ch
    : ( Vec f ) out ( vec_with_cap [f] n )
    ? == ch 1 {
        : ~ i k 0
        ~ < k n {
            ( vec_push [f] out ( __wget . w samples k ) )
            = k + k 1
        }
        ^ out
    } {}
    : ~ i k 0
    ~ < k n {
        : ~ f s 0.0
        : ~ i c 0
        ~ < c ch {
            = s + s ( __wget . w samples + * k ch c )
            = c + c 1
        }
        ( vec_push [f] out / s # f ch )
        = k + k 1
    }
    ^ out
}

@ __wget ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// ── write ───────────────────────────────────────────────────────────

@ __wpush_u32 ( Vec u ) d i v → v {
    ( vec_push [u] d # u & v 255 )
    ( vec_push [u] d # u & >> v 8 255 )
    ( vec_push [u] d # u & >> v 16 255 )
    ( vec_push [u] d # u & >> v 24 255 )
}

@ __wpush_u16 ( Vec u ) d i v → v {
    ( vec_push [u] d # u & v 255 )
    ( vec_push [u] d # u & >> v 8 255 )
}

@ __wpush_tag ( Vec u ) d s four → v {
    : ~ i k 0
    ~ < k 4 {
        ( vec_push [u] d # u ( nurl_str_get four k ) )
        = k + k 1
    }
}

// 16-bit PCM, which every tool on earth reads.
@ wav_write s path ( Vec f ) samples i rate i channels → !v String {
    : i n ( vec_len [f] samples )
    : i data_len * n 2
    : ( Vec u ) d ( vec_with_cap [u] + 44 data_len )
    ( __wpush_tag d `RIFF` )
    ( __wpush_u32 d + 36 data_len )
    ( __wpush_tag d `WAVE` )
    ( __wpush_tag d `fmt ` )
    ( __wpush_u32 d 16 )
    ( __wpush_u16 d WAV_PCM )
    ( __wpush_u16 d channels )
    ( __wpush_u32 d rate )
    ( __wpush_u32 d * * rate channels 2 )
    ( __wpush_u16 d * channels 2 )
    ( __wpush_u16 d 16 )
    ( __wpush_tag d `data` )
    ( __wpush_u32 d data_len )
    : ~ i k 0
    ~ < k n {
        : f v ( __wget samples k )
        : f cl ? > v 1.0 1.0 ? < v -1.0 -1.0 v
        : i q # i ( round * cl 32767.0 )
        ( __wpush_u16 d & q 65535 )
        = k + k 1
    }
    ?? ( write_file_bytes path d ) {
        T _ → {
            ( vec_free [u] d )
            ^ @ !v String { T 0 }
        }
        F _ → {
            ( vec_free [u] d )
            ^ @ !v String { F ( string_from `wav: cannot write file` ) }
        }
    }
}
