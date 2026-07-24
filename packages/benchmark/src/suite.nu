// packages/bench/src/suite.nu — the benchmarks themselves. Each returns a
// BenchRow measured on this machine, right now. Everything is pure NURL and
// self-contained: the inputs are generated deterministically at setup (that
// work is not timed — std/bench snapshots the clock and the allocation
// counter around the timed loop only), no file, model, GPU or network is
// touched, and there are no dependencies beyond the standard library.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/utf8.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/cbor.nu`
$ `stdlib/ext/csv.nu`
$ `src/report.nu`

// ---- deterministic input generators (setup, never timed) --------------

// n pseudo-random bytes (a seeded xorshift, so the buffer is identical run
// to run and machine to machine)
@ __gen_bytes i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i s 88172645463325252
    : ~ i k 0
    ~ < k n {
        = s ^^ s << s 13
        = s ^^ s >> s 7
        = s ^^ s << s 17
        ( vec_push [u] v # u & s 255 )
        = k + k 1
    }
    ^ v
}

// n seeded i64s in [0, 1e9) — an unsorted column to sort
@ __gen_ints i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : Rng g ( rng_seed 2463534242 )
    : ~ i k 0
    ~ < k n {
        ( vec_push [i] v ( rng_below g 1000000000 ) )
        = k + k 1
    }
    ( rng_free g )
    ^ v
}

// A JSON array of `m` small objects, stringified to a parseable document.
@ __gen_json_doc i m → String {
    : Json arr ( json_arr_new )
    : ~ i k 0
    ~ < k m {
        : Json o ( json_obj_new )
        : b _a ( json_obj_set o `id` ( json_int k ) )
        : b _b ( json_obj_set o `name` ( json_str_lit `benchmark-item` ) )
        : b _c ( json_obj_set o `value` ( json_int * k 7 ) )
        : b _d ( json_obj_set o `enabled` ( json_bool ? == & k 1 0 T F ) )
        : b _e ( json_arr_push arr o )
        = k + k 1
    }
    : String txt ( json_stringify arr )
    ( json_free arr )
    ^ txt
}

// A UTF-8 string of roughly `n` bytes, mixing ASCII and multi-byte runes so
// utf8_decode does real continuation-byte work.
@ __gen_utf8 i n → String {
    : String out ( string_with_cap + n 8 )
    ~ < ( string_len out ) n {
        ( string_push_str out `the quick brown fox — héllo, wörld ☃ 日本語 ` )
    }
    ^ out
}

// f-or-0 read (Vec i length-1 accumulators can't be dead-code eliminated)
@ __ipeek ( Vec i ) v i idx → i {
    ?? ( vec_get [i] v idx ) { T x → { ^ x } F → { ^ 0 } }
}

// --- one-time key extraction (setup): read each row's sort keys ONCE from
// the zero-copy CSV views into compact integers, so the timed sort compares
// integers, not re-parsed cell text. This is the lesson from the pre-1.0 CSV
// tuning: a comparator that re-parses on every call is why the naive sort was
// orders of magnitude slower.
//
// Bytes are read straight off the `*u` view pointer (`# i . p k`), NEVER via
// nurl_str_get: that bounds-checks with strlen(), and a CSV view points into
// the middle of one big arena buffer with no interior NUL, so a single
// nurl_str_get would scan to the end of the file — O(rows) per byte, O(N²)
// over the table (measured: it turned a sub-second extract into minutes).

// byte at offset k of a *u pointer, as an int
@ __b * u p i k → i { ^ # i . p k }

// decimal digit at offset k
@ __dig * u p i k → i { ^ - ( __b p k ) 48 }

// "type" cell → 0..9 (the ten words start with distinct letters a..j)
@ __type_id * u p → i { ^ - ( __b p 0 ) 97 }

// "YYYY-MM-DD" → a compact, order-preserving day key in [0, ~1112) (11 bits),
// so type+date+uuid pack into one non-negative i64 for a radix sort.
@ __date_key * u p → i {
    : i y + + + * ( __dig p 0 ) 1000 * ( __dig p 1 ) 100 * ( __dig p 2 ) 10 ( __dig p 3 )
    : i mo + * ( __dig p 5 ) 10 ( __dig p 6 )
    : i da + * ( __dig p 8 ) 10 ( __dig p 9 )
    ^ + + * - y 2023 372 * - mo 1 31 - da 1
}

// hex digit value of a character code
@ __hexv i c → i { ? <= c 57 - c 48 - c 87 }

// first 16 hex chars of a uuid → an i64 tie-breaker
@ __hex16 * u p → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 16 {
        = acc | << acc 4 ( __hexv ( __b p k ) )
        = k + k 1
    }
    ^ acc
}

