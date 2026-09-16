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
// Normalised the way the reference service normalises: lower case, ASCII
// punctuation removed, whitespace collapsed. The lower-casing covers the
// Latin-1 supplement as well as ASCII, because a Finnish transcript is full
// of Ä and Ö and treating those as different letters from ä and ö would
// count every sentence-initial one as an error.

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

// The words of a normalised text.
@ f5_words s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len text )
    : ~ String cur ( string_new )
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ? < c 128 {
            ? ( __f5v_is_space c ) {
                ? > ( string_len cur ) 0 {
                    ( vec_push [String] out ( string_clone cur ) )
                    ( string_clear cur )
                } {}
            } {
                ? ( __f5v_is_punct c ) {} {
                    ( string_push_char cur ? & >= c 65 <= c 90 + c 32 c )
                }
            }
            = i + i 1
        } {
            // a two-byte Latin-1 supplement letter: C3 80..9E lower-cases to
            // C3 A0..BE, and C3 97 (the multiplication sign) is not a letter
            ? & == c 195 < + i 1 n {
                : i b ( nurl_str_get text + i 1 )
                ( string_push_char cur 195 )
                ( string_push_char cur ? & & >= b 128 <= b 158 != b 151 + b 32 b )
                = i + i 2
            } {
                ( string_push_char cur c )
                = i + i 1
            }
        }
    }
    ? > ( string_len cur ) 0 { ( vec_push [String] out ( string_clone cur ) ) } {}
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

// Levenshtein over WORDS, divided by the reference's length — jiwer's word
// error rate. One row of the matrix at a time: a long sentence is a hundred
// words, not a hundred thousand.
@ f5_wer s reference s hypothesis → f {
    : ( Vec String ) r ( f5_words reference )
    : ( Vec String ) h ( f5_words hypothesis )
    : i nr ( vec_len [String] r )
    : i nh ( vec_len [String] h )
    : ( @ v String ) drop_w \ String s → v { ( string_free s ) }
    ? == nr 0 {
        ( vec_free_with [String] r drop_w )
        ( vec_free_with [String] h drop_w )
        ^ ? == nh 0 0.0 1.0
    } {}
    ? == nh 0 {
        ( vec_free_with [String] r drop_w )
        ( vec_free_with [String] h drop_w )
        ^ 1.0
    } {}
    : ( Vec i ) prev ( vec_with_cap [i] + nh 1 )
    : ( Vec i ) row ( vec_with_cap [i] + nh 1 )
    : ~ i j 0
    ~ <= j nh { ( vec_push [i] prev j ) ( vec_push [i] row 0 ) = j + j 1 }
    : ~ i i 1
    ~ <= i nr {
        ( vec_set [i] row 0 i )
        : s rw ( __f5v_word r - i 1 )
        = j 1
        ~ <= j nh {
            : i cost ? ( __f5v_word_eq h - j 1 rw ) 0 1
            : i a + ( __f5v_geti prev j ) 1
            : i b + ( __f5v_geti row - j 1 ) 1
            : i c + ( __f5v_geti prev - j 1 ) cost
            : ~ i m a
            ? < b m { = m b } {}
            ? < c m { = m c } {}
            ( vec_set [i] row j m )
            = j + j 1
        }
        = j 0
        ~ <= j nh { ( vec_set [i] prev j ( __f5v_geti row j ) ) = j + j 1 }
        = i + i 1
    }
    : f d # f ( __f5v_geti prev nh )
    ( vec_free [i] prev )
    ( vec_free [i] row )
    ( vec_free_with [String] r drop_w )
    ( vec_free_with [String] h drop_w )
    ^ / d # f nr
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
