// packages/audio/src/main.nu — the CLI.
//
//   audio info <file.wav>                 rate, channels, bits, duration
//   audio mel <file.wav> -o mel.f32       whisper log-mel (80 × 3000), raw f32 LE
//   audio resample <in.wav> <out.wav> --rate 16000
//   audio tone <out.wav> --rate 16000     a known signal, for tests
//   audio vad <file.wav>                  where the speech is (and how much is not)

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `src/wav.nu`
$ `src/mel.nu`
$ `src/resample.nu`
$ `src/vad.nu`

@ __say String m → v {
    ( nurl_print ( string_data m ) )
    ( nurl_print `\n` )
    ( string_free m )
}

// f32 little-endian bytes of a float vector — how a spectrogram leaves this
// program and reaches numpy (or a GPU).
@ __write_f32 s path ( Vec f ) v → i {
    : ( Vec u ) d ( vec_with_cap [u] * 4 ( vec_len [f] v ) )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ?? ( vec_get [f] v k ) {
            T x → { ( bytes_push_u32_le d # u32 ( f32_to_bits # f32 x ) ) }
            F → {}
        }
        = k + k 1
    }
    : ~ i rc 0
    ?? ( write_file_bytes path d ) {
        T _ → {}
        F _ → {
            ( nurl_eprintln `audio: cannot write output` )
            = rc 1
        }
    }
    ( vec_free [u] d )
    ^ rc
}

@ main → i {
    : ArgParser p ( args_new `audio` `Read WAV audio, resample it, and compute the log-mel spectrogram speech models eat.` )
    ( args_opt p `output` 111 `FILE` `for mel: write the f32-LE spectrogram here` )
    ( args_opt p `rate` 0 `HZ` `for resample/tone: the target sample rate (default 16000)` )
    ( args_opt p `seconds` 0 `S` `for tone: length in seconds (default 1)` )
    ( args_opt p `mels` 0 `N` `for mel: how many mel bands (default 80; whisper large-v3 wants 128)` )
    ( args_flag p `help` 104 `show this help` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  info <file.wav>\n  mel <file.wav> -o mel.f32\n  resample <in.wav> <out.wav> --rate 16000\n  vad <file.wav>\n  tone <out.wav> [--rate N] [--seconds S]\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    ? < ( args_positional_count p ) 2 {
        ( nurl_eprintln `usage: audio <info|mel|resample|tone> <file> … (audio --help)` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd ( string_data c ) } F → {} }
    : ~ s path ``
    ?? ( vec_get [String] pos 1 ) { T c → { = path ( string_data c ) } F → {} }
    : ~ s path2 ``
    ? >= ( args_positional_count p ) 3 {
        ?? ( vec_get [String] pos 2 ) { T c → { = path2 ( string_data c ) } F → {} }
    } {}
    : ~ i want_rate 16000
    : String srate ( args_value_or p `rate` `16000` )
    ?? ( string_to_int srate ) { T v → { = want_rate v } F _ → {} }
    ( string_free srate )

    // `tone` writes a file rather than reading one
    ? ( nurl_str_eq cmd `tone` ) {
        : ~ i secs 1
        : String ssecs ( args_value_or p `seconds` `1` )
        ?? ( string_to_int ssecs ) { T v → { = secs v } F _ → {} }
        ( string_free ssecs )
        : i n * want_rate secs
        : ( Vec f ) x ( vec_with_cap [f] n )
        : ~ i k 0
        ~ < k n {
            // 440 Hz + 1 kHz, so a spectrogram has something to show
            : f t / # f k # f want_rate
            ( vec_push [f] x + * 0.5 ( sin * * 2.0 3.14159265358979323846 * 440.0 t )
            * 0.25 ( sin * * 2.0 3.14159265358979323846 * 1000.0 t ) )
            = k + k 1
        }
        : ~ i rc 0
        ?? ( wav_write path x want_rate 1 ) {
            T _ → {}
            F e → {
                ( nurl_eprintln ( string_data e ) )
                ( string_free e )
                = rc 1
            }
        }
        ( vec_free [f] x )
        ( args_free p )
        ^ rc
    } {}

    ?? ( wav_read path ) {
        T w → {
            : ~ i rc 0
            ? ( nurl_str_eq cmd `info` ) {
                : i frames / ( vec_len [f] . w samples ) . w channels
                : String m ( string_from `wav — ` )
                ( string_push_int m . w rate )
                ( string_push_str m ` Hz, ` )
                ( string_push_int m . w channels )
                ( string_push_str m ` ch, ` )
                ( string_push_int m . w bits )
                ( string_push_str m ` bit, ` )
                ( string_push_int m frames )
                ( string_push_str m ` frames (` )
                ( string_push_float m / # f frames # f . w rate )
                ( string_push_str m ` s)` )
                ( __say m )
            } {}
            ? ( nurl_str_eq cmd `mel` ) {
                : ~ i nmel 80
                : String smel ( args_value_or p `mels` `80` )
                ?? ( string_to_int smel ) { T v → { = nmel v } F _ → {} }
                ( string_free smel )
                : ( Vec f ) mono ( wav_mono w )
                : ( Vec f ) at16 ( resample mono . w rate 16000 )
                // whisper always feeds its encoder exactly 30 s
                : ( Vec f ) fixed ( pad_or_trim at16 480000 )
                : ( Vec f ) mel ( log_mel_whisper fixed 400 160 nmel 16000 )
                : String o ( args_value_or p `output` `mel.f32` )
                = rc ( __write_f32 ( string_data o ) mel )
                : String m ( string_from `mel — ` )
                ( string_push_int m / ( vec_len [f] mel ) nmel )
                ( string_push_str m ` frames x ` )
                ( string_push_int m nmel )
                ( string_push_str m ` mels → ` )
                ( string_push_str m ( string_data o ) )
                ( __say m )
                ( string_free o )
                ( vec_free [f] mono )
                ( vec_free [f] at16 )
                ( vec_free [f] fixed )
                ( vec_free [f] mel )
            } {}
            ? ( nurl_str_eq cmd `vad` ) {
                : ( Vec f ) mono ( wav_mono w )
                : ( Vec f ) at16 ( resample mono . w rate 16000 )
                : ( Vec VadSeg ) segs ( vad_segments at16 16000 ( vad_default_opts ) )
                : i total ( vec_len [f] at16 )
                : i voiced ( vad_voiced_samples segs )
                : ~ i k 0
                ~ < k ( vec_len [VadSeg] segs ) {
                    ?? ( vec_get [VadSeg] segs k ) {
                        T sg → {
                            : String m ( string_new )
                            ( string_push_float m / # f . sg start 16000.0 )
                            ( string_push_str m ` - ` )
                            ( string_push_float m / # f . sg end 16000.0 )
                            ( string_push_str m ` s` )
                            ( __say m )
                        }
                        F → {}
                    }
                    = k + k 1
                }
                : String m ( string_from `vad — ` )
                ( string_push_int m ( vec_len [VadSeg] segs ) )
                ( string_push_str m ` segment(s), ` )
                ( string_push_float m / * 100.0 # f voiced # f ? > total 0 total 1 )
                ( string_push_str m ` % of the audio is speech` )
                ( __say m )
                ( vec_free [f] mono )
                ( vec_free [f] at16 )
                ( vec_free [VadSeg] segs )
            } {}
            ? ( nurl_str_eq cmd `resample` ) {
                : ( Vec f ) mono ( wav_mono w )
                : ( Vec f ) rs ( resample mono . w rate want_rate )
                ?? ( wav_write path2 rs want_rate 1 ) {
                    T _ → {}
                    F e → {
                        ( nurl_eprintln ( string_data e ) )
                        ( string_free e )
                        = rc 1
                    }
                }
                ( vec_free [f] mono )
                ( vec_free [f] rs )
            } {}
            ( wav_free w )
            ( args_free p )
            ^ rc
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ( args_free p )
            ^ 1
        }
    }
}
