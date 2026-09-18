// packages/f5tts/src/verify.nu — listening to what came out.
//
// A flow-matching model given a duration estimate and some noise does not
// always say the words. It drops a short one, it runs two together, it
// mumbles the end of a chunk whose duration guess was tight. There is no
// signal inside the model that says so — the velocity field is just as
// confident either way.
//
// So the deployed service checks by LISTENING: it transcribes what it
// generated, compares that against the text it was asked for, and if the word
// error rate is over a threshold it generates the segment again from a
// different seed. That loop is the difference between a demo and a service,
// and it is why the Python one is configured with WHISPER_HOST.
//
// This talks to the same endpoint — POST /inference with a wav, {"text": …}
// back — which whisper.cpp's server and packages/whisper's both speak.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `deps/audio/src/wav.nu`

: ~ s g_f5v_host ``

: ~ i g_f5v_port 6543

: ~ s g_f5v_lang ``  // empty = let the transcriber detect one

@ f5_whisper_set s host i port s lang → v {
    = g_f5v_host host
    = g_f5v_port port
    ? > ( nurl_str_len lang ) 0 { = g_f5v_lang lang } {}
}

@ f5_whisper_enabled → b { ^ > ( nurl_str_len g_f5v_host ) 0 }

@ f5_whisper_where → String {
    : String u ( string_from `http://` )
    ( string_push_str u g_f5v_host )
    ( string_push_char u 58 )
    ( string_push_int u g_f5v_port )
    ^ u
}

// ── word error rate ─────────────────────────────────────────────────
//
// Normalised the way the reference service normalises — lower case,
// punctuation removed, whitespace collapsed — and then a little further,
// because the gate is meant to measure what the MODEL said, not how the
// transcriber chose to spell it. Three things a transcript does that the
// audio did not:
//
//   * it writes a number in digits: "2026" for kaksituhatta
//     kaksikymmentäkuusi. Digits are expanded to Finnish number words
//     before comparing, on both sides, so the two spellings meet.
//   * it hyphenates: "Vapaat Äänet-podcastin". A hyphen or a dash is a
//     word boundary here, not a letter — removing it (as string.punctuation
//     does) glues two words into one and charges two errors for one.
//   * it joins or splits a compound: "lepakonkosto" for "lepakon kosto".
//     The alignment lets one word on either side match the concatenation
//     of up to four consecutive words on the other, at no cost — see f5_wer.
//
// The lower-casing covers the Latin-1 supplement as well as ASCII, because a
// Finnish transcript is full of Ä and Ö and treating those as different
// letters from ä and ö would count every sentence-initial one as an error.

@ __f5v_is_punct i c → b {
    ? & >= c 33 <= c 47 { ^ T } {}
    ? & >= c 58 <= c 64 { ^ T } {}
    ? & >= c 91 <= c 96 { ^ T } {}
    ? & >= c 123 <= c 126 { ^ T } {}
    ^ F
}

@ __f5v_is_space i c → b {
    ? == c 32 { ^ T } {}
    ^ & >= c 9 <= c 13
}

@ __f5v_is_digit i c → b { ^ & >= c 48 <= c 57 }

// Finnish number words for 0 ≤ n < 1 000 000 000, written as one word the
// way the language writes them: 2026 → kaksituhattakaksikymmentäkuusi.
@ __f5v_num_unit i d → s {
    ? == d 1 { ^ `yksi` } {}
    ? == d 2 { ^ `kaksi` } {}
    ? == d 3 { ^ `kolme` } {}
    ? == d 4 { ^ `neljä` } {}
    ? == d 5 { ^ `viisi` } {}
    ? == d 6 { ^ `kuusi` } {}
    ? == d 7 { ^ `seitsemän` } {}
    ? == d 8 { ^ `kahdeksan` } {}
    ? == d 9 { ^ `yhdeksän` } {}
    ^ ``
}

