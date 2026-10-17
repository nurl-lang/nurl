// packages/whisper/src/silero.nu — Silero VAD v5 (the 16 kHz network) on the CPU.
//
//   ( silero_open path )                → !Silero String
//   ( silero_state_new )                → SileroState    one per stream
//   ( silero_prob net st x off )        → f              p(speech) of x[off, off+512)
//
// An energy detector hears "loud enough"; this hears "a voice". A fan, a game's
// music, a keyboard or a door is loud and is not speech, and a quiet "neljä"
// at the end of a sentence is speech and is not loud — the cases a margin
// over a noise floor gets wrong in both directions. faster-whisper and
// whisper.cpp both ship Silero for that reason, and it is small enough to run
// on the CPU between WebSocket frames: 309 k weights, ~0.7 M multiply-adds
// per 32 ms of audio.
//
// The network, chunk by chunk (512 samples = 32 ms at 16 kHz):
//   64 samples of the previous chunk + the chunk, reflect-padded by 64 on the
//   right → a 256-point STFT, hop 128 (4 frames × 129 magnitudes)
//   → four conv1d (k3, pad 1; strides 1 2 2 1) with ReLU: 129→128→64→64→128
//   → one LSTM cell step (128), its state carried to the next chunk
//   → ReLU, a 1×1 conv to one logit, sigmoid.
// Checked against onnxruntime on the original ONNX file: max |Δp| 2·10⁻⁶.
//
// The weights are vad/silero_vad_v5.safetensors (tests/silero_export.py
// takes them from snakers4/silero-vad's ONNX file; MIT, vad/LICENSE-silero-vad).
// The STFT basis is not in the file: it is a periodic-Hann DFT, computed here.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `deps/safetensor/src/safetensor.nu`

// The chunk the network was trained on, and the context it carries over.
: i SILERO_CHUNK 512
: i __SV_CTX 64

: SileroW {
    ( Vec f ) cosb  // [129][256]: periodic Hann × cos
    ( Vec f ) sinb  // [129][256]: periodic Hann × −sin
    ( Vec f ) w0  // [128][129][3]
    ( Vec f ) b0
    ( Vec f ) w1  // [64][128][3], stride 2
    ( Vec f ) b1
    ( Vec f ) w2  // [64][64][3], stride 2
    ( Vec f ) b2
    ( Vec f ) w3  // [128][64][3]
    ( Vec f ) b3
    ( Vec f ) wih  // [512][128], gates i f g o
    ( Vec f ) whh  // [512][128]
    ( Vec f ) bsum  // bias_ih + bias_hh
    ( Vec f ) wd  // [128]
    f bd
}

// The network, read-only once loaded: every copy is the same weights, and
// every stream that runs it keeps its own SileroState.
: Silero { ( Arc SileroW ) a }

@ Silero_share Silero h → Silero { ^ @ Silero { ( arc_clone [SileroW] . h a ) } }

// The recurrent state and the 64-sample context of one stream.
: SileroState {
    ( Vec f ) h
    ( Vec f ) c
    ( Vec f ) ctx
}

@ __sv_zeros i n → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : b _r ( vec_resize_zeroed [f] v n )
    ^ v
}

@ silero_state_new → SileroState {
    ^ @ SileroState { ( __sv_zeros 128 ) ( __sv_zeros 128 ) ( __sv_zeros __SV_CTX ) }
}

// Forget everything heard: the state a fresh stream starts in.
@ silero_reset inout SileroState st → v {
    : ~ i k 0
    ~ < k 128 {
        ( vec_put [f] . st h k 0.0 )
        ( vec_put [f] . st c k 0.0 )
        = k + k 1
    }
    = k 0
    ~ < k __SV_CTX {
        ( vec_put [f] . st ctx k 0.0 )
        = k + k 1
    }
}

@ __sv_err s msg → !( Vec f ) String { ^ @ !( Vec f ) String { F ( string_from msg ) } }

