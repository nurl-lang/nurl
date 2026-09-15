// packages/f5tts/src/text.nu — the vocabulary, and the exact character
// sequence an F5-TTS checkpoint was trained to read.
//
// F5-TTS calls its text front-end `convert_char_to_pinyin`, and for Chinese
// that is what it does. For a Latin-script language it does something else
// entirely, and the something else is not cosmetic. The text is segmented by
// jieba first, and jieba's "han" character class — [一-鿕a-zA-Z0-9+#&
// ._%-] — does NOT contain ä, ö or å. A Finnish word therefore breaks into
// pieces at every umlaut, and the rule that puts a space in front of a
// multi-character ASCII segment then fires INSIDE the word:
//
//     "Yöllä"   segments: Y | ö | ll | ä   characters: Y ö _ l l ä
//
// The Finnish checkpoint was fine-tuned through this same front-end, so the
// inserted space is what the model expects to read. Reproducing it is not
// bug-compatibility for its own sake: drop it and every umlauted word becomes
// a word the model has never seen.
//
// Everything jieba does to a Latin run beyond that is nothing — a run of
// han-class bytes comes back out whole (the DAG finds no dictionary word in
// it, the buffer flush hands it to finalseg, and finalseg's own skip class
// yields alphanumerics unsplit). So the segmentation needs no dictionary and
// no Viterbi: it is a three-way byte classification, done here in one pass.
//
//   ( f5_vocab_load path )              → !*F5Vocab String
//   ( f5_text_ids vocab text out )      → v         ids appended to `out`
//   ( f5_chunk_text text max_bytes )    → ( Vec String )

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/symtab.nu`
$ `stdlib/std/fs.nu`

: F5Vocab {
    ( Vec i ) ascii  // 128 slots: a one-byte character's id, -1 when absent
    i map  // symtab: a multi-byte character → its id, in decimal
    i size  // the vocabulary's length, which is also text_num_embeds
}

// The same read, public: run.nu's silence walk needs it too.
@ _f5t_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

@ __f5t_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ -1 } }
}

@ __f5t_err s msg → !*F5Vocab String {
    ^ @ !*F5Vocab String { F ( string_from msg ) }
}

// Read a vocab.txt — one token per line, the line NUMBER is the id. Python
// reads it as `for i, char in enumerate(f)` and drops the last character of
// each line, so a trailing "\r" from a CRLF file would be part of the token;
// a file ending in a newline yields no extra empty token.
@ f5_vocab_load s path → !*F5Vocab String {
    ?? ( read_file path ) {
        T txt → {
            : *F5Vocab v # *F5Vocab ( nurl_alloc Z F5Vocab )
            : ( Vec i ) asc ( vec_with_cap [i] 128 )
            : ~ i k 0
            ~ < k 128 { ( vec_push [i] asc -1 ) = k + k 1 }
            = . v ascii asc
            = . v map ( nurl_sym_new )
            : s data ( string_data txt )
            : i n ( nurl_str_len data )
            : ~ i id 0
            : ~ i start 0
            : ~ i i 0
            ~ <= i n {
                ? | == i n == ( nurl_str_get data i ) 10 {
                    // a token is the line's bytes; the final piece counts only
                    // when the file does not end with a newline
                    ? | < i n > - i start 0 {
                        : i len - i start
                        ? == len 1 {
                            : i c ( nurl_str_get data start )
                            ? < c 128 { ( vec_set [i] asc c id ) } {}
                        } {}
                        ? > len 1 {
                            : String key ( string_new )
                            : ~ i j start
                            ~ < j i { ( string_push_char key ( nurl_str_get data j ) ) = j + j 1 }
                            : String val ( string_new )
                            ( string_push_int val id )
                            ( nurl_sym_def . v map ( string_data key ) ( string_data val ) )
                            ( string_free key )
                            ( string_free val )
                        } {}
                        ? == len 0 {
                            // an empty line is a real token in the file's eyes
                            ( nurl_sym_def . v map `` ( string_data ( string_from `0` ) ) )
                        } {}
                        = id + id 1
                    } {}
                    = start + i 1
                } {}
                = i + i 1
            }
            = . v size id
            ( string_free txt )
            ^ @ !*F5Vocab String { T v }
        }
        F _e → { ^ ( __f5t_err `f5tts: cannot read the vocabulary file` ) }
    }
}

@ f5_vocab_size * F5Vocab v → i { ^ . v size }

@ f5_vocab_free * F5Vocab v → v {
    ( vec_free [i] . v ascii )
    ( nurl_free # s v )
}

// jieba's han class, Latin half: [a-zA-Z0-9+#&._%-]. A run of these is one
// segment; everything else is one character per segment, except that a
// whitespace byte is its own segment too (jieba's re_skip).
@ __f5t_is_hanb i c → b {
    ? & >= c 97 <= c 122 { ^ T } {}
    ? & >= c 65 <= c 90 { ^ T } {}
    ? & >= c 48 <= c 57 { ^ T } {}
    ? | == c 43 == c 35 { ^ T } {}
    ? | == c 38 == c 46 { ^ T } {}
    ? | == c 95 == c 37 { ^ T } {}
    ? == c 45 { ^ T } {}
    ^ F
}

@ __f5t_is_ws i c → b {
    ? == c 32 { ^ T } {}
    ^ & >= c 9 <= c 13
}

// How many bytes this UTF-8 lead byte begins.
@ __f5t_clen i c → i {
    ? < c 128 { ^ 1 } {}
    ? == 192 & c 224 { ^ 2 } {}
    ? == 224 & c 240 { ^ 3 } {}
    ? == 240 & c 248 { ^ 4 } {}
    ^ 1
}

// `last` is the previously emitted character: -2 = nothing yet, -1 = a
// multi-byte character, otherwise its single byte. F5-TTS inserts the space
// unless the list is empty or the previous character is one of " :'\"".
@ __f5t_needs_space i last → b {
    ? == last -2 { ^ F } {}
    ? == last 32 { ^ F } {}
    ? == last 58 { ^ F } {}
    ? == last 39 { ^ F } {}
    ? == last 34 { ^ F } {}
    ^ T
}

@ __f5t_id_ascii * F5Vocab v i c → i {
    ? >= c 128 { ^ 0 } {}
    : i id ( __f5t_geti . v ascii c )
    ? < id 0 { ^ 0 } {}
    ^ id
}

@ __f5t_id_multi * F5Vocab v s text i off i len → i {
    : String key ( string_new )
    : ~ i j 0
    ~ < j len { ( string_push_char key ( nurl_str_get text + off j ) ) = j + j 1 }
    : s got ( nurl_sym_get . v map ( string_data key ) )
    ( string_free key )
    ? == ( nurl_str_len got ) 0 { ^ 0 } {}
    ^ ( nurl_str_to_int got )
}

// The three characters F5-TTS rewrites before anything else looks at the text
// (`custom_trans`): ';' → ',', and the curly quotes to their straight forms.
// The rewrite happens first, so it also decides what the "previous character"
// is for the space rule — a '”' that becomes '"' suppresses the next space.
@ __f5t_translate s text i off i len → i {
    ? == len 1 {
        : i c ( nurl_str_get text off )
        ? == c 59 { ^ 44 } {}
        ^ c
    } {}
    ? == len 3 {
        : i a ( nurl_str_get text off )
        : i b ( nurl_str_get text + off 1 )
        : i c ( nurl_str_get text + off 2 )
        ? & == a 226 == b 128 {
            ? | == c 156 == c 157 { ^ 34 } {}
            ? | == c 152 == c 153 { ^ 39 } {}
        } {}
    } {}
    ^ -1
}

@ __f5t_is_alnum i c → b {
    ? & >= c 97 <= c 122 { ^ T } {}
    ? & >= c 65 <= c 90 { ^ T } {}
    ^ & >= c 48 <= c 57
}

@ __f5t_is_digit i c → b { ^ & >= c 48 <= c 57 }

// jieba's finalseg skip class, as jieba-rs actually spells it:
//     ([a-zA-Z0-9]+(?:.\d+)?%?)
// The dot in that pattern is UNESCAPED, so it matches ANY character — which
// is why "ab-34" and "y2.5" come out whole while "ab-cd" and "12.cd" split.
// Returns the match's length at `pos`, or 0.
@ __f5t_skip_match s text i pos i end → i {
    : ~ i j pos
    ~ & < j end ( __f5t_is_alnum ( nurl_str_get text j ) ) { = j + j 1 }
    ? == j pos { ^ 0 } {}
    ? < + j 1 end {
        ? ( __f5t_is_digit ( nurl_str_get text + j 1 ) ) {
            : ~ i d + j 1
            ~ & < d end ( __f5t_is_digit ( nurl_str_get text d ) ) { = d + d 1 }
            = j d
        } {}
    } {}
    ? & < j end == ( nurl_str_get text j ) 37 { = j + j 1 } {}
    ^ - j pos
}

// Emit one segment's characters, preceded by the space F5-TTS inserts in
// front of a multi-character pure-ASCII segment. Returns the new `last`.
@ __f5t_emit_seg * F5Vocab v s text i from i to ( Vec i ) out i last → i {
    : ~ i lst last
    ? & > - to from 1 ( __f5t_needs_space lst ) {
        ( vec_push [i] out ( __f5t_id_ascii v 32 ) )
        = lst 32
    } {}
    : ~ i k from
    ~ < k to {
        : i b ( nurl_str_get text k )
        ( vec_push [i] out ( __f5t_id_ascii v b ) )
        = lst b
        = k + k 1
    }
    ^ lst
}

// A stretch of a han block with no dictionary word in it: the skip class
// takes the alphanumeric runs, and each gap between them is ONE segment
// (finalseg yields the split's leftovers whole, not character by character).
@ __f5t_scan_plain * F5Vocab v s text i from i to ( Vec i ) out i last → i {
    : ~ i lst last
    : ~ i j from
    : ~ i gs -1
    ~ < j to {
        : i m ( __f5t_skip_match text j to )
        ? > m 0 {
            ? >= gs 0 {
                = lst ( __f5t_emit_seg v text gs j out lst )
                = gs -1
            } {}
            = lst ( __f5t_emit_seg v text j + j m out lst )
            = j + j m
        } {
            ? < gs 0 { = gs j } {}
            = j + j 1
        }
    }
    ? >= gs 0 { = lst ( __f5t_emit_seg v text gs to out lst ) } {}
    ^ lst
}

@ __f5t_lit_at s text i pos i end s w → i {
    : i n ( nurl_str_len w )
    ? > + pos n end { ^ 0 } {}
    : ~ i k 0
    ~ < k n {
        ? != ( nurl_str_get text + pos k ) ( nurl_str_get w k ) { ^ 0 } {}
        = k + k 1
    }
    ^ n
}

// jieba's dictionary holds exactly five entries written only in ASCII —
// AT&T, C++, c++, C#, c# — and a han block containing one is cut around it.
// None of them can occur inside a word of any Latin-script language, so this
// is the whole of the dictionary's influence here, not a sample of it.
@ __f5t_dict_at s text i pos i end → i {
    : i a ( __f5t_lit_at text pos end `AT&T` )
    ? > a 0 { ^ a } {}
    : i b ( __f5t_lit_at text pos end `C++` )
    ? > b 0 { ^ b } {}
    : i c ( __f5t_lit_at text pos end `c++` )
    ? > c 0 { ^ c } {}
    : i d ( __f5t_lit_at text pos end `C#` )
    ? > d 0 { ^ d } {}
    ^ ( __f5t_lit_at text pos end `c#` )
}

