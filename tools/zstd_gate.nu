// tools/zstd_gate.nu — the differential harness for stdlib/std/zstd.nu.
//
// It does exactly one thing per invocation so the shell side can pin
// down which direction failed:
//
//   zstd_gate d <in.zst> <out>   decode a frame produced by the zstd CLI
//   zstd_gate e <in> <out.zst>   encode, for the CLI to decode
//   zstd_gate el <in> <out.zst> <level>
//   zstd_gate rt <in>            encode then decode in-process, compare
//   zstd_gate size <in.zst>      print the declared content size, or "-"
//   zstd_gate leak <in> [iters] [level]  round-trip N times, report RSS
//
// Exit status is 0 on success and 1 on a decoder error, with the error
// name on stderr — a corrupt-input test asserts on that name, so a
// crash and a refusal are never confused for one another.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/zstd.nu`
$ `stdlib/core/slice.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ __fail s msg → i {
    ( nurl_eprint msg )
    ( nurl_eprint `\n` )
    ^ 1
}

@ __read s path → !( Vec u ) IoErr { ^ ( read_file_bytes path ) }

@ __cmd_decode s inp s outp → i {
    ?? ( __read inp ) {
        T src → {
            ?? ( zstd_decode src ) {
                T out → {
                    ?? ( write_file_bytes outp out ) {
                        T _ok → {}
                        F _e → { ^ ( __fail `write failed` ) }
                    }
                    ^ 0
                }
                F e → {
                    ^ ( __fail ( zstd_err_name e ) )
                }
            }
        }
        F _e → { ^ ( __fail `read failed` ) }
    }
}

@ __cmd_encode s inp s outp i level → i {
    ?? ( __read inp ) {
        T src → {
            : ( Vec u ) out ( zstd_encode_at src level )
            ?? ( write_file_bytes outp out ) {
                T _ok → {}
                F _e → { ^ ( __fail `write failed` ) }
            }
            ^ 0
        }
        F _e → { ^ ( __fail `read failed` ) }
    }
}

@ __cmd_roundtrip s inp → i {
    ?? ( __read inp ) {
        T src → {
            : ( Vec u ) enc ( zstd_encode src )
            : ~ i rc 0
            ?? ( zstd_decode enc ) {
                T dec → {
                    ? ( vec_eq [u] src dec \ u a u b → b { ^ == a b } ) {} { = rc 1 }
                    ? != rc 0 { ( nurl_eprint `roundtrip mismatch\n` ) } {}
                }
                F e → {
                    ( nurl_eprint ( zstd_err_name e ) )
                    ( nurl_eprint `\n` )
                    = rc 1
                }
            }
            : String note ( string_with_cap 32 )
            ( string_push_int note ( vec_len [u] src ) )
            ( string_push_char note 32 )
            ( string_push_int note ( vec_len [u] enc ) )
            ( string_push_char note 10 )
            ( nurl_print ( string_data note ) )
            ^ rc
        }
        F _e → { ^ ( __fail `read failed` ) }
    }
}

// Resident set size in KiB, straight out of /proc. A leak shows up as
// a number that keeps climbing; nothing else about this process should.
@ __rss_kib → i {
    ?? ( read_file `/proc/self/statm` ) {
        T s → {
            // Field 2 is the resident page count.
            : s raw ( string_data s )
            : ( Slice u ) raw_v ( slice_of_str raw )
            : i n ( nurl_str_len raw )
            : ~ i k 0
            ~ & < k n != ( slice_byte raw_v k ) 32 { = k + k 1 }
            = k + k 1
            : ~ i pages 0
            ~ & < k n & >= ( slice_byte raw_v k ) 48 <= ( slice_byte raw_v k ) 57 {
                = pages + * pages 10 - ( slice_byte raw_v k ) 48
                = k + k 1
            }
            ^ * pages 4
        }
        F _e → { ^ -1 }
    }
}

// One encode + decode. A function of its own so both buffers are released
// when it returns — before the loop below reads the live-allocation count.
@ __round_trip ( Vec u ) src i level → b {
    : ( Vec u ) enc ( zstd_encode_at src level )
    ?? ( zstd_decode enc ) {
        T _ → { ^ T }
        F _e → { ^ F }
    }
}

// Encode and decode the same input `iters` times in ONE process and
// report resident size at three points. Unlike LeakSanitizer this works
// on a box whose stop-the-world tracer deadlocks (see the CLI package's
// notes), and unlike a single before/after reading it can TELL A LEAK
// FROM FRAGMENTATION: an allocator settling into a working set grows
// less and less, while a buffer leaked once per call grows the same
// amount in every equal-length stretch. So the readings straddle two
// stretches of the same length and the caller compares them.
//
// Output: `rss <at 10%> <at 55%> <at 100%> <iters> live <at 55%> <at 100%>`.
// `live` is the runtime's own count of allocations not yet freed: exact,
// where resident size is only a sample. A buffer orphaned once per round
// trip moves it by one per iteration however small the buffer, and RSS
// can miss that for a whole run (zstd_decode's output buffer did).
unsafe @ __cmd_leak s inp i iters i level → i {
    ?? ( __read inp ) {
        T src → {
            : ~ i warm 0
            : ~ i mid 0
            : ~ i live_mid 0
            : ~ i k 0
            : ~ i rc 0
            : i at_warm ? > / iters 10 1 / iters 10 1
            : i at_mid + at_warm / - iters at_warm 2
            ~ < k iters {
                ? ! ( __round_trip src level ) { = rc 1 } {}
                = k + k 1
                ? == k at_warm { = warm ( __rss_kib ) } {}
                ? == k at_mid { = mid ( __rss_kib ) = live_mid - ( nurl_alloc_count ) ( nurl_free_count ) } {}
            }
            : i after ( __rss_kib )
            : i live_after - ( nurl_alloc_count ) ( nurl_free_count )
            : String out ( string_with_cap 48 )
            ( string_push_str out `rss ` )
            ( string_push_int out warm )
            ( string_push_char out 32 )
            ( string_push_int out mid )
            ( string_push_char out 32 )
            ( string_push_int out after )
            ( string_push_char out 32 )
            ( string_push_int out iters )
            ( string_push_str out ` live ` )
            ( string_push_int out live_mid )
            ( string_push_char out 32 )
            ( string_push_int out live_after )
            ( string_push_char out 10 )
            ( nurl_print ( string_data out ) )
            ^ rc
        }
        F _e → { ^ ( __fail `read failed` ) }
    }
}

// Decode and report what the frame's sequences look like:
// "seqs N lit L match M rep R"
unsafe @ __cmd_stats s inp → i {
    ?? ( __read inp ) {
        T src → {
            : ~ i rc 0
            ?? ( zstd_decode src ) {
                T out → {}
                F _e → { = rc 1 }
            }
            : ( Vec i ) st ( zstd_seq_stats )
            : *i sp ( vec_data [i] st )
            : String o ( string_with_cap 96 )
            ( string_push_str o `seqs ` )
            ( string_push_int o # i . sp 0 )
            ( string_push_str o ` lit ` )
            ( string_push_int o # i . sp 1 )
            ( string_push_str o ` match ` )
            ( string_push_int o # i . sp 2 )
            ( string_push_str o ` rep ` )
            ( string_push_int o # i . sp 3 )
            ( string_push_char o 10 )
            ( nurl_print ( string_data o ) )
            ^ rc
        }
        F _e → { ^ ( __fail `read failed` ) }
    }
}

@ __cmd_size s inp → i {
    ?? ( __read inp ) {
        T src → {
            : String out ( string_with_cap 24 )
            ?? ( zstd_content_size src ) {
                T n → { ( string_push_int out n ) }
                F → { ( string_push_str out `-` ) }
            }
            ( string_push_char out 10 )
            ( nurl_print ( string_data out ) )
            ^ 0
        }
        F _e → { ^ ( __fail `read failed` ) }
    }
}

@ main → i {
    : i argc ( nurl_argv_count )
    ? < argc 3 { ^ ( __fail `usage: zstd_gate d|e|el|rt|size <in> [out] [level]` ) } {}
    : s mode ( nurl_argv_get 1 )
    : s inp ( nurl_argv_get 2 )
    ? ( nurl_str_eq mode `size` ) { ^ ( __cmd_size inp ) } {}
    ? ( nurl_str_eq mode `st` ) { ^ ( __cmd_stats inp ) } {}
    ? ( nurl_str_eq mode `rt` ) { ^ ( __cmd_roundtrip inp ) } {}
    ? ( nurl_str_eq mode `leak` ) {
        ^ ( __cmd_leak inp ? >= argc 4 ( nurl_str_to_int ( nurl_argv_get 3 ) ) 200
        ? >= argc 5 ( nurl_str_to_int ( nurl_argv_get 4 ) ) 3 )
    } {}
    ? < argc 4 { ^ ( __fail `missing output path` ) } {}
    : s outp ( nurl_argv_get 3 )
    ? ( nurl_str_eq mode `d` ) { ^ ( __cmd_decode inp outp ) } {}
    ? ( nurl_str_eq mode `e` ) { ^ ( __cmd_encode inp outp 3 ) } {}
    ? ( nurl_str_eq mode `el` ) {
        ? < argc 5 { ^ ( __fail `missing level` ) } {}
        ^ ( __cmd_encode inp outp ( nurl_str_to_int ( nurl_argv_get 4 ) ) )
    } {}
    ^ ( __fail `unknown mode` )
}
