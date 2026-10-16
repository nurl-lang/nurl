// packages/whisper/src/stream.nu — the live endpointer behind the WebSocket.
//
//   : ~ WsStream s ( ws_stream_new net cfg )   net: ?Silero (F = energy only)
//   ( ws_stream_feed s samples )               16 kHz audio as it arrives
//   ~ T {
//       : i act ( ws_stream_next s )           what is due, in stream order
//       ? == act WSS_NONE { break } …          START / PARTIAL / FINAL / LEVEL
//   }
//   ( ws_stream_end s )                        the client says it is done
//
// The stream decides WHEN; the server (serve.nu) does the transcribing. Each
// action names a stretch of the stream (act_from, act_to: absolute samples)
// and ws_stream_audio copies it out.
//
// What is heard, 32 ms at a time:
//
//   * p(speech) from Silero (silero.nu) — a voice detector, not a loudness
//     detector, so a fan, music or a keyboard does not hold an utterance
//     open, and a quiet word ending does not cut it short. With no weights
//     it falls back to an energy margin over the noise floor.
//   * the chunk's level in dB, which feeds three trackers: the NOISE FLOOR
//     (the 20th percentile of the last 10 s of non-speech chunks — the room,
//     re-measured continuously, so a fan switched on is the floor within
//     seconds), the SPEECH LEVEL (the median of the last ~6 s of voiced
//     chunks — the speaker's own voice at their own microphone), and how
//     twitchy Silero is on THIS room's noise (the 90th percentile of its p
//     over chunks that are at the floor). Where the room makes Silero
//     twitchy, its thresholds rise to stay above it.
//   * the near-field gate: a chunk more than `near_db` below the speaker's
//     own level is not the speaker — a television, a sibling across the
//     room, the game's own sound. Without it, someone else talking is an
//     utterance that never pauses.
//
// When an utterance ends is the pause that follows it — and how long a
// pause has to be is the SPEAKER's, not a constant: the gaps between words
// inside an utterance are measured as they happen, and the silence that
// closes one is set from them (1.3 × their 90th percentile + 150 ms, within
// [min_pause_ms, max_pause_ms]). A fluent speaker's 120 ms gaps close an
// answer after ~300 ms; a child reading word by word with 600 ms gaps is not
// cut after every word. A close followed quickly by more speech counts as a
// gap as well, so a threshold that keeps splitting a speaker's sentences
// grows until it stops.
//
// Drafts (cfg.partials): the open utterance is transcribed every
// `partial_ms` of new speech, and once more as soon as a pause starts — that
// one with the full encoder context, so when the pause turns out to be the
// end, the draft IS the final and nothing has to run.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/sort.nu`
$ `src/silero.nu`

: i WSS_NONE 0
: i WSS_START 1  // speech confirmed at act_from
: i WSS_PARTIAL 2  // a draft of [act_from, act_to) is due (act_full: the full context)
: i WSS_FINAL 3  // the utterance [act_from, act_to) closed
: i WSS_LEVEL 4  // a second went by: the levels, for a client that asked

: i __WSS_RATE 16000
: i __WSS_HOP 512  // one Silero chunk, 32 ms

// A stream's tunables — the client may set any of them in its config
// message (serve.nu), at any time.
: WssCfg {
    b partials  // send drafts
    i partial_ms  // a draft every this much new audio
    i pause_ms  // the closing silence before any gap has been measured
    i min_pause_ms
    i max_pause_ms
    b adaptive  // F = pause_ms, always
    f threshold  // Silero p that opens an utterance (it stays open down to −0.15)
    f near_db  // the near-field gate (0 = off)
    i max_utt_ms  // an utterance this long is closed at its best recent gap
    b levels  // WSS_LEVEL once a second
    b events  // WSS_START
}

@ wss_default_cfg → WssCfg {
    ^ @ WssCfg { F 300 400 300 1000 T 0.5 10.0 28000 F F }
}