@ __f5v_num_below_1000 String out i n → v {
    : i h / n 100
    : i t / % n 100 10
    : i u % n 10
    ? > h 0 {
        ? > h 1 { ( string_push_str out ( __f5v_num_unit h ) ) } {}
        ( string_push_str out ? > h 1 `sataa` `sata` )
    } {}
    ? == t 1 {
        ? == u 0 { ( string_push_str out `kymmenen` ) } {
            ( string_push_str out ( __f5v_num_unit u ) )
            ( string_push_str out `toista` )
        }
        ^ v
    } {}
    ? > t 1 {
        ( string_push_str out ( __f5v_num_unit t ) )
        ( string_push_str out `kymmentä` )
    } {}
    ? > u 0 { ( string_push_str out ( __f5v_num_unit u ) ) } {}
}

@ f5_number_words i n → String {
    : String out ( string_new )
    ? == n 0 { ( string_push_str out `nolla` ) ^ out } {}
    ? < n 0 { ( string_push_str out `miinus` ) } {}
    : ~ i m ? < n 0 - 0 n n
    : i millions / m 1000000
    : i thousands / % m 1000000 1000
    : i rest % m 1000
    ? > millions 0 {
        ? > millions 1 { ( __f5v_num_below_1000 out millions ) } {}
        ( string_push_str out ? > millions 1 `miljoonaa` `miljoona` )
    } {}
    ? > thousands 0 {
        ? > thousands 1 { ( __f5v_num_below_1000 out thousands ) } {}
        ( string_push_str out ? > thousands 1 `tuhatta` `tuhat` )
    } {}
    ? > rest 0 { ( __f5v_num_below_1000 out rest ) } {}
    ^ out
}

@ __f5v_flush String cur ( Vec String ) out → v {
    ? > ( string_len cur ) 0 {
        ( vec_push [String] out ( string_clone cur ) )
        ( string_clear cur )
    } {}
}

// The words of a normalised text.
@ f5_words s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len text )
    : ~ String cur ( string_new )
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ? < c 128 {
            ? ( __f5v_is_digit c ) {
                // a run of digits, spoken: its own word, so that "2026" and
                // "kaksituhatta kaksikymmentäkuusi" can meet through the
                // compound rule
                : ~ i v 0
                : ~ i nd 0
                ~ & < i n ( __f5v_is_digit ( nurl_str_get text i ) ) {
                    ? < nd 9 { = v + * v 10 - ( nurl_str_get text i ) 48 } {}
                    = nd + nd 1
                    = i + i 1
                }
                ( __f5v_flush cur out )
                : String w ( f5_number_words v )
                ( vec_push [String] out w )
            } {
                ? | ( __f5v_is_space c ) == c 45 {
                    ( __f5v_flush cur out )
                } {
                    ? ( __f5v_is_punct c ) {} {
                        ( string_push_char cur ? & >= c 65 <= c 90 + c 32 c )
                    }
                }
                = i + i 1
            }
        } {
            // a two-byte Latin-1 supplement letter: C3 80..9E lower-cases to
            // C3 A0..BE, and C3 97 (the multiplication sign) is not a letter
            ? & == c 195 < + i 1 n {
                : i b ( nurl_str_get text + i 1 )
                ( string_push_char cur 195 )
                ( string_push_char cur ? & & >= b 128 <= b 158 != b 151 + b 32 b )
                = i + i 2
            } {
                // U+2010..U+2027 — dashes, quotes, the ellipsis — are
                // punctuation, and a dash separates
                ? & & == c 226 < + i 2 n == ( nurl_str_get text + i 1 ) 128 {
                    ( __f5v_flush cur out )
                    = i + i 3
                } {
                    ( string_push_char cur c )
                    = i + i 1
                }
            }
        }
    }
    ( __f5v_flush cur out )
    ( string_free cur )
    ^ out
}

@ __f5v_word_eq ( Vec String ) v i k s w → b {
    ?? ( vec_get [String] v k ) {
        T x → { ^ != 0 ( nurl_str_eq ( string_data x ) w ) }
        F → { ^ F }
    }
}