// Inline i64 quicksort — the same Hoare-partition / median-of-three /
// recurse-the-smaller-half shape as std/sort, but comparing i64 values
// directly instead of through a `( @ i A A )` closure. That one change is
// the whole point: a closure call per comparison (~20 M of them) is what
// makes the generic sort_by path several times slower here.
@ __swp_i * i a i i i j → v {
    : i x . a i
    : i y . a j
    = . a i y
    = . a j x
}

@ __part_i * i a i lo i hi → i {
    : i mid + lo / - hi lo 2
    ? > . a lo . a mid { ( __swp_i a lo mid ) } {}
    ? > . a lo . a hi { ( __swp_i a lo hi ) } {}
    ? > . a mid . a hi { ( __swp_i a mid hi ) } {}
    : i pivot . a mid
    : ~ i i - lo 1
    : ~ i j + hi 1
    ~ T {
        = i + i 1
        ~ < . a i pivot { = i + i 1 }
        = j - j 1
        ~ > . a j pivot { = j - j 1 }
        ? >= i j { ^ j } {}
        ( __swp_i a i j )
    }
}

// insertion sort for a small range — cheaper than partitioning once the
// subarray is tiny, and where a median-of-three quicksort spends most of
// its comparisons
@ __ins_i * i a i lo i hi → v {
    : ~ i i + lo 1
    ~ <= i hi {
        : i x . a i
        : ~ i j i
        ~ & > j lo > . a - j 1 x {
            = . a j . a - j 1
            = j - j 1
        }
        = . a j x
        = i + i 1
    }
}

@ __qs_i * i a i lo i hi → v {
    : ~ i l lo
    : ~ i h hi
    ~ < l h {
        ? <= - h l 16 {
            ( __ins_i a l h )
            = l h
        } {
            : i p ( __part_i a l h )
            ? < - p l - h p {
                ( __qs_i a l p )
                = l + p 1
            } {
                ( __qs_i a + p 1 h )
                = h p
            }
        }
    }
}

// one of ten low-cardinality `type` values (many rows share each, so the
// date and uuid keys actually decide the order)
@ __type_word i i → s {
    ? == i 0 { ^ `alpha` } {}
    ? == i 1 { ^ `bravo` } {}
    ? == i 2 { ^ `charlie` } {}
    ? == i 3 { ^ `delta` } {}
    ? == i 4 { ^ `echo` } {}
    ? == i 5 { ^ `foxtrot` } {}
    ? == i 6 { ^ `golf` } {}
    ? == i 7 { ^ `hotel` } {}
    ? == i 8 { ^ `india` } {}
    ^ `juliet`
}

// low nibble of v as a hex character code
@ __hexc i v → i {
    : i d & v 15
    ^ ? < d 10 + 48 d + 87 d
}

// a canonical 36-char UUID string from 128 bits (hi:lo), 8-4-4-4-12
@ __fmt_uuid i hi i lo → String {
    : String o ( string_with_cap 36 )
    : ~ i n 0
    ~ < n 16 {
        ? | == n 8 | == n 12 == n 16 { ( string_push_char o 45 ) } {}
        ( string_push_char o ( __hexc >> hi * - 15 n 4 ) )
        = n + n 1
    }
    ( string_push_char o 45 )
    = n 0
    ~ < n 16 {
        ? | == n 4 == n 8 { ( string_push_char o 45 ) } {}
        ( string_push_char o ( __hexc >> lo * - 15 n 4 ) )
        = n + n 1
    }
    ^ o
}