: WsStream {
    WssCfg cfg
    ? Silero net
    SileroState sst
    ( Vec f ) buf  // samples not yet released; buf[0] is absolute sample `base`
    i base
    i pos  // the endpointer has heard everything before this sample
    // the trackers (rings of chunk levels in dB; p of the noise chunks)
    ( Vec f ) noise_e
    ( Vec f ) noise_p
    i noise_i
    i noise_pi
    ( Vec f ) all_e
    i all_i
    ( Vec f ) voice_e
    i voice_i
    ( Vec f ) pw3  // the last three chunks' power: the level the gates read
    f noise_db
    f speech_db
    f th_on
    f th_off
    f p_noise  // Silero's 90th-percentile p on this room's noise
    i nchunk
    // the open utterance
    i seg  // utterances started so far
    i seg_start  // absolute sample (−1 = none open)
    i onset  // where its speech began
    i last_voice  // end of the last voiced chunk
    i voiced_n
    b confirmed
    i split_at  // the middle of the latest real gap (a force-close point)
    // pauses
    ( Vec i ) gaps  // the last 16 gaps between words, ms
    i gaps_i
    i eou_ms  // the silence that closes an utterance now
    i last_end  // where the last utterance's speech ended (absolute), −1 = none
    // drafts
    i draft_at  // the stream position the last draft heard up to (−1 = none)
    i draft_voice  // last_voice when it was made
    i full_voice  // … and when the last full-context one was
    b full_ok  // … and that one did run (a skipped one is not retried)
    b draft_full
    // the action being handed out
    i act_seg  // the utterance it belongs to (1, 2, …)
    b start_due
    b final_due
    i act_from
    i act_to
    b act_full
    b act_reuse  // FINAL: the last draft heard exactly this — no need to run again
    i act_pause_ms  // how long the speaker had been quiet at act_to
    i act_speech_from  // the speech itself: onset …
    i act_speech_to  // … to the end of the last voiced chunk
    i level_at
}

@ __wss_ring i n f v → ( Vec f ) {
    : ( Vec f ) r ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] r v )
        = k + k 1
    }
    ^ r
}

@ ws_stream_new ? Silero net WssCfg cfg → WsStream {
    : ( Vec i ) g ( vec_new [i] )
    ^ @ WsStream {
        cfg net ( silero_state_new ) ( vec_new [f] ) 0 0
        ( vec_new [f] ) ( vec_new [f] ) 0 0 ( vec_new [f] ) 0 ( vec_new [f] ) 0 ( __wss_ring 3 0.0 )
        -100.0 -100.0 . cfg threshold - . cfg threshold 0.15 0.0 0
        0 -1 -1 -1 0 F -1
        g 0 . cfg pause_ms -1
        -1 -1 -1 F F
        0 F F 0 0 F F 0 0 0 0
    }
}

// New settings for a running stream. A pause or threshold the client sets
// takes effect at once; the measured gaps are kept.
@ ws_stream_set_cfg inout WsStream s WssCfg cfg → v {
    = . s cfg cfg
    ? ! . cfg adaptive { = . s eou_ms . cfg pause_ms } {}
    ? < . s eou_ms . cfg min_pause_ms { = . s eou_ms . cfg min_pause_ms } {}
    ? > . s eou_ms . cfg max_pause_ms { = . s eou_ms . cfg max_pause_ms } {}
    ( __wss_thresholds s )
}

@ ws_stream_feed inout WsStream s ( Vec f ) x → v {
    : ~ i k 0
    ~ < k ( vec_len [f] x ) {
        ( vec_push [f] . s buf ( vec_at [f] x k ) )
        = k + k 1
    }
}

// The samples [from, to) of the stream (what is still held of them).
@ ws_stream_audio WsStream s i from i to → ( Vec f ) {
    : ~ i a - from . s base
    : ~ i b - to . s base
    ? < a 0 { = a 0 } {}
    ? > b ( vec_len [f] . s buf ) { = b ( vec_len [f] . s buf ) } {}
    : ( Vec f ) out ( vec_with_cap [f] ? > b a - b a 0 )
    ~ < a b {
        ( vec_push [f] out ( vec_at [f] . s buf a ) )
        = a + a 1
    }
    ^ out
}

// p-th fraction percentile of the first `n` values of a ring.
@ __wss_pct ( Vec f ) r i n f p → f {
    : ( Vec f ) c ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] c ( vec_at [f] r k ) )
        = k + k 1
    }
    ( sort_by [f] c \ f a f b → i { ^ ? < a b -1 ? > a b 1 0 } )
    : ~ i at # i * p # f n
    ? >= at n { = at - n 1 } {}
    ^ ( vec_at [f] c at )
}