@ __f5v_word ( Vec String ) v i k → s {
    ?? ( vec_get [String] v k ) { T x → { ^ ( string_data x ) } F → { ^ `` } }
}

@ __f5v_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

// Does words[from..to) of `v`, concatenated, spell `w`?
@ __f5v_concat_eq ( Vec String ) v i from i to s w → b {
    : i wn ( nurl_str_len w )
    : ~ i pos 0
    : ~ i k from
    ~ < k to {
        : s x ( __f5v_word v k )
        : i xn ( nurl_str_len x )
        ? > + pos xn wn { ^ F } {}
        : ~ i j 0
        ~ < j xn {
            ? != ( nurl_str_get x j ) ( nurl_str_get w + pos j ) { ^ F } {}
            = j + j 1
        }
        = pos + pos xn
        = k + k 1
    }
    ^ == pos wn
}

: i F5V_MERGE 4

// Edit distance over WORDS with one extension: a word on either side may
// match the concatenation of up to F5V_MERGE consecutive words on the other
// at no cost. "lepakon kosto" against "lepakonkosto" is then zero errors, as
// it should be — the speaker said both words, the transcriber wrote one.
// Returns the distance; the caller divides by the reference's length.
@ f5_word_errors ( Vec String ) r ( Vec String ) h → i {
    : i nr ( vec_len [String] r )
    : i nh ( vec_len [String] h )
    ? == nr 0 { ^ nh } {}
    ? == nh 0 { ^ nr } {}
    : i w + nh 1
    : ( Vec i ) d ( vec_with_cap [i] * + nr 1 w )
    : ~ i k 0
    ~ < k * + nr 1 w { ( vec_push [i] d 0 ) = k + k 1 }
    : ~ i i 0
    ~ <= i nr { ( vec_set [i] d * i w i ) = i + i 1 }
    : ~ i j 0
    ~ <= j nh { ( vec_set [i] d j j ) = j + j 1 }
    = i 1
    ~ <= i nr {
        : s rw ( __f5v_word r - i 1 )
        = j 1
        ~ <= j nh {
            : s hw ( __f5v_word h - j 1 )
            : i cost ? ( nurl_str_eq rw hw ) 0 1
            : ~ i m + ( __f5v_geti d + * - i 1 w j ) 1
            : i b + ( __f5v_geti d + * i w - j 1 ) 1
            ? < b m { = m b } {}
            : i c + ( __f5v_geti d + * - i 1 w - j 1 ) cost
            ? < c m { = m c } {}
            // several reference words spelt as this one transcript word
            = k 2
            ~ & <= k F5V_MERGE <= k i {
                ? ( __f5v_concat_eq r - i k i hw ) {
                    : i e ( __f5v_geti d + * - i k w - j 1 )
                    ? < e m { = m e } {}
                } {}
                = k + k 1
            }
            // one reference word spelt as several transcript words
            = k 2
            ~ & <= k F5V_MERGE <= k j {
                ? ( __f5v_concat_eq h - j k j rw ) {
                    : i e ( __f5v_geti d + * - i 1 w - j k )
                    ? < e m { = m e } {}
                } {}
                = k + k 1
            }
            ( vec_set [i] d + * i w j m )
            = j + j 1
        }
        = i + i 1
    }
    : i out ( __f5v_geti d + * nr w nh )
    ( vec_free [i] d )
    ^ out
}

// The transcriber's word errors against the text, and the text's own word
// count as the gate counts it — normalised, digits spelt out.
@ f5_errors s reference s hypothesis → i {
    : ( Vec String ) r ( f5_words reference )
    : ( Vec String ) h ( f5_words hypothesis )
    : i e ( f5_word_errors r h )
    : ( @ v String ) drop_w \ String s → v { ( string_free s ) }
    ( vec_free_with [String] r drop_w )
    ( vec_free_with [String] h drop_w )
    ^ e
}

@ f5_word_count_norm s text → i {
    : ( Vec String ) r ( f5_words text )
    : i n ( vec_len [String] r )
    : ( @ v String ) drop_w \ String s → v { ( string_free s ) }
    ( vec_free_with [String] r drop_w )
    ^ n
}

