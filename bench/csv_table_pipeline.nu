// benchmark-contract: csv-table-pipeline;rows=100000;cols=id,name,city,qty,price,note;eol=CRLF;lcg=mmix(seed=1);draw=state>>33;name=names[r&15],form=(r>>4)&7(0:"O""<n>",1:"<n>, Jr.",else:<n>);city=cities[(r>>7)&7];qty=(r>>10)%1000;price=((r>>20)%100000)/100.2dp;note=(r>>27)&3(0:empty,1:fragile,2:"line one\nline two",3:"says ""hi""");passes=4;agg=per-city sum(qty*cents),count;fold=fnv64(seed=1469598103934665603,prime=1099511628211)
//
// csv_table_pipeline — the standard library's own CSV path, end to end.
// The program builds a deterministic 100k-row RFC 4180 document in
// memory (CRLF rows; quoted fields with embedded commas, with `""`
// escapes, and one with an embedded line break), then four times: copies
// the text (as loading it would), parses the copy into a `CSVTable`
// (stdlib/ext/csv.nu: `csv_table_from_string`), finds the columns by
// header name, and walks every row through zero-copy `csv_table_view`s
// of five columns — matching the city against eight names, parsing the
// quantity and the price in cents, summing revenue and a row count per
// city, and counting the bytes, quotes and line breaks of the name and
// note columns. Each pass's aggregates are folded into the checksum.
//
// What this row adds: the stdlib's parsing and cell-access hot path on a
// realistic table — byte scanning, quote and escape handling, the cell
// index the parser builds, and the per-cell view accessor — with the
// allocation and memory profile that goes with it. `json_parse` is the
// nearest row (another stdlib parser), and the only other one that
// allocates on its hot path.
//
// The C and Rust peers carry the same parser written out by hand — the
// CSVTable layout (one content buffer, an (offset, length) pair per
// cell, a separate buffer for the unescaped bytes of cells with `""`
// escapes, a row-start / row-length index, the header row kept apart),
// the same quote, separator and end-of-row rules, and an accessor that
// bounds-checks (row, column) the way `csv_table_view` does. They scan
// an unquoted cell byte by byte; the stdlib scans it 16 bytes at a time
// (`nurl_scan_byte3`, SSE2), which is a real difference of method the
// row is there to show, not to hide. No `unsafe` in this file.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`
$ `stdlib/ext/csv.nu`

@ fnv u64 h u64 v → u64 { ^ * ^^ h v 1099511628211 }