// two-digit zero-padded decimal
@ __pad2 i n → String {
    : String o ( string_with_cap 2 )
    ? < n 10 { ( string_push_char o 48 ) } {}
    ( string_push_str o ( nurl_str_int n ) )
    ^ o
}

// ---- the benchmarks ---------------------------------------------------

@ bench_sha256 → BenchRow {
    : i n 1048576
    : ( Vec u ) buf ( __gen_bytes n )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `sha256` n `MB/s` \ → v {
        : *Sha256 h ( sha256_init )
        ( sha256_update h buf )
        : ( Vec u ) d ( sha256_final h )
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) ( vec_len [u] d ) )
        ( vec_free [u] d )
    } )
    ( vec_free [u] buf )
    ( vec_free [i] sink )
    ^ r
}

@ bench_json_parse → BenchRow {
    : String doc ( __gen_json_doc 1200 )
    : i bytes ( string_len doc )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `json parse` bytes `MB/s` \ → v {
        ?? ( json_parse ( string_data doc ) ) {
            T j → {
                ( vec_set [i] sink 0 + ( __ipeek sink 0 ) ( json_arr_len j ) )
                ( json_free j )
            }
            F _ → {}
        }
    } )
    ( string_free doc )
    ( vec_free [i] sink )
    ^ r
}

@ bench_sort → BenchRow {
    : i n 50000
    : ( Vec i ) base ( __gen_ints n )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `sort i64` n `M/s` \ → v {
        : ( Vec i ) c ( vec_clone [i] base )
        ( sort_by [i] c \ i a i b → i { ^ - a b } )
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) ( __ipeek c 0 ) )
        ( vec_free [i] c )
    } )
    ( vec_free [i] base )
    ( vec_free [i] sink )
    ^ r
}

@ bench_cbor_decode → BenchRow {
    : Json doc ( json_arr_new )
    : ~ i k 0
    ~ < k 2000 {
        ( json_arr_push doc ( json_int * k 3 ) )
        = k + k 1
    }
    : ~ ( Vec u ) enc ( vec_new [u] )
    ?? ( cbor_encode doc ) { T v → { ( vec_free [u] enc ) = enc v } F _ → {} }
    ( json_free doc )
    : i bytes ( vec_len [u] enc )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `cbor decode` bytes `MB/s` \ → v {
        ?? ( cbor_decode enc ) {
            T j → {
                ( vec_set [i] sink 0 + ( __ipeek sink 0 ) ( json_arr_len j ) )
                ( json_free j )
            }
            F _ → {}
        }
    } )
    ( vec_free [u] enc )
    ( vec_free [i] sink )
    ^ r
}

@ bench_utf8_decode → BenchRow {
    : String s ( __gen_utf8 262144 )
    : i bytes ( string_len s )
    : s sd ( string_data s )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `utf8 decode` bytes `MB/s` \ → v {
        : ~ i pos 0
        : ~ i cps 0
        ~ < pos bytes {
            : Utf8Dec d ( utf8_decode_n sd bytes pos )
            : i w ? > . d width 0 . d width 1
            = pos + pos w
            = cps + cps 1
        }
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) cps )
    } )
    ( string_free s )
    ( vec_free [i] sink )
    ^ r
}

@ bench_int_loop → BenchRow {
    : i n 2000000
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    // a data-dependent xorshift mix per iteration: the feedback through the
    // shifts is non-polynomial, so the optimiser cannot collapse the loop to
    // a closed form (a plain sum would be evaluated at compile time and
    // measure nothing).
    : BenchRow r ( bench_thpt `int loop` n `M/s` \ → v {
        : ~ i acc 1
        : ~ i k 0
        ~ < k n {
            = acc ^^ acc << acc 13
            = acc ^^ acc >> acc 7
            = acc + acc k
            = k + k 1
        }
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) acc )
    } )
    ( vec_free [i] sink )
    ^ r
}