// The word error rate: errors over the reference's word count.
@ f5_wer s reference s hypothesis → f {
    : ( Vec String ) r ( f5_words reference )
    : ( Vec String ) h ( f5_words hypothesis )
    : i nr ( vec_len [String] r )
    : i nh ( vec_len [String] h )
    : i e ( f5_word_errors r h )
    : ( @ v String ) drop_w \ String s → v { ( string_free s ) }
    ( vec_free_with [String] r drop_w )
    ( vec_free_with [String] h drop_w )
    ? == nr 0 { ^ ? == nh 0 0.0 1.0 } {}
    ^ / # f e # f nr
}

// ── asking whisper ──────────────────────────────────────────────────

// The generated audio, transcribed. Empty on any failure — a transcription
// that did not happen must not be read as "it said nothing", so the caller
// checks `f5_whisper_enabled` first and treats an empty answer as a skipped
// check rather than a perfect error rate.
// A multipart body carrying the wav and, when one was configured, the
// language to decode it as. The transcriber also accepts a bare wav body, and
// that is what this sends when no language is set — a language field it would
// have to guess at is worse than the detector it already has.
@ __f5v_push_str ( Vec u ) out s t → v {
    : i n ( nurl_str_len t )
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] out # u ( nurl_str_get t k ) )
        = k + k 1
    }
}

@ __f5v_multipart ( Vec u ) wav s lang s boundary → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : String head ( string_from `--` )
    ( string_push_str head boundary )
    ( string_push_str head `\r\nContent-Disposition: form-data; name="language"\r\n\r\n` )
    ( string_push_str head lang )
    ( string_push_str head `\r\n--` )
    ( string_push_str head boundary )
    ( string_push_str head `\r\nContent-Disposition: form-data; name="file"; filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n` )
    ( __f5v_push_str out ( string_data head ) )
    ( string_free head )
    : ~ i k 0
    ~ < k ( vec_len [u] wav ) {
        ?? ( vec_get [u] wav k ) { T b → { ( vec_push [u] out b ) } F → {} }
        = k + k 1
    }
    : String tail ( string_from `\r\n--` )
    ( string_push_str tail boundary )
    ( string_push_str tail `--\r\n` )
    ( __f5v_push_str out ( string_data tail ) )
    ( string_free tail )
    ^ out
}

@ f5_transcribe ( Vec f ) wave → String {
    : ( Vec u ) wav ( wav_encode wave 24000 1 )
    : b as_form > ( nurl_str_len g_f5v_lang ) 0
    // Built as statements rather than one ternary: both arms here allocate,
    // and an arm that is chosen but never taken still has to be nobody's.
    : ~ String ctype ( string_new )
    : ~ ( Vec u ) bytes ( vec_new [u] )
    ? as_form {
        ( string_push_str ctype `multipart/form-data; boundary=f5ttsboundary` )
        ( vec_free [u] bytes )
        = bytes ( __f5v_multipart wav g_f5v_lang `f5ttsboundary` )
    } {
        ( string_push_str ctype `audio/wav` )
        ( vec_free [u] bytes )
        = bytes ( vec_clone [u] wav )
    }
    ( vec_free [u] wav )
    : String url ( f5_whisper_where )
    ( string_push_str url `/inference` )
    : String out ( string_new )
    ?? ( http_post_bytes ( string_data url ) bytes ( string_data ctype ) ) {
        T resp → {
            ? == ( http_status resp ) 200 {
                ?? ( json_parse ( http_body_str resp ) ) {
                    T root → {
                        ?? ( json_obj_get root `text` ) {
                            T tv → { ( string_push_str out ( json_as_str tv ) ) }
                            F → {}
                        }
                        ( json_free root )
                    }
                    F _e → {}
                }
            } {}
            ( response_free resp )
        }
        F _e → {}
    }
    ( string_free url )
    ( string_free ctype )
    ( vec_free [u] bytes )
    ^ ( string_trim out )
}
