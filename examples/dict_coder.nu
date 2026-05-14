// ============================================================
// dict_coder.nu — Mini text compressor & decompressor
//
// Builds a dictionary as it scans the input: each new word gets a
// fresh integer ID, recurring words reuse it. The output is a flat
// list of IDs that can be expanded back into the original text by
// indexing into the dictionary vector. The savings depend on how
// repetitive the input is — natural language usually compresses
// well because a small core vocabulary covers most occurrences.
//
// Showcases the NURL stdlib generics:
//   - HashMap[s i]  (word → ID lookup, fast O(1) average)
//   - Vec[s]        (ID → word reverse lookup, fast O(1) random access)
//   - Vec[i]        (compressed stream)
//   - Option[?T]    (map_get returns Some/None — pattern-matched with ??)
//   - Closures      (hash + eq passed per-call, since NURL has no
//                    type-class dispatch)
//
// Ownership note: the words below are raw string-literal pointers,
// so the HashMap and Vecs only borrow them — bare `map_free` /
// `vec_free` is correct. For an owned-String dictionary you would
// reach for `vec_free_with` + `map_free_with` instead.
// ============================================================

$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/hashmap.nu`

// ── Closure wrappers ────────────────────────────────────────────────
// NURL doesn't auto-promote @-functions to closure values, so the stock
// hash_string / eq_string from hashmap.nu need a `\`-wrapper at the
// call site. Defined once at top level and reused everywhere.

@ make_hash → ( @ i s ) {
    ^ \ s w → i { ^ ( hash_string w ) }
}

@ make_eq → ( @ b s s ) {
    ^ \ s a s b → b { ^ ( eq_string a b ) }
}

// ── Pretty-printing helpers ─────────────────────────────────────────

@ banner s title → v {
    ( nurl_print `\n── ` )
    ( nurl_print title )
    ( nurl_print ` ` )
    : ~ i pad 0
    ~ < pad 50 {
        ( nurl_print `─` )
        = pad + pad 1
    }
    ( nurl_print `\n` )
}

@ kv_line s key i val → v {
    ( nurl_print `  ` )
    ( nurl_print key )
    ( nurl_print `: ` )
    ( nurl_print ( nurl_str_int val ) )
    ( nurl_print `\n` )
}

// ── Encoder ─────────────────────────────────────────────────────────
// For each word in the input slice:
//   * if it is already in the dictionary, emit its existing ID
//   * otherwise assign the next free ID, push to both lookup tables,
//     and emit that
// The dictionary is grown in place; the compressed stream is returned
// implicitly via the (Vec i) handle (mutations propagate through the
// shared heap control block — same model as String).

@ encode [s words ( HashMap s i ) word_to_id ( Vec s ) id_to_word ( Vec i ) compressed → i {
    : ( @ i s ) hs ( make_hash )
    : ( @ b s s ) es ( make_eq )

    : ~ i new_words 0

    ~ word words {
        : ?i looked_up ( map_get [s i] word_to_id word hs es )

        : ~ i id 0
        ?? looked_up {
            T existing → { = id existing }
            F → {
                // First sighting: ID = current dictionary size.
                = id ( vec_len [s] id_to_word )
                ( map_set [s i] word_to_id word id hs es )
                ( vec_push [s] id_to_word word )
                = new_words + new_words 1
            }
        }

        ( vec_push [i] compressed id )
    }

    ^ new_words
}

// ── Decoder ─────────────────────────────────────────────────────────
// Walks the compressed Vec[i] and prints the matching dictionary entry
// for every ID. A malformed ID (out of dictionary range) is rendered as
// `??` rather than aborted — the kind of resilience a real codec wants.

@ decode ( Vec s ) id_to_word ( Vec i ) compressed → v {
    : i n ( vec_len [i] compressed )
    : ~ i j 0
    ~ < j n {
        : ?i lookup_id ( vec_get [i] compressed j )
        ?? lookup_id {
            T id → {
                : ?s lookup_word ( vec_get [s] id_to_word id )
                ?? lookup_word {
                    T w → ( nurl_print w )
                    F → ( nurl_print `??` )
                }
            }
            F → ( nurl_print `??` )
        }
        ( nurl_print ` ` )
        = j + j 1
    }
    ( nurl_print `\n` )
}

// ── Frequency report ────────────────────────────────────────────────
// One pass over the compressed stream tallies how often each ID appears.
// Implemented with map_fold to demonstrate higher-order stdlib calls:
// the closure receives (acc, key, val) for every dictionary entry and
// returns the running maximum frequency. We do the actual counting by
// sweeping the compressed Vec into a fresh HashMap[i i].

@ tally_freqs ( Vec i ) compressed → ( HashMap i i ) {
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }

    : ( HashMap i i ) freqs ( map_new [i i] )
    : i n ( vec_len [i] compressed )
    : ~ i k 0
    ~ < k n {
        : ?i opt_id ( vec_get [i] compressed k )
        ?? opt_id {
            T id → {
                : ?i prev ( map_get [i i] freqs id hi ei )
                : ~ i count 1
                ?? prev {
                    T c → { = count + c 1 }
                    F → {}
                }
                ( map_set [i i] freqs id count hi ei )
            }
            F → {}
        }
        = k + k 1
    }
    ^ freqs
}

@ report_top_word ( HashMap i i ) freqs ( Vec s ) id_to_word → v {
    : ( @ i i i i ) pick_max \ i acc i k i v → i {
        ^ ? > v acc v acc
    }
    : i max_count ( map_fold [i i i] freqs 0 pick_max )

    ( nurl_print `  most frequent ID hit count: ` )
    ( nurl_print ( nurl_str_int max_count ) )
    ( nurl_print ` (` )

    // Find any ID matching that count and render its word. We don't have
    // a built-in `map_find` yet, so iterate id_to_word and probe.
    : i dict_size ( vec_len [s] id_to_word )
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i a i b → b { ^ ( eq_int a b ) }
    : ~ i id 0
    : ~ b printed F
    ~ & < id dict_size ! printed {
        : ?i c ( map_get [i i] freqs id hi ei )
        ?? c {
            T n → ?== n max_count {
                : ?s w ( vec_get [s] id_to_word id )
                ?? w {
                    T s → { ( nurl_print `'` ) ( nurl_print s ) ( nurl_print `'` ) }
                    F → ( nurl_print `?` )
                }
                = printed T
            } {}
            F → {}
        }
        = id + id 1
    }
    ( nurl_print `)\n` )
}

// ── Entry point ─────────────────────────────────────────────────────

@ main → i {
    ( nurl_print `NURL dict_coder — minimal vocabulary compression\n` )

    // A fragment with deliberate repetition — the closer it gets to
    // "lots of the same words", the better the compression ratio.
    : [s words [s |
    `the` `quick` `brown` `fox` `jumps` `over` `the` `lazy` `dog`
    `the` `dog` `barks` `the` `fox` `runs` `the` `fox` `is` `quick`
    `the` `quick` `fox` `is` `clever` `the` `dog` `is` `loyal`
    `the` `quick` `brown` `fox` `is` `back`
    ]

    // Construct the three working tables. They live for the whole run
    // and are freed in reverse order at the end.
    : ( HashMap s i ) word_to_id ( map_new [s i] )
    : ( Vec s ) id_to_word ( vec_new [s] )
    : ( Vec i ) compressed ( vec_new [i] )

    ( banner `Encoding` )
    : i n_input . words length
    : i n_new ( encode words word_to_id id_to_word compressed )

    // Honest size metrics: text format counts each byte plus a
    // separator; compressed format is 4 bytes per ID *plus* the
    // dictionary itself (each unique word's bytes + a separator).
    : ~ i raw_bytes 0
    ~ w words {
        = raw_bytes + raw_bytes + ( nurl_str_len w ) 1
    }
    : ~ i dict_bytes 0
    : i dict_size ( vec_len [s] id_to_word )
    : ~ i di 0
    ~ < di dict_size {
        : ?s ow ( vec_get [s] id_to_word di )
        : s entry ( opt_unwrap_or [s] ow `` )
        = dict_bytes + dict_bytes + ( nurl_str_len entry ) 1
        = di + di 1
    }
    // Pick the narrowest fixed-width integer that fits every ID — for
    // small dictionaries one byte is plenty, and that's where dictionary
    // coding actually starts paying off.
    : i id_width ? > dict_size 65536 4 ? > dict_size 256 2 1
    : i stream_bytes * ( vec_len [i] compressed ) id_width
    : i comp_bytes + stream_bytes dict_bytes
    : i ratio_pct ? > raw_bytes 0 / * comp_bytes 100 raw_bytes 0

    ( kv_line `input tokens          ` n_input )
    ( kv_line `unique words          ` n_new )
    ( kv_line `compressed stream len ` ( vec_len [i] compressed ) )
    ( kv_line `ID width (bytes)      ` id_width )
    ( kv_line `raw bytes (text)      ` raw_bytes )
    ( kv_line `bytes: ID stream      ` stream_bytes )
    ( kv_line `bytes: dictionary     ` dict_bytes )
    ( kv_line `bytes: total comp     ` comp_bytes )
    ( kv_line `compression % of raw  ` ratio_pct )

    ( banner `Decoding` )
    ( nurl_print `  ` )
    ( decode id_to_word compressed )

    ( banner `Frequencies` )
    : ( HashMap i i ) freqs ( tally_freqs compressed )
    ( report_top_word freqs id_to_word )
    ( map_free [i i] freqs )

    ( banner `Cleanup` )
    ( map_free [s i] word_to_id )
    ( vec_free [s] id_to_word )
    ( vec_free [i] compressed )
    ( nurl_print `  done.\n` )

    ^ 0
}
