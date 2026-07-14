// packages/audio/src/vad.nu — voice activity detection.
//
// Finding where the speech IS, so the parts that are not speech never reach a
// model. An hour of recording is mostly not speech, and a speech model does not
// get cheaper by running over silence — it costs exactly the same.
//
//   ( vad_segments samples rate opts ) → ( Vec VadSeg )   [start, end) in samples
//   ( vad_default_opts )              → VadOpts
//
// This is an ENERGY detector with an adaptive noise floor, not a neural one.
// Being clear about that matters, because it decides where it fails: it hears
// "something loud enough, often enough" rather than "a human voice". It handles
// clean speech with a steady noise floor — a recording, a call, a meeting — and
// it will call a slammed door speech. faster-whisper uses Silero, a small neural
// VAD, for exactly that reason; this is the honest version of what can be done
// without a second model, and the seam is here for one.
//
// What it is NOT is a fixed threshold. A fixed dB threshold works on the file it
// was tuned on and nowhere else. The floor here is the 10th percentile of the
// frame energies — whatever the quiet part of THIS recording sounds like — and
// speech is what stands a margin above it.

$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/sort.nu`

: VadSeg {
    i start  // first sample
    i end  // one past the last
}

: VadOpts {
    f margin_db  // how far above the noise floor speech has to be
    i min_speech_ms  // a burst shorter than this is not speech
    i min_silence_ms  // a gap shorter than this does not split a segment
    i pad_ms  // keep this much either side — speech starts before it
}  // gets loud, and a word's tail is quiet

// Defaults that work on speech: 6 dB over the floor, 250 ms of it, gaps under
// 400 ms bridged (that is a pause between words, not between sentences), and
// 200 ms of padding kept either side so no consonant is clipped off.
@ vad_default_opts → VadOpts {
    ^ @ VadOpts { 6.0 250 400 200 }
}

@ __vad_get ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// Frame energy in dB, one value per 10 ms hop over a 30 ms window.
@ __vad_energies ( Vec f ) x i rate i win i hop → ( Vec f ) {
    : i n ( vec_len [f] x )
    : ( Vec f ) out ( vec_new [f] )
    : ~ i p 0
    ~ <= + p win n {
        : ~ f e 0.0
        : ~ i k 0
        ~ < k win {
            : f v ( __vad_get x + p k )
            = e + e * v v
            = k + k 1
        }
        : f rms ( sqrt / e # f win )
        // dB, floored so silence does not become -inf
        ( vec_push [f] out * 20.0 ( log10 ? > rms 1.0e-10 rms 1.0e-10 ) )
        = p + p hop
    }
    ^ out
}

// The noise floor: the 10th percentile of the frame energies. Not the minimum —
// one anomalously quiet frame would drag the floor down and the whole recording
// would look like speech.
@ __vad_floor ( Vec f ) e → f {
    : i n ( vec_len [f] e )
    ? == n 0 { ^ -100.0 } {}
    : ( Vec f ) s ( vec_new [f] )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] s ( __vad_get e k ) )
        = k + k 1
    }
    ( sort_by [f] s \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    : i idx / n 10
    : f v ( __vad_get s ? < idx n idx - n 1 )
    ( vec_free [f] s )
    ^ v
}

@ vad_segments ( Vec f ) x i rate VadOpts o → ( Vec VadSeg ) {
    : i win / * rate 30 1000  // 30 ms
    : i hop / * rate 10 1000  // 10 ms
    : ( Vec VadSeg ) segs ( vec_new [VadSeg] )
    : i n ( vec_len [f] x )
    ? | < n win < hop 1 { ^ segs } {}

    : ( Vec f ) e ( __vad_energies x rate win hop )
    : i nf ( vec_len [f] e )
    ? == nf 0 {
        ( vec_free [f] e )
        ^ segs
    } {}
    : f floor ( __vad_floor e )
    : f thr + floor . o margin_db

    // frames → runs, with hysteresis in milliseconds rather than frames
    : i min_speech / . o min_speech_ms 10
    : i min_sil / . o min_silence_ms 10
    : i pad / * . o pad_ms rate 1000

    : ~ i run_start -1
    : ~ i last_voiced -1
    : ~ i k 0
    ~ < k nf {
        : b voiced > ( __vad_get e k ) thr
        ? voiced {
            ? < run_start 0 { = run_start k } {}
            = last_voiced k
        } {
            // a gap only ends the run once it is long enough to be a real pause
            ? & >= run_start 0 > - k last_voiced min_sil {
                ? >= - + last_voiced 1 run_start min_speech {
                    ( __vad_push segs run_start + last_voiced 1 hop pad n )
                } {}
                = run_start -1
            } {}
        }
        = k + k 1
    }
    ? >= run_start 0 {
        ? >= - + last_voiced 1 run_start min_speech {
            ( __vad_push segs run_start + last_voiced 1 hop pad n )
        } {}
    } {}
    ( vec_free [f] e )
    ^ segs
}

// frames → samples, padded and clamped, merging into the previous segment when
// the padding makes them touch
@ __vad_push ( Vec VadSeg ) segs i f0 i f1 i hop i pad i n → v {
    : ~ i s - * f0 hop pad
    : ~ i t + * f1 hop pad
    ? < s 0 { = s 0 } {}
    ? > t n { = t n } {}
    : i last - ( vec_len [VadSeg] segs ) 1
    ? >= last 0 {
        ?? ( vec_get [VadSeg] segs last ) {
            T prev → {
                ? <= s . prev end {
                    ( vec_set [VadSeg] segs last @ VadSeg { . prev start ? > t . prev end t . prev end } )
                    ^ v
                } {}
            }
            F → {}
        }
    } {}
    ( vec_push [VadSeg] segs @ VadSeg { s t } )
}

// How much of the audio the segments actually cover — what a caller saves.
@ vad_voiced_samples ( Vec VadSeg ) segs → i {
    : ~ i total 0
    : ~ i k 0
    ~ < k ( vec_len [VadSeg] segs ) {
        ?? ( vec_get [VadSeg] segs k ) {
            T s → { = total + total - . s end . s start }
            F → {}
        }
        = k + k 1
    }
    ^ total
}

// A run of the condensed audio and where it came from: condensed sample
// `cond` … `cond+len` is original sample `orig` … `orig+len`. What the
// condensation THREW AWAY is exactly what is not covered by any run — and it
// is why the runs exist at all: a model transcribing the condensed audio
// reports times in the CONDENSED timeline, and a caller who wants to say
// "this was said at 3:12 of the recording" has to walk the map back.
: VadRun {
    i cond
    i orig
    i len
}

// The audio with the silence taken out: the segments, with at most `max_gap`
// samples of the real audio kept between consecutive ones, and one VadRun
// appended to `runs` for every contiguous stretch that survives.
//
// The cap is not a detail. Glue two segments together with NOTHING between them
// and a listener — a speech model included — hears one utterance where there
// were two: whisper, handed two sentences back to back with no pause, will run
// them together and get the second one's words wrong. Keeping a fraction of a
// second of the actual room gives it the boundary it needs, and capping that
// fraction is what keeps the silence from being the cost again. `max_gap` = 0
// concatenates.
@ vad_extract_runs ( Vec f ) x ( Vec VadSeg ) segs i max_gap ( Vec VadRun ) runs → ( Vec f ) {
    : ( Vec f ) out ( vec_new [f] )
    : ~ i prev_end -1
    : ~ i k 0
    ~ < k ( vec_len [VadSeg] segs ) {
        ?? ( vec_get [VadSeg] segs k ) {
            T s → {
                : ~ i from . s start
                ? & >= prev_end 0 > max_gap 0 {
                    : i gap - . s start prev_end
                    : i keep ? < gap max_gap gap max_gap
                    // the tail of the gap, so what is heard is the room right
                    // before the speech resumes
                    = from - . s start keep
                } {}
                ( vec_push [VadRun] runs @ VadRun { ( vec_len [f] out ) from - . s end from } )
                : ~ i i0 from
                ~ < i0 . s end {
                    ( vec_push [f] out ( __vad_get x i0 ) )
                    = i0 + i0 1
                }
                = prev_end . s end
            }
            F → {}
        }
        = k + k 1
    }
    ^ out
}

@ vad_extract ( Vec f ) x ( Vec VadSeg ) segs i max_gap → ( Vec f ) {
    : ( Vec VadRun ) runs ( vec_new [VadRun] )
    : ( Vec f ) out ( vad_extract_runs x segs max_gap runs )
    ( vec_free [VadRun] runs )
    ^ out
}

// A condensed sample position, mapped back to the original recording. Positions
// past the end of a run but before the next (which cannot arise from a model
// reading the condensed audio, but can arise from a rounded-up timestamp) clamp
// to the end of the nearer run.
@ vad_map_sample ( Vec VadRun ) runs i s → i {
    : ~ i best s
    : ~ i k 0
    ~ < k ( vec_len [VadRun] runs ) {
        ?? ( vec_get [VadRun] runs k ) {
            T r → {
                ? >= s . r cond {
                    : ~ i off - s . r cond
                    ? > off . r len { = off . r len } {}
                    = best + . r orig off
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ best
}
