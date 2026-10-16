// tests/mel_padded_check.nu — log_mel_whisper_padded against padding first.
//
//   mel_padded_check <audio.wav> [n_mels]
//
// Prints the number of values that differ (0 = bit-identical) and both
// timings. Exit 1 on any difference.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/time.nu`
$ `src/wav.nu`
$ `src/resample.nu`
$ `src/mel.nu`

@ main → i {
    : ArgParser p ( args_new `mel_padded_check` `` )
    ? ( args_parse_argv p ) {} { ^ 2 }
    : ( Vec String ) pos ( args_positionals p )
    : ~ s apath ``
    : ~ i nmel 80
    ?? ( vec_get [String] pos 0 ) { T c → { = apath ( string_data c ) } F → {} }
    ?? ( vec_get [String] pos 1 ) { T c → { ?? ( string_to_int c ) { T v → { = nmel v } F _ → {} } } F → {} }
    ?? ( wav_read apath ) {
        T aw → {
            : ( Vec f ) mono ( wav_mono aw )
            : ( Vec f ) x ( resample mono . aw rate 16000 )
            : i t0 ( monotonic_ns )
            : ( Vec f ) fixed ( pad_or_trim x 480000 )
            : ( Vec f ) a ( log_mel_whisper fixed 400 160 nmel 16000 )
            : i t1 ( monotonic_ns )
            : ( Vec f ) b ( log_mel_whisper_padded x 480000 400 160 nmel 16000 )
            : i t2 ( monotonic_ns )
            : ~ i diff 0
            ? != ( vec_len [f] a ) ( vec_len [f] b ) { = diff -1 } {
                : ~ i k 0
                ~ < k ( vec_len [f] a ) {
                    ? != ( vec_at [f] a k ) ( vec_at [f] b k ) { = diff + diff 1 } {}
                    = k + k 1
                }
            }
            : String m ( string_from `differ ` )
            ( string_push_int m diff )
            ( string_push_str m ` of ` )
            ( string_push_int m ( vec_len [f] a ) )
            ( string_push_str m ` full_ms ` )
            ( string_push_int m / - t1 t0 1000000 )
            ( string_push_str m ` padded_ms ` )
            ( string_push_int m / - t2 t1 1000000 )
            ( nurl_println ( string_data m ) )
            ^ ? == diff 0 0 1
        }
        F e → { ( nurl_eprintln ( string_data e ) ) ^ 1 }
    }
}
