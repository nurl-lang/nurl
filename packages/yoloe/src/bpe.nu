// packages/yoloe/src/bpe.nu — the CLIP byte-pair-encoding tokenizer in pure
// NURL. This is the word → token-id half of the MobileCLIP text path; the
// other half (token-ids → 512-d features) is the text-encoder ONNX graph
// already run by the onnx runtime (see tests/text_fwd.nu).
//
// Faithful port of open_clip's SimpleTokenizer (the tokenizer MobileCLIP's
// ClipTokenizer wraps as get_tokenizer("ViT-B-16")):
//
//   * bytes_to_unicode() byte→symbol table (reversible byte-level coding),
//   * a 49408-entry encoder: 256 base symbols + 256 word-end (</w>) variants
//     + 48894 merge tokens + <start_of_text>/<end_of_text>,
//   * bpe_ranks from assets/clip_merges.txt (the decompressed
//     bpe_simple_vocab_16e6.txt, lines 1..48894),
//   * the BPE merge loop (lowest-rank bigram first, merge all occurrences),
//   * [sot] + ids + [eot] padded/truncated to the context length (77).
//
// Word splitting reproduces CLIP's regex
//   'r"'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"
// for the common case (ASCII / Latin-1 letters, digits, punctuation,
// English contractions). A letter is a-z / Latin-1 letters / any codepoint
// >= U+0100; a digit is 0-9. Exotic symbol-vs-letter classification of rare
// BMP punctuation may differ from full Unicode \p{L}/\p{N}, which does not
// arise for object-detection class names.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/utf8.nu`
$ `stdlib/std/hashmap.nu`

: i BPE_INF 1000000000

// A loaded tokenizer. The hash maps key on `s` (raw char*) pointers, so the
// backing strings must outlive the maps: `arena` owns every key string that
// is not already owned by `byte_enc`.
: Tokenizer {
    ( Vec String ) byte_enc      // byte value 0..255 → its symbol string
    ( HashMap s i ) enc          // token string → id
    ( HashMap s i ) ranks        // "a b" merge line → rank
    ( Vec String ) arena         // owns enc/ranks key strings
    i sot
    i eot
}

// ── small Vec<i> helpers ─────────────────────────────────────────
@ __ig ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 } }
@ __is ( Vec i ) v i k i val → v { ( vec_set [i] v k val ) }