@ __f5t_scan_block * F5Vocab v s text i from i to ( Vec i ) out i last → i {
    : ~ i lst last
    : ~ i i from
    : ~ i start from
    ~ < i to {
        : i w ( __f5t_dict_at text i to )
        ? > w 0 {
            ? < start i { = lst ( __f5t_scan_plain v text start i out lst ) } {}
            = lst ( __f5t_emit_seg v text i + i w out lst )
            = i + i w
            = start i
        } { = i + i 1 }
    }
    ? < start to { = lst ( __f5t_scan_plain v text start to out lst ) } {}
    ^ lst
}

// The character sequence, as vocabulary ids, appended to `out`.
@ f5_text_ids * F5Vocab v s text ( Vec i ) out → v {
    : i n ( nurl_str_len text )
    : ~ i last -2
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        ? ( __f5t_is_hanb c ) {
            : ~ i j i
            ~ & < j n ( __f5t_is_hanb ( nurl_str_get text j ) ) { = j + j 1 }
            = last ( __f5t_scan_block v text i j out last )
            = i j
        } {
            : i clen ( __f5t_clen c )
            : i tr ( __f5t_translate text i clen )
            ? >= tr 0 {
                ( vec_push [i] out ( __f5t_id_ascii v tr ) )
                = last tr
            } {
                ? == clen 1 {
                    ( vec_push [i] out ( __f5t_id_ascii v c ) )
                    = last c
                } {
                    ( vec_push [i] out ( __f5t_id_multi v text i clen ) )
                    = last -1
                }
            }
            = i + i clen
        }
    }
}