// One f32 tensor of exactly `n` elements, widened.
@ __sv_tensor St st s name i n → !( Vec f ) String {
    : i ti ( st_find_tensor st name )
    ? < ti 0 {
        : String m ( string_from `silero: the weights file has no tensor ` )
        ( string_push_str m name )
        ^ @ !( Vec f ) String { F m }
    } {}
    ?? ( vec_get [StTensor] ( st_tensors st ) ti ) {
        T t → {
            ? | != . t dtype ST_F32 != . t nelems n {
                : String m ( string_from `silero: tensor ` )
                ( string_push_str m name )
                ( string_push_str m ` is not ` )
                ( string_push_int m n )
                ( string_push_str m ` f32 values` )
                ^ @ !( Vec f ) String { F m }
            } {}
            : ( Slice u ) b ( st_tensor_bytes st t )
            : ( Vec f ) out ( vec_with_cap [f] n )
            : ~ i k 0
            ~ < k n {
                ( vec_push [f] out # f ( bits_to_f32 ( slice_u32_le b * k 4 ) ) )
                = k + k 1
            }
            ^ @ !( Vec f ) String { T out }
        }
        F → { ^ ( __sv_err `silero: tensor index out of range` ) }
    }
}

// The STFT basis: row c is the periodic Hann window times cos (or −sin) of
// c cycles per 256 samples. The angle is reduced mod 256 in integers, so
// row 128 is as exact as row 1.
@ __sv_basis b sine → ( Vec f ) {
    : ( Vec f ) out ( vec_with_cap [f] * 129 256 )
    : f step / * 2.0 PI 256.0
    : ~ i c 0
    ~ < c 129 {
        : ~ i n 0
        ~ < n 256 {
            : f win - 0.5 * 0.5 ( cos * step # f n )
            : f ang * step # f % * c n 256
            ( vec_push [f] out ? sine * win - 0.0 ( sin ang ) * win ( cos ang ) )
            = n + n 1
        }
        = c + c 1
    }
    ^ out
}

// Load the network from a safetensors file holding the 16 kHz branch's
// weights under their PyTorch names (what tests/silero_export.py writes).
@ silero_open s path → !Silero String {
    ?? ( st_open path ) {
        T st → {
            : ( Vec String ) names ( vec_new [String] )
            ( vec_push [String] names ( string_from `encoder.0.reparam_conv.weight` ) )
            ( vec_push [String] names ( string_from `encoder.0.reparam_conv.bias` ) )
            ( vec_push [String] names ( string_from `encoder.1.reparam_conv.weight` ) )
            ( vec_push [String] names ( string_from `encoder.1.reparam_conv.bias` ) )
            ( vec_push [String] names ( string_from `encoder.2.reparam_conv.weight` ) )
            ( vec_push [String] names ( string_from `encoder.2.reparam_conv.bias` ) )
            ( vec_push [String] names ( string_from `encoder.3.reparam_conv.weight` ) )
            ( vec_push [String] names ( string_from `encoder.3.reparam_conv.bias` ) )
            ( vec_push [String] names ( string_from `decoder.rnn.weight_ih` ) )
            ( vec_push [String] names ( string_from `decoder.rnn.weight_hh` ) )
            ( vec_push [String] names ( string_from `decoder.rnn.bias_ih` ) )
            ( vec_push [String] names ( string_from `decoder.rnn.bias_hh` ) )
            ( vec_push [String] names ( string_from `decoder.decoder.2.weight` ) )
            ( vec_push [String] names ( string_from `decoder.decoder.2.bias` ) )
            : ( Vec i ) sizes ( vec_new [i] )
            ( vec_push [i] sizes * * 128 129 3 )
            ( vec_push [i] sizes 128 )
            ( vec_push [i] sizes * * 64 128 3 )
            ( vec_push [i] sizes 64 )
            ( vec_push [i] sizes * * 64 64 3 )
            ( vec_push [i] sizes 64 )
            ( vec_push [i] sizes * * 128 64 3 )
            ( vec_push [i] sizes 128 )
            ( vec_push [i] sizes * 512 128 )
            ( vec_push [i] sizes * 512 128 )
            ( vec_push [i] sizes 512 )
            ( vec_push [i] sizes 512 )
            ( vec_push [i] sizes 128 )
            ( vec_push [i] sizes 1 )
            : ( Vec ( Vec f ) ) ts ( vec_new [( Vec f )] )
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( __sv_tensor st ( string_data ( vec_at [String] names k ) ) ( vec_at [i] sizes k ) ) {
                    T v → { ( vec_push [( Vec f )] ts v ) }
                    F e → { ^ @ !Silero String { F e } }
                }
                = k + k 1
            }
            : ( Vec f ) bsum ( vec_with_cap [f] 512 )
            = k 0
            ~ < k 512 {
                ( vec_push [f] bsum + ( vec_at [f] ( vec_at [( Vec f )] ts 10 ) k ) ( vec_at [f] ( vec_at [( Vec f )] ts 11 ) k ) )
                = k + k 1
            }
            : SileroW w @ SileroW {
                ( __sv_basis F ) ( __sv_basis T )
                ( vec_at [( Vec f )] ts 0 ) ( vec_at [( Vec f )] ts 1 )
                ( vec_at [( Vec f )] ts 2 ) ( vec_at [( Vec f )] ts 3 )
                ( vec_at [( Vec f )] ts 4 ) ( vec_at [( Vec f )] ts 5 )
                ( vec_at [( Vec f )] ts 6 ) ( vec_at [( Vec f )] ts 7 )
                ( vec_at [( Vec f )] ts 8 ) ( vec_at [( Vec f )] ts 9 )
                bsum
                ( vec_at [( Vec f )] ts 12 ) ( vec_at [f] ( vec_at [( Vec f )] ts 13 ) 0 )
            }
            ^ @ !Silero String { T @ Silero { ( arc_new [SileroW] w ) } }
        }
        F e → { ^ @ !Silero String { F e } }
    }
}

// Where the weights live when no path is given — the same places the test
// page is looked for (nurlpkg stages [install].assets into share/whisper/):
//   <exe-dir>/vad/…, <exe-dir>/../share/whisper/vad/…, ./vad/… (package dir).
// "" = not found.
@ silero_default_path → String {
    : !String IoErr exe ( fs_readlink `/proc/self/exe` )
    ?? exe {
        T ep → {
            : String bindir ( path_dirname ( string_data ep ) )
            : String c1 ( path_join ( string_data bindir ) `vad/silero_vad_v5.safetensors` )
            ? ( file_exists ( string_data c1 ) ) { ^ c1 } {}
            : String c2 ( path_join ( string_data bindir ) `../share/whisper/vad/silero_vad_v5.safetensors` )
            ? ( file_exists ( string_data c2 ) ) { ^ c2 } {}
        }
        F _ → {}
    }
    ? ( file_exists `vad/silero_vad_v5.safetensors` ) { ^ ( string_from `vad/silero_vad_v5.safetensors` ) } {}
    ^ ( string_new )
}

@ __sv_sig f x → f { ^ / 1.0 + 1.0 ( exp - 0.0 x ) }

@ __sv_tanh f x → f { ^ - * 2.0 ( __sv_sig * 2.0 x ) 1.0 }

// conv1d, kernel 3, padding 1, then ReLU. `inp` is [cin][tin], `wt`
// [cout][cin][3]; the result is [cout][tout].
@ __sv_conv ( Vec f ) inp i cin i tin ( Vec f ) wt ( Vec f ) bias i cout i stride → ( Vec f ) {
    : i tout + / - + tin 2 3 stride 1
    : ( Vec f ) out ( vec_with_cap [f] * cout tout )
    : ~ i o 0
    ~ < o cout {
        : ~ i t 0
        ~ < t tout {
            : ~ f acc ( vec_at [f] bias o )
            : i t0 - * t stride 1
            : ~ i c 0
            ~ < c cin {
                : i wb * + * o cin c 3
                : i ib * c tin
                : ~ i j 0
                ~ < j 3 {
                    : i ti + t0 j
                    ? & >= ti 0 < ti tin {
                        = acc + acc * ( vec_at [f] wt + wb j ) ( vec_at [f] inp + ib ti )
                    } {}
                    = j + j 1
                }
                = c + c 1
            }
            ( vec_push [f] out ? > acc 0.0 acc 0.0 )
            = t + t 1
        }
        = o + o 1
    }
    ^ out
}

// p(speech) for the 512 samples x[off, off+512), advancing `st` past them.
// Chunks have to be fed in order and without gaps: the LSTM state and the
// 64-sample context are what the previous chunk left.
@ silero_prob Silero net inout SileroState st ( Vec f ) x i off → f {
    : SileroW w ( arc_get [SileroW] . net a )
    // context + chunk (576), reflect-padded by 64 on the right (640)
    : ( Vec f ) xp ( vec_with_cap [f] 640 )
    : ~ i k 0
    ~ < k __SV_CTX {
        ( vec_push [f] xp ( vec_at [f] . st ctx k ) )
        = k + k 1
    }
    = k 0
    ~ < k SILERO_CHUNK {
        ( vec_push [f] xp ( vec_at [f] x + off k ) )
        = k + k 1
    }
    = k 0
    ~ < k 64 {
        ( vec_push [f] xp ( vec_at [f] xp - 574 k ) )
        = k + k 1
    }
    = k 0
    ~ < k __SV_CTX {
        ( vec_put [f] . st ctx k ( vec_at [f] xp + SILERO_CHUNK k ) )
        = k + k 1
    }
    // |STFT|: [129][4]
    : ( Vec f ) mag ( vec_with_cap [f] * 129 4 )
    : ~ i c 0
    ~ < c 129 {
        : i bb * c 256
        : ~ i t 0
        ~ < t 4 {
            : i s0 * t 128
            : ~ f re 0.0
            : ~ f im 0.0
            : ~ i n 0
            ~ < n 256 {
                : f v ( vec_at [f] xp + s0 n )
                = re + re * v ( vec_at [f] . w cosb + bb n )
                = im + im * v ( vec_at [f] . w sinb + bb n )
                = n + n 1
            }
            ( vec_push [f] mag ( sqrt + * re re * im im ) )
            = t + t 1
        }
        = c + c 1
    }
    : ( Vec f ) e0 ( __sv_conv mag 129 4 . w w0 . w b0 128 1 )
    : ( Vec f ) e1 ( __sv_conv e0 128 4 . w w1 . w b1 64 2 )
    : ( Vec f ) e2 ( __sv_conv e1 64 2 . w w2 . w b2 64 2 )
    : ( Vec f ) e3 ( __sv_conv e2 64 1 . w w3 . w b3 128 1 )
    // the LSTM cell: gates = W_ih x + W_hh h + b, in PyTorch's i f g o order
    : ( Vec f ) g ( vec_with_cap [f] 512 )
    : ~ i r 0
    ~ < r 512 {
        : ~ f acc ( vec_at [f] . w bsum r )
        : i rb * r 128
        : ~ i q 0
        ~ < q 128 {
            = acc + acc + * ( vec_at [f] . w wih + rb q ) ( vec_at [f] e3 q ) * ( vec_at [f] . w whh + rb q ) ( vec_at [f] . st h q )
            = q + q 1
        }
        ( vec_push [f] g acc )
        = r + r 1
    }
    : ~ f z . w bd
    : ~ i q2 0
    ~ < q2 128 {
        : f ig ( __sv_sig ( vec_at [f] g q2 ) )
        : f fg ( __sv_sig ( vec_at [f] g + 128 q2 ) )
        : f gg ( __sv_tanh ( vec_at [f] g + 256 q2 ) )
        : f og ( __sv_sig ( vec_at [f] g + 384 q2 ) )
        : f cn + * fg ( vec_at [f] . st c q2 ) * ig gg
        : f hn * og ( __sv_tanh cn )
        ( vec_put [f] . st c q2 cn )
        ( vec_put [f] . st h q2 hn )
        ? > hn 0.0 { = z + z * ( vec_at [f] . w wd q2 ) hn } {}
        = q2 + q2 1
    }
    ^ ( __sv_sig z )
}