// ── string→int hash map helpers (wrap the closure-coercion dance) ──
@ __msi_set ( HashMap s i ) m s key i val → v {
    ( map_set [s i] m key val \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
}
@ __msi_get ( HashMap s i ) m s key → ?i {
    ^ ( map_get [s i] m key \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
}

// ── classification (cleaned, lowercased text) ────────────────────
@ __is_space i cp → b {
    ^ | | | == cp 32 == cp 9 == cp 10 == cp 13
}
@ __is_digit i cp → b { ^ & >= cp 48 <= cp 57 }
@ __is_letter i cp → b {
    ? & >= cp 97 <= cp 122 { ^ T } {}            // a-z
    ? & >= cp 65 <= cp 90 { ^ T } {}             // A-Z (text is lowercased, kept for safety)
    ? >= cp 256 { ^ T } {}                        // any non-Latin-1 codepoint: treat as letter
    ? & >= cp 192 <= cp 255 {                     // Latin-1 letters minus ×(215) ÷(247)
        ? == cp 215 { ^ F } {}
        ? == cp 247 { ^ F } {}
        ^ T
    } {}
    ^ F
}

// ── bytes_to_unicode (byte_enc[b] + the base-vocab insertion order) ──
// Fills byte2cp[b] = codepoint for byte b, and appends the byte values in
// dict-insertion order (33..126, 161..172, 174..255, then the leftovers in
// ascending order) to `order` — that order assigns the base vocab ids.
@ __mark_self ( Vec i ) byte2cp ( Vec i ) order i lo i hi → v {
    : ~ i b lo
    ~ <= b hi {
        ( __is byte2cp b b )
        ( vec_push [i] order b )
        = b + b 1
    }
}
@ __build_byte_enc ( Vec i ) order → ( Vec String ) {
    : ( Vec i ) byte2cp ( vec_new [i] )
    : ~ i i 0
    ~ < i 256 { ( vec_push [i] byte2cp -1 ) = i + i 1 }
    ( __mark_self byte2cp order 33 126 )
    ( __mark_self byte2cp order 161 172 )
    ( __mark_self byte2cp order 174 255 )
    // leftover bytes → codepoint 256+n, appended after the kept ranges
    : ~ i n 0
    : ~ i b 0
    ~ < b 256 {
        ? < ( __ig byte2cp b ) 0 {
            ( __is byte2cp b + 256 n )
            ( vec_push [i] order b )
            = n + n 1
        } {}
        = b + b 1
    }
    // byte_enc[b] = utf8(byte2cp[b]) — indexed by byte value
    : ( Vec String ) out ( vec_new [String] )
    : ~ i k 0
    ~ < k 256 {
        ( vec_push [String] out ( utf8_encode_cp ( __ig byte2cp k ) ) )
        = k + k 1
    }
    ( vec_free [i] byte2cp )
    ^ out
}

// First space index in `line`, or -1.
@ __first_space s line → i {
    : i n ( nurl_str_len line )
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get line k ) 32 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Register a key→id mapping, taking ownership of `key` in the arena.
@ __enc_put Tokenizer tk String key i id → v {
    ( vec_push [String] . tk arena key )
    ( __msi_set . tk enc ( string_data key ) id )
}

// ── load ─────────────────────────────────────────────────────────
// Build the tokenizer from the merges asset. Returns a Tokenizer whose maps
// are empty (sot=-1) on read failure.
@ tokenizer_load s merges_path → Tokenizer {
    : ( Vec i ) order ( vec_new [i] )
    : ( Vec String ) byte_enc ( __build_byte_enc order )
    : Tokenizer tk @ Tokenizer {
        byte_enc
        ( map_new [s i] )
        ( map_new [s i] )
        ( vec_new [String] )
        -1
        -1
    }
    // base vocab: order[j] → id j, plus </w> variant → id 256+j
    : ~ i j 0
    ~ < j 256 {
        : i b ( __ig order j )
        : String sym ?? ( vec_get [String] byte_enc b ) { T s → s F _ → ( string_new ) }
        // base symbol (id j): key = a fresh copy so the arena owns it
        : String k0 ( string_from ( string_data sym ) )
        ( __enc_put tk k0 j )
        // </w> variant (id 256+j)
        : String k1 ( string_from ( string_data sym ) )
        ( string_push_str k1 `</w>` )
        ( __enc_put tk k1 + 256 j )
        = j + j 1
    }
    ( vec_free [i] order )
    // merges: line r → rank r, vocab token (a+b) → id 512+r
    ?? ( read_file_bytes merges_path ) {
        T buf → {
            : i n ( vec_len [u] buf )
            : ~ ( Vec u ) cur ( vec_new [u] )
            : ~ i rank 0
            : ~ i p 0
            ~ < p n {
                : i ch ?? ( vec_get [u] buf p ) { T x → # i x F _ → 0 }
                ? == ch 10 {
                    ( __load_merge_line tk cur rank )
                    = rank + rank 1
                    = cur ( vec_new [u] )
                } {
                    ? != ch 13 { ( vec_push [u] cur # u ch ) } {}
                }
                = p + p 1
            }
            ? > ( vec_len [u] cur ) 0 { ( __load_merge_line tk cur rank ) } { ( vec_free [u] cur ) }
        }
        F _ → { ^ tk }
    }
    // specials
    : String s_sot ( string_from `<start_of_text>` )
    ( __enc_put tk s_sot 49406 )
    : String s_eot ( string_from `<end_of_text>` )
    ( __enc_put tk s_eot 49407 )
    = . tk sot 49406
    = . tk eot 49407
    ^ tk
}

// Consume one merge line (held as raw bytes in `cur`): record rank + vocab id.
@ __load_merge_line Tokenizer tk ( Vec u ) cur i rank → v {
    : String line ( string_new )
    : i m ( vec_len [u] cur )
    : ~ i q 0
    ~ < q m {
        : i ch ?? ( vec_get [u] cur q ) { T x → # i x F _ → 0 }
        ( string_push_char line ch )
        = q + q 1
    }
    ( vec_free [u] cur )
    : i sp ( __first_space ( string_data line ) )
    ? < sp 0 { ( string_free line ) ^ } {}
    // rank: key = the whole "a b" line (arena-owned)
    ( vec_push [String] . tk arena line )
    ( __msi_set . tk ranks ( string_data line ) rank )
    // vocab token = a + b (space removed)
    : String tokv ( string_substr line 0 sp )
    : String bpart ( string_substr line + sp 1 - ( string_len line ) + sp 1 )
    ( string_push_str tokv ( string_data bpart ) )
    ( string_free bpart )
    ( __enc_put tk tokv + 512 rank )
}

// ── bpe ──────────────────────────────────────────────────────────
// `token` is a byte-encoded string. Returns its subword pieces (Vec String).
@ __bpe Tokenizer tk s token → ( Vec String ) {
    // split into codepoint symbols; last symbol gets the </w> word-end marker
    : ( Vec i ) cps ( utf8_codepoints token )
    : i nc ( vec_len [i] cps )
    : ~ ( Vec String ) word ( vec_new [String] )
    : ~ i i 0
    ~ < i nc {
        : String sym ( utf8_encode_cp ( __ig cps i ) )
        ? == i - nc 1 { ( string_push_str sym `</w>` ) } {}
        ( vec_push [String] word sym )
        = i + i 1
    }
    ( vec_free [i] cps )
    ? <= nc 1 { ^ word } {}

    ~ T {
        : i len ( vec_len [String] word )
        ? <= len 1 { ^ word } {}
        // lowest-rank adjacent bigram
        : ~ i best BPE_INF
        : ~ i besti -1
        : ~ i k 0
        ~ < k - len 1 {
            : i r ( __pair_rank tk word k )
            ? < r best { = best r = besti k } {}
            = k + k 1
        }
        ? < besti 0 { ^ word } {}
        ? == best BPE_INF { ^ word } {}
        // merge every occurrence of the chosen (first,second) bigram
        : s first ?? ( vec_get [String] word besti ) { T s → ( string_data s ) F _ → `` }
        : s second ?? ( vec_get [String] word + besti 1 ) { T s → ( string_data s ) F _ → `` }
        : ( Vec String ) nw ( vec_new [String] )
        : ~ i p 0
        ~ < p len {
            : s wp ?? ( vec_get [String] word p ) { T s → ( string_data s ) F _ → `` }
            ? & < p - len 1 & ( __seq wp first ) ( __seq ?? ( vec_get [String] word + p 1 ) { T s → ( string_data s ) F _ → `` } second ) {
                : String merged ( string_from first )
                ( string_push_str merged second )
                ( vec_push [String] nw merged )
                = p + p 2
            } {
                ( vec_push [String] nw ( string_from wp ) )
                = p + p 1
            }
        }
        ( __free_strvec word )
        = word nw
    }
    ^ word
}

@ __seq s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

// Rank of the bigram (word[k], word[k+1]); BPE_INF if not a known merge.
@ __pair_rank Tokenizer tk ( Vec String ) word i k → i {
    : s a ?? ( vec_get [String] word k ) { T s → ( string_data s ) F _ → `` }
    : s b ?? ( vec_get [String] word + k 1 ) { T s → ( string_data s ) F _ → `` }
    : String key ( string_from a )
    ( string_push_char key 32 )
    ( string_push_str key b )
    : ~ i r BPE_INF
    ?? ( __msi_get . tk ranks ( string_data key ) ) {
        T v → = r v
        F _ → {}
    }
    ( string_free key )
    ^ r
}

@ __free_strvec ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] v k ) { T s → ( string_free s ) F _ → {} }
        = k + k 1
    }
    ( vec_free [String] v )
}

// Byte substring of a raw char* (string_substr only takes a managed String).
@ __sub s text i from i len → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k len { ( string_push_char out ( nurl_str_get text + from k ) ) = k + k 1 }
    ^ out
}

// ── word splitting (CLIP regex) ──────────────────────────────────
// Returns the regex tokens of `text` as byte substrings.
@ __split_words s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len text )
    : ~ i pos 0
    ~ < pos n {
        : Utf8Dec d ( utf8_decode text pos )
        : i cp . d cp
        : i w . d width
        ? <= w 0 { = pos + pos 1 } {
            ? ( __is_space cp ) { = pos + pos w } {
                ? == cp 39 {
                    // apostrophe: try an English contraction, else punctuation
                    : i clen ( __contraction text pos )
                    ? > clen 0 {
                        ( vec_push [String] out ( __sub text pos clen ) )
                        = pos + pos clen
                    } {
                        : i e ( __run_punct text pos )
                        ( vec_push [String] out ( __sub text pos - e pos ) )
                        = pos e
                    }
                } {
                    ? ( __is_letter cp ) {
                        : i e ( __run_letters text pos )
                        ( vec_push [String] out ( __sub text pos - e pos ) )
                        = pos e
                    } {
                        ? ( __is_digit cp ) {
                            ( vec_push [String] out ( __sub text pos w ) )
                            = pos + pos w
                        } {
                            : i e ( __run_punct text pos )
                            ( vec_push [String] out ( __sub text pos - e pos ) )
                            = pos e
                        }
                    }
                }
            }
        }
    }
    ^ out
}