// `v` in decimal, most significant digit first.
@ push_dec String out u64 v → v {
    ? >= v 10 { ( push_dec out / v 10 ) } {}
    ( string_push_char out # i + 48 % v 10 )
}

@ gen_csv i rows ( Vec s ) names ( Vec s ) cities → String {
    : String out ( string_with_cap * rows 64 )
    ( string_push_str out `id,name,city,qty,price,note` )
    ( string_push_char out 13 )
    ( string_push_char out 10 )
    : ~ u64 x 1
    : ~ i row 0
    ~ < row rows {
        = x + * x 6364136223846793005 1442695040888963407
        : u64 r >> x 33
        ( push_dec out # u64 row )
        ( string_push_char out 44 )
        : s name ( vec_at [s] names # i & r 15 )
        : u64 form & >> r 4 7
        ? == form 0 {
            ( string_push_str out `"O""` )
            ( string_push_str out name )
            ( string_push_char out 34 )
        } {
            ? == form 1 {
                ( string_push_char out 34 )
                ( string_push_str out name )
                ( string_push_str out `, Jr."` )
            } { ( string_push_str out name ) }
        }
        ( string_push_char out 44 )
        ( string_push_str out ( vec_at [s] cities # i & >> r 7 7 ) )
        ( string_push_char out 44 )
        ( push_dec out % >> r 10 1000 )
        ( string_push_char out 44 )
        : u64 cents % >> r 20 100000
        ( push_dec out / cents 100 )
        ( string_push_char out 46 )
        ( string_push_char out # i + 48 % / cents 10 10 )
        ( string_push_char out # i + 48 % cents 10 )
        ( string_push_char out 44 )
        : u64 note & >> r 27 3
        ? == note 1 { ( string_push_str out `fragile` ) } {}
        ? == note 2 {
            ( string_push_str out `"line one` )
            ( string_push_char out 10 )
            ( string_push_str out `line two"` )
        } {}
        ? == note 3 { ( string_push_str out `"says ""hi"""` ) } {}
        ( string_push_char out 13 )
        ( string_push_char out 10 )
        = row + row 1
    }
    ^ out
}

// The decimal digits of a cell, read as one number (the price's `.` is
// skipped, so `123.45` is 12345 cents).
@ digits ( Slice u ) b → u64 {
    : i n ( slice_len [u] b )
    : ~ u64 acc 0
    : ~ i j 0
    ~ < j n {
        : i c ( slice_byte b j )
        ? & >= c 48 <= c 57 { = acc + * acc 10 # u64 - c 48 } {}
        = j + j 1
    }
    ^ acc
}

@ count_byte ( Slice u ) b i want → u64 {
    : i n ( slice_len [u] b )
    : ~ u64 hits 0
    : ~ i j 0
    ~ < j n {
        ? == ( slice_byte b j ) want { = hits + hits 1 } {}
        = j + j 1
    }
    ^ hits
}

// The index of the key `v` equals, or the key count when none does.
@ city_index ( Vec ( Slice u ) ) keys ( Slice u ) v → i {
    : i n ( vec_len [( Slice u )] keys )
    : ~ i j 0
    ~ < j n {
        ? ( slice_bytes_eq ( vec_at [( Slice u )] keys j ) v ) { ^ j } {}
        = j + j 1
    }
    ^ n
}

@ col CSVTable t s name → i { ^ ( opt_expect [i] ( csv_table_col_index t name ) `csv_table_pipeline: missing column` ) }

@ main → i {
    // The workload multiplier: bench/wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : i passes * 4 # i BENCH_SCALE
    : i rows 100000

    : ( Vec s ) names ( vec_with_cap [s] 16 )
    ( vec_push [s] names `Aino` )
    ( vec_push [s] names `Eino` )
    ( vec_push [s] names `Helmi` )
    ( vec_push [s] names `Väinö` )
    ( vec_push [s] names `Ilona` )
    ( vec_push [s] names `Toivo` )
    ( vec_push [s] names `Siiri` )
    ( vec_push [s] names `Onni` )
    ( vec_push [s] names `Lempi` )
    ( vec_push [s] names `Arvo` )
    ( vec_push [s] names `Kerttu` )
    ( vec_push [s] names `Urho` )
    ( vec_push [s] names `Elli` )
    ( vec_push [s] names `Paavo` )
    ( vec_push [s] names `Saimi` )
    ( vec_push [s] names `Veikko` )
    // The city cells as written, and the values the parser hands back.
    : ( Vec s ) cities ( vec_with_cap [s] 8 )
    ( vec_push [s] cities `Helsinki` )
    ( vec_push [s] cities `Tampere` )
    ( vec_push [s] cities `Oulu` )
    ( vec_push [s] cities `Turku` )
    ( vec_push [s] cities `Espoo` )
    ( vec_push [s] cities `"Washington, D.C."` )
    ( vec_push [s] cities `Vantaa` )
    ( vec_push [s] cities `"Lahti"` )
    : ( Vec ( Slice u ) ) keys ( vec_with_cap [( Slice u )] 8 )
    ( vec_push [( Slice u )] keys ( slice_of_str `Helsinki` ) )
    ( vec_push [( Slice u )] keys ( slice_of_str `Tampere` ) )
    ( vec_push [( Slice u )] keys ( slice_of_str `Oulu` ) )
    ( vec_push [( Slice u )] keys ( slice_of_str `Turku` ) )
    ( vec_push [( Slice u )] keys ( slice_of_str `Espoo` ) )
    ( vec_push [( Slice u )] keys ( slice_of_str `Washington, D.C.` ) )
    ( vec_push [( Slice u )] keys ( slice_of_str `Vantaa` ) )
    ( vec_push [( Slice u )] keys ( slice_of_str `Lahti` ) )

    : String text ( gen_csv rows names cities )

    : ~ u64 h 1469598103934665603
    : ~ i pass 0
    ~ < pass passes {
        : CSVTable t ( csv_table_from_string ( string_clone text ) )
        : i n ( csv_table_n_rows t )
        : i c_name ( col t `name` )
        : i c_city ( col t `city` )
        : i c_qty ( col t `qty` )
        : i c_price ( col t `price` )
        : i c_note ( col t `note` )
        : ( Vec u64 ) rev ( vec_zeroed [u64] 9 )
        : ( Vec u64 ) cnt ( vec_zeroed [u64] 9 )
        : ~ u64 quoted 0
        : ~ u64 name_bytes 0
        : ~ u64 note_bytes 0
        : ~ u64 multiline 0
        : ~ i row 0
        ~ < row n {
            : i city ( city_index keys ( csv_table_view t row c_city ) )
            : u64 qty ( digits ( csv_table_view t row c_qty ) )
            : u64 cents ( digits ( csv_table_view t row c_price ) )
            ( vec_put [u64] rev city + ( vec_at [u64] rev city ) * qty cents )
            ( vec_put [u64] cnt city + ( vec_at [u64] cnt city ) 1 )
            : ( Slice u ) nm ( csv_table_view t row c_name )
            = quoted + quoted ( count_byte nm 34 )
            = name_bytes + name_bytes # u64 ( slice_len [u] nm )
            : ( Slice u ) nt ( csv_table_view t row c_note )
            = note_bytes + note_bytes # u64 ( slice_len [u] nt )
            = multiline + multiline ( count_byte nt 10 )
            = row + row 1
        }
        : ~ i c 0
        ~ < c 9 {
            = h ( fnv h ( vec_at [u64] rev c ) )
            = h ( fnv h ( vec_at [u64] cnt c ) )
            = c + c 1
        }
        = h ( fnv h quoted )
        = h ( fnv h name_bytes )
        = h ( fnv h note_bytes )
        = h ( fnv h multiline )
        = h ( fnv h # u64 n )
        = pass + pass 1
    }
    ( nurl_println_int # i & h 0x7fffffffffffffff )
    ^ 0
}