// Generate an 8-column CSV (id,type,date,uuid,name,value,flag,score) of `n`
// rows plus a header. `type` is one of ten words (heavy ties), `date` is a
// random day across the three previous years as YYYY-MM-DD (so a byte compare
// is chronological), and `uuid` is a canonical 36-char UUID (the tie-breaker).
@ __gen_csv i n → String {
    : String o ( string_with_cap * n 96 )
    ( string_push_str o `id,type,date,uuid,name,value,flag,score\n` )
    : Rng g ( rng_seed 987654321 )
    : ~ i k 0
    ~ < k n {
        ( string_push_str o ( nurl_str_int k ) )
        ( string_push_char o 44 )
        ( string_push_str o ( __type_word ( rng_below g 10 ) ) )
        ( string_push_char o 44 )
        ( string_push_str o ( nurl_str_int + 2023 ( rng_below g 3 ) ) )
        ( string_push_char o 45 )
        : String mm ( __pad2 + 1 ( rng_below g 12 ) )
        ( string_push_str o ( string_data mm ) ) ( string_free mm )
        ( string_push_char o 45 )
        : String dd ( __pad2 + 1 ( rng_below g 28 ) )
        ( string_push_str o ( string_data dd ) ) ( string_free dd )
        ( string_push_char o 44 )
        : String uu ( __fmt_uuid ( rng_next g ) ( rng_next g ) )
        ( string_push_str o ( string_data uu ) ) ( string_free uu )
        ( string_push_char o 44 )
        ( string_push_str o `item` ) ( string_push_char o 44 )
        ( string_push_str o ( nurl_str_int * k 7 ) ) ( string_push_char o 44 )
        ( string_push_str o ? == & k 1 0 `true` `false` ) ( string_push_char o 44 )
        ( string_push_str o ( nurl_str_int ( rng_below g 1000 ) ) )
        ( string_push_char o 10 )
        = k + k 1
    }
    ( rng_free g )
    ^ o
}

// unwrap a column index by name (0 if absent — the generated header has it)
@ __col * CSVTable t s name → i {
    ?? ( csv_table_col_index t name ) { T c → { ^ c } F → { ^ 0 } }
}

@ bench_csv_sort → BenchRow {
    : i n 1000000
    // --- setup (not timed): parse with the standard library's CSV reader,
    // then extract each row's (type, date, uuid) keys ONCE into integers.
    : *CSVTable t ( csv_table_from_string ( __gen_csv n ) )
    : i cty ( __col t `type` )
    : i cda ( __col t `date` )
    : i cuu ( __col t `uuid` )
    // Pack (type, date, uuid) into ONE non-negative i64 per row so the sort
    // is a single radix pass with no comparator:
    //   bits 58..61 type (0-9) · bits 47..57 date · bits 0..46 uuid (47-bit
    //   tie-breaker). date < 2^11 and type < 2^4, so the order is exactly
    //   type, then date, then uuid, and every key stays positive.
    : ( Vec i ) key ( vec_with_cap [i] n )
    : ~ i r0 0
    ~ < r0 n {
        : i tid ( __type_id # *u ( csv_table_view t r0 cty ) )
        : i dk ( __date_key # *u ( csv_table_view t r0 cda ) )
        : i uu & ( __hex16 # *u ( csv_table_view t r0 cuu ) ) 140737488355327
        ( vec_push [i] key | | << tid 58 << dk 47 uu )
        = r0 + r0 1
    }
    ( csv_table_free t )
    : *i kp ( vec_data [i] key )
    : ( Vec i ) work ( vec_with_cap [i] n )
    : ~ i f 0
    ~ < f n { ( vec_push [i] work 0 ) = f + f 1 }
    : *i wp ( vec_data [i] work )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    // --- timed: copy the packed keys into the work buffer (fresh unsorted
    // input each pass), then quicksort them in place.
    : BenchRow r ( bench_thpt `csv sort 1M×8` n `M/s` \ → v {
        : ~ i c 0
        ~ < c n { = . wp c . kp c = c + c 1 }
        ( __qs_i wp 0 - n 1 )
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) . wp 0 )
    } )
    ( vec_free [i] key )
    ( vec_free [i] work )
    ( vec_free [i] sink )
    ^ r
}
