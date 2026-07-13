// packages/tokenizer/src/tokenizer.nu — the tokenizer engine.
//
// This is nurllama's tokenizer, lifted out of it: SentencePiece bigram merging
// for llama-family vocabularies, byte-level BPE for gpt2-family ones, inline
// special-token parsing, and decoding — the parts that have nothing to do with
// where the vocabulary came from.
//
// It is deliberately loader-agnostic. `tok_build` takes the PARTS — pieces,
// scores, token types, merges, and the handful of flags — so a vocabulary can
// arrive from a GGUF's metadata (nurllama), from Hugging Face's vocab.json +
// merges.txt (whisper, see src/hf.nu), or from anywhere else, without this file
// gaining a dependency on any container format.
//
//   ( tok_build spec pieces scores types merges ) → !*Tok String   (takes ownership)
//   ( tok_encode t text add_special )             → ( Vec i )
//   ( tok_decode t ids )                          → ( Vec u )
//   ( tok_piece t id )                            → ( Vec u )
//   ( tok_free t )                                → v
//
// The engine's behaviour is pinned by nurllama's existing parity tests, which
// compare it token-for-token against independent python SentencePiece and BPE
// implementations on real models — the extraction is faithful iff those still
// pass.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/utf8.nu`

: i TT_NORMAL 1
: i TT_UNKNOWN 2
: i TT_CONTROL 3
: i TT_USER 4
: i TT_UNUSED 5
: i TT_BYTE 6

: i TOK_SPM 0
: i TOK_BPE 1

// BPE pre-tokenizer variants (tokenizer.ggml.pre)
: i PRE_DEFAULT 0
: i PRE_QWEN2 1

: Tok {
    i mode
    ( Vec String ) pieces
    ( Vec f ) scores
    ( Vec i ) ttype
    ( HashMap s i ) lookup
    ( HashMap s i ) ranks
    ( Vec String ) rankkeys
    ( Vec String ) byte_enc
    ( Vec i ) byte_id
    i pre
    i bos
    i eos
    i unk
    b add_bos
    b add_eos
    b add_space_prefix
    // Inline special tokens (CONTROL / USER_DEFINED pieces such as
    // `<start_of_turn>` or `<|im_start|>`). A chat template puts these in the
    // TEXT, and they must come out as their own single id — tokenised as
    // ordinary text they shred into a dozen pieces and the model answers a
    // different question than the one asked. `sp_first` is a 256-entry table
    // of the bytes any special piece can start with, so ordinary text pays
    // one array lookup per byte rather than a scan of the whole list.
    ( Vec i ) sp_ids
    ( Vec i ) sp_first
}

// ── string-keyed map helpers (yoloe/bpe.nu idiom) ───────────────────
@ __tk_set ( HashMap s i ) m s key i val → v {
    : ?i _old ( map_set [s i] m key val \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
}

@ __tk_get ( HashMap s i ) m s key → ?i {
    ^ ( map_get [s i] m key \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
}

@ __tk_geti ( Vec i ) v i k i def → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ def } }
}

@ __tk_getf ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

// Borrowed data pointer of piece #k ("" when out of range).
@ __tk_piece_data * Tok t i k → s {
    ?? ( vec_get [String] . t pieces k ) { T p → { ^ ( string_data p ) } F → { ^ `` } }
}

// ── GPT-2 byte→unicode remap ────────────────────────────────────────
// Bytes that are "printable" keep their codepoint ('!'..'~', 0xA1..0xAC,
// 0xAE..0xFF); every other byte b gets 256+n with n counting the
// non-printable bytes in ascending byte order. Exactly gpt2's
// bytes_to_unicode().
@ __tk_byte_keeps_cp i b2 → b {
    ? & >= b2 33 <= b2 126 { ^ T } {}
    ? & >= b2 161 <= b2 172 { ^ T } {}
    ^ & >= b2 174 <= b2 255
}

