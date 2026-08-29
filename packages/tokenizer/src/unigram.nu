// packages/tokenizer/src/unigram.nu — Hugging Face Unigram tokenizer
// (tokenizer.json), the XLM-RoBERTa / BGE / sentencepiece-Unigram family.
//
// The engine in tokenizer.nu covers llama-style SentencePiece (greedy
// bigram merging) and byte-level BPE. Unigram is a THIRD model: pieces
// carry log probabilities and a sentence is segmented by Viterbi — the
// highest-total-score path over the whole string — which greedy merging
// does not reproduce. This file implements the full tokenizer.json
// pipeline for `model.type == "Unigram"`:
//
//   1. added-token extraction (specials matched literally on RAW text)
//   2. normalizer: sentencepiece "Precompiled" charsmap — a darts-clone
//      double-array trie of replacement rules (NFKC-style) — followed by
//      the Replace rule (collapse space runs), as in the file
//   3. Metaspace pre-tokenization: prepend ▁, every ' ' → ▁ (U+2581)
//   4. Unigram Viterbi over piece scores; unknown characters take
//      unk_score = min_score − 10 and consecutive unks FUSE into one
//   5. TemplateProcessing: <s> … </s> (ids read from the file)
//
//   ( uni_load path )              → !*Unigram String
//   ( uni_encode u text add_special ( Vec i ) out ) → b
//   ( uni_free u )                 → v
//   plus uni_n_vocab / uni_bos / uni_eos / uni_unk / uni_piece
//
// Verified token-for-token against Hugging Face `tokenizers` on a
// multilingual corpus (see tests/unigram_test.sh).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/utf8.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/ext/json.nu`

: Unigram {
    ( Vec String ) pieces
    ( Vec f ) scores
    ( HashMap s i ) lookup
    // fast piece lookup for the Viterbi inner loop: open-addressed,
    // power-of-2 table with the FNV-1a hash STORED per slot, probing
    // against raw text bytes — no substring copy, no re-hash, and a
    // memcmp only when the 64-bit hashes already agree. `lookup` stays
    // for the cold callers (added-token names).
    //
    // Hash and id are INTERLEAVED in one array — slot s is ft[2s] and
    // ft[2s+1] — not two parallel Vecs. At 250k pieces the table is 8 MB,
    // so every probe is a cache miss, and two arrays make it two misses
    // for what fits in one 64-byte line. ft[2s+1] holds id+1; 0 is an
    // empty slot.
    ( Vec i ) ft
    i ft_mask
    i unk_id
    f unk_score
    i max_piece  // longest piece, in bytes
    // Precompiled charsmap: darts double-array units + replacement pool
    ( Vec u ) trie
    ( Vec u ) pool
    b has_norm
    b collapse_spaces  // the Replace " {2,}" → " " rule
    b add_prefix  // Metaspace prepend ▁
    i bos
    i eos
    ( Vec String ) added  // added-token literals, longest first
    ( Vec i ) added_ids
    ( Vec i ) added_lstrip  // 1 = whitespace BEFORE the token is consumed
    ( Vec i ) added_rstrip  // 1 = whitespace AFTER the token is consumed
}