// ── chunking ────────────────────────────────────────────────────────
//
// F5-TTS splits the text to be spoken at a whitespace run that follows one of
// ;:,.!? (the whitespace is DROPPED — it is the regex separator), and after
// each of the full-width CJK marks. Sentences are then packed greedily into
// chunks of at most `max_bytes` bytes.

@ __f5t_is_break i c → b {
    ? | == c 59 == c 58 { ^ T } {}
    ? | == c 44 == c 46 { ^ T } {}
    ? | == c 33 == c 63 { ^ T } {}
    ^ F
}

// The three-byte full-width marks ；：，。！？ — all of them start ef bc or ef bd
// except 。 (e3 80 82). Compared as whole characters, not bytes.
@ __f5t_is_cjk_break s text i off i clen → b {
    ? != clen 3 { ^ F } {}
    : i a ( nurl_str_get text off )
    : i b ( nurl_str_get text + off 1 )
    : i c ( nurl_str_get text + off 2 )
    ? & == a 227 & == b 128 == c 130 { ^ T } {}
    ? != a 239 { ^ F } {}
    ? != b 188 { ^ F } {}
    ? | == c 155 == c 154 { ^ T } {}
    ? | == c 140 == c 129 { ^ T } {}
    ? == c 159 { ^ T } {}
    ^ F
}