@ __tk_build_byte_enc → ( Vec String ) {
    : ( Vec String ) enc ( vec_new [String] )
    : ~ i n 0
    : ~ i b2 0
    ~ < b2 256 {
        ? ( __tk_byte_keeps_cp b2 ) {
            ( vec_push [String] enc ( utf8_encode_cp b2 ) )
        } {
            ( vec_push [String] enc ( utf8_encode_cp + 256 n ) )
            = n + n 1
        }
        = b2 + b2 1
    }
    ^ enc
}

// ── construction ────────────────────────────────────────────────────

@ __tk_err s msg → !*Tok String {
    ^ @ !*Tok String { F ( string_from msg ) }
}

// Parse "<0xNN>" → byte value, -1 when the piece is not that shape.
@ __tk_parse_byte_piece s p → i {
    ? != ( nurl_str_len p ) 6 { ^ -1 } {}
    ? | == ( nurl_str_starts p `<0x` ) 0 != ( nurl_str_get p 5 ) 62 { ^ -1 } {}
    : i h1 ( hex_val ( nurl_str_get p 3 ) )
    : i h2 ( hex_val ( nurl_str_get p 4 ) )
    ? | < h1 0 < h2 0 { ^ -1 } {}
    ^ | << h1 4 h2
}

// Build a tokenizer from an open GGUF model. Copies the vocabulary —
// the Gguf may be closed afterwards.

// Everything a vocabulary needs to say about itself, whatever file it came in.
: TokSpec {
    i mode  // TOK_SPM | TOK_BPE
    i pre  // PRE_DEFAULT | PRE_QWEN2
    i bos
    i eos
    i unk
    b add_bos
    b add_eos
    b add_space_prefix
}

// Build a tokenizer from its PARTS. TAKES OWNERSHIP of the four vectors — they
// become the Tok's, and tok_free releases them.
//
//   pieces  the vocabulary, in id order
//   scores  SPM merge scores (empty for BPE)
//   types   token types (TT_NORMAL/CONTROL/USER/BYTE/…); empty = all NORMAL
//   merges  BPE merge rules, "A B", in rank order (empty for SPM)
@ tok_build TokSpec spec ( Vec String ) pieces ( Vec f ) scores ( Vec i ) types ( Vec String ) merges → !*Tok String {
    : i nvocab ( vec_len [String] pieces )
    ? == nvocab 0 {
        ( vec_free_with [String] pieces \ String s → v { ( string_free s ) } )
        ( vec_free [f] scores )
        ( vec_free [i] types )
        ( vec_free_with [String] merges \ String s → v { ( string_free s ) } )
        ^ ( __tk_err `tokenizer: empty vocabulary` )
    } {}
    : i mode . spec mode
    ? & != mode TOK_SPM != mode TOK_BPE {
        ( vec_free_with [String] pieces \ String s → v { ( string_free s ) } )
        ( vec_free [f] scores )
        ( vec_free [i] types )
        ( vec_free_with [String] merges \ String s → v { ( string_free s ) } )
        ^ ( __tk_err `tokenizer: unknown tokenizer mode` )
    } {}
    ? & == mode TOK_BPE == 0 ( vec_len [String] merges ) {
        ( vec_free_with [String] pieces \ String s → v { ( string_free s ) } )
        ( vec_free [f] scores )
        ( vec_free [i] types )
        ( vec_free_with [String] merges \ String s → v { ( string_free s ) } )
        ^ ( __tk_err `tokenizer: a BPE vocabulary needs merge rules` )
    } {}

    : *Tok t # *Tok ( nurl_alloc Z Tok )
    = . t mode mode
    = . t pieces pieces
    = . t scores scores
    = . t ttype types
    = . t sp_ids ( vec_new [i] )
    = . t sp_first ( vec_new [i] )
    = . t lookup ( map_new [s i] )
    = . t ranks ( map_new [s i] )
    = . t rankkeys merges
    = . t byte_enc ? == mode TOK_BPE ( __tk_build_byte_enc ) ( vec_new [String] )
    = . t byte_id ( vec_new [i] )
    = . t pre . spec pre
    = . t bos . spec bos
    = . t eos . spec eos
    = . t unk . spec unk
    = . t add_bos . spec add_bos
    = . t add_eos . spec add_eos
    = . t add_space_prefix . spec add_space_prefix

    // types default to NORMAL when the source gave none
    : ~ i k ( vec_len [i] . t ttype )
    ~ < k nvocab {
        ( vec_push [i] . t ttype TT_NORMAL )
        = k + k 1
    }

    // piece → id (last one wins on a duplicate piece, like llama.cpp's
    // token_to_id map). Keys borrow the pieces' heap buffers.
    = k 0
    ~ < k nvocab {
        ( __tk_set . t lookup ( __tk_piece_data t k ) k )
        = k + k 1
    }

    // Special-token index: every CONTROL / USER_DEFINED piece, plus the table
    // of first bytes so ordinary text is not scanned against the whole list.
    = k 0
    ~ < k 256 {
        ( vec_push [i] . t sp_first 0 )
        = k + k 1
    }
    = k 0
    ~ < k nvocab {
        : i ty ( __tk_geti . t ttype k TT_NORMAL )
        ? | == ty TT_CONTROL == ty TT_USER {
            : s pc ( __tk_piece_data t k )
            ? > ( nurl_str_len pc ) 0 {
                ( vec_push [i] . t sp_ids k )
                ( vec_set [i] . t sp_first ( nurl_str_get pc 0 ) 1 )
            } {}
        } {}
        = k + k 1
    }

    // byte → id table: SPM <0xNN> BYTE pieces; BPE remapped singles
    = k 0
    ~ < k 256 {
        ( vec_push [i] . t byte_id -1 )
        = k + k 1
    }
    ? == mode TOK_SPM {
        = k 0
        ~ < k nvocab {
            : i bv ( __tk_parse_byte_piece ( __tk_piece_data t k ) )
            ? >= bv 0 { ( vec_set [i] . t byte_id bv k ) } {}
            = k + k 1
        }
    } {
        = k 0
        ~ < k 256 {
            ?? ( vec_get [String] . t byte_enc k ) {
                T e → {
                    ?? ( __tk_get . t lookup ( string_data e ) ) {
                        T id → { ( vec_set [i] . t byte_id k id ) }
                        F → {}
                    }
                }
                F → {}
            }
            = k + k 1
        }
    }

    // BPE merge ranks: "A B" → rank. The keys borrow the merge strings' own
    // buffers, which the Tok now owns.
    ? == mode TOK_BPE {
        : ~ i r 0
        ~ < r ( vec_len [String] . t rankkeys ) {
            ?? ( vec_get [String] . t rankkeys r ) {
                T own → { ( __tk_set . t ranks ( string_data own ) r ) }
                F → {}
            }
            = r + r 1
        }
    } {}
    ^ @ !*Tok String { T t }
}