// Push into a ring of capacity `cap`: grows to it, then wraps at `i`.
@ __wss_push_ring ( Vec f ) r i cap i at f v → i {
    ? < ( vec_len [f] r ) cap {
        ( vec_push [f] r v )
        ^ 0
    } {}
    ( vec_put [f] r at v )
    ^ % + at 1 cap
}

// The thresholds Silero is held to: the configured ones, raised above
// whatever this room's noise makes it say.
@ __wss_thresholds inout WsStream s → v {
    : f base_on . . s cfg threshold
    : f base_off - base_on 0.15
    : ~ f off ? > + . s p_noise 0.1 base_off + . s p_noise 0.1 base_off
    ? > off 0.7 { = off 0.7 } {}
    : ~ f on ? > + off 0.15 base_on + off 0.15 base_on
    ? > on 0.85 { = on 0.85 } {}
    = . s th_on on
    = . s th_off off
}

// Re-measure the room: the floor, the speaker, Silero's noise p.
@ __wss_refresh inout WsStream s → v {
    : i nn ( vec_len [f] . s noise_e )
    ? >= nn 30 {
        = . s noise_db ( __wss_pct . s noise_e nn 0.2 )
    } {
        : i na ( vec_len [f] . s all_e )
        ? > na 0 { = . s noise_db ( __wss_pct . s all_e na 0.1 ) } {}
    }
    // the speaker's level: the LOUD end of what was voiced. Someone else
    // talking in the room is voiced too, and quieter — the median of a room
    // with a television in it is the television.
    : i nv ( vec_len [f] . s voice_e )
    ? >= nv 30 { = . s speech_db ( __wss_pct . s voice_e nv 0.9 ) } {}
    : i np ( vec_len [f] . s noise_p )
    ? >= np 30 { = . s p_noise ( __wss_pct . s noise_p np 0.9 ) } {}
    ( __wss_thresholds s )
}

// The closing silence, from the speaker's own gaps.
@ __wss_adapt inout WsStream s → v {
    ? ! . . s cfg adaptive { ^ {} } {}
    : i n ( vec_len [i] . s gaps )
    ? < n 3 { ^ {} } {}
    : ( Vec f ) g ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] g # f ( vec_at [i] . s gaps k ) )
        = k + k 1
    }
    : f p90 ( __wss_pct g n 0.9 )
    : ~ i e + # i * 1.3 p90 150
    ? < e . . s cfg min_pause_ms { = e . . s cfg min_pause_ms } {}
    ? > e . . s cfg max_pause_ms { = e . . s cfg max_pause_ms } {}
    = . s eou_ms e
}

@ __wss_gap inout WsStream s i ms → v {
    ? < ( vec_len [i] . s gaps ) 16 {
        ( vec_push [i] . s gaps ms )
    } {
        ( vec_put [i] . s gaps . s gaps_i ms )
        = . s gaps_i % + . s gaps_i 1 16
    }
    ( __wss_adapt s )
}

// Has the room been heard? The floor is only trusted once a second of
// non-speech has gone into it — a stream that opens on speech must not
// take the speaker for the room.
@ __wss_room_known WsStream s → b { ^ >= ( vec_len [f] . s noise_e ) 30 }

// Close the open utterance at `end` (absolute): FINAL is due.
@ __wss_close inout WsStream s i end → v {
    = . s final_due T
    = . s act_seg . s seg
    = . s act_from . s seg_start
    = . s act_to end
    = . s act_full T
    = . s act_reuse & . s full_ok == . s full_voice . s last_voice
    = . s act_pause_ms / - . s pos . s last_voice 16
    = . s act_speech_from . s onset
    = . s act_speech_to . s last_voice
    = . s last_end . s last_voice
    = . s seg_start -1
    = . s confirmed F
    = . s voiced_n 0
    = . s draft_at -1
    = . s draft_voice -1
    = . s full_voice -1
    = . s draft_full F
    = . s split_at -1
}

