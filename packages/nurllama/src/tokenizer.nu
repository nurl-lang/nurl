// packages/nurllama/src/tokenizer.nu — LLM tokenizer from a GGUF vocabulary.
//
// Everything comes out of the model file itself (tokenizer.ggml.* metadata
// read through packages/gguf) — no external vocab files, no exporter step:
//
//   ( tok_new g )                     → !*Tok String    from an open *Gguf
//   ( tok_free t )
//   ( tok_encode t text add_special ) → ( Vec i )       token ids
//   ( tok_piece t id )                → ( Vec u )       one token's raw bytes
//   ( tok_decode t ids )              → ( Vec u )       ids → bytes (skips
//                                                        control tokens)
//   ( tok_n_vocab t ) ( tok_bos t ) ( tok_eos t ) ( tok_unk t )
//
// Two tokenizer families, selected by `tokenizer.ggml.model`:
//
//   SPM ("llama") — SentencePiece-style bigram merging: split the
//   space-escaped text (` ` → ▁ U+2581, optional leading space) into
//   UTF-8 characters, then repeatedly merge the adjacent pair whose
//   concatenation is a vocab piece with the HIGHEST score (ties →
//   leftmost), exactly llama.cpp's llm_tokenizer_spm selection order.
//   Characters that never reach a vocab piece fall back to the <0xXX>
//   BYTE tokens, then to UNK.
//
//   BPE ("gpt2") — byte-level BPE: GPT-2's byte→unicode remap, greedy
//   regex-style pre-split (contractions / letters / digits / punct /
//   whitespace), then lowest-merge-rank pairing driven by
//   tokenizer.ggml.merges. NOTE v1: the pre-split implements the GPT-2
//   pattern with \p{L} approximated as "ASCII letters + any cp ≥ 0x80"
//   — per-model `tokenizer.ggml.pre` variants (qwen2 digit splitting
//   etc.) are a follow-up.
//
// The Tok owns copies of every piece (the source Gguf can be closed
// after tok_new). The piece→id map borrows the buffers of `pieces` —
// stable because Vec growth moves the String structs, never the heap
// buffers they point to.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/utf8.nu`
$ `deps/gguf/src/gguf.nu`

// token_type values (tokenizer.ggml.token_type, llama.cpp llama_token_type)
: i TT_NORMAL 1
: i TT_UNKNOWN 2
: i TT_CONTROL 3
: i TT_USER 4
: i TT_UNUSED 5
: i TT_BYTE 6

