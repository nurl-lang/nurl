// packages/audio/src/mp3.nu — MPEG-1/2/2.5 Layer III, encoding side.
//
// An MP3 encoder in pure NURL, because a program that can only hand back WAV
// is a program that cannot answer `output_format: "mp3"`, and shelling out to
// ffmpeg is not an answer — it moves the dependency, it does not remove it.
//
//   ( mp3_encode samples rate channels bitrate )  → !( Vec u ) String
//
// `samples` are f32 in [-1, 1], interleaved when `channels` is 2. `rate` must
// be one of the nine the format defines — 32/44.1/48 kHz (MPEG-1),
// 16/22.05/24 kHz (MPEG-2) or 8/11.025/12 kHz (MPEG-2.5) — and `bitrate` one
// the chosen version allows. Anything else is an error naming what was wrong,
// never a silently resampled guess.
//
// WHAT IS AND IS NOT HERE. This is the full Layer III bitstream: the polyphase
// analysis filterbank, the 18-point MDCT with its alias-reduction butterflies,
// the quantiser's step-size search, Huffman coding over the big-values regions
// and the count1 quadruples, and a frame layout a decoder reads without
// knowing where it came from. What is NOT here is a psychoacoustic model.
// There is no masking threshold, so there are no scalefactors — every band
// gets the same step size, chosen only to fill the frame. That is the shape
// the fixed-point encoder `shine` proved is enough for speech and it is the
// honest description of the quality: the bits go where the signal is loud,
// not where the ear is deaf. For speech at 128 kbps the difference is not
// audible; for music at 64 it would be.
//
// Long blocks only (block_type 0). Window switching exists to stop pre-echo on
// transients, and choosing when to switch is a psychoacoustic decision, so it
// belongs with the model that is not here rather than guessed at.
//
// THE SCALE. Every value below is an ordinary f64, but the arithmetic mirrors
// a fixed-point encoder's exactly: a sample of 1.0 is what a decoder will call
// full scale, and the quantiser's `2^(-step/4)` lands on the same integers.
// The three factors of 0.5 in the filterbank and the MDCT are what make that
// true — they are not a normalisation choice, they are the >>32 of the
// fixed-point original written out.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `mp3tab.nu`

: i MP3_GRAN 576
: i MP3_HAN 512
: f MP3_PI 3.14159265358979323846

// One granule's side information. Each (granule, channel) owns ten of these
// slots in a flat array; the fields that only matter inside the quantiser's
// loop live on the encoder itself as `c_*`.
: i MP3_SI_PART23 0
: i MP3_SI_BIGV 1
: i MP3_SI_CNT1 2
: i MP3_SI_GGAIN 3
: i MP3_SI_TS0 4
: i MP3_SI_TS1 5
: i MP3_SI_TS2 6
: i MP3_SI_R0 7
: i MP3_SI_R1 8
: i MP3_SI_C1T 9
: i MP3_SI_N 10

: Mp3 {
    i channels
    i rate
    i sri  // samplerate index 0..8
    i version  // 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5
    i gpf  // granules per frame: 2 for MPEG-1, 1 otherwise
    i bri  // bitrate index as it goes in the header
    i sideinfo_len  // bits
    i whole_slots
    f frac_slots
    f slot_lag
    i padding
    i mean_bits
    i resv_size
    i resv_drain
    // tables, built once
    ( Vec f ) enw  // 512 analysis window coefficients
    ( Vec f ) fl  // 32 x 64 filterbank
    ( Vec f ) cosl  // 18 x 36 windowed MDCT basis
    ( Vec f ) ca  // 8 alias-reduction coefficients
    ( Vec f ) cs  // and their companions
    ( Vec i ) sfb  // 9 x 23 scalefactor band starts
    ( Vec i ) hcode
    ( Vec i ) hlen
    ( Vec i ) hxlen
    ( Vec i ) hylen
    ( Vec i ) hlinbits
    ( Vec i ) hlinmax
    ( Vec i ) hoff
    ( Vec i ) sdv0  // region0 band count per big-values width
    ( Vec i ) sdv1  // region1 band count
    ( Vec i ) idx34  // x^(3/4) for x = 0..9999
    // running state
    ( Vec f ) xbuf  // channels x 512, the filterbank's memory
    ( Vec i ) xoff  // where each channel's ring cursor sits
    ( Vec f ) sb  // channels x (gpf+1) x 18 x 32 subband samples
    ( Vec f ) xr  // channels x gpf x 576 spectral values
    ( Vec i ) ix  // the same, quantised
    ( Vec i ) si  // gpf x channels x 10
    ( Vec f ) yw  // 64 scratch
    ( Vec f ) mdin  // 36 scratch
    // the granule being worked on
    i c_bigv
    i c_cnt1
    i c_ts0
    i c_ts1
    i c_ts2
    i c_r0
    i c_r1
    i c_c1t
    i c_a1
    i c_a2
    i c_a3
    i c_step
    // output
    ( Vec u ) out
    i cache
    i cbits
}