// One 32 ms chunk at `pos`.
@ __wss_chunk inout WsStream s → v {
    : i off - . s pos . s base
    : ~ f en 0.0
    : ~ i k 0
    ~ < k __WSS_HOP {
        : f v ( vec_at [f] . s buf + off k )
        = en + en * v v
        = k + k 1
    }
    : f pwr / en # f __WSS_HOP
    : f db * 10.0 ( log10 ? > pwr 1.0e-20 pwr 1.0e-20 )
    // the gates read 96 ms of level, not 32: a single loud syllable of
    // someone else's speech is not the speaker, and a single quiet one of
    // the speaker's is not a pause
    ( vec_put [f] . s pw3 % . s nchunk 3 pwr )
    : f pm / + + ( vec_at [f] . s pw3 0 ) ( vec_at [f] . s pw3 1 ) ( vec_at [f] . s pw3 2 ) 3.0
    : f dbs * 10.0 ( log10 ? > pm 1.0e-20 pm 1.0e-20 )
    : ~ f p 0.0
    ?? . s net {
        T net → { = p ( silero_prob net . s sst . s buf off ) }
        F → {
            // no network: a soft margin of 6 dB over the floor
            : f z / - db + . s noise_db 6.0 1.5
            = p / 1.0 + 1.0 ( exp - 0.0 z )
        }
    }
    : i start . s pos
    = . s pos + . s pos __WSS_HOP
    = . s nchunk + . s nchunk 1
    : i now . s pos

    // the trackers
    = . s all_i ( __wss_push_ring . s all_e 312 . s all_i db )
    ? < p 0.3 {
        = . s noise_i ( __wss_push_ring . s noise_e 312 . s noise_i db )
    } {}
    ? & ( __wss_room_known s ) < db + . s noise_db 3.0 {
        = . s noise_pi ( __wss_push_ring . s noise_p 312 . s noise_pi p )
    } {}
    ? | < . s nchunk 8 == 0 % . s nchunk 16 { ( __wss_refresh s ) } {}

    : f th ? >= . s seg_start 0 . s th_off . s th_on
    : ~ b voiced >= p th
    // quieter than the floor allows for speech: noise Silero liked
    ? & ( __wss_room_known s ) < dbs + . s noise_db 3.0 { = voiced F } {}
    ? & >= p . s th_on > dbs + . s noise_db 6.0 {
        = . s voice_i ( __wss_push_ring . s voice_e 625 . s voice_i dbs )
    } {}
    // the near-field gate, once the speaker's own level is known — with
    // hysteresis: an utterance has to START clearly at the speaker's level
    // (within 0.6 × near_db of it), and stays open down to near_db below
    ? & & voiced > . . s cfg near_db 0.0 >= ( vec_len [f] . s voice_e ) 30 {
        : f nd ? >= . s seg_start 0 . . s cfg near_db * 0.6 . . s cfg near_db
        ? < dbs - . s speech_db nd { = voiced F } {}
    } {}

    ? voiced {
        ? < . s seg_start 0 {
            // an utterance may be starting: 300 ms of lead-in, but never
            // back into the last one
            : ~ i st - start 4800
            ? < st . s base { = st . s base } {}
            ? < st . s last_end { = st . s last_end } {}
            ? < st 0 { = st 0 } {}
            // a close followed this quickly by more speech was a pause
            // inside a sentence: count it as one
            ? >= . s last_end 0 {
                // (within twice the closing pause, and under a second: past
                // that it is the pause between sentences, and learning from
                // it would grow the closing pause past every one of them)
                : i gms / - start . s last_end 16
                ? & < gms * . s eou_ms 2 < gms 1000 { ( __wss_gap s gms ) } {}
            } {}
            = . s seg_start st
            = . s onset start
            = . s voiced_n 0
            = . s confirmed F
            = . s draft_at -1
            = . s draft_voice -1
            = . s full_voice -1
            = . s split_at -1
        } {
            : i gap - start . s last_voice
            // a real gap between words: measured, and a place to split
            ? & . s confirmed >= gap 1280 {
                ( __wss_gap s / gap 16 )
                = . s split_at - start / gap 2
            } {}
        }
        = . s voiced_n + . s voiced_n 1
        = . s last_voice now
        ? & ! . s confirmed >= . s voiced_n 3 {
            = . s confirmed T
            = . s seg + . s seg 1
            = . s start_due . . s cfg events
            = . s act_seg . s seg
            = . s act_from . s seg_start
            = . s act_to now
        } {}
    } {
        ? >= . s seg_start 0 {
            : i quiet / - now . s last_voice 16
            ? . s confirmed {
                ? >= quiet . s eou_ms {
                    // the closing silence goes along (up to 400 ms): a word's
                    // quiet tail is past where Silero stopped hearing it
                    : ~ i end + . s last_voice 6400
                    ? > end now { = end now } {}
                    ( __wss_close s end )
                } {}
            } {
                // a blip that never became speech
                ? >= quiet 160 { = . s seg_start -1 } {}
            }
        } {}
    }

    // the length bound: whisper hears 30 s at most
    ? & . s confirmed >= - now . s seg_start * . . s cfg max_utt_ms 16 {
        : ~ i at now
        ? > . s split_at + . s seg_start 80000 { = at . s split_at } {}
        : i keep_voice . s last_voice
        ( __wss_close s at )
        = . s act_reuse F
        // speech goes on past the cut: the rest is the next utterance
        ? < at now {
            = . s seg_start at
            = . s onset at
            = . s confirmed T
            = . s seg + . s seg 1
            = . s voiced_n 3
            = . s last_voice keep_voice
        } {}
    } {}
}