@ __uni_set ( HashMap s i ) m s key i val → v {
    : ?i _old ( map_set [s i] m key val \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
}

@ __uni_get ( HashMap s i ) m s key → ?i {
    ^ ( map_get [s i] m key \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
}

// FNV-1a 64-bit — extendable one byte at a time, which is what lets the
// Viterbi loop keep ONE rolling hash per start position instead of
// re-hashing every substring from scratch.
: i UNI_FNV_OFF -3750763034362895579
: i UNI_FNV_PRIME 1099511628211

@ __uni_fnv s ptr i len → i {
    : ~ i h UNI_FNV_OFF
    : ~ i k 0
    ~ < k len {
        = h ^^ h ( nurl_str_at ptr len k )
        = h * h UNI_FNV_PRIME
        = k + k 1
    }
    ^ h
}

@ __uni_ft_build * Unigram u → v {
    : i nv ( vec_len [String] . u pieces )
    : ~ i cap 16
    ~ < cap * nv 2 { = cap * cap 2 }
    = . u ft_mask - cap 1
    ( vec_clear [i] . u ft )
    ( vec_reserve [i] . u ft * cap 2 )
    : ~ i k 0
    ~ < k * cap 2 { ( vec_push [i] . u ft 0 ) = k + k 1 }
    = k 0
    ~ < k nv {
        ?? ( vec_get [String] . u pieces k ) {
            T pc → {
                : i h ( __uni_fnv ( string_data pc ) ( string_len pc ) )
                : ~ i sl & h . u ft_mask
                : ~ b put F
                ~ ! put {
                    ? == ( __uni_geti . u ft + * sl 2 1 0 ) 0 {
                        ( vec_set [i] . u ft * sl 2 h )
                        ( vec_set [i] . u ft + * sl 2 1 + k 1 )
                        = put T
                    } {
                        = sl & + sl 1 . u ft_mask
                    }
                }
            }
            F → {}
        }
        = k + k 1
    }
}

// id of the piece equal to text[off .. off+len), or -1 — `h` is the
// caller's rolling FNV over exactly those bytes.
@ __uni_ft_get * Unigram u i h s text i off i len → i {
    : *u ftp # *u ( vec_data [i] . u ft )
    : ~ i sl & h . u ft_mask
    : ~ i found -1
    : ~ b run T
    ~ run {
        : i base * sl 2
        : i ide ( nurl_peek ftp + base 1 )
        ? == ide 0 { = run F } {
            : ~ b hit F
            ? == ( nurl_peek ftp base ) h {
                ?? ( vec_get [String] . u pieces - ide 1 ) {
                    T pc → {
                        ? == ( string_len pc ) len {
                            ? == 0 # i ( memcmp ( string_data pc ) # s + # i text off len ) {
                                = hit T
                            } {}
                        } {}
                    }
                    F → {}
                }
            } {}
            ? hit { = found - ide 1 = run F } { = sl & + sl 1 . u ft_mask }
        }
    }
    ^ found
}

@ __uni_geti ( Vec i ) v i k i def → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ def } }
}

@ __uni_getf ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

@ __uni_err s msg → !*Unigram String {
    ^ @ !*Unigram String { F ( string_from msg ) }
}

// ── darts-clone double-array trie ────────────────────────────────────
// Each unit is a little-endian u32:
//   label(u)    = u & 0x800000FF        (leaf flag folded into the label)
//   offset(u)   = (u >> 10) << ((u & 0x200) ? 8 : 0)
//   has_leaf(u) = (u >> 8) & 1
//   value(u)    = u & 0x7FFFFFFF        (read from the leaf unit)

@ __uni_unit ( Vec u ) trie i k → i {
    : *u p ( vec_data [u] trie )
    : i o * k 4
    : i b0 # i . p o
    : i b1 # i . p + o 1
    : i b2 # i . p + o 2
    : i b3 # i . p + o 3
    ^ | | | b0 << b1 8 << b2 16 << b3 24
}

@ __uni_label i u2 → i { ^ & u2 2147483903 }  // 0x800000FF

@ __uni_offset i u2 → i {
    : i sh ? != & u2 512 0 { 8 } { 0 }
    ^ << >> u2 10 sh
}

@ __uni_has_leaf i u2 → b { ^ != & >> u2 8 1 0 }

@ __uni_value i u2 → i { ^ & u2 2147483647 }  // 0x7FFFFFFF