// End offset of a maximal run of letters starting at `pos`.
@ __run_letters s text i pos → i {
    : i n ( nurl_str_len text )
    : ~ i p pos
    ~ < p n {
        : Utf8Dec d ( utf8_decode text p )
        ? <= . d width 0 { ^ p } {}
        ? ! ( __is_letter . d cp ) { ^ p } {}
        = p + p . d width
    }
    ^ p
}

// End offset of a maximal run of non-space, non-letter, non-digit codepoints.
@ __run_punct s text i pos → i {
    : i n ( nurl_str_len text )
    : ~ i p pos
    ~ < p n {
        : Utf8Dec d ( utf8_decode text p )
        ? <= . d width 0 { ^ p } {}
        : i cp . d cp
        ? | | ( __is_space cp ) ( __is_letter cp ) ( __is_digit cp ) { ^ p } {}
        = p + p . d width
    }
    ^ p
}

// Length (bytes) of an English contraction at `pos` ('s 't 're 've 'm 'll 'd),
// or 0. `pos` is at the apostrophe.
@ __contraction s text i pos → i {
    : i n ( nurl_str_len text )
    : i c1 ? < + pos 1 n ( nurl_str_get text + pos 1 ) -1
    : i c2 ? < + pos 2 n ( nurl_str_get text + pos 2 ) -1
    // two-letter: 're 've 'll
    ? & == c1 114 == c2 101 { ^ 3 } {}   // 're
    ? & == c1 118 == c2 101 { ^ 3 } {}   // 've
    ? & == c1 108 == c2 108 { ^ 3 } {}   // 'll
    // one-letter: 's 't 'm 'd
    ? == c1 115 { ^ 2 } {}   // 's
    ? == c1 116 { ^ 2 } {}   // 't
    ? == c1 109 { ^ 2 } {}   // 'm
    ? == c1 100 { ^ 2 } {}   // 'd
    ^ 0
}