// Split into sentences the way the regex does, then pack.
@ f5_chunk_text s text i max_bytes → ( Vec String ) {
    : ( Vec String ) sents ( vec_new [String] )
    : i n ( nurl_str_len text )
    : ~ i start 0
    : ~ i i 0
    ~ < i n {
        : i c ( nurl_str_get text i )
        : i clen ( __f5t_clen c )
        ? & ( __f5t_is_break c ) < + i 1 n {
            ? ( __f5t_is_ws ( nurl_str_get text + i 1 ) ) {
                : ~ i e + i 1
                ~ & < e n ( __f5t_is_ws ( nurl_str_get text e ) ) { = e + e 1 }
                ( vec_push [String] sents ( string_from ( nurl_str_slice text start - + i 1 start ) ) )
                = start e
                = i e
            } { = i + i clen }
        } {
            ? ( __f5t_is_cjk_break text i clen ) {
                ( vec_push [String] sents ( string_from ( nurl_str_slice text start - + i clen start ) ) )
                = start + i clen
                = i + i clen
            } { = i + i clen }
        }
    }
    ? < start n {
        ( vec_push [String] sents ( string_from ( nurl_str_slice text start - n start ) ) )
    } {}

    : ( Vec String ) chunks ( vec_new [String] )
    : String cur ( string_new )
    : i ns ( vec_len [String] sents )
    : ~ i k 0
    ~ < k ns {
        ?? ( vec_get [String] sents k ) {
            T s → {
                : i sl ( string_len s )
                : b pad ? > sl 0 < ( nurl_str_get ( string_data s ) - sl 1 ) 128 F
                ? <= + ( string_len cur ) sl max_bytes {
                    ( string_push_str cur ( string_data s ) )
                    ? pad { ( string_push_char cur 32 ) } {}
                } {
                    ? > ( string_len cur ) 0 {
                        ( vec_push [String] chunks ( string_trim cur ) )
                        ( string_clear cur )
                    } {}
                    ( string_push_str cur ( string_data s ) )
                    ? pad { ( string_push_char cur 32 ) } {}
                }
            }
            F → {}
        }
        = k + k 1
    }
    ? > ( string_len cur ) 0 { ( vec_push [String] chunks ( string_trim cur ) ) } {}
    ( string_free cur )
    : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
    ( vec_free_with [String] sents drop_str )
    ^ chunks
}