@ mp3_free sink * Mp3 m → v {
    ( vec_free [f] . m enw )
    ( vec_free [f] . m fl )
    ( vec_free [f] . m cosl )
    ( vec_free [f] . m ca )
    ( vec_free [f] . m cs )
    ( vec_free [i] . m sfb )
    ( vec_free [i] . m hcode )
    ( vec_free [i] . m hlen )
    ( vec_free [i] . m hxlen )
    ( vec_free [i] . m hylen )
    ( vec_free [i] . m hlinbits )
    ( vec_free [i] . m hlinmax )
    ( vec_free [i] . m hoff )
    ( vec_free [i] . m sdv0 )
    ( vec_free [i] . m sdv1 )
    ( vec_free [i] . m idx34 )
    ( vec_free [f] . m xbuf )
    ( vec_free [i] . m xoff )
    ( vec_free [f] . m sb )
    ( vec_free [f] . m xr )
    ( vec_free [i] . m ix )
    ( vec_free [i] . m si )
    ( vec_free [f] . m yw )
    ( vec_free [f] . m mdin )
    ( vec_free [u] . m out )
    ( nurl_free # s m )
}

// ---------------------------------------------------------------- tables

// The nine rates the format defines, in the order the header numbers them.
@ __mp3_srate_index i rate → i {
    ? == rate 44100 { ^ 0 } {}
    ? == rate 48000 { ^ 1 } {}
    ? == rate 32000 { ^ 2 } {}
    ? == rate 22050 { ^ 3 } {}
    ? == rate 24000 { ^ 4 } {}
    ? == rate 16000 { ^ 5 } {}
    ? == rate 11025 { ^ 6 } {}
    ? == rate 12000 { ^ 7 } {}
    ? == rate 8000 { ^ 8 } {}
    ^ -1
}

// bitrates[index][version], version 0 = MPEG-2.5, 2 = MPEG-2, 3 = MPEG-1.
// Index 0 is free format and 15 is forbidden; both read as -1 here, so no
// caller can ask for them by accident.
@ __mp3_bitrate_table → ( Vec i ) {
    : ( Vec i ) v ( _mp3_zeros 64 )
    : *i p ( vec_data [i] v )
    : ~ i at 0
    = at ( _mp3_pl8 p at -1 -1 -1 -1 8 -1 8 32 )
    = at ( _mp3_pl8 p at 16 -1 16 40 24 -1 24 48 )
    = at ( _mp3_pl8 p at 32 -1 32 56 40 -1 40 64 )
    = at ( _mp3_pl8 p at 48 -1 48 80 56 -1 56 96 )
    = at ( _mp3_pl8 p at 64 -1 64 112 -1 -1 80 128 )
    = at ( _mp3_pl8 p at -1 -1 96 160 -1 -1 112 192 )
    = at ( _mp3_pl8 p at -1 -1 128 224 -1 -1 144 256 )
    = at ( _mp3_pl8 p at -1 -1 160 320 -1 -1 -1 -1 )
    ^ v
}

@ __mp3_bitrate_index i bitr i version → i {
    : ( Vec i ) t ( __mp3_bitrate_table )
    : *i p ( vec_data [i] t )
    : ~ i found -1
    : ~ i k 0
    ~ < k 16 {
        : i here . p + * k 4 version
        ? & < found 0 == here bitr { = found k } {}
        = k + k 1
    }
    ( vec_free [i] t )
    ^ found
}

// Which big-values width gets how many scalefactor bands in region 0 and
// region 1. The two regions exist so three different Huffman books can cover
// one granule; the split points have to fall on band boundaries.
@ __mp3_subdv0 → ( Vec i ) {
    : ( Vec i ) v ( _mp3_zeros 24 )
    : *i p ( vec_data [i] v )
    : ~ i at 0
    = at ( _mp3_pl8 p at 0 0 0 0 0 0 1 1 )
    = at ( _mp3_pl8 p at 1 2 2 2 3 3 3 4 )
    = at ( _mp3_pl8 p at 4 4 5 5 5 6 6 0 )
    ^ v
}

@ __mp3_subdv1 → ( Vec i ) {
    : ( Vec i ) v ( _mp3_zeros 24 )
    : *i p ( vec_data [i] v )
    : ~ i at 0
    = at ( _mp3_pl8 p at 0 0 0 0 0 1 1 1 )
    = at ( _mp3_pl8 p at 2 2 3 3 4 4 4 5 )
    = at ( _mp3_pl8 p at 5 6 6 6 7 7 7 0 )
    ^ v
}

// The filterbank, rounded to the nine decimals the ISO tables carry. The
// rounding is not cosmetic: it is what makes this filterbank the standard's
// filterbank rather than one that merely comes very close to it.
@ __mp3_build_fl → ( Vec f ) {
    : ( Vec f ) v ( _mp3_fzeros 2048 )
    : *f p ( vec_data [f] v )
    : f step / MP3_PI 64.0
    : ~ i i 0
    ~ < i 32 {
        : i two_i_1 + * 2 i 1
        : ~ i j 0
        ~ < j 64 {
            : i k - 16 j
            : f ang * step * # f two_i_1 # f k
            : f c * 1.0e9 ( cos ang )
            : f r ? >= c 0.0 ( floor + c 0.5 ) ( ceil - c 0.5 )
            = . p + * i 64 j / r 1.0e9
            = j + j 1
        }
        = i + i 1
    }
    ^ v
}

// Window and basis folded into one table: the MDCT of a long block is a
// 36-tap dot product per output, and the sine window belongs inside it.
@ __mp3_build_cosl → ( Vec f ) {
    : ( Vec f ) v ( _mp3_fzeros 648 )
    : *f p ( vec_data [f] v )
    : f pi36 / MP3_PI 36.0
    : f pi72 / MP3_PI 72.0
    : ~ i mm 0
    ~ < mm 18 {
        : i two_m_1 + * 2 mm 1
        : ~ i k 0
        ~ < k 36 {
            : f w ( sin * pi36 + # f k 0.5 )
            : i two_k_19 + * 2 k 19
            : f ang * pi72 * # f two_k_19 # f two_m_1
            = . p + * mm 36 k * w ( cos ang )
            = k + k 1
        }
        = mm + mm 1
    }
    ^ v
}

// Table B.9: the butterfly between neighbouring bands cancels the aliasing
// the filterbank introduced, and the decoder runs the same one backwards.
// `which` 0 gives the c/sqrt(1+c²) half, 1 the 1/sqrt(1+c²) half.
@ __mp3_alias_c i which → ( Vec f ) {
    : ( Vec f ) v ( _mp3_fzeros 8 )
    : *f p ( vec_data [f] v )
    : ( Vec f ) src ( _mp3_fzeros 8 )
    : *f s ( vec_data [f] src )
    = . s 0 -0.6
    = . s 1 -0.535
    = . s 2 -0.33
    = . s 3 -0.185
    = . s 4 -0.095
    = . s 5 -0.041
    = . s 6 -0.0142
    = . s 7 -0.0037
    : ~ i k 0
    ~ < k 8 {
        : f c . s k
        : f d ( sqrt + 1.0 * c c )
        = . p k ? == which 0 / c d / 1.0 d
        = k + k 1
    }
    ( vec_free [f] src )
    ^ v
}

// x^(3/4) with the standard's -0.0946 offset and a rounding half, for every
// integer a quantised value can reach before the escape path takes over.
@ __mp3_build_idx34 → ( Vec i ) {
    : ( Vec i ) v ( _mp3_zeros 10000 )
    : *i p ( vec_data [i] v )
    : ~ i k 0
    ~ < k 10000 {
        = . p k # i + ( pow # f k 0.75 ) 0.4054
        = k + k 1
    }
    ^ v
}

// ---------------------------------------------------------------- the encoder

@ __mp3_new i rate i channels i bitrate → !*Mp3 String {
    ? | < channels 1 > channels 2 {
        ^ @ !*Mp3 String { F ( string_from `mp3: only mono and stereo exist in this format` ) }
    } {}
    : i sri ( __mp3_srate_index rate )
    ? < sri 0 {
        : String e ( string_from `mp3: ` )
        ( string_push_int e rate )
        ( string_push_str e ` Hz is not an MPEG sample rate (32000/44100/48000, 16000/22050/24000, 8000/11025/12000)` )
        ^ @ !*Mp3 String { F e }
    } {}
    : i version ? < sri 3 3 ? < sri 6 2 0
    : i gpf ? == version 3 2 1
    : i bri ( __mp3_bitrate_index bitrate version )
    ? < bri 0 {
        : String e ( string_from `mp3: ` )
        ( string_push_int e bitrate )
        ( string_push_str e ` kbit/s is not a bitrate this MPEG version allows at ` )
        ( string_push_int e rate )
        ( string_push_str e ` Hz` )
        ^ @ !*Mp3 String { F e }
    } {}
    : *Mp3 m # *Mp3 ( nurl_alloc Z Mp3 )
    = . m channels channels
    = . m rate rate
    = . m sri sri
    = . m version version
    = . m gpf gpf
    = . m bri bri
    // A frame carries the header, the side information, and then as many
    // whole bytes ("slots") as the bitrate buys. The rate rarely divides
    // evenly, so the leftover fraction accumulates and buys one extra slot
    // whenever it crosses — that is the padding bit in the header.
    : i sil ? == gpf 2 ? == channels 1 168 288 ? == channels 1 104 168
    = . m sideinfo_len sil
    : f nsamp * # f gpf 576.0
    : f bits_per_sec * 1000.0 # f bitrate
    : f avg / * nsamp bits_per_sec * # f rate 8.0
    : i whole # i avg
    = . m whole_slots whole
    = . m frac_slots - avg # f whole
    = . m slot_lag - 0.0 . m frac_slots
    = . m padding 0
    = . m mean_bits 0
    = . m resv_size 0
    = . m resv_drain 0
    = . m enw ( _mp3_enwindow )
    = . m fl ( __mp3_build_fl )
    = . m cosl ( __mp3_build_cosl )
    = . m ca ( __mp3_alias_c 0 )
    = . m cs ( __mp3_alias_c 1 )
    = . m sfb ( _mp3_sfb_index )
    = . m hcode ( _mp3_hcode )
    = . m hlen ( _mp3_hlen )
    = . m hxlen ( _mp3_hxlen )
    = . m hylen ( _mp3_hylen )
    = . m hlinbits ( _mp3_hlinbits )
    = . m hlinmax ( _mp3_hlinmax )
    = . m hoff ( _mp3_hoff )
    = . m sdv0 ( __mp3_subdv0 )
    = . m sdv1 ( __mp3_subdv1 )
    = . m idx34 ( __mp3_build_idx34 )
    = . m xbuf ( _mp3_fzeros * channels MP3_HAN )
    = . m xoff ( _mp3_zeros channels )
    = . m sb ( _mp3_fzeros * * channels + gpf 1 576 )
    = . m xr ( _mp3_fzeros * * channels gpf MP3_GRAN )
    = . m ix ( _mp3_zeros * * channels gpf MP3_GRAN )
    = . m si ( _mp3_zeros * * gpf channels MP3_SI_N )
    = . m yw ( _mp3_fzeros 64 )
    = . m mdin ( _mp3_fzeros 36 )
    = . m c_bigv 0
    = . m c_cnt1 0
    = . m c_ts0 0
    = . m c_ts1 0
    = . m c_ts2 0
    = . m c_r0 0
    = . m c_r1 0
    = . m c_c1t 0
    = . m c_a1 0
    = . m c_a2 0
    = . m c_a3 0
    = . m c_step 0
    = . m out ( vec_new [u] )
    = . m cache 0
    = . m cbits 0
    ^ @ !*Mp3 String { T m }
}

// ---------------------------------------------------------------- bit output

// Bits go in most-significant first, which is the only order the format has.
@ __mp3_putbits * Mp3 m i val i n → v {
    : ~ i k n
    ~ > k 0 {
        = k - k 1
        : i bit & >> val k 1
        = . m cache | << . m cache 1 bit
        = . m cbits + . m cbits 1
        ? == . m cbits 8 {
            ( vec_push [u] . m out # u & . m cache 255 )
            = . m cache 0
            = . m cbits 0
        } {}
    }
}

@ __mp3_bitpos * Mp3 m → i {
    ^ + * ( vec_len [u] . m out ) 8 . m cbits
}

// ------------------------------------------------------ analysis filterbank

// 32 new samples in, 32 subband samples out. The window buffer is a ring of
// 512: each call drops the oldest 32 and the cursor walks back by 32 (480
// forward, modulo 512), which is why the samples go in backwards.
@ __mp3_subband * Mp3 m ( Vec f ) pcm i npcm i pos i stride i ch i sbase → v {
    : *f x ( vec_data [f] . m xbuf )
    : *f ew ( vec_data [f] . m enw )
    : *f flp ( vec_data [f] . m fl )
    : *f y ( vec_data [f] . m yw )
    : *f sbp ( vec_data [f] . m sb )
    : *f src ( vec_data [f] pcm )
    : *i offp ( vec_data [i] . m xoff )
    : i xb * ch MP3_HAN
    : i off . offp ch
    : ~ i mm 0
    ~ < mm 32 {
        : i idx + pos * mm stride
        : f s ? < idx npcm . src idx 0.0
        = . x + xb & + off - 31 mm 511 s
        = mm + mm 1
    }
    // Fold the 512-tap window down to 64 by adding the eight 64-sample
    // stretches on top of each other: the polyphase identity that turns one
    // long convolution into 32 short ones.
    : ~ i i 0
    ~ < i 64 {
        : ~ f acc 0.0
        : ~ i j 0
        ~ < j 8 {
            : i k << j 6
            : f xv . x + xb & + + off i k 511
            : f wv . ew + i k
            = acc + acc * xv wv
            = j + j 1
        }
        = . y i * 0.5 acc
        = i + i 1
    }
    = . offp ch & + off 480 511
    = i 0
    ~ < i 32 {
        : i fb * i 64
        : ~ f acc 0.0
        : ~ i j 0
        ~ < j 64 {
            : f fv . flp + fb j
            : f yv . y j
            = acc + acc * fv yv
            = j + j 1
        }
        = . sbp + sbase i * 0.5 acc
        = i + i 1
    }
}

@ __mp3_sb_row * Mp3 m i ch i g i k → i {
    : i per + . m gpf 1
    ^ * + * + * ch per g 18 k 32
}

// Polyphase, then the MDCT of 18 previous subband samples with 18 new ones.
@ __mp3_mdct * Mp3 m ( Vec f ) pcm i npcm i base → v {
    : i chn . m channels
    : i gpf . m gpf
    : *f sbp ( vec_data [f] . m sb )
    : *f xrp ( vec_data [f] . m xr )
    : *f mi ( vec_data [f] . m mdin )
    : *f cosl ( vec_data [f] . m cosl )
    : *f cap ( vec_data [f] . m ca )
    : *f csp ( vec_data [f] . m cs )
    : ~ i ch 0
    ~ < ch chn {
        : ~ i gr 0
        ~ < gr gpf {
            : ~ i k 0
            ~ < k 18 {
                : i off * * + * gr 18 k 32 chn
                ( __mp3_subband m pcm npcm + base + off ch chn ch
                ( __mp3_sb_row m ch + gr 1 k ) )
                = k + k 1
            }
            // The analysis filter inverts every other band on every other
            // row; undoing it here is cheaper than a second filterbank.
            = k 1
            ~ < k 18 {
                : i row ( __mp3_sb_row m ch + gr 1 k )
                : ~ i band 1
                ~ < band 32 {
                    : i at + row band
                    = . sbp at - 0.0 . sbp at
                    = band + band 2
                }
                = k + k 2
            }
            : i xrbase * + * ch gpf gr MP3_GRAN
            : ~ i band 0
            ~ < band 32 {
                = k 0
                ~ < k 18 {
                    : i r0 ( __mp3_sb_row m ch gr k )
                    : i r1 ( __mp3_sb_row m ch + gr 1 k )
                    = . mi k . sbp + r0 band
                    = . mi + k 18 . sbp + r1 band
                    = k + k 1
                }
                : i obase + xrbase * band 18
                : ~ i mm 0
                ~ < mm 18 {
                    : i cb * mm 36
                    : ~ f acc 0.0
                    : ~ i j 0
                    ~ < j 36 {
                        : f iv . mi j
                        : f cvv . cosl + cb j
                        = acc + acc * iv cvv
                        = j + j 1
                    }
                    = . xrp + obase mm * 0.5 acc
                    = mm + mm 1
                }
                ? > band 0 {
                    : i pbase + xrbase * - band 1 18
                    : ~ i t 0
                    ~ < t 8 {
                        : i ia + obase t
                        : i ib + pbase - 17 t
                        : f a . xrp ia
                        : f b . xrp ib
                        : f cv . csp t
                        : f av . cap t
                        = . xrp ia - * a cv * b av
                        = . xrp ib + * b cv * a av
                        = t + t 1
                    }
                } {}
                = band + band 1
            }
            = gr + gr 1
        }
        // The last granule's subband samples are the next frame's history.
        : i from ( __mp3_sb_row m ch gpf 0 )
        : i to ( __mp3_sb_row m ch 0 0 )
        : ~ i k 0
        ~ < k 576 {
            = . sbp + to k . sbp + from k
            = k + k 1
        }
        = ch + ch 1
    }
}

// ---------------------------------------------------------------- quantiser

// Every spectral value divided by one step size and raised to 3/4, which is
// the companding curve the format fixes. `step` is the exponent the decoder
// will undo; a larger step is a coarser grid and fewer bits.
@ __mp3_quantize * Mp3 m i xrbase i ixbase i step f xrmax → i {
    : f e / # f - 0 step 4.0
    : f scale ( pow 2.0 e )
    // 8192^(4/3): past this the values no longer fit the code books, so
    // there is nothing to learn from finishing the pass.
    ? > * xrmax scale 165140.0 { ^ 16384 } {}
    : *f xrp ( vec_data [f] . m xr )
    : *i ixp ( vec_data [i] . m ix )
    : *i t34 ( vec_data [i] . m idx34 )
    : ~ i mx 0
    : ~ i i 0
    ~ < i MP3_GRAN {
        : f xv . xrp + xrbase i
        : f u * ( fabs xv ) scale
        : ~ i q 0
        ? < u 9999.0 {
            : i ln # i + u 0.5
            = q . t34 ln
        } {
            = q # i ( pow u 0.75 )
        }
        = . ixp + ixbase i q
        ? > q mx { = mx q } {}
        = i + i 1
    }
    ^ mx
}

@ __mp3_ix_max * Mp3 m i ixbase i begin i end → i {
    : *i ixp ( vec_data [i] . m ix )
    : ~ i mx 0
    : ~ i i begin
    ~ < i end {
        : i v . ixp + ixbase i
        ? > v mx { = mx v } {}
        = i + i 1
    }
    ^ mx
}

// A granule ends in zeros, and before them in values of at most one. Those
// two tails get cheaper codings than the general one, so the boundaries
// between the three areas are worth finding exactly.
@ __mp3_calc_runlen * Mp3 m i ixbase → v {
    : *i ixp ( vec_data [i] . m ix )
    : ~ i i MP3_GRAN
    : ~ b stop F
    ~ & > i 1 ! stop {
        : i a . ixp + ixbase - i 1
        : i b . ixp + ixbase - i 2
        ? & == a 0 == b 0 { = i - i 2 } { = stop T }
    }
    = . m c_cnt1 0
    = stop F
    ~ & > i 3 ! stop {
        : i a . ixp + ixbase - i 1
        : i b . ixp + ixbase - i 2
        : i c . ixp + ixbase - i 3
        : i d . ixp + ixbase - i 4
        ? & & <= a 1 <= b 1 & <= c 1 <= d 1 {
            = . m c_cnt1 + . m c_cnt1 1
            = i - i 4
        } { = stop T }
    }
    = . m c_bigv >> i 1
}

// The quadruple area has two code books and no way to tell in advance which
// is cheaper, so both are counted and the smaller wins.
@ __mp3_count1_bits * Mp3 m i ixbase → i {
    : *i ixp ( vec_data [i] . m ix )
    : *i hl ( vec_data [i] . m hlen )
    : *i ho ( vec_data [i] . m hoff )
    : i o32 . ho 32
    : i o33 . ho 33
    : ~ i sum0 0
    : ~ i sum1 0
    : ~ i i << . m c_bigv 1
    : ~ i k 0
    ~ < k . m c_cnt1 {
        : i v . ixp + ixbase i
        : i w . ixp + ixbase + i 1
        : i x . ixp + ixbase + i 2
        : i y . ixp + ixbase + i 3
        : i p + + + v << w 1 << x 2 << y 3
        : ~ i sg 0
        ? != v 0 { = sg + sg 1 } {}
        ? != w 0 { = sg + sg 1 } {}
        ? != x 0 { = sg + sg 1 } {}
        ? != y 0 { = sg + sg 1 } {}
        : i l0 . hl + o32 p
        : i l1 . hl + o33 p
        = sum0 + sum0 + sg l0
        = sum1 + sum1 + sg l1
        = i + i 4
        = k + k 1
    }
    ? < sum0 sum1 { = . m c_c1t 0 ^ sum0 } { = . m c_c1t 1 ^ sum1 }
}

// Where the big-values area splits into its three regions. The split has to
// land on a scalefactor band boundary, so this walks the band table down from
// the nominal count until it finds one that fits.
@ __mp3_subdivide * Mp3 m → v {
    ? == . m c_bigv 0 {
        = . m c_r0 0
        = . m c_r1 0
        = . m c_a1 0
        = . m c_a2 0
        = . m c_a3 0
    } {
        : *i sf ( vec_data [i] . m sfb )
        : *i d0 ( vec_data [i] . m sdv0 )
        : *i d1 ( vec_data [i] . m sdv1 )
        : i sb0 * . m sri 23
        : i bvr << . m c_bigv 1
        : ~ i anz 0
        : ~ b go T
        ~ go {
            : i sv . sf + sb0 anz
            ? < sv bvr { = anz + anz 1 } { = go F }
        }
        : ~ i tc . d0 anz
        : ~ b done F
        ~ & > tc 0 ! done {
            : i sv . sf + sb0 + tc 1
            ? <= sv bvr { = done T } { = tc - tc 1 }
        }
        = . m c_r0 tc
        = . m c_a1 . sf + sb0 + tc 1
        : i base2 + sb0 + tc 1
        = tc . d1 anz
        = done F
        ~ & > tc 0 ! done {
            : i sv . sf + base2 + tc 1
            ? <= sv bvr { = done T } { = tc - tc 1 }
        }
        = . m c_r1 tc
        = . m c_a2 . sf + base2 + tc 1
        = . m c_a3 bvr
    }
}

@ __mp3_count_bit * Mp3 m i ixbase i start i end i table → i {
    ? == table 0 { ^ 0 } {}
    : *i ixp ( vec_data [i] . m ix )
    : *i hl ( vec_data [i] . m hlen )
    : *i ho ( vec_data [i] . m hoff )
    : *i hy ( vec_data [i] . m hylen )
    : *i hb ( vec_data [i] . m hlinbits )
    : i off . ho table
    : i ylen . hy table
    : i linbits . hb table
    : i esc ? > table 15 1 0
    : ~ i sum 0
    : ~ i i start
    ~ < i end {
        : ~ i x . ixp + ixbase i
        : ~ i y . ixp + ixbase + i 1
        ? == esc 1 {
            ? > x 14 { = x 15 = sum + sum linbits } {}
            ? > y 14 { = y 15 = sum + sum linbits } {}
        } {}
        : i l . hl + off + * x ylen y
        = sum + sum l
        ? != x 0 { = sum + sum 1 } {}
        ? != y 0 { = sum + sum 1 } {}
        = i + i 2
    }
    ^ sum
}

// Which code book spends the fewest bits on this stretch. The candidates are
// not arbitrary: the books come in families that only differ in how far they
// reach, so the first one wide enough is the first one worth counting, and
// only its near neighbours can beat it.
@ __mp3_choose_table * Mp3 m i ixbase i begin i end → i {
    : i mx0 ( __mp3_ix_max m ixbase begin end )
    ? == mx0 0 { ^ 0 } {}
    : *i hx ( vec_data [i] . m hxlen )
    : *i hm ( vec_data [i] . m hlinmax )
    ? < mx0 15 {
        : ~ i ch0 0
        : ~ i i 14
        : ~ b go T
        ~ & > i 0 go {
            = i - i 1
            : i xl . hx i
            ? > xl mx0 { = ch0 i = go F } {}
        }
        : ~ i s0 ( __mp3_count_bit m ixbase begin end ch0 )
        ? == ch0 2 {
            : i s1 ( __mp3_count_bit m ixbase begin end 3 )
            ? <= s1 s0 { = ch0 3 } {}
        } {}
        ? == ch0 5 {
            : i s1 ( __mp3_count_bit m ixbase begin end 6 )
            ? <= s1 s0 { = ch0 6 } {}
        } {}
        ? == ch0 7 {
            : i s1 ( __mp3_count_bit m ixbase begin end 8 )
            ? <= s1 s0 { = ch0 8 = s0 s1 } {}
            : i s2 ( __mp3_count_bit m ixbase begin end 9 )
            ? <= s2 s0 { = ch0 9 } {}
        } {}
        ? == ch0 10 {
            : i s1 ( __mp3_count_bit m ixbase begin end 11 )
            ? <= s1 s0 { = ch0 11 = s0 s1 } {}
            : i s2 ( __mp3_count_bit m ixbase begin end 12 )
            ? <= s2 s0 { = ch0 12 } {}
        } {}
        ? == ch0 13 {
            : i s1 ( __mp3_count_bit m ixbase begin end 15 )
            ? <= s1 s0 { = ch0 15 } {}
        } {}
        ^ ch0
    } {}
    // Above 14 the value rides in an escape field, and the two families
    // differ in how wide that field is.
    : i rest - mx0 15
    : ~ i ca0 0
    : ~ i cb0 0
    : ~ i i 15
    : ~ b go T
    ~ & < i 24 go {
        : i lm . hm i
        ? >= lm rest { = ca0 i = go F } {}
        = i + i 1
    }
    = i 24
    = go T
    ~ & < i 32 go {
        : i lm . hm i
        ? >= lm rest { = cb0 i = go F } {}
        = i + i 1
    }
    : i sa ( __mp3_count_bit m ixbase begin end ca0 )
    : i sbv ( __mp3_count_bit m ixbase begin end cb0 )
    ? < sbv sa { ^ cb0 } {}
    ^ ca0
}

@ __mp3_bigv_tab_select * Mp3 m i ixbase → v {
    = . m c_ts0 0
    = . m c_ts1 0
    = . m c_ts2 0
    ? > . m c_a1 0 {
        = . m c_ts0 ( __mp3_choose_table m ixbase 0 . m c_a1 )
    } {}
    ? > . m c_a2 . m c_a1 {
        = . m c_ts1 ( __mp3_choose_table m ixbase . m c_a1 . m c_a2 )
    } {}
    : i bvr << . m c_bigv 1
    ? > bvr . m c_a2 {
        = . m c_ts2 ( __mp3_choose_table m ixbase . m c_a2 bvr )
    } {}
}

@ __mp3_bigv_bitcount * Mp3 m i ixbase → i {
    : ~ i bits 0
    ? != . m c_ts0 0 {
        = bits + bits ( __mp3_count_bit m ixbase 0 . m c_a1 . m c_ts0 )
    } {}
    ? != . m c_ts1 0 {
        = bits + bits ( __mp3_count_bit m ixbase . m c_a1 . m c_a2 . m c_ts1 )
    } {}
    ? != . m c_ts2 0 {
        = bits + bits ( __mp3_count_bit m ixbase . m c_a2 . m c_a3 . m c_ts2 )
    } {}
    ^ bits
}

// A step size that nearly fills the frame, found by halving rather than by
// walking: 120 candidate exponents, seven counts.
@ __mp3_bin_search * Mp3 m i xrbase i ixbase f xrmax i desired → i {
    : ~ i next -120
    : ~ i count 120
    : ~ b go T
    ~ go {
        : i half / count 2
        : ~ i bit 0
        : i mx ( __mp3_quantize m xrbase ixbase + next half xrmax )
        ? > mx 8192 {
            = bit 100000
        } {
            ( __mp3_calc_runlen m ixbase )
            = bit ( __mp3_count1_bits m ixbase )
            ( __mp3_subdivide m )
            ( __mp3_bigv_tab_select m ixbase )
            = bit + bit ( __mp3_bigv_bitcount m ixbase )
        }
        ? < bit desired { = count half } {
            = next + next half
            = count - count half
        }
        ? > count 1 {} { = go F }
    }
    ^ next
}

// From there, one step at a time until the granule fits. Without a masking
// model there is nothing else to trade: the step size IS the bit allocation.
@ __mp3_inner_loop * Mp3 m i xrbase i ixbase f xrmax i max_bits → i {
    : ~ i bits 0
    ? < max_bits 0 { = . m c_step - . m c_step 1 } {}
    : ~ b done F
    ~ ! done {
        : ~ b ok F
        ~ ! ok {
            = . m c_step + . m c_step 1
            : i mx ( __mp3_quantize m xrbase ixbase . m c_step xrmax )
            ? > mx 8192 {} { = ok T }
        }
        ( __mp3_calc_runlen m ixbase )
        = bits ( __mp3_count1_bits m ixbase )
        ( __mp3_subdivide m )
        ( __mp3_bigv_tab_select m ixbase )
        = bits + bits ( __mp3_bigv_bitcount m ixbase )
        ? > bits max_bits {} { = done T }
    }
    ^ bits
}

// ------------------------------------------------------------ frame assembly

@ __mp3_iteration * Mp3 m → v {
    : i chn . m channels
    : i gpf . m gpf
    : *f xrp ( vec_data [f] . m xr )
    : *i sip ( vec_data [i] . m si )
    : i per_ch / . m mean_bits chn
    : ~ i ch 0
    ~ < ch chn {
        : ~ i gr 0
        ~ < gr gpf {
            : i xrbase * + * ch gpf gr MP3_GRAN
            : ~ f xrmax 0.0
            : ~ i i 0
            ~ < i MP3_GRAN {
                : f a ( fabs . xrp + xrbase i )
                ? > a xrmax { = xrmax a } {}
                = i + i 1
            }
            : ~ i maxb per_ch
            ? > maxb 4095 { = maxb 4095 } {}
            = . m c_bigv 0
            = . m c_cnt1 0
            = . m c_ts0 0
            = . m c_ts1 0
            = . m c_ts2 0
            = . m c_r0 0
            = . m c_r1 0
            = . m c_c1t 0
            = . m c_a1 0
            = . m c_a2 0
            = . m c_a3 0
            = . m c_step 0
            : ~ i part23 0
            ? > xrmax 0.0 {
                = . m c_step ( __mp3_bin_search m xrbase xrbase xrmax maxb )
                = part23 ( __mp3_inner_loop m xrbase xrbase xrmax maxb )
            } {}
            = . m resv_size + . m resv_size - per_ch part23
            : i sb0 * + * gr chn ch MP3_SI_N
            = . sip + sb0 MP3_SI_PART23 part23
            = . sip + sb0 MP3_SI_BIGV . m c_bigv
            = . sip + sb0 MP3_SI_CNT1 . m c_cnt1
            = . sip + sb0 MP3_SI_GGAIN + . m c_step 210
            = . sip + sb0 MP3_SI_TS0 . m c_ts0
            = . sip + sb0 MP3_SI_TS1 . m c_ts1
            = . sip + sb0 MP3_SI_TS2 . m c_ts2
            = . sip + sb0 MP3_SI_R0 . m c_r0
            = . sip + sb0 MP3_SI_R1 . m c_r1
            = . sip + sb0 MP3_SI_C1T . m c_c1t
            = gr + gr 1
        }
        = ch + ch 1
    }
    ( __mp3_resv_end m )
}

// This encoder never carries bits forward into the next frame, so whatever a
// granule did not spend has to be spent here, as stuffing. A frame that came
// out short is a frame the next sync word starts in the middle of.
@ __mp3_resv_end * Mp3 m → v {
    : *i sip ( vec_data [i] . m si )
    = . m resv_drain 0
    ? & == . m channels 2 == & . m mean_bits 1 1 {
        = . m resv_size + . m resv_size 1
    } {}
    : ~ i over . m resv_size
    ? < over 0 { = over 0 } {}
    = . m resv_size - . m resv_size over
    : ~ i stuff over
    : i rem - . m resv_size * / . m resv_size 8 8
    ? != rem 0 {
        = stuff + stuff rem
        = . m resv_size - . m resv_size rem
    } {}
    ? > stuff 0 {
        : i cur . sip MP3_SI_PART23
        ? < + cur stuff 4095 {
            = . sip MP3_SI_PART23 + cur stuff
        } {
            : ~ i left stuff
            : ~ i gr 0
            ~ < gr . m gpf {
                : ~ i ch 0
                ~ < ch . m channels {
                    ? > left 0 {
                        : i sb0 * + * gr . m channels ch MP3_SI_N
                        : i c . sip + sb0 MP3_SI_PART23
                        : i extra - 4095 c
                        : i take ? < extra left extra left
                        = . sip + sb0 MP3_SI_PART23 + c take
                        = left - left take
                    } {}
                    = ch + ch 1
                }
                = gr + gr 1
            }
            // Anything still left over becomes ancillary data at the end of
            // the frame, which is where the standard says it may go.
            = . m resv_drain left
        }
    } {}
}

@ __mp3_side_info * Mp3 m → v {
    : *i sip ( vec_data [i] . m si )
    : i chn . m channels
    : i gpf . m gpf
    ( __mp3_putbits m 2047 11 )
    ( __mp3_putbits m . m version 2 )
    ( __mp3_putbits m 1 2 )
    ( __mp3_putbits m 1 1 )
    ( __mp3_putbits m . m bri 4 )
    : i sr3 - . m sri * / . m sri 3 3
    ( __mp3_putbits m sr3 2 )
    ( __mp3_putbits m . m padding 1 )
    ( __mp3_putbits m 0 1 )
    : i mode ? == chn 1 3 0
    ( __mp3_putbits m mode 2 )
    ( __mp3_putbits m 0 2 )
    ( __mp3_putbits m 0 1 )
    ( __mp3_putbits m 1 1 )
    ( __mp3_putbits m 0 2 )
    // main_data_begin is always zero here: nothing is ever borrowed from a
    // previous frame, so every frame stands alone.
    ? == . m version 3 {
        ( __mp3_putbits m 0 9 )
        ( __mp3_putbits m 0 ? == chn 2 3 5 )
        : ~ i ch 0
        ~ < ch chn {
            ( __mp3_putbits m 0 4 )
            = ch + ch 1
        }
    } {
        ( __mp3_putbits m 0 8 )
        ( __mp3_putbits m 0 ? == chn 2 2 1 )
    }
    : ~ i gr 0
    ~ < gr gpf {
        : ~ i ch 0
        ~ < ch chn {
            : i sb0 * + * gr chn ch MP3_SI_N
            ( __mp3_putbits m . sip + sb0 MP3_SI_PART23 12 )
            ( __mp3_putbits m . sip + sb0 MP3_SI_BIGV 9 )
            ( __mp3_putbits m . sip + sb0 MP3_SI_GGAIN 8 )
            // scalefac_compress 0: with no masking model there are no
            // scalefactors, so every band's slen is zero.
            ? == . m version 3 { ( __mp3_putbits m 0 4 ) } { ( __mp3_putbits m 0 9 ) }
            ( __mp3_putbits m 0 1 )
            ( __mp3_putbits m . sip + sb0 MP3_SI_TS0 5 )
            ( __mp3_putbits m . sip + sb0 MP3_SI_TS1 5 )
            ( __mp3_putbits m . sip + sb0 MP3_SI_TS2 5 )
            ( __mp3_putbits m . sip + sb0 MP3_SI_R0 4 )
            ( __mp3_putbits m . sip + sb0 MP3_SI_R1 3 )
            ? == . m version 3 { ( __mp3_putbits m 0 1 ) } {}
            ( __mp3_putbits m 0 1 )
            ( __mp3_putbits m . sip + sb0 MP3_SI_C1T 1 )
            = ch + ch 1
        }
        = gr + gr 1
    }
}

@ __mp3_huffman_pair * Mp3 m i table i x0 i y0 → v {
    : *i hc ( vec_data [i] . m hcode )
    : *i hl ( vec_data [i] . m hlen )
    : *i ho ( vec_data [i] . m hoff )
    : *i hy ( vec_data [i] . m hylen )
    : *i hb ( vec_data [i] . m hlinbits )
    : i signx ? > x0 0 0 1
    : i signy ? > y0 0 0 1
    : ~ i x ? > x0 0 x0 - 0 x0
    : ~ i y ? > y0 0 y0 - 0 y0
    : i off . ho table
    : i ylen . hy table
    ? > table 15 {
        : i linbits . hb table
        : ~ i lx 0
        : ~ i ly 0
        ? > x 14 { = lx - x 15 = x 15 } {}
        ? > y 14 { = ly - y 15 = y 15 } {}
        : i idx + off + * x ylen y
        : ~ i ext 0
        : ~ i xbits 0
        ( __mp3_putbits m . hc idx . hl idx )
        ? > x 14 { = ext | ext lx = xbits + xbits linbits } {}
        ? != x 0 { = ext | << ext 1 signx = xbits + xbits 1 } {}
        ? > y 14 { = ext | << ext linbits ly = xbits + xbits linbits } {}
        ? != y 0 { = ext | << ext 1 signy = xbits + xbits 1 } {}
        ( __mp3_putbits m ext xbits )
    } {
        : i idx + off + * x ylen y
        : ~ i code . hc idx
        : ~ i cbits . hl idx
        ? != x 0 { = code | << code 1 signx = cbits + cbits 1 } {}
        ? != y 0 { = code | << code 1 signy = cbits + cbits 1 } {}
        ( __mp3_putbits m code cbits )
    }
}

@ __mp3_huffman_quad * Mp3 m i table i v0 i w0 i x0 i y0 → v {
    : *i hc ( vec_data [i] . m hcode )
    : *i hl ( vec_data [i] . m hlen )
    : *i ho ( vec_data [i] . m hoff )
    : i off . ho table
    : i sv ? > v0 0 0 1
    : i sw ? > w0 0 0 1
    : i sx ? > x0 0 0 1
    : i sy ? > y0 0 0 1
    : i v ? > v0 0 v0 - 0 v0
    : i w ? > w0 0 w0 - 0 w0
    : i x ? > x0 0 x0 - 0 x0
    : i y ? > y0 0 y0 - 0 y0
    : i p + + + v << w 1 << x 2 << y 3
    : i idx + off p
    ( __mp3_putbits m . hc idx . hl idx )
    : ~ i code 0
    : ~ i cbits 0
    ? != v 0 { = code sv = cbits 1 } {}
    ? != w 0 { = code | << code 1 sw = cbits + cbits 1 } {}
    ? != x 0 { = code | << code 1 sx = cbits + cbits 1 } {}
    ? != y 0 { = code | << code 1 sy = cbits + cbits 1 } {}
    ( __mp3_putbits m code cbits )
}

@ __mp3_huffman_bits * Mp3 m i gr i ch → v {
    : *i ixp ( vec_data [i] . m ix )
    : *i sip ( vec_data [i] . m si )
    : *i sf ( vec_data [i] . m sfb )
    : i chn . m channels
    : i gpf . m gpf
    : i ixbase * + * ch gpf gr MP3_GRAN
    : i sb0 * + * gr chn ch MP3_SI_N
    : i bits0 ( __mp3_bitpos m )
    : i bv . sip + sb0 MP3_SI_BIGV
    : i bigvalues << bv 1
    : i sbi * . m sri 23
    : i r0v . sip + sb0 MP3_SI_R0
    : i r1v . sip + sb0 MP3_SI_R1
    : i i1 + r0v 1
    : i r1start . sf + sbi i1
    : i i2 + i1 + r1v 1
    : i r2start . sf + sbi i2
    : i ts0 . sip + sb0 MP3_SI_TS0
    : i ts1 . sip + sb0 MP3_SI_TS1
    : i ts2 . sip + sb0 MP3_SI_TS2
    : ~ i i 0
    ~ < i bigvalues {
        : i a ? >= i r1start 1 0
        : i b ? >= i r2start 1 0
        : i which + a b
        : i table ? == which 0 ts0 ? == which 1 ts1 ts2
        ? != table 0 {
            ( __mp3_huffman_pair m table . ixp + ixbase i . ixp + ixbase + i 1 )
        } {}
        = i + i 2
    }
    : i c1v . sip + sb0 MP3_SI_C1T
    : i cntv . sip + sb0 MP3_SI_CNT1
    : i c1table + c1v 32
    : i count1end + bigvalues << cntv 2
    = i bigvalues
    ~ < i count1end {
        ( __mp3_huffman_quad m c1table . ixp + ixbase i . ixp + ixbase + i 1
        . ixp + ixbase + i 2 . ixp + ixbase + i 3 )
        = i + i 4
    }
    // Whatever the granule was given and did not use is padded with ones,
    // which is the one pattern no Huffman code in the format begins with.
    : i used - ( __mp3_bitpos m ) bits0
    : i p23 . sip + sb0 MP3_SI_PART23
    : ~ i left - p23 used
    ~ >= left 32 {
        ( __mp3_putbits m 4294967295 32 )
        = left - left 32
    }
    ? > left 0 {
        : i ones - << 1 left 1
        ( __mp3_putbits m ones left )
    } {}
}

@ __mp3_format * Mp3 m → v {
    : *f xrp ( vec_data [f] . m xr )
    : *i ixp ( vec_data [i] . m ix )
    : i chn . m channels
    : i gpf . m gpf
    // The quantiser worked on magnitudes; the sign comes back from the
    // spectrum it came from.
    : ~ i ch 0
    ~ < ch chn {
        : ~ i gr 0
        ~ < gr gpf {
            : i base * + * ch gpf gr MP3_GRAN
            : ~ i i 0
            ~ < i MP3_GRAN {
                : f xv . xrp + base i
                : i q . ixp + base i
                ? & < xv 0.0 > q 0 { = . ixp + base i - 0 q } {}
                = i + i 1
            }
            = gr + gr 1
        }
        = ch + ch 1
    }
    ( __mp3_side_info m )
    : ~ i gr 0
    ~ < gr gpf {
        = ch 0
        ~ < ch chn {
            ( __mp3_huffman_bits m gr ch )
            = ch + ch 1
        }
        = gr + gr 1
    }
    : ~ i drain . m resv_drain
    ~ >= drain 32 {
        ( __mp3_putbits m 0 32 )
        = drain - drain 32
    }
    ? > drain 0 { ( __mp3_putbits m 0 drain ) } {}
}

// ---------------------------------------------------------------- public

// Samples in, an MP3 file out. `samples` are f32 in [-1, 1] and interleaved
// when `channels` is 2; nothing is resampled and nothing is normalised, so
// what goes in is what a decoder gets back.
@ mp3_encode ( Vec f ) samples i rate i channels i bitrate → !( Vec u ) String {
    ?? ( __mp3_new rate channels bitrate ) {
        T m → {
            : i nper * . m gpf MP3_GRAN
            : i navail ( vec_len [f] samples )
            : i total / navail channels
            // Two frames past the end: the filterbank carries 512 samples of
            // history and the MDCT a granule of it, so the last real sample
            // only reaches the bitstream after that much silence follows it.
            : i frames + / + total - nper 1 nper 2
            : ~ i fi 0
            ~ < fi frames {
                ? > . m frac_slots 0.0 {
                    : f thr - . m frac_slots 1.0
                    = . m padding ? <= . m slot_lag thr 1 0
                    : f d - # f . m padding . m frac_slots
                    = . m slot_lag + . m slot_lag d
                } {}
                : i bpf * 8 + . m whole_slots . m padding
                = . m mean_bits / - bpf . m sideinfo_len . m gpf
                : i base * fi * nper channels
                ( __mp3_mdct m samples navail base )
                ( __mp3_iteration m )
                ( __mp3_format m )
                = fi + fi 1
            }
            // Every frame is a whole number of bytes, so this only ever runs
            // if something above got the arithmetic wrong.
            ? > . m cbits 0 {
                ( __mp3_putbits m 0 - 8 . m cbits )
            } {}
            : ( Vec u ) out . m out
            = . m out ( vec_new [u] )
            ( mp3_free m )
            ^ @ !( Vec u ) String { T out }
        }
        F e → { ^ @ !( Vec u ) String { F e } }
    }
}