// Longest charsmap match for text[p..): writes the matched byte length to
// `mlen_cell`, returns the pool offset of the replacement (−1 = no match).
@ __uni_norm_prefix * Unigram u s text i p i n * u mlen_cell → i {
    ( nurl_poke mlen_cell 0 0 )
    ? . u has_norm {} { ^ -1 }
    : i nunits / ( vec_len [u] . u trie ) 4
    ? > nunits 0 {} { ^ -1 }
    : ~ i node 0
    : i u0 ( __uni_unit . u trie 0 )
    = node ^^ node ( __uni_offset u0 )
    : *u TP # *u text
    : ~ i best -1
    : ~ i k p
    : ~ b run T
    ~ & run < k n {
        : i c & 255 # i . TP k
        ? != c 0 {} { = run F }
        ? run {
            = node ^^ node c
            ? < node nunits {} { = run F }
            ? run {
                : i un ( __uni_unit . u trie node )
                ? == ( __uni_label un ) c {} { = run F }
                ? run {
                    = node ^^ node ( __uni_offset un )
                    ? ( __uni_has_leaf un ) {
                        ? < node nunits {
                            = best ( __uni_value ( __uni_unit . u trie node ) )
                            ( nurl_poke mlen_cell 0 + - k p 1 )
                        } {}
                    } {}
                } {}
            } {}
        } {}
        = k + k 1
    }
    ^ best
}

// Append the pool's NUL-terminated string at `off` to `out`.
@ __uni_pool_push * Unigram u i off String out → v {
    : i pn ( vec_len [u] . u pool )
    : *u pp ( vec_data [u] . u pool )
    : ~ i k off
    : ~ b run T
    ~ & run < k pn {
        : i b2 # i . pp k
        ? == b2 0 { = run F } { ( string_push_char out b2 ) = k + k 1 }
    }
}