// Release what nothing can need: with no utterance open, everything before
// the lead-in of one that might start now.
@ __wss_trim inout WsStream s → v {
    : ~ i keep - . s pos 6400
    ? >= . s seg_start 0 { = keep . s seg_start } {}
    : i drop - keep . s base
    ? < drop 16000 { ^ {} } {}
    : ( Vec f ) nb ( vec_with_cap [f] - ( vec_len [f] . s buf ) drop )
    : ~ i k drop
    ~ < k ( vec_len [f] . s buf ) {
        ( vec_push [f] nb ( vec_at [f] . s buf k ) )
        = k + k 1
    }
    = . s buf nb
    = . s base keep
}

// What is due next. Runs the endpointer forward chunk by chunk and stops at
// the first action, so each one is handed out at the moment in the stream
// it became due (a draft hears exactly the audio up to its act_to).
@ ws_stream_next inout WsStream s → i {
    ~ T {
        ? . s start_due {
            = . s start_due F
            ^ WSS_START
        } {}
        ? . s final_due {
            = . s final_due F
            ^ WSS_FINAL
        } {}
        ? & . s confirmed >= . s seg_start 0 {
            : i quiet / - . s pos . s last_voice 16
            // the pause just started: a full-context draft, which is the
            // final if the pause turns out to be the end. A client that
            // asked for drafts sees it at once; for one that did not it is
            // speculative, made late enough in the pause to waste little
            // and early enough to be ready when the pause closes.
            : i spec ? . . s cfg partials 96 ? > - . s eou_ms 250 96 - . s eou_ms 250 96
            ? & >= quiet spec != . s full_voice . s last_voice {
                = . s draft_at . s pos
                = . s draft_voice . s last_voice
                = . s full_voice . s last_voice
                = . s full_ok T
                = . s draft_full T
                = . s act_seg . s seg
                = . s act_from . s seg_start
                = . s act_to . s pos
                = . s act_full T
                = . s act_pause_ms quiet
                = . s act_speech_from . s onset
                = . s act_speech_to . s last_voice
                ^ WSS_PARTIAL
            } {}
            ? & . . s cfg partials != . s draft_voice . s last_voice {
                // the first draft waits for a quarter second of speech: less
                // than that is not yet a word
                ? & >= - . s last_voice . s onset 4000
                >= - . s pos ? < . s draft_at 0 . s seg_start . s draft_at * . . s cfg partial_ms 16 {
                    = . s draft_at . s pos
                    = . s draft_voice . s last_voice
                    = . s draft_full F
                    = . s act_seg . s seg
                    = . s act_from . s seg_start
                    = . s act_to . s pos
                    = . s act_full F
                    = . s act_pause_ms quiet
                    = . s act_speech_from . s onset
                    = . s act_speech_to . s last_voice
                    ^ WSS_PARTIAL
                } {}
            } {}
        } {}
        ? & . . s cfg levels >= - . s pos . s level_at __WSS_RATE {
            = . s level_at . s pos
            ^ WSS_LEVEL
        } {}
        ? > + - . s pos . s base __WSS_HOP ( vec_len [f] . s buf ) {
            ( __wss_trim s )
            ^ WSS_NONE
        } {}
        ( __wss_chunk s )
    }
    ^ WSS_NONE
}

// The draft just handed out did not run (the GPU was busy, or the stream's
// share of it was spent): a full-context one can no longer stand in for
// the final.
@ ws_stream_draft_skipped inout WsStream s → v {
    ? . s act_full { = . s full_ok F } {}
}