@ tok_free * Tok t → v {
    ( vec_free_with [String] . t pieces \ String s → v { ( string_free s ) } )
    ( vec_free [f] . t scores )
    ( vec_free [i] . t ttype )
    ( map_free [s i] . t lookup )
    ( map_free [s i] . t ranks )
    ( vec_free_with [String] . t rankkeys \ String s → v { ( string_free s ) } )
    ( vec_free_with [String] . t byte_enc \ String s → v { ( string_free s ) } )
    ( vec_free [i] . t byte_id )
    ( vec_free [i] . t sp_ids )
    ( vec_free [i] . t sp_first )
    ( nurl_free # s t )
}

@ tok_n_vocab * Tok t → i { ^ ( vec_len [String] . t pieces ) }

@ tok_bos * Tok t → i { ^ . t bos }

@ tok_eos * Tok t → i { ^ . t eos }

@ tok_unk * Tok t → i { ^ . t unk }

// ── SPM encode ──────────────────────────────────────────────────────

// Push token(s) for one unmerged symbol: vocab piece, else per-byte
// <0xNN>, else UNK once.
@ __tk_spm_emit * Tok t s esc i off i len ( Vec i ) out → v {
    : String sym ( string_new )
    ( string_push_bytes sym # *u + # i esc off len )
    ?? ( __tk_get . t lookup ( string_data sym ) ) {
        T id → { ( vec_push [i] out id ) }
        F → {
            : ~ i j 0
            ~ < j len {
                : i bv ( nurl_str_get esc + off j )
                : i bid ( __tk_geti . t byte_id bv -1 )
                ? >= bid 0 { ( vec_push [i] out bid ) } {
                    ? >= . t unk 0 { ( vec_push [i] out . t unk ) } {}
                }
                = j + j 1
            }
        }
    }
    ( string_free sym )
}

@ __tk_spm_encode * Tok t s text ( Vec i ) out → v {
    // escape: optional leading space, then every ' ' → ▁ (E2 96 81)
    : String esc ( string_new )
    ? & . t add_space_prefix > ( nurl_str_len text ) 0 {
        ( string_push_str esc `▁` )
    } {}
    : ~ i p 0
    : i tn ( nurl_str_len text )
    ~ < p tn {
        : i b2 ( nurl_str_get text p )
        ? == b2 32 { ( string_push_str esc `▁` ) } { ( string_push_char esc b2 ) }
        = p + p 1
    }
    : s e ( string_data esc )
    : i en ( string_len esc )

    // split into UTF-8 characters: parallel start/len + doubly-linked
    // alive list (nxt/prv by symbol index, -1 = end)
    : ( Vec i ) starts ( vec_new [i] )
    : ( Vec i ) lens ( vec_new [i] )
    : ( Vec i ) nxt ( vec_new [i] )
    : ( Vec i ) prv ( vec_new [i] )
    = p 0
    : ~ i nsym 0
    ~ < p en {
        : Utf8Dec d ( utf8_decode e p )
        ? < . d width 1 { = p en } {
            ( vec_push [i] starts p )
            ( vec_push [i] lens . d width )
            ( vec_push [i] nxt + nsym 1 )
            ( vec_push [i] prv - nsym 1 )
            = nsym + nsym 1
            = p + p . d width
        }
    }
    ? == nsym 0 {
        ( string_free esc )
        ( vec_free [i] starts ) ( vec_free [i] lens )
        ( vec_free [i] nxt ) ( vec_free [i] prv )
        ^ v
    } {}
    ( vec_set [i] nxt - nsym 1 -1 )

    // bigram merge: highest-score vocab pair wins, leftmost on ties —
    // llama.cpp llm_tokenizer_spm order. Rescan per round: prompt-sized
    // inputs make O(n²) irrelevant next to the model forward pass.
    : String pair ( string_new )
    : ~ b again T
    ~ again {
        = again F
        : ~ i best -1
        : ~ f best_score -1.0e30
        : ~ i j 0
        ~ >= j 0 {
            : i nj ( __tk_geti nxt j -1 )
            ? >= nj 0 {
                : i o1 ( __tk_geti starts j 0 )
                : i l1 ( __tk_geti lens j 0 )
                : i l2 ( __tk_geti lens nj 0 )
                ( string_clear pair )
                ( string_push_bytes pair # *u + # i e o1 + l1 l2 )
                ?? ( __tk_get . t lookup ( string_data pair ) ) {
                    T id → {
                        : f sc ( __tk_getf . t scores id )
                        ? > sc best_score {
                            = best j
                            = best_score sc
                        } {}
                    }
                    F → {}
                }
            } {}
            = j nj
        }
        ? >= best 0 {
            : i nb ( __tk_geti nxt best -1 )
            ( vec_set [i] lens best + ( __tk_geti lens best 0 ) ( __tk_geti lens nb 0 ) )
            : i nn ( __tk_geti nxt nb -1 )
            ( vec_set [i] nxt best nn )
            ? >= nn 0 { ( vec_set [i] prv nn best ) } {}
            = again T
        } {}
    }
    ( string_free pair )

    : ~ i j 0
    ~ >= j 0 {
        ( __tk_spm_emit t e ( __tk_geti starts j 0 ) ( __tk_geti lens j 0 ) out )
        = j ( __tk_geti nxt j -1 )
    }
    ( vec_free [i] starts ) ( vec_free [i] lens )
    ( vec_free [i] nxt ) ( vec_free [i] prv )
    ( string_free esc )
}

// ── BPE encode ──────────────────────────────────────────────────────

@ __tk_is_ascii_letter i b2 → b {
    ^ | & >= b2 65 <= b2 90 & >= b2 97 <= b2 122
}

@ __tk_is_ascii_digit i b2 → b { ^ & >= b2 48 <= b2 57 }

@ __tk_is_ws i b2 → b {
    ^ | | | == b2 32 == b2 9 == b2 10 == b2 13
}

// "letter" under the v1 \p{L} approximation: ASCII letter or any
// non-ASCII lead byte (multibyte scripts tokenize as letter runs).
@ __tk_is_letterish i b2 → b {
    ^ | ( __tk_is_ascii_letter b2 ) >= b2 128
}

// GPT-2 contraction after an apostrophe at text[p]: returns the length
// INCLUDING the apostrophe, or 0.
@ __tk_contraction s text i p i n → i {
    ? >= + p 1 n { ^ 0 } {}
    : i c1 ( nurl_str_get text + p 1 )
    ? | | == c1 115 == c1 116 | == c1 109 == c1 100 { ^ 2 } {}
    ? >= + p 2 n { ^ 0 } {}
    : i c2 ( nurl_str_get text + p 2 )
    ? & == c1 114 == c2 101 { ^ 3 } {}
    ? & == c1 118 == c2 101 { ^ 3 } {}
    ? & == c1 108 == c2 108 { ^ 3 } {}
    ^ 0
}

// qwen2's pre-tokenizer, alternation by alternation — the order is what
// decides the token ids:
//
//   1  (?i:'s|'t|'re|'ve|'m|'ll|'d)      case-insensitive contractions
//   2  [^\r\n\p{L}\p{N}]?\p{L}+          letters, optionally absorbing ONE
//                                        leading non-letter/digit char
//                                        (a space, but also "(" in "(foo")
//   3  \p{N}                              ONE digit (GPT-2 groups runs)
//   4   ?[^\s\p{L}\p{N}]+[\r\n]*         punctuation run + trailing newlines
//   5  \s*[\r\n]+                        whitespace ending in newlines
//   6  \s+(?!\S)                         whitespace NOT followed by a
//                                        non-space — a run of k spaces
//                                        before a word yields k−1 here and
//                                        leaves the last space to rule 2
//   7  \s+                                anything left
@ __tk_pretoken_len_qwen2 s text i p i n → i {
    : i b0 ( nurl_str_get text p )

    // 1
    ? == b0 39 {
        : i cl ( __tk_contraction_ci text p n )
        ? > cl 0 { ^ cl } {}
    } {}

    // 2 — the lead char must not be a letter, a digit or a newline
    ? & ! ( __tk_is_letterish b0 ) & ! ( __tk_is_ascii_digit b0 ) & != b0 10 != b0 13 {
        ? & < + p 1 n ( __tk_is_letterish ( nurl_str_get text + p 1 ) ) {
            : ~ i r + p 1
            ~ & < r n ( __tk_is_letterish ( nurl_str_get text r ) ) { = r + r 1 }
            ^ - r p
        } {}
    } {}
    ? ( __tk_is_letterish b0 ) {
        : ~ i r p
        ~ & < r n ( __tk_is_letterish ( nurl_str_get text r ) ) { = r + r 1 }
        ^ - r p
    } {}

    // 3
    ? ( __tk_is_ascii_digit b0 ) { ^ 1 } {}

    // 4 — an optional single space, then a punctuation run, then newlines
    : ~ i q p
    : ~ i lead 0
    ? & == b0 32 < + p 1 n {
        : i b1 ( nurl_str_get text + p 1 )
        ? & ! ( __tk_is_ws b1 ) & ! ( __tk_is_letterish b1 ) ! ( __tk_is_ascii_digit b1 ) {
            = q + p 1
            = lead 1
        } {}
    } {}
    ? | > lead 0 & ! ( __tk_is_ws b0 ) & ! ( __tk_is_letterish b0 ) ! ( __tk_is_ascii_digit b0 ) {
        : ~ i r q
        : ~ b more T
        ~ & more < r n {
            : i cc ( nurl_str_get text r )
            ? | | ( __tk_is_ws cc ) ( __tk_is_letterish cc ) ( __tk_is_ascii_digit cc ) { = more F } { = r + r 1 }
        }
        ? > r q {
            ~ & < r n | == ( nurl_str_get text r ) 10 == ( nurl_str_get text r ) 13 { = r + r 1 }
            ^ - r p
        } {}
    } {}

    // 5/6/7 — whitespace
    ? ( __tk_is_ws b0 ) {
        : ~ i r p
        ~ & < r n ( __tk_is_ws ( nurl_str_get text r ) ) { = r + r 1 }
        // 5: through the LAST newline inside the run, if any
        : ~ i nl -1
        : ~ i k p
        ~ < k r {
            : i cc ( nurl_str_get text k )
            ? | == cc 10 == cc 13 { = nl k } {}
            = k + k 1
        }
        ? >= nl 0 { ^ - + nl 1 p } {}
        // 6: a run followed by a non-space yields all but its last char —
        // rule 2 (or 4) picks that one up as its leading character
        ? & < r n > - r p 1 { ^ - - r p 1 } {}
        // 7
        ^ - r p
    } {}

    ^ 1
}

// Case-insensitive contraction after the apostrophe at text[p]
// ('s 't 're 've 'm 'll 'd, either case). Length includes the quote.
@ __tk_contraction_ci s text i p i n → i {
    ? >= + p 1 n { ^ 0 } {}
    : i c1 ( __tk_lower ( nurl_str_get text + p 1 ) )
    ? | | == c1 115 == c1 116 | == c1 109 == c1 100 { ^ 2 } {}
    ? >= + p 2 n { ^ 0 } {}
    : i c2 ( __tk_lower ( nurl_str_get text + p 2 ) )
    ? & == c1 114 == c2 101 { ^ 3 } {}
    ? & == c1 118 == c2 101 { ^ 3 } {}
    ? & == c1 108 == c2 108 { ^ 3 } {}
    ^ 0
}

@ __tk_lower i c → i {
    ^ ? & >= c 65 <= c 90 + c 32 c
}

// One GPT-2 pre-token starting at p; returns its byte length (≥ 1).
@ __tk_pretoken_len s text i p i n → i {
    : i b0 ( nurl_str_get text p )
    ? == b0 39 {
        : i cl ( __tk_contraction text p n )
        ? > cl 0 { ^ cl } {}
    } {}
    // ' ?<run>': a single leading space glues to a following letter /
    // digit / punct run
    : ~ i q p
    : ~ i lead 0
    ? & == b0 32 < + p 1 n {
        : i b1 ( nurl_str_get text + p 1 )
        ? ! ( __tk_is_ws b1 ) {
            = q + p 1
            = lead 1
        } {}
    } {}
    : i c ( nurl_str_get text q )
    ? ( __tk_is_letterish c ) {
        : ~ i r q
        ~ & < r n ( __tk_is_letterish ( nurl_str_get text r ) ) { = r + r 1 }
        ^ + lead - r q
    } {}
    ? ( __tk_is_ascii_digit c ) {
        : ~ i r q
        ~ & < r n ( __tk_is_ascii_digit ( nurl_str_get text r ) ) { = r + r 1 }
        ^ + lead - r q
    } {}
    ? ( __tk_is_ws c ) {
        // Whitespace run (only reachable with lead == 0). GPT-2's rule is
        // `\s+(?!\S)` BEFORE `\s+`: a run followed by a non-space gives its
        // LAST character back, so that the next token starts with it — " leading"
        // is one piece, not " " + "leading". Swallowing the whole run instead
        // produces ids no model has ever seen for text as ordinary as two
        // spaces. (The qwen2 variant below always had this; the default one did
        // not, and nothing noticed until a vocabulary without a merge for the
        // double space came along.)
        : ~ i r q
        ~ & < r n ( __tk_is_ws ( nurl_str_get text r ) ) { = r + r 1 }
        ? & < r n > - r q 1 { ^ - - r q 1 } {}
        ^ - r q
    } {}
    // punct run: neither ws nor letterish nor digit
    : ~ i r q
    : ~ b more T
    ~ & more < r n {
        : i cc ( nurl_str_get text r )
        ? | | ( __tk_is_ws cc ) ( __tk_is_letterish cc ) ( __tk_is_ascii_digit cc ) { = more F } { = r + r 1 }
    }
    ^ + lead - r q
}

// BPE-merge one pre-token (raw bytes text[off..off+len)) and append ids.
@ __tk_bpe_word * Tok t s text i off i len ( Vec i ) out → v {
    // word = remapped single-byte symbols
    : ( Vec String ) word ( vec_new [String] )
    : ~ i j 0
    ~ < j len {
        : i bv ( nurl_str_get text + off j )
        ?? ( vec_get [String] . t byte_enc bv ) {
            T e → { ( vec_push [String] word ( string_clone e ) ) }
            F → {}
        }
        = j + j 1
    }
    // lowest-rank adjacent pair merges first (yoloe __bpe idiom, ranks
    // keyed as "A B" exactly as the merges array stores them)
    : String key ( string_new )
    : ~ b again T
    ~ again {
        = again F
        : ~ i best -1
        : ~ i best_rank 2147483647
        : ~ i k 0
        ~ < k - ( vec_len [String] word ) 1 {
            ( string_clear key )
            ?? ( vec_get [String] word k ) {
                T a → { ( string_push_str key ( string_data a ) ) }
                F → {}
            }
            ( string_push_char key 32 )
            ?? ( vec_get [String] word + k 1 ) {
                T b3 → { ( string_push_str key ( string_data b3 ) ) }
                F → {}
            }
            ?? ( __tk_get . t ranks ( string_data key ) ) {
                T r → {
                    ? < r best_rank {
                        = best k
                        = best_rank r
                    } {}
                }
                F → {}
            }
            = k + k 1
        }
        ? >= best 0 {
            // concat word[best] ++ word[best+1], drop word[best+1]
            ?? ( vec_get [String] word + best 1 ) {
                T b3 → {
                    ?? ( vec_get [String] word best ) {
                        T a → { ( string_push_str a ( string_data b3 ) ) }
                        F → {}
                    }
                    ( string_free b3 )
                }
                F → {}
            }
            : ?String _rm ( vec_remove [String] word + best 1 )
            = again T
        } {}
    }
    ( string_free key )
    : ~ i k 0
    ~ < k ( vec_len [String] word ) {
        ?? ( vec_get [String] word k ) {
            T a → {
                ?? ( __tk_get . t lookup ( string_data a ) ) {
                    T id → { ( vec_push [i] out id ) }
                    F → { ? >= . t unk 0 { ( vec_push [i] out . t unk ) } {} }
                }
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] word \ String s → v { ( string_free s ) } )
}

@ __tk_bpe_encode * Tok t s text ( Vec i ) out → v {
    : i n ( nurl_str_len text )
    : ~ i p 0
    ~ < p n {
        : i len ? == . t pre PRE_QWEN2 ( __tk_pretoken_len_qwen2 text p n ) ( __tk_pretoken_len text p n )
        ( __tk_bpe_word t text p ? < len 1 1 len out )
        = p + p ? < len 1 1 len
    }
}

// ── public encode / decode ──────────────────────────────────────────

// The longest special-token piece matching `text` at `p`, or -1. Only called
// when text[p] is a byte some special piece starts with.
@ __tk_special_at * Tok t s text i p i n → i {
    : ~ i best -1
    : ~ i best_len 0
    : ~ i j 0
    : i ns ( vec_len [i] . t sp_ids )
    ~ < j ns {
        : i id ( __tk_geti . t sp_ids j -1 )
        : s pc ( __tk_piece_data t id )
        : i pl ( nurl_str_len pc )
        ? & > pl best_len <= + p pl n {
            : ~ b eq T
            : ~ i c 0
            ~ & eq < c pl {
                ? != ( nurl_str_get text + p c ) ( nurl_str_get pc c ) { = eq F } {}
                = c + c 1
            }
            ? eq { = best id = best_len pl } {}
        } {}
        = j + j 1
    }
    ^ ? >= best 0 best -1
}

// Encode one run of ordinary text (no special tokens inside it).
@ __tk_encode_raw * Tok t s text ( Vec i ) out → v {
    ? == . t mode TOK_SPM { ( __tk_spm_encode t text out ) } { ( __tk_bpe_encode t text out ) }
}

@ tok_encode * Tok t s text b add_special → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    ? & & add_special . t add_bos >= . t bos 0 { ( vec_push [i] out . t bos ) } {}
    // Split the text on special tokens (`<start_of_turn>`, `<|im_start|>`, …)
    // and emit each as its own id — a chat template writes them as text, and
    // shredding them into ordinary pieces feeds the model a prompt it has
    // never seen. Only done under add_special, which is exactly llama.cpp's
    // parse_special: `nurllama tokenize --no-special` still treats the markers
    // as literal text.
    ? & add_special > ( vec_len [i] . t sp_ids ) 0 {
        : i n ( nurl_str_len text )
        : String buf ( string_new )
        : ~ i p 0
        ~ < p n {
            : i b0 ( nurl_str_get text p )
            : ~ i hit -1
            ? != 0 ( __tk_geti . t sp_first b0 0 ) { = hit ( __tk_special_at t text p n ) } {}
            ? >= hit 0 {
                ? > ( string_len buf ) 0 {
                    ( __tk_encode_raw t ( string_data buf ) out )
                    ( string_clear buf )
                } {}
                ( vec_push [i] out hit )
                = p + p ( nurl_str_len ( __tk_piece_data t hit ) )
            } {
                ( string_push_char buf b0 )
                = p + p 1
            }
        }
        ? > ( string_len buf ) 0 { ( __tk_encode_raw t ( string_data buf ) out ) } {}
        ( string_free buf )
    } {
        ( __tk_encode_raw t text out )
    }
    ? & & add_special . t add_eos >= . t eos 0 { ( vec_push [i] out . t eos ) } {}
    ^ out
}

// Raw bytes of one token: SPM BYTE pieces become their byte, ▁ becomes
// a space, control tokens become nothing; BPE pieces run the inverse
// byte remap.
@ tok_piece * Tok t i id → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    ? | < id 0 >= id ( tok_n_vocab t ) { ^ out } {}
    : i ty ( __tk_geti . t ttype id TT_NORMAL )
    ? == ty TT_CONTROL { ^ out } {}
    : s p ( __tk_piece_data t id )
    ? == . t mode TOK_SPM {
        ? == ty TT_BYTE {
            : i bv ( __tk_parse_byte_piece p )
            ? >= bv 0 {
                ( vec_push [u] out # u bv )
                ^ out
            } {}
        } {}
        // copy piece bytes, ▁ (E2 96 81) → ' '
        : i n ( nurl_str_len p )
        : ~ i j 0
        ~ < j n {
            : i b2 ( nurl_str_get p j )
            ? & & == b2 226 < + j 2 n & == ( nurl_str_get p + j 1 ) 150 == ( nurl_str_get p + j 2 ) 129 {
                ( vec_push [u] out # u 32 )
                = j + j 3
            } {
                ( vec_push [u] out # u b2 )
                = j + j 1
            }
        }
        ^ out
    } {}
    // BPE: decode remapped codepoints back to bytes
    : ~ i j 0
    : i n ( nurl_str_len p )
    ~ < j n {
        : Utf8Dec d ( utf8_decode p j )
        ? < . d width 1 { = j n } {
            // find the byte whose enc codepoint is d.cp — 256-entry scan
            // is fine at decode granularity
            : ~ i bv 0
            : ~ i hit -1
            ~ < bv 256 {
                ?? ( vec_get [String] . t byte_enc bv ) {
                    T e → {
                        : Utf8Dec de ( utf8_decode ( string_data e ) 0 )
                        ? == . de cp . d cp { = hit bv = bv 256 } { = bv + bv 1 }
                    }
                    F → { = bv + bv 1 }
                }
            }
            ? >= hit 0 { ( vec_push [u] out # u hit ) } {}
            = j + j . d width
        }
    }
    ^ out
}

@ tok_decode * Tok t ( Vec i ) ids → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : ~ i k 0
    ~ < k ( vec_len [i] ids ) {
        : ( Vec u ) pb ( tok_piece t ( __tk_geti ids k -1 ) )
        ( vec_extend [u] out pb )
        ( vec_free [u] pb )
        = k + k 1
    }
    ^ out
}