: i TOK_SPM 0
: i TOK_BPE 1

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
    i bos
    i eos
    i unk
    b add_bos
    b add_eos
    b add_space_prefix
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
@ tok_new * Gguf g → !*Tok String {
    : s model ( gguf_kv_str_or g `tokenizer.ggml.model` `` )
    : ~ i mode -1
    ? ( nurl_str_eq model `llama` ) { = mode TOK_SPM } {}
    ? ( nurl_str_eq model `gpt2` ) { = mode TOK_BPE } {}
    ? < mode 0 {
        : String m ( string_from `tokenizer: unsupported tokenizer.ggml.model '` )
        ( string_push_str m model )
        ( string_push_str m `' (supported: llama, gpt2)` )
        ^ @ !*Tok String { F m }
    } {}

    : i tki ( gguf_find_kv g `tokenizer.ggml.tokens` )
    ? < tki 0 { ^ ( __tk_err `tokenizer: model has no tokenizer.ggml.tokens vocabulary` ) } {}

    : *Tok t # *Tok ( nurl_alloc Z Tok )
    = . t mode mode
    = . t pieces ( vec_new [String] )
    = . t scores ( vec_new [f] )
    = . t ttype ( vec_new [i] )
    = . t lookup ( map_new [s i] )
    = . t ranks ( map_new [s i] )
    = . t rankkeys ( vec_new [String] )
    = . t byte_enc ? == mode TOK_BPE ( __tk_build_byte_enc ) ( vec_new [String] )
    = . t byte_id ( vec_new [i] )
    = . t bos ( gguf_kv_int_or g `tokenizer.ggml.bos_token_id` -1 )
    = . t eos ( gguf_kv_int_or g `tokenizer.ggml.eos_token_id` -1 )
    = . t unk ( gguf_kv_int_or g `tokenizer.ggml.unknown_token_id` -1 )
    = . t add_bos ? != 0 ( gguf_kv_int_or g `tokenizer.ggml.add_bos_token` ? == mode TOK_SPM 1 0 ) T F
    = . t add_eos ? != 0 ( gguf_kv_int_or g `tokenizer.ggml.add_eos_token` 0 ) T F
    = . t add_space_prefix ? != 0 ( gguf_kv_int_or g `tokenizer.ggml.add_space_prefix` ? == mode TOK_SPM 1 0 ) T F

    // vocabulary: copy pieces + scores + types out of the kv arrays
    ?? ( vec_get [GgufKv] . g kvs tki ) {
        T a → {
            : i n ( vec_len [String] . a astr )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] . a astr k ) {
                    T p → { ( vec_push [String] . t pieces ( string_clone p ) ) }
                    F → { ( vec_push [String] . t pieces ( string_new ) ) }
                }
                = k + k 1
            }
        }
        F → {}
    }
    : i nvocab ( vec_len [String] . t pieces )
    ? == nvocab 0 {
        ( tok_free t )
        ^ ( __tk_err `tokenizer: empty vocabulary` )
    } {}

    : i sci ( gguf_find_kv g `tokenizer.ggml.scores` )
    ? >= sci 0 {
        ?? ( vec_get [GgufKv] . g kvs sci ) {
            T a → {
                : ~ i k 0
                ~ < k nvocab {
                    ( vec_push [f] . t scores ( __tk_getf . a af k ) )
                    = k + k 1
                }
            }
            F → {}
        }
    } {}
    : i tyi ( gguf_find_kv g `tokenizer.ggml.token_type` )
    ? >= tyi 0 {
        ?? ( vec_get [GgufKv] . g kvs tyi ) {
            T a → {
                : ~ i k 0
                ~ < k nvocab {
                    ( vec_push [i] . t ttype ( __tk_geti . a ai k TT_NORMAL ) )
                    = k + k 1
                }
            }
            F → {}
        }
    } {}

    // piece → id (last one wins on a duplicate piece, like llama.cpp's
    // token_to_id map). Keys borrow the pieces' heap buffers.
    : ~ i k 0
    ~ < k nvocab {
        ( __tk_set . t lookup ( __tk_piece_data t k ) k )
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

    // BPE merge ranks: "A B" (as stored in the merges array) → rank
    ? == mode TOK_BPE {
        : i mgi ( gguf_find_kv g `tokenizer.ggml.merges` )
        ? < mgi 0 {
            ( tok_free t )
            ^ ( __tk_err `tokenizer: gpt2 model has no tokenizer.ggml.merges` )
        } {}
        ?? ( vec_get [GgufKv] . g kvs mgi ) {
            T a → {
                : i nm ( vec_len [String] . a astr )
                : ~ i r 0
                ~ < r nm {
                    ?? ( vec_get [String] . a astr r ) {
                        T mstr → {
                            ( vec_push [String] . t rankkeys ( string_clone mstr ) )
                            ?? ( vec_get [String] . t rankkeys r ) {
                                T own → { ( __tk_set . t ranks ( string_data own ) r ) }
                                F → {}
                            }
                        }
                        F → {}
                    }
                    = r + r 1
                }
            }
            F → {}
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
        // whitespace run (only reachable with lead == 0)
        : ~ i r q
        ~ & < r n ( __tk_is_ws ( nurl_str_get text r ) ) { = r + r 1 }
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
        : i len ( __tk_pretoken_len text p n )
        ( __tk_bpe_word t text p ? < len 1 1 len out )
        = p + p ? < len 1 1 len
    }
}

// ── public encode / decode ──────────────────────────────────────────

@ tok_encode * Tok t s text b add_special → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    ? & & add_special . t add_bos >= . t bos 0 { ( vec_push [i] out . t bos ) } {}
    ? == . t mode TOK_SPM { ( __tk_spm_encode t text out ) } { ( __tk_bpe_encode t text out ) }
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