// The client is done (or gone): whatever is open closes now, over all the
// audio received. T = a FINAL is due.
@ ws_stream_end inout WsStream s → b {
    ? < . s seg_start 0 { ^ F } {}
    ? & ! . s confirmed < . s voiced_n 1 {
        = . s seg_start -1
        ^ F
    } {}
    : i end + . s base ( vec_len [f] . s buf )
    // the unheard tail may hold speech: count it as voiced
    = . s last_voice end
    ? ! . s confirmed { = . s seg + . s seg 1 } {}
    ( __wss_close s end )
    ^ T
}

// Drop the open utterance unheard (a new question: what was being said is
// no longer an answer). The room's measurements are kept.
@ ws_stream_reset inout WsStream s → v {
    = . s seg_start -1
    = . s confirmed F
    = . s voiced_n 0
    = . s start_due F
    = . s final_due F
    = . s draft_at -1
    = . s draft_voice -1
    = . s full_voice -1
    = . s draft_full F
    = . s split_at -1
    = . s last_end -1
}

// ── drafts that agree ───────────────────────────────────────────────
//
// A draft of an utterance still being spoken is a guess at its tail: the
// last word may be half a word. A word that two drafts in a row agree on,
// with more audio heard in between, is one the speaker has finished
// (LocalAgreement-2, as in whisper_streaming) — that prefix goes out as
// `stable`, and a client that must not act on a guess acts on it.

@ __wss_is_punct u c → b {
    ^ | | | | | | | == c 46 == c 44 == c 33 == c 63 == c 58 == c 59 == c 34 == c 39
}

// Words of a transcript: split on spaces, compared without case or the
// punctuation that whisper hangs on a word's edges.
@ __wss_norm_word ( Vec u ) t i a i b → String {
    : ~ i lo a
    : ~ i hi b
    ~ & < lo hi ( __wss_is_punct ( vec_at [u] t lo ) ) { = lo + lo 1 }
    ~ & < lo hi ( __wss_is_punct ( vec_at [u] t - hi 1 ) ) { = hi - hi 1 }
    : String w ( string_new )
    ~ < lo hi {
        : ~ u c ( vec_at [u] t lo )
        ? & >= c 65 <= c 90 { = c + c 32 } {}
        ( string_push_char w c )
        = lo + lo 1
    }
    ^ w
}

// Word boundaries: (start, end) byte pairs.
@ wss_words ( Vec u ) t → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i n ( vec_len [u] t )
    : ~ i k 0
    ~ < k n {
        ~ & < k n | == ( vec_at [u] t k ) 32 == ( vec_at [u] t k ) 10 { = k + k 1 }
        : i a k
        ~ & < k n & != ( vec_at [u] t k ) 32 != ( vec_at [u] t k ) 10 { = k + k 1 }
        ? > k a {
            ( vec_push [i] out a )
            ( vec_push [i] out k )
        } {}
    }
    ^ out
}

// How many leading words two transcripts share.
@ wss_agree ( Vec u ) a ( Vec u ) b → i {
    : ( Vec i ) wa ( wss_words a )
    : ( Vec i ) wb ( wss_words b )
    : i na / ( vec_len [i] wa ) 2
    : i nb / ( vec_len [i] wb ) 2
    : ~ i k 0
    ~ & < k na < k nb {
        : String x ( __wss_norm_word a ( vec_at [i] wa * k 2 ) ( vec_at [i] wa + * k 2 1 ) )
        : String y ( __wss_norm_word b ( vec_at [i] wb * k 2 ) ( vec_at [i] wb + * k 2 1 ) )
        ? == 0 ( nurl_str_eq ( string_data x ) ( string_data y ) ) { ^ k } {}
        = k + k 1
    }
    ^ k
}

// The first `n` words of `t`, as it spelt them (leading space included,
// the way whisper starts a transcript).
@ wss_prefix ( Vec u ) t i n → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    ? <= n 0 { ^ out } {}
    : ( Vec i ) w ( wss_words t )
    : i nw / ( vec_len [i] w ) 2
    : i upto ? < n nw ( vec_at [i] w - * n 2 1 ) ( vec_len [u] t )
    : ~ i k 0
    ~ < k upto {
        ( vec_push [u] out ( vec_at [u] t k ) )
        = k + k 1
    }
    ^ out
}