// Precompiled charsmap pass: longest-match replace, unmatched UTF-8 chars
// copy through (invalid bytes copy as-is, one at a time).
@ __uni_normalize * Unigram u s text i n String out → v {
    : *u mlen ( nurl_alloc 8 )
    : *u TP # *u text
    : ~ i p 0
    ~ < p n {
        : i off ( __uni_norm_prefix u text p n mlen )
        : i ml ( nurl_peek mlen 0 )
        ? & >= off 0 > ml 0 {
            ( __uni_pool_push u off out )
            = p + p ml
        } {
            : Utf8Dec d ( utf8_decode_n text n p )
            : i w ? > . d width 0 { . d width } { 1 }
            : ~ i j 0
            ~ < j w { ( string_push_char out & 255 # i . TP + p j ) = j + j 1 }
            = p + p w
        }
    }
    ( nurl_free mlen )
}

// ── the pipeline for one added-token-free segment ────────────────────

// normalize (charsmap → collapse spaces) → Metaspace: every ' ' → ▁, then
// prepend ▁ UNLESS the result is empty or already starts with ▁ (that is
// what HF's Metaspace does — a leading space becomes the prefix itself).
@ __uni_pretoken * Unigram u s text i n → String {
    : String nrm ( string_new )
    ( __uni_normalize u text n nrm )
    : String body ( string_new )
    : s d ( string_data nrm )
    : i dn ( string_len nrm )
    : *u DP # *u d
    : ~ i p 0
    : ~ b prev_sp F
    ~ < p dn {
        : i b2 & 255 # i . DP p
        ? == b2 32 {
            // Replace " {2,}"→" " (collapse), then Metaspace ' ' → ▁
            ? & . u collapse_spaces prev_sp {} { ( string_push_str body `▁` ) }
            = prev_sp T
        } {
            ( string_push_char body b2 )
            = prev_sp F
        }
        = p + p 1
    }
    ( string_free nrm )
    : i bn ( string_len body )
    : s bd ( string_data body )
    : b starts_meta & >= bn 3 & & == ( nurl_str_get bd 0 ) 226 == ( nurl_str_get bd 1 ) 150 == ( nurl_str_get bd 2 ) 129
    ? & . u add_prefix & > bn 0 ! starts_meta {} { ^ body }
    : String out ( string_from `▁` )
    ( string_push_str out bd )
    ( string_free body )
    ^ out
}

// Unigram Viterbi over the pre-tokenized bytes. Appends ids to `out`;
// consecutive unknowns fuse into ONE unk id (HF fuse_unk).
@ __uni_viterbi * Unigram u String seg ( Vec i ) out → v {
    : s e ( string_data seg )
    : i n ( string_len seg )
    ? > n 0 {} { ^ }
    // char-boundary flags (0/1) for 0..n
    : ( Vec i ) bnd ( vec_with_cap [i] + n 1 )
    : ~ i k 0
    ~ <= k n { ( vec_push [i] bnd 0 ) = k + k 1 }
    : ~ i p 0
    ~ < p n {
        ( vec_set [i] bnd p 1 )
        : Utf8Dec d ( utf8_decode_n e n p )
        = p + p ? > . d width 0 { . d width } { 1 }
    }
    ( vec_set [i] bnd n 1 )
    // dp
    : ( Vec f ) best ( vec_with_cap [f] + n 1 )
    : ( Vec i ) bpos ( vec_with_cap [i] + n 1 )
    : ( Vec i ) bid ( vec_with_cap [i] + n 1 )
    = k 0
    ~ <= k n {
        ( vec_push [f] best -1.0e30 )
        ( vec_push [i] bpos -1 )
        ( vec_push [i] bid -1 )
        = k + k 1
    }
    ( vec_set [f] best 0 0.0 )
    = p 0
    ~ < p n {
        ? & == ( __uni_geti bnd p 1 ) 1 > ( __uni_getf best p ) -1.0e29 {
            : f base ( __uni_getf best p )
            // pieces starting at p, ending on a later char boundary —
            // one rolling FNV per start position, extended a byte per
            // step, probed against the stored-hash table (__uni_ft_get):
            // nothing is copied and no substring is ever re-hashed
            : ~ i q + p 1
            : i qmax ? < + p . u max_piece n { + p . u max_piece } { n }
            : ~ i h UNI_FNV_OFF
            ~ <= q qmax {
                = h ^^ h ( nurl_str_at e n - q 1 )
                = h * h UNI_FNV_PRIME
                ? == ( __uni_geti bnd q 1 ) 1 {
                    : i id ( __uni_ft_get u h e p - q p )
                    ? >= id 0 {
                        : f sc + base ( __uni_getf . u scores id )
                        ? > sc ( __uni_getf best q ) {
                            ( vec_set [f] best q sc )
                            ( vec_set [i] bpos q p )
                            ( vec_set [i] bid q id )
                        } {}
                    } {}
                } {}
                = q + q 1
            }
            // unknown transition: exactly one character
            : ~ i q2 + p 1
            ~ & <= q2 n != ( __uni_geti bnd q2 1 ) 1 { = q2 + q2 1 }
            ? <= q2 n {
                : f sc2 + base . u unk_score
                ? > sc2 ( __uni_getf best q2 ) {
                    ( vec_set [f] best q2 sc2 )
                    ( vec_set [i] bpos q2 p )
                    ( vec_set [i] bid q2 . u unk_id )
                } {}
            } {}
        } {}
        = p + p 1
    }
    // backtrack (collect reversed, then emit fused)
    : ( Vec i ) rev ( vec_new [i] )
    : ~ i cur n
    ~ > cur 0 {
        : i id ( __uni_geti bid cur -1 )
        : i pr ( __uni_geti bpos cur -1 )
        ? >= id 0 {} { = cur 0 }
        ? >= id 0 {
            ( vec_push [i] rev id )
            = cur pr
        } {}
    }
    : ~ i j ( vec_len [i] rev )
    : ~ i prev -1
    ~ > j 0 {
        : i id2 ( __uni_geti rev - j 1 -1 )
        ? & == id2 . u unk_id == prev . u unk_id {} { ( vec_push [i] out id2 ) }
        = prev id2
        = j - j 1
    }
    ( vec_free [i] bnd )
    ( vec_free [f] best )
    ( vec_free [i] bpos )
    ( vec_free [i] bid )
    ( vec_free [i] rev )
}

// ── loading ──────────────────────────────────────────────────────────

@ __uni_load_vocab Json model * Unigram u → b {
    ?? ( json_obj_get model `vocab` ) {
        T vocab → {
            : i nv ( json_arr_len vocab )
            : ~ i k 0
            : ~ f minsc 0.0
            ~ < k nv {
                ?? ( json_arr_get vocab k ) {
                    T ent → {
                        : ?Json pj ( json_arr_get ent 0 )
                        : ?Json sj ( json_arr_get ent 1 )
                        : String pc ?? pj { T x → ( string_from ( json_str_data x ) ) F → ( string_new ) }
                        : f sc ?? sj { T x → ?? ( json_num_as_f x ) { T v → v F → 0.0 } F → 0.0 }
                        ( vec_push [String] . u pieces pc )
                        ( vec_push [f] . u scores sc )
                        ? < sc minsc { = minsc sc } {}
                        : i blen ( string_len pc )
                        ? > blen . u max_piece { = . u max_piece blen } {}
                    }
                    F → {}
                }
                = k + k 1
            }
            = . u unk_score - minsc 10.0
            // lookup: piece → id (keys BORROW the piece strings)
            = k 0
            ~ < k nv {
                ?? ( vec_get [String] . u pieces k ) {
                    T pc → { ( __uni_set . u lookup ( string_data pc ) k ) }
                    F → {}
                }
                = k + k 1
            }
            ^ > nv 0
        }
        F → { ^ F }
    }
}

@ __uni_load_charsmap Json norm * Unigram u → v {
    : s ty ?? ( json_obj_get norm `type` ) { T t → ( json_str_data t ) F → `` }
    ? == 1 ( nurl_str_eq ty `Precompiled` ) {
        ?? ( json_obj_get norm `precompiled_charsmap` ) {
            T cm → {
                ?? ( b64_decode_vec ( json_str_data cm ) ) {
                    T blob → {
                        : i bn ( vec_len [u] blob )
                        ? >= bn 4 {
                            : *u bp ( vec_data [u] blob )
                            : i tsz | | | # i . bp 0 << # i . bp 1 8 << # i . bp 2 16 << # i . bp 3 24
                            ? <= + 4 tsz bn {
                                : ~ i k 4
                                ~ < k + 4 tsz { ( vec_push [u] . u trie # i . bp k ) = k + k 1 }
                                = k + 4 tsz
                                ~ < k bn { ( vec_push [u] . u pool # i . bp k ) = k + k 1 }
                                = . u has_norm T
                            } {}
                        } {}
                        ( vec_free [u] blob )
                    }
                    F _e → {}
                }
            }
            F → {}
        }
    } {}
    ? == 1 ( nurl_str_eq ty `Replace` ) { = . u collapse_spaces T } {}
    ? == 1 ( nurl_str_eq ty `Sequence` ) {
        ?? ( json_obj_get norm `normalizers` ) {
            T seq → {
                : i sn ( json_arr_len seq )
                : ~ i k 0
                ~ < k sn {
                    ?? ( json_arr_get seq k ) { T sub → { ( __uni_load_charsmap sub u ) } F → {} }
                    = k + k 1
                }
            }
            F → {}
        }
    } {}
}

// The template's <s>/</s> ids: first SpecialToken before the Sequence entry
// and first after it, resolved through the vocab lookup.
@ __uni_load_template Json root * Unigram u → v {
    ?? ( json_get root `post_processor.single` ) {
        T single → {
            : i sn ( json_arr_len single )
            : ~ b seen_seq F
            : ~ i k 0
            ~ < k sn {
                ?? ( json_arr_get single k ) {
                    T ent → {
                        ? ( json_obj_has ent `Sequence` ) { = seen_seq T } {}
                        ?? ( json_obj_get ent `SpecialToken` ) {
                            T st → {
                                : s nm ?? ( json_obj_get st `id` ) { T x → ( json_str_data x ) F → `` }
                                ?? ( __uni_get . u lookup nm ) {
                                    T id → {
                                        ? seen_seq { ? < . u eos 0 { = . u eos id } {} } { ? < . u bos 0 { = . u bos id } {} }
                                    }
                                    F → {}
                                }
                            }
                            F → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }
}

// Added tokens, kept longest-first so overlapping literals match greedily.
@ __uni_load_added Json root * Unigram u → v {
    ?? ( json_obj_get root `added_tokens` ) {
        T arr → {
            : i an ( json_arr_len arr )
            : ~ i k 0
            ~ < k an {
                ?? ( json_arr_get arr k ) {
                    T ent → {
                        : s content ?? ( json_obj_get ent `content` ) { T x → ( json_str_data x ) F → `` }
                        : i id ?? ( json_obj_get ent `id` ) { T x → ?? ( json_num_as_i x ) { T v → v F → -1 } F → -1 }
                        ? & >= id 0 > ( nurl_str_len content ) 0 {
                            : i ls ?? ( json_obj_get ent `lstrip` ) { T x → ? ( json_as_bool x ) { 1 } { 0 } F → 0 }
                            : i rs ?? ( json_obj_get ent `rstrip` ) { T x → ? ( json_as_bool x ) { 1 } { 0 } F → 0 }
                            // insertion sort by length, longest first
                            : i cl ( nurl_str_len content )
                            : ~ i pos 0
                            : i cnt ( vec_len [String] . u added )
                            ~ < pos cnt {
                                : i ol ?? ( vec_get [String] . u added pos ) { T x → ( string_len x ) F → 0 }
                                ? >= ol cl { = pos + pos 1 } { = pos cnt }
                            }
                            ( vec_insert [String] . u added pos ( string_from content ) )
                            ( vec_insert [i] . u added_ids pos id )
                            ( vec_insert [i] . u added_lstrip pos ls )
                            ( vec_insert [i] . u added_rstrip pos rs )
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }
}

@ uni_load s path → !*Unigram String {
    ?? ( read_file path ) {
        T txt → {
            : ~ ? * Unigram result @ ?*Unigram { F }
            : ~ String errmsg ( string_new )
            ?? ( json_parse ( string_data txt ) ) {
                T root → {
                    : s mtype ?? ( json_get root `model.type` ) { T t → ( json_str_data t ) F → `` }
                    ? == 1 ( nurl_str_eq mtype `Unigram` ) {
                        : *Unigram u # *Unigram ( nurl_alloc Z Unigram )
                        = . u pieces ( vec_new [String] )
                        = . u scores ( vec_new [f] )
                        = . u lookup ( map_new [s i] )
                        = . u ft ( vec_new [i] )
                        = . u ft_mask 0
                        = . u trie ( vec_new [u] )
                        = . u pool ( vec_new [u] )
                        = . u added ( vec_new [String] )
                        = . u added_ids ( vec_new [i] )
                        = . u added_lstrip ( vec_new [i] )
                        = . u added_rstrip ( vec_new [i] )
                        = . u has_norm F
                        = . u collapse_spaces F
                        = . u add_prefix T
                        = . u max_piece 1
                        = . u bos -1
                        = . u eos -1
                        = . u unk_id ?? ( json_get root `model.unk_id` ) { T x → ?? ( json_num_as_i x ) { T v → v F → 0 } F → 0 }
                        : ?Json model ( json_obj_get root `model` )
                        : ~ b okv F
                        ?? model { T m → { = okv ( __uni_load_vocab m u ) } F → {} }
                        ? okv {
                            ( __uni_ft_build u )
                            ?? ( json_obj_get root `normalizer` ) { T nrm → { ( __uni_load_charsmap nrm u ) } F → {} }
                            : b apfx ?? ( json_get root `pre_tokenizer.add_prefix_space` ) { T x → ( json_as_bool x ) F → T }
                            = . u add_prefix apfx
                            ( __uni_load_template root u )
                            ( __uni_load_added root u )
                            = result @ ?*Unigram { T u }
                        } {
                            ( uni_free u )
                            ( string_push_str errmsg `unigram: empty or missing model.vocab` )
                        }
                    } {
                        ( string_push_str errmsg `unigram: model.type is not Unigram` )
                    }
                    ( json_free root )
                }
                F je → {
                    ( string_push_str errmsg `unigram: tokenizer.json parse error` )
                }
            }
            ( string_free txt )
            ?? result {
                T u2 → { ( string_free errmsg ) ^ @ !*Unigram String { T u2 } }
                F → { ^ @ !*Unigram String { F errmsg } }
            }
        }
        F _e → { ^ ( __uni_err `unigram: cannot read tokenizer.json` ) }
    }
}

@ uni_free * Unigram u → v {
    : ~ i k 0
    : i np ( vec_len [String] . u pieces )
    ~ < k np {
        ?? ( vec_get [String] . u pieces k ) { T p → { ( string_free p ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] . u pieces )
    ( vec_free [f] . u scores )
    ( map_free [s i] . u lookup )
    ( vec_free [i] . u ft )
    ( vec_free [u] . u trie )
    ( vec_free [u] . u pool )
    = k 0
    : i na ( vec_len [String] . u added )
    ~ < k na {
        ?? ( vec_get [String] . u added k ) { T p → { ( string_free p ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] . u added )
    ( vec_free [i] . u added_ids )
    ( vec_free [i] . u added_lstrip )
    ( vec_free [i] . u added_rstrip )
    ( nurl_free # *u u )
}

@ uni_n_vocab * Unigram u → i { ^ ( vec_len [String] . u pieces ) }

@ uni_bos * Unigram u → i { ^ . u bos }

@ uni_eos * Unigram u → i { ^ . u eos }

@ uni_unk * Unigram u → i { ^ . u unk_id }

// Borrowed piece text ("" out of range).
@ uni_piece * Unigram u i id → s {
    ?? ( vec_get [String] . u pieces id ) { T p → { ^ ( string_data p ) } F → { ^ `` } }
}

@ __uni_is_ws i b2 → b {
    ^ | | | == b2 32 == b2 9 == b2 10 == b2 13
}

// Does an added token match text[p..)? Returns its index or −1.
@ __uni_added_at * Unigram u s text i p i n → i {
    : i na ( vec_len [String] . u added )
    : ~ i k 0
    ~ < k na {
        ?? ( vec_get [String] . u added k ) {
            T lit → {
                : i ll ( string_len lit )
                ? <= + p ll n {
                    ? == 0 ( nurl_memcmp_lex # s + # i text p ll ( string_data lit ) ll ) { ^ k } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ -1
}

// One raw segment (no added tokens inside) through the full pipeline.
@ __uni_segment * Unigram u s text i off i len ( Vec i ) out → v {
    ? > len 0 {} { ^ }
    : String raw ( string_new )
    ( string_push_bytes raw # *u + # i text off len )
    : String pre ( __uni_pretoken u ( string_data raw ) ( string_len raw ) )
    ( __uni_viterbi u pre out )
    ( string_free raw )
    ( string_free pre )
}

// Encode `text`. add_special wraps the result in the file's template
// (<s> … </s>). Returns F only when the tokenizer is unusable.
@ uni_encode * Unigram u s text b add_special ( Vec i ) out → b {
    ? > ( uni_n_vocab u ) 0 {} { ^ F }
    ? & add_special >= . u bos 0 { ( vec_push [i] out . u bos ) } {}
    : i n ( nurl_str_len text )
    : ~ i seg 0
    : ~ i p 0
    ~ < p n {
        : i ai ( __uni_added_at u text p n )
        ? >= ai 0 {
            // lstrip: whitespace before the token belongs to it
            : ~ i segend p
            ? == ( __uni_geti . u added_lstrip ai 0 ) 1 {
                ~ & > segend seg ( __uni_is_ws ( nurl_str_at text n - segend 1 ) ) { = segend - segend 1 }
            } {}
            ( __uni_segment u text seg - segend seg out )
            ( vec_push [i] out ( __uni_geti . u added_ids ai -1 ) )
            : i al ?? ( vec_get [String] . u added ai ) { T x → ( string_len x ) F → 1 }
            = p + p al
            ? == ( __uni_geti . u added_rstrip ai 0 ) 1 {
                ~ & < p n ( __uni_is_ws ( nurl_str_at text n p ) ) { = p + p 1 }
            } {}
            = seg p
        } {
            = p + p 1
        }
    }
    ( __uni_segment u text seg - n seg out )
    ? & add_special >= . u eos 0 { ( vec_push [i] out . u eos ) } {}
    ^ T
}