// ── clean (basic_clean + whitespace_clean + lower, ASCII) ─────────
@ __clean s text → String {
    : String out ( string_new )
    : i n ( nurl_str_len text )
    : ~ i pos 0
    : ~ i pending 0   // a deferred single space between runs
    : ~ i started 0
    ~ < pos n {
        : Utf8Dec d ( utf8_decode text pos )
        : i cp . d cp
        : i w ? > . d width 0 . d width 1
        ? ( __is_space cp ) {
            ? == started 1 { = pending 1 } {}
            = pos + pos w
        } {
            ? == pending 1 { ( string_push_char out 32 ) = pending 0 } {}
            = started 1
            // ASCII upper → lower
            : i lc ? & >= cp 65 <= cp 90 + cp 32 cp
            ( utf8_push_cp out lc )
            = pos + pos w
        }
    }
    ^ out
}

// ── encode / tokenize ────────────────────────────────────────────
// text → list of token ids (no sot/eot, no padding).
@ bpe_encode Tokenizer tk s text → ( Vec i ) {
    : ( Vec i ) ids ( vec_new [i] )
    : String cleaned ( __clean text )
    : ( Vec String ) words ( __split_words ( string_data cleaned ) )
    : i nw ( vec_len [String] words )
    : ~ i wi 0
    ~ < wi nw {
        : s w ?? ( vec_get [String] words wi ) { T s → ( string_data s ) F _ → `` }
        // byte-encode: map each UTF-8 byte through byte_enc
        : String benc ( string_new )
        : i bl ( nurl_str_len w )
        : ~ i bp 0
        ~ < bp bl {
            : i bb ( nurl_str_get w bp )
            ?? ( vec_get [String] . tk byte_enc bb ) { T s → ( string_push_str benc ( string_data s ) ) F _ → {} }
            = bp + bp 1
        }
        : ( Vec String ) pieces ( __bpe tk ( string_data benc ) )
        : i np ( vec_len [String] pieces )
        : ~ i pi 0
        ~ < pi np {
            : s piece ?? ( vec_get [String] pieces pi ) { T s → ( string_data s ) F _ → `` }
            ?? ( __msi_get . tk enc piece ) {
                T id → ( vec_push [i] ids id )
                F _ → {}
            }
            = pi + pi 1
        }
        ( __free_strvec pieces )
        ( string_free benc )
        = wi + wi 1
    }
    ( __free_strvec words )
    ( string_free cleaned )
    ^ ids
}

// text → padded context: [sot] + ids + [eot], zero-padded/truncated to ctx.
// Returns a Vec<i> of length `ctx`.
@ bpe_tokenize Tokenizer tk s text i ctx → ( Vec i ) {
    : ( Vec i ) ids ( bpe_encode tk text )
    : ( Vec i ) out ( vec_new [i] )
    : ~ i k 0
    ~ < k ctx { ( vec_push [i] out 0 ) = k + k 1 }
    ( __is out 0 . tk sot )
    : i nid ( vec_len [i] ids )
    // room for ids between sot and eot: positions 1..ctx-2, plus eot
    : ~ i w 1
    : ~ i j 0
    ~ & < j nid < w - ctx 1 {
        ( __is out w ( __ig ids j ) )
        = w + w 1
        = j + j 1
    }
    ( __is out w . tk eot )
    ( vec_free [i] ids )
    ^ out
}
