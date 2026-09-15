// gen_test.nu — the whole pipeline against PyTorch: sampler and vocoder.
//
// tests/ref_gen.py generates one utterance with the reference implementation
// and writes the noise it started from. Starting from the same noise, the
// same trajectory should come out — so this compares the integrated mel frame
// by frame, and then the waveform sample by sample.
//
//   /tmp/g5 <ckpt.safetensors> <vocab.txt> <vocos.bin> <refdir> <ref_audio_len> <nfe>

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/time.nu`
$ `deps/audio/src/wav.nu`
$ `src/model.nu`
$ `src/sample.nu`
$ `src/vocos.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ __g_path s dir s name → String {
    : String p ( string_from dir )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

@ __g_read_f32 s dir s name → ( Vec f ) {
    : String p ( __g_path dir name )
    : ( Vec f ) out ( vec_new [f] )
    ?? ( read_file_bytes ( string_data p ) ) {
        T bs → {
            : i n / ( vec_len [u] bs ) 4
            : ~ i k 0
            ~ < k n {
                ?? ( bytes_read_f32_le bs * k 4 ) { T x → { ( vec_push [f] out # f x ) } F → {} }
                = k + k 1
            }
            ( vec_free [u] bs )
        }
        F _e → { ( nurl_eprint `cannot read ` ) ( nurl_eprintln ( string_data p ) ) }
    }
    ( string_free p )
    ^ out
}

@ __g_read_i32 s dir s name → ( Vec i ) {
    : String p ( __g_path dir name )
    : ( Vec i ) out ( vec_new [i] )
    ?? ( read_file_bytes ( string_data p ) ) {
        T bs → {
            : i n / ( vec_len [u] bs ) 4
            : ~ i k 0
            ~ < k n {
                ?? ( bytes_read_u32_le bs * k 4 ) { T x → { ( vec_push [i] out # i x ) } F → {} }
                = k + k 1
            }
            ( vec_free [u] bs )
        }
        F _e → {}
    }
    ( string_free p )
    ^ out
}

@ __g_get ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

@ __g_cmp ( Vec f ) got ( Vec f ) want s label f tol → v {
    : i n ( vec_len [f] want )
    : i gn ( vec_len [f] got )
    ? != n gn {
        ( nurl_print `  FAIL ` ) ( nurl_print label )
        ( nurl_print ` — length ` ) ( nurl_print_int gn )
        ( nurl_print ` but the reference has ` ) ( nurl_print_int n )
        ( nurl_print `\n` )
        = g_fail + g_fail 1
        ^ v
    } {}
    : ~ f md 0.0
    : ~ f mx 1.0e-12
    : ~ i k 0
    ~ < k n {
        : f w ( __g_get want k )
        : f d ( fabs - ( __g_get got k ) w )
        ? > d md { = md d } {}
        ? > ( fabs w ) mx { = mx ( fabs w ) } {}
        = k + k 1
    }
    : f rel / md mx
    : String m ( string_from label )
    ( string_push_str m `  max |Δ| ` )
    ( string_push_float m md )
    ( string_push_str m `  relative ` )
    ( string_push_float m rel )
    ? < rel tol { ( nurl_print `  ok   ` ) = g_pass + g_pass 1 } {
        ( nurl_print `  FAIL ` ) = g_fail + g_fail 1
    }
    ( nurl_println ( string_data m ) )
    ( string_free m )
}

@ main → i {
    ? < ( nurl_argv_count ) 8 {
        ( nurl_eprintln `usage: gen_test <ckpt> <vocab> <vocos.bin> <refdir> <ref_audio_len> <nfe> <rms>` )
        ^ 2
    } {}
    : s ckpt ( nurl_argv_get 1 )
    : s vocab ( nurl_argv_get 2 )
    : s vocp ( nurl_argv_get 3 )
    : s dir ( nurl_argv_get 4 )
    : i ref_len ( nurl_str_to_int ( nurl_argv_get 5 ) )
    : i nfe ( nurl_str_to_int ( nurl_argv_get 6 ) )

    : ( Vec i ) ids ( __g_read_i32 dir `text_ids.i32` )
    : ( Vec f ) noise ( __g_read_f32 dir `noise.f32` )
    : ( Vec f ) cond ( __g_read_f32 dir `cond_mel.f32` )
    : ( Vec f ) want_y ( __g_read_f32 dir `y_final.f32` )
    : ( Vec f ) want_w ( __g_read_f32 dir `wave.f32` )
    : i duration / ( vec_len [f] noise ) 100
    ( nurl_print `duration ` ) ( nurl_print_int duration )
    ( nurl_print ` frames, reference ` ) ( nurl_print_int / ( vec_len [f] cond ) 100 )
    ( nurl_print ` frames, ` ) ( nurl_print_int ( vec_len [i] ids ) )
    ( nurl_print ` characters, ` ) ( nurl_print_int nfe ) ( nurl_print ` steps\n` )

    ?? ( f5_open ckpt vocab -1 ) {
        T m → {
            : ( Vec f ) y ( vec_new [f] )
            : i t0 ( now_ms )
            ? ( f5_sample m ids duration cond nfe 2.0 -1.0 noise y ) {} {
                ( nurl_eprintln `sampling failed` ) ( f5_close m ) ^ 1
            }
            : i t1 ( now_ms )
            ( __g_cmp y want_y `the integrated mel` 2.0e-3 )
            ( nurl_print `  (sampling took ` ) ( nurl_print_int - t1 t0 ) ( nurl_print ` ms)\n` )

            // The conditioned frames are put back before the cut, and the cut
            // is one frame SHORTER than the conditioning: the reference mel
            // has 1 + samples/hop frames where ref_audio_len is samples/hop,
            // so the generated segment starts on the reference's own last
            // frame. Slice without restoring and that frame is the ODE's
            // guess instead — audible for the first quarter-second, because
            // the vocoder's eight dilation-free blocks still reach 24 frames
            // either side of it.
            : i cond_frames / ( vec_len [f] cond ) 100
            : ~ i k 0
            ~ < k * cond_frames 100 { ( vec_set [f] y k ( __g_get cond k ) ) = k + k 1 }
            : i gen_frames - duration ref_len
            : ( Vec f ) gmel ( vec_with_cap [f] * gen_frames 100 )
            = k 0
            ~ < k * gen_frames 100 {
                ( vec_push [f] gmel ( __g_get y + * ref_len 100 k ) )
                = k + k 1
            }
            ?? ( voc_open vocp ( f5_kit m ) ) {
                T vc → {
                    : ( Vec f ) wave ( vec_new [f] )
                    : i t2 ( now_ms )
                    ? ( voc_decode vc gmel gen_frames wave ) {} {
                        ( nurl_eprintln `vocoder failed` ) ( voc_close vc ) ( f5_close m ) ^ 1
                    }
                    : i t3 ( now_ms )
                    // infer_batch_process normalises the reference recording up
                    // to an rms of 0.1 before the mel, and scales the result
                    // back down by the same factor afterwards
                    : f rms ( nurl_str_to_float ( nurl_argv_get 7 ) )
                    ? < rms 0.1 {
                        : ~ i j 0
                        ~ < j ( vec_len [f] wave ) {
                            ( vec_set [f] wave j * ( __g_get wave j ) / rms 0.1 )
                            = j + j 1
                        }
                    } {}
                    ( __g_cmp wave want_w `the waveform` 5.0e-3 )
                    ( nurl_print `  (vocoder took ` ) ( nurl_print_int - t3 t2 ) ( nurl_print ` ms)\n` )
                    : String outp ( __g_path dir `nurl.wav` )
                    ?? ( wav_write ( string_data outp ) wave 24000 1 ) {
                        T _ → { ( nurl_print `  wrote ` ) ( nurl_println ( string_data outp ) ) }
                        F e → { ( nurl_eprintln ( string_data e ) ) ( string_free e ) }
                    }
                    ( string_free outp )
                    ( vec_free [f] wave )
                    ( voc_close vc )
                }
                F e → { ( nurl_eprintln ( string_data e ) ) ( string_free e ) }
            }
            ( vec_free [f] gmel )
            ( vec_free [f] y )
            ( f5_close m )
        }
        F e → { ( nurl_eprintln ( string_data e ) ) ( string_free e ) ^ 1 }
    }
    ( nurl_print `\npassed ` ) ( nurl_print_int g_pass )
    ( nurl_print `, failed ` ) ( nurl_print_int g_fail ) ( nurl_print `\n` )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
