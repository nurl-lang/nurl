// stdlib/ext/csv.nu — CSV reader/writer + bulk CSVTable
//
// Two complementary APIs:
//
//   Streaming, per-row:
//     CSVReader      — line-by-line scan, owns the input String
//     CSVDictReader  — header-mapped HashMap rows
//     CSVWriter      — line-by-line writer over a FILE*
//     CSVDictWriter  — header-mapped writer
//
//   Bulk, in-memory:
//     CSVTable       — arena-backed table. One file buffer + (off, len)
//                      cell pairs into it. RFC 4180 quoting by default.
//                      Cells expose borrowed `s` views (zero-copy) or
//                      owned String copies on request.
//
// Both layers share `CSVDialect` (delimiter, line terminator, quote
// byte). All readers and writers in this module honour RFC 4180
// quoting when `dialect.quote_char != 0`. Use `csv_dialect_unquoted`
// (`quote_char = 0`) on data known to be quote-free to bypass the
// per-cell quote-byte branch in both reader and writer.
//
// CSVTable layout:
//
//   content     — owned file buffer; cells point into here
//   headers     — owned column-name Strings (deep copies of cells)
//   flat_cells  — [off0,len0,off1,len1,...]; off ≥ 0 means content[off..],
//                 off < 0 means escape_buf[-off-1..] (only for quoted
//                 cells with `""` escapes)
//   row_starts  — cell index of row r (cell index, NOT i64 index)
//   row_lens    — cell count of row r
//   escape_buf  — unescaped quoted-cell bytes
//
// Allocation profile (1 M-row × 8-col fixture): ~10 calloc / realloc
// total — one file buffer + 4 row-index vecs + headers. Per-cell
// String allocs are paid only on `csv_table_get` (owned-copy
// accessor); the `csv_table_view` path stays zero-copy.
//
// Cell views are NOT NUL-terminated — they are raw byte pointers into
// the content (or escape) buffer. Combine with `csv_table_view_len`
// for length. Borrows are valid until `csv_table_free`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/hashmap.nu`

// ── Dialect ────────────────────────────────────────────────────────

: CSVDialect {
    i delimiter  // byte value, e.g. 44 (',') or 9 ('\t')
    b crlf_terminator  // T = write '\r\n', F = write '\n'
    i quote_char  // RFC 4180 quote byte (34 = `"`); 0 disables quoting
}

@ csv_dialect_default → CSVDialect { ^ @ CSVDialect { 44 F 34 } }

@ csv_dialect_excel → CSVDialect { ^ @ CSVDialect { 44 T 34 } }

@ csv_dialect_excel_tab → CSVDialect { ^ @ CSVDialect { 9 T 34 } }

@ csv_dialect_unix → CSVDialect { ^ @ CSVDialect { 44 F 34 } }

// Unquoted dialect: every byte except delim/CR/LF is content. Use for
// data sets that NEVER contain quoted fields — skips the per-cell
// branch on the quote byte and matches the raw-write speed exactly.
@ csv_dialect_unquoted → CSVDialect { ^ @ CSVDialect { 44 F 0 } }

// ── Shared row-vec helpers (streaming API) ─────────────────────────

@ __csv_drop_string String s → v { ( string_free s ) }

@ __csv_row_free ( Vec String ) row → v {
    ( vec_free_with [String] row \ String s → v { ( string_free s ) } )
}

// ── CSVReader (per-row stream) ─────────────────────────────────────

: CSVReader {
    String content
    i pos
    CSVDialect dialect
}

@ csv_reader_new String content → *CSVReader {
    : *CSVReader r # *CSVReader ( nurl_malloc Z CSVReader )
    = . r content ( string_from ( string_data content ) )
    = . r pos 0
    = . r dialect ( csv_dialect_default )
    ^ r
}

@ csv_reader_new_dialect String content CSVDialect dia → *CSVReader {
    : *CSVReader r # *CSVReader ( nurl_malloc Z CSVReader )
    = . r content ( string_from ( string_data content ) )
    = . r pos 0
    = . r dialect dia
    ^ r
}

@ csv_reader_free * CSVReader r → v {
    ( string_free . r content )
    ( nurl_free r )
}

@ csv_reader_next * CSVReader r → ?( Vec String ) {
    : i clen ( string_len . r content )
    : ~ i p . r pos
    ? >= p clen { ^ @ ?( Vec String ) { F # ( Vec String ) 0 } } {}

    : *u cd # *u ( string_data . r content )
    : i delim . . r dialect delimiter
    : i quote . . r dialect quote_char

    : ( Vec String ) row ( vec_with_cap [String] 8 )
    : ~ b in_row T

    ~ in_row {
        : ~ i cell_off 0
        : ~ i cell_len 0
        : ~ b is_quoted F

        ? & != quote 0 < p clen {
            ? == # i . cd p quote { = is_quoted T } {}
        } {}

        ? is_quoted {
            = p + p 1  // skip opening quote
            : i scan_start p
            : String cell_buf ( string_new )
            : ~ b had_escape F
            : ~ b cq_done F
            ~ ! cq_done {
                ? >= p clen { = cq_done T } {
                    : i c # i . cd p
                    ? == c quote {
                        : i p1 + p 1
                        : ~ b is_escape F
                        ? < p1 clen {
                            ? == # i . cd p1 quote { = is_escape T } {}
                        } {}
                        ? is_escape {
                            ( string_push_char cell_buf quote )
                            = p + p 2
                            = had_escape T
                        } { = cq_done T }
                    } {
                        ( string_push_char cell_buf c )
                        = p + p 1
                    }
                }
            }
            ( vec_push [String] row cell_buf )
            ? < p clen {
                ? == # i . cd p quote { = p + p 1 } {}
            } {}
        } {
            : i field_start p
            : ~ b done F
            ~ ! done {
                ? >= p clen { = done T } {
                    : i c # i . cd p
                    ? == c delim { = done T } {
                        ? | == c 10 == c 13 { = done T } { = p + p 1 }
                    }
                }
            }
            ( vec_push [String] row ( string_from_bytes # *u + # i cd field_start - p field_start ) )
        }

        : ~ b sep_found F
        ~ & ! sep_found < p clen {
            : i c # i . cd p
            ? == c delim {
                = p + p 1
                = sep_found T
            } {
                ? == c 10 {
                    = p + p 1
                    = in_row F
                    = sep_found T
                } {
                    ? == c 13 {
                        = p + p 1
                        ? < p clen {
                            : i nx # i . cd p
                            ? == nx 10 { = p + p 1 } {}
                        } {}
                        = in_row F
                        = sep_found T
                    } { = p + p 1 }
                }
            }
        }
        ? >= p clen { = in_row F } {}
    }

    = . r pos p
    // Drop solitary empty trailing record
    ? == ( vec_len [String] row ) 1 {
        : *String rp ( vec_data [String] row )
        ? == ( string_len . rp 0 ) 0 {
            ( __csv_row_free row )
            ^ ( csv_reader_next r )
        } {}
    } {}

    ^ @ ?( Vec String ) { T row }
}

// ── CSVDictReader ──────────────────────────────────────────────────

: CSVDictReader {
    ( Vec String ) header
    * CSVReader reader
}

@ csv_dict_reader_new * CSVReader r → *CSVDictReader {
    : ?( Vec String ) h_opt ( csv_reader_next r )
    : ( Vec String ) h ( opt_unwrap_or [( Vec String )] h_opt ( vec_new [String] ) )
    : *CSVDictReader dr # *CSVDictReader ( nurl_malloc Z CSVDictReader )
    = . dr header h
    = . dr reader r
    ^ dr
}

@ csv_dict_reader_next * CSVDictReader dr → ?( HashMap s String ) {
    : *CSVReader r . dr reader
    : ?( Vec String ) row_opt ( csv_reader_next r )
    ?? row_opt {
        T row → {
            : ( HashMap s String ) map ( map_new [s String] )
            : ( Vec String ) hdr . dr header
            : i n_header ( vec_len [String] hdr )
            : i n_row ( vec_len [String] row )
            : i n ? < n_header n_row n_header n_row
            : ~ i i 0
            ~ < i n {
                : ?String k_opt ( vec_get [String] hdr i )
                : ?String v_opt ( vec_get [String] row i )
                ?? k_opt {
                    T k → {
                        ?? v_opt {
                            T v → {
                                ( map_set [s String] map ( string_data k ) ( string_from ( string_data v ) ) \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
                            }
                            F → {}
                        }
                    }
                    F → {}
                }
                = i + i 1
            }
            ( __csv_row_free row )
            ^ @ ?( HashMap s String ) { T map }
        }
        F → { ^ @ ?( HashMap s String ) { F # ( HashMap s String ) 0 } }
    }
}

@ csv_dict_reader_free * CSVDictReader dr → v {
    ( __csv_row_free . dr header )
    ( csv_reader_free . dr reader )
    ( nurl_free dr )
}

// ── CSVWriter (per-row stream over a FILE*) ───────────────────────

: CSVWriter {
    * v f
    i delimiter
    b crlf_terminator
    i quote_char
}

@ csv_writer_new s path → *CSVWriter {
    : *CSVWriter w # *CSVWriter ( nurl_malloc Z CSVWriter )
    = . w f ( nurl_file_open path `w` )
    = . w delimiter 44
    = . w crlf_terminator F
    = . w quote_char 34
    ^ w
}

@ csv_writer_new_with s path CSVDialect dia → *CSVWriter {
    : *CSVWriter w # *CSVWriter ( nurl_malloc Z CSVWriter )
    = . w f ( nurl_file_open path `w` )
    = . w delimiter . dia delimiter
    = . w crlf_terminator . dia crlf_terminator
    = . w quote_char . dia quote_char
    ^ w
}

@ __csv_write_field * v file s data i delim i quote → v {
    : ~ b need_quote F
    ? != quote 0 {
        : i len ( nurl_str_len data )
        : ~ i i 0
        ~ & ! need_quote < i len {
            : i c ( nurl_str_get data i )
            ? | | | == c delim == c quote == c 10 == c 13 { = need_quote T } {}
            = i + i 1
        }
    } {}

    ? need_quote {
        ( nurl_file_write_byte file quote )
        : i len ( nurl_str_len data )
        : ~ i i 0
        ~ < i len {
            : i c ( nurl_str_get data i )
            ? == c quote { ( nurl_file_write_byte file quote ) } {}
            ( nurl_file_write_byte file c )
            = i + i 1
        }
        ( nurl_file_write_byte file quote )
    } {
        ( nurl_file_write file data )
    }
}

@ csv_writer_writerow * CSVWriter w ( Vec String ) row → v {
    : *v file . w f
    : i n ( vec_len [String] row )
    : i delim . w delimiter
    : i quote . w quote_char

    : *u sep_buf # *u ( nurl_malloc 2 )
    = . sep_buf 0 # u delim
    = . sep_buf 1 # u 0
    : s sep # s sep_buf

    : ~ i i 0
    ~ < i n {
        : ?String s ( vec_get [String] row i )
        ?? s {
            T ss → ( __csv_write_field file ( string_data ss ) delim quote )
            F → {}
        }
        ? < i - n 1 { ( nurl_file_write file sep ) } {}
        = i + i 1
    }
    ? . w crlf_terminator { ( nurl_file_write file `\r\n` ) } { ( nurl_file_write file `\n` ) }
    ( nurl_free sep_buf )
}

@ csv_writer_close * CSVWriter w → v {
    ( nurl_file_close . w f )
    ( nurl_free w )
}

// ── CSVDictWriter ──────────────────────────────────────────────────

: CSVDictWriter {
    ( Vec String ) fieldnames
    * CSVWriter writer
}

@ csv_dict_writer_new * CSVWriter w ( Vec String ) fieldnames → *CSVDictWriter {
    : *CSVDictWriter dw # *CSVDictWriter ( nurl_malloc Z CSVDictWriter )
    = . dw fieldnames fieldnames
    = . dw writer w
    ^ dw
}

@ csv_dict_writer_writeheader * CSVDictWriter dw → v {
    ( csv_writer_writerow . dw writer . dw fieldnames )
}

@ csv_dict_writer_writerow * CSVDictWriter dw ( HashMap s String ) row → v {
    : ( Vec String ) fns . dw fieldnames
    : *CSVWriter wr . dw writer
    : i n ( vec_len [String] fns )
    : ( Vec String ) line ( vec_with_cap [String] n )
    : ~ i i 0
    ~ < i n {
        : ?String k_opt ( vec_get [String] fns i )
        ?? k_opt {
            T k → {
                : ?String v_opt ( map_get [s String] row ( string_data k ) \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
                ?? v_opt {
                    T v → ( vec_push [String] line ( string_from ( string_data v ) ) )
                    F → ( vec_push [String] line ( string_new ) )
                }
            }
            F → ( vec_push [String] line ( string_new ) )
        }
        = i + i 1
    }
    ( csv_writer_writerow wr line )
    ( __csv_row_free line )
}

@ csv_dict_writer_close * CSVDictWriter dw → v {
    ( __csv_row_free . dw fieldnames )
    ( csv_writer_close . dw writer )
    ( nurl_free dw )
}

// ── CSVTable: arena-backed bulk container ──────────────────────────

: CSVTable {
    String content
    ( Vec String ) headers
    ( Vec i ) flat_cells  // [off0,len0,off1,len1,...]
    ( Vec i ) row_starts  // cell-index of row r
    ( Vec i ) row_lens  // cell count of row r
    ( Vec u ) escape_buf  // unescaped quoted-cell bytes
    // off ≥ 0 → into content[]
    // off  < 0 → into escape_buf[-off-1..]
}

@ csv_table_new → *CSVTable {
    : *CSVTable t # *CSVTable ( nurl_malloc Z CSVTable )
    = . t content ( string_new )
    = . t headers ( vec_new [String] )
    = . t flat_cells ( vec_new [i] )
    = . t row_starts ( vec_new [i] )
    = . t row_lens ( vec_new [i] )
    = . t escape_buf ( vec_new [u] )
    ^ t
}

@ csv_table_free * CSVTable t → v {
    ( string_free . t content )
    ( __csv_row_free . t headers )
    ( vec_free [i] . t flat_cells )
    ( vec_free [i] . t row_starts )
    ( vec_free [i] . t row_lens )
    ( vec_free [u] . t escape_buf )
    ( nurl_free t )
}

@ csv_table_n_rows * CSVTable t → i { ^ ( vec_len [i] . t row_starts ) }

@ csv_table_n_cols * CSVTable t → i { ^ ( vec_len [String] . t headers ) }

@ csv_table_n_cells_in_row * CSVTable t i row → i {
    : i nr ( csv_table_n_rows t )
    ? | < row 0 >= row nr { ^ 0 } {}
    : *i rlp ( vec_data [i] . t row_lens )
    ^ . rlp row
}

// Borrowed `s` view of (row, col). NOT NUL-terminated; pair with
// csv_table_view_len. `# s 0` (NULL) when (row, col) is out of range.
//
// Cells whose underlying offset is < 0 came from a quoted field with
// embedded `""` escapes — the materialized bytes live in
// `t.escape_buf` at index `-off - 1`. Unquoted cells and quoted cells
// without escapes both stay zero-copy into `t.content`.
@ csv_table_view * CSVTable t i row i col → s {
    : i nr ( csv_table_n_rows t )
    ? | < row 0 >= row nr { ^ # s 0 } {}
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : i row_first . rsp row
    : i row_count . rlp row
    ? | < col 0 >= col row_count { ^ # s 0 } {}
    : i cell_idx + row_first col
    : *i fcp ( vec_data [i] . t flat_cells )
    : i off . fcp * cell_idx 2
    ? >= off 0 {
        : *u cd # *u ( string_data . t content )
        ^ # s + # i cd off
    } {}
    : i esc_off - 0 + off 1
    : *u eb ( vec_data [u] . t escape_buf )
    ^ # s + # i eb esc_off
}

@ csv_table_view_len * CSVTable t i row i col → i {
    : i nr ( csv_table_n_rows t )
    ? | < row 0 >= row nr { ^ 0 } {}
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : i row_first . rsp row
    : i row_count . rlp row
    ? | < col 0 >= col row_count { ^ 0 } {}
    : i cell_idx + row_first col
    : *i fcp ( vec_data [i] . t flat_cells )
    ^ . fcp + * cell_idx 2 1
}

// Owned String copy of (row, col). One per call; caller frees.
@ csv_table_get * CSVTable t i row i col → ?String {
    : s view ( csv_table_view t row col )
    ? == # i view 0 { ^ @ ?String { F # String 0 } } {}
    : i len ( csv_table_view_len t row col )
    ^ @ ?String { T ( string_from_bytes # *u view len ) }
}

// Index of a column by header name (case-sensitive). None if absent.
@ csv_table_col_index * CSVTable t s name → ?i {
    : ( Vec String ) hs . t headers
    : i n ( vec_len [String] hs )
    : *String hp ( vec_data [String] hs )
    : ~ i i 0
    ~ < i n {
        : String h . hp i
        ? == ( nurl_str_eq ( string_data h ) name ) 1 {
            ^ @ ?i { T i }
        } {}
        = i + i 1
    }
    ^ @ ?i { F 0 }
}

// Borrowed `s` view by column name. `# s 0` (NULL) on miss.
@ csv_table_view_by_name * CSVTable t i row s name → s {
    : ?i col_opt ( csv_table_col_index t name )
    ?? col_opt {
        T col → { ^ ( csv_table_view t row col ) }
        F → { ^ # s 0 }
    }
}

// Owned String by column name. None if column missing or row out of
// range. Caller frees.
@ csv_table_get_by_name * CSVTable t i row s name → ?String {
    : ?i col_opt ( csv_table_col_index t name )
    ?? col_opt {
        T col → { ^ ( csv_table_get t row col ) }
        F → { ^ @ ?String { F # String 0 } }
    }
}

// ── Typed column extraction ────────────────────────────────────────
//
// One-shot single-column type coercion. Returns an owned Vec[i] /
// Vec[f] indexed by ORIGINAL row order — same indexing as the row
// argument to a `csv_table_filter` predicate. Caller frees with the
// usual `vec_free [i] / [f]`.
//
// Use case: hot per-row predicates. Caller pre-parses the numeric
// column once, then the predicate does a single load instead of
// `nurl_parse_float_range` per call. Lifecycle: extract → use
// inside the filter closure → free.
//
// Unparseable cells coerce to 0 / 0.0 (matches `csv_table_sort_by_*`
// semantics). Out-of-range `col` yields a Vec of zeros (no error).

@ csv_table_extract_col_i64 * CSVTable t i col → ( Vec i ) {
    : i n ( csv_table_n_rows t )
    : ( Vec i ) out ( vec_with_cap [i] n )
    ? <= n 0 { ^ out } {}
    ( vec_reserve [i] out n )
    : *i outp ( vec_data [i] out )
    : *u cd # *u ( string_data . t content )
    : *u eb ( vec_data [u] . t escape_buf )
    : *i fcp ( vec_data [i] . t flat_cells )
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : b col_neg < col 0
    : ~ i ri 0
    ~ < ri n {
        : ~ i v 0
        ? col_neg {} {
            : i row_count . rlp ri
            ? < col row_count {
                : i row_first . rsp ri
                : i cell_idx + row_first col
                : i off . fcp * cell_idx 2
                : i len . fcp + * cell_idx 2 1
                ? > len 0 {
                    : ~ s src # s 0
                    ? >= off 0 { = src # s + # i cd off }
                    { = src # s + # i eb - 0 + off 1 }
                    = v ( nurl_parse_int_range src len )
                } {}
            } {}
        }
        = . outp ri v
        = ri + ri 1
    }
    : b _r ( vec_set_len [i] out n )
    ^ out
}

@ csv_table_extract_col_f64 * CSVTable t i col → ( Vec f ) {
    : i n ( csv_table_n_rows t )
    : ( Vec f ) out ( vec_with_cap [f] n )
    ? <= n 0 { ^ out } {}
    ( vec_reserve [f] out n )
    : *f outp ( vec_data [f] out )
    : *u cd # *u ( string_data . t content )
    : *u eb ( vec_data [u] . t escape_buf )
    : *i fcp ( vec_data [i] . t flat_cells )
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : b col_neg < col 0
    : ~ i ri 0
    ~ < ri n {
        : ~ f v 0.0
        ? col_neg {} {
            : i row_count . rlp ri
            ? < col row_count {
                : i row_first . rsp ri
                : i cell_idx + row_first col
                : i off . fcp * cell_idx 2
                : i len . fcp + * cell_idx 2 1
                ? > len 0 {
                    : ~ s src # s 0
                    ? >= off 0 { = src # s + # i cd off }
                    { = src # s + # i eb - 0 + off 1 }
                    = v ( nurl_parse_float_range src len )
                } {}
            } {}
        }
        = . outp ri v
        = ri + ri 1
    }
    : b _r ( vec_set_len [f] out n )
    ^ out
}

// ── Parsing ────────────────────────────────────────────────────────
//
// Single-pass arena parser. Cells are written as (offset, length)
// pairs into `flat_cells` directly via raw pointer arithmetic — each
// `vec_push` would cost two unavoidable FFI calls (`nurl_peek` ctl
// read + `nurl_poke` len bump) and `runtime.o` is built without LTO,
// so those calls don't inline. By calling `vec_reserve` + `vec_data`
// once per ROW (~2 FFI × n_rows) and doing cell stores as raw memory
// writes, we trade ~32 M FFI calls per million rows for ~5 M.
//
// Earlier failed approaches kept as cautionary notes (helpers live in
// `stdlib/runtime.c` for the future typed-schema reader):
//   • bulk C parser `nurl_csv_parse_arena`: large up-front contiguous
//     reservation page-faulted across the buffer.
//   • per-row C scanner `nurl_csv_scan_row_pairs`: 1 M FFI calls +
//     transfer copy from C buffer to flat_cells via vec_push brought
//     back the per-cell FFI cost.
@ __csv_parse_content * CSVTable t CSVDialect dia → v {
    : *u cd # *u ( string_data . t content )
    : i clen ( string_len . t content )
    : i delim . dia delimiter
    : i quote . dia quote_char

    // Worst-case slack per row, so the row's writes never overrun
    // the buffer between reserve calls. 256 cells/row is far above
    // any realistic CSV.
    : i max_row_i64 * 256 2

    // Pre-size the row index vectors. One pair (start, len) per row.
    : i row_est / clen 100
    ? < row_est 16 { = row_est 16 } {}
    ( vec_reserve [i] . t row_starts row_est )
    ( vec_reserve [i] . t row_lens row_est )

    : ~ i row_w 0  // committed body-row count

    : ~ i pos 0
    : ~ b first_row T

    // Fast path: when the dialect has quoting disabled OR the entire
    // content has no quote byte, each row goes through the SSE2-
    // vectorised `nurl_csv_scan_row_pairs` (16 bytes/iter looking for
    // delim/CR/LF simultaneously) instead of the per-byte NURL loop
    // below. The C scanner writes (off, len) pairs DIRECTLY into the
    // flat_cells buffer via the pre-fetched fcp_w pointer — no copy.
    // One quote-detection memchr (~5 ms for 100 MB) gates the path.

    ~ < pos clen {
        : i row_first_i64 ( vec_len [i] . t flat_cells )
        : i row_first_cell / row_first_i64 2

        // Reserve once per row; if cap already suffices vec_reserve
        // is a fast no-op (one ctl read). We re-arm row_starts /
        // row_lens too so a single grow per ~2× row budget keeps
        // their pointers stable for the inner body of this row.
        ( vec_reserve [i] . t flat_cells + row_first_i64 max_row_i64 )
        ( vec_reserve [i] . t row_starts + row_w 1 )
        ( vec_reserve [i] . t row_lens + row_w 1 )
        : *i fcp ( vec_data [i] . t flat_cells )
        : *i rsp_w ( vec_data [i] . t row_starts )
        : *i rlp_w ( vec_data [i] . t row_lens )

        // Per-cell scanner. Each iteration produces ONE cell pair
        // (cell_off, cell_len) and advances past one trailing
        // delim / CR / LF / EOF.  cell_off ≥ 0 means the bytes live
        // in `cd[off..off+len]`; cell_off < 0 means the bytes were
        // unescaped into `escape_buf[-off-1..]` (only happens for
        // quoted cells containing `""` escapes).
        : ~ i p pos
        : ~ i wi row_first_i64
        : ~ b in_row T
        ~ in_row {
            : ~ i cell_off 0
            : ~ i cell_len 0
            : ~ b is_quoted F

            ? & != quote 0 < p clen {
                ? == # i . cd p quote { = is_quoted T } {}
            } {}

            ? is_quoted {
                = p + p 1  // skip opening quote
                : i scan_start p
                : ~ b had_escape F
                : ~ i esc_buf_start 0
                : ~ b cq_done F
                ~ ! cq_done {
                    ? >= p clen { = cq_done T } {
                        : i c # i . cd p
                        ? == c quote {
                            : i p1 + p 1
                            : ~ b is_escape F
                            ? < p1 clen {
                                ? == # i . cd p1 quote { = is_escape T } {}
                            } {}
                            ? is_escape {
                                ? ! had_escape {
                                    : i eb_len ( vec_len [u] . t escape_buf )
                                    = esc_buf_start eb_len
                                    : i pre_len - p scan_start
                                    ? > pre_len 0 {
                                        ( vec_reserve [u] . t escape_buf + eb_len + pre_len 16 )
                                        : *u ebw ( vec_data [u] . t escape_buf )
                                        : ~ i j 0
                                        ~ < j pre_len {
                                            = . ebw + eb_len j # u . cd + scan_start j
                                            = j + j 1
                                        }
                                        : b _r ( vec_set_len [u] . t escape_buf + eb_len pre_len )
                                    } {}
                                    = had_escape T
                                } {}
                                ( vec_push [u] . t escape_buf # u quote )
                                = p + p 2
                            } { = cq_done T }
                        } {
                            ? had_escape {
                                ( vec_push [u] . t escape_buf # u c )
                            } {}
                            = p + p 1
                        }
                    }
                }
                ? had_escape {
                    : i eb_end ( vec_len [u] . t escape_buf )
                    = cell_off - 0 + esc_buf_start 1
                    = cell_len - eb_end esc_buf_start
                } {
                    = cell_off scan_start
                    = cell_len - p scan_start
                }
                // Skip closing quote if we landed on one.
                ? < p clen {
                    ? == # i . cd p quote { = p + p 1 } {}
                } {}
            } {
                // Unquoted cell: SSE2-vectorised C scanner finds the
                // next delim / '\n' / '\r' in 16-byte chunks. With
                // LTO the FFI inlines completely — net ~5-10 ns per
                // cell vs the ~20 ns NURL bytecode scalar loop on
                // typical 10-byte cells, ~50 ns saved on wide cells.
                // Drops load by ~30 ms on 1 M-row × 8-col CSV.
                : i field_start p
                : i scan_off ( nurl_csv_scan_cell # s + # i cd p - clen p delim )
                = p + p scan_off
                = cell_off field_start
                = cell_len - p field_start
            }

            = . fcp wi cell_off
            = . fcp + wi 1 cell_len
            = wi + wi 2

            // Advance past separator. Bonus bytes between a closing
            // quote and the next separator are silently consumed.
            : ~ b sep_found F
            ~ & ! sep_found < p clen {
                : i c # i . cd p
                ? == c delim {
                    = p + p 1
                    = sep_found T
                } {
                    ? == c 10 {
                        = p + p 1
                        = in_row F
                        = sep_found T
                    } {
                        ? == c 13 {
                            = p + p 1
                            ? < p clen {
                                : i nx # i . cd p
                                ? == nx 10 { = p + p 1 } {}
                            } {}
                            = in_row F
                            = sep_found T
                        } { = p + p 1 }
                    }
                }
            }
            ? >= p clen { = in_row F } {}
        }

        : i n_cells / - wi row_first_i64 2
        : b is_phantom & == n_cells 1 == . fcp + row_first_i64 1 0

        ? & is_phantom >= p clen {
            // drop phantom — don't commit
            = pos p
        } {
            ? first_row {
                ( __csv_row_free . t headers )
                = . t headers ( vec_with_cap [String] n_cells )
                : ~ i k 0
                ~ < k n_cells {
                    : i off . fcp + row_first_i64 * k 2
                    : i len . fcp + + row_first_i64 * k 2 1
                    : ~ * u src # *u 0
                    ? >= off 0 {
                        = src # *u + # i cd off
                    } {
                        : i esc_off - 0 + off 1
                        : *u ebh ( vec_data [u] . t escape_buf )
                        = src # *u + # i ebh esc_off
                    }
                    ( vec_push [String] . t headers ( string_from_bytes src len ) )
                    = k + k 1
                }
                // header slots stay unused; row_first_i64 was the
                // pre-write len, so flat_cells len has not advanced.
                = first_row F
            } {
                : b _r ( vec_set_len [i] . t flat_cells wi )
                = . rsp_w row_w row_first_cell
                = . rlp_w row_w n_cells
                = row_w + row_w 1
            }
            = pos p
        }
    }

    // Commit raw row counters into the underlying Vec[i]'s len field.
    : b _r1 ( vec_set_len [i] . t row_starts row_w )
    : b _r2 ( vec_set_len [i] . t row_lens row_w )
}

// Build a table from a freshly-allocated String. Consumes `content`
// (the table takes ownership of the buffer).
@ csv_table_from_string String content → *CSVTable {
    : *CSVTable t ( csv_table_new )
    ( string_free . t content )
    = . t content content
    ( __csv_parse_content t ( csv_dialect_default ) )
    ^ t
}

@ csv_table_from_string_dialect String content CSVDialect dia → *CSVTable {
    : *CSVTable t ( csv_table_new )
    ( string_free . t content )
    = . t content content
    ( __csv_parse_content t dia )
    ^ t
}

// Load a CSV file using the default dialect. Returns NULL on read
// failure (use file_exists / read_file separately for diagnostics).
@ csv_table_load s path → *CSVTable {
    : !String IoErr res ( read_file path )
    ?? res {
        F e → { ^ # *CSVTable 0 }
        T content → { ^ ( csv_table_from_string content ) }
    }
}

@ csv_table_load_dialect s path CSVDialect dia → *CSVTable {
    : !String IoErr res ( read_file path )
    ?? res {
        F e → { ^ # *CSVTable 0 }
        T content → { ^ ( csv_table_from_string_dialect content dia ) }
    }
}

// ── Writing ────────────────────────────────────────────────────────

// Internal: write a single cell to `fh`, applying RFC 4180 quoting if
// the cell contains delim, quote_char, CR, or LF. Cells whose bytes
// live in `escape_buf` (off < 0, only produced by the parser for
// cells that contained `""` escapes) are always emitted quoted —
// they had embedded quotes by definition.
@ __csv_write_cell * v fh * u src i len i delim i quote → v {
    ? == quote 0 {
        ( nurl_file_write_range fh # s src len )
    } {
        : ~ b needs_quote F
        : ~ i j 0
        ~ & ! needs_quote < j len {
            : i c # i . src j
            ? == c delim { = needs_quote T } {
                ? == c quote { = needs_quote T } {
                    ? == c 10 { = needs_quote T } {
                        ? == c 13 { = needs_quote T } { = j + j 1 }
                    }
                }
            }
        }
        ? ! needs_quote {
            ( nurl_file_write_range fh # s src len )
        } {
            ( nurl_file_write_byte fh quote )
            : ~ i k 0
            : ~ i run_start 0
            ~ < k len {
                : i c # i . src k
                ? == c quote {
                    ? > k run_start {
                        : *u rp # *u + # i src run_start
                        ( nurl_file_write_range fh # s rp - k run_start )
                    } {}
                    ( nurl_file_write_byte fh quote )
                    ( nurl_file_write_byte fh quote )
                    = k + k 1
                    = run_start k
                } { = k + k 1 }
            }
            ? > len run_start {
                : *u rp # *u + # i src run_start
                ( nurl_file_write_range fh # s rp - len run_start )
            } {}
            ( nurl_file_write_byte fh quote )
        }
    }
}

// Write the table to `path` using `dia`. Returns T on success, F if
// the file could not be opened. Cells are emitted as raw byte ranges
// from `content` (zero-copy) unless RFC 4180 quoting is required.
@ csv_table_write * CSVTable t s path CSVDialect dia → b {
    : *v fh ( nurl_file_open path `w` )
    ? == # i fh 0 { ^ F } {}
    : i delim . dia delimiter
    : b crlf . dia crlf_terminator
    : i quote . dia quote_char

    // headers
    : ( Vec String ) hs . t headers
    : i nh ( vec_len [String] hs )
    : *String hp ( vec_data [String] hs )
    : ~ i hi 0
    ~ < hi nh {
        : String h . hp hi
        : *u hsrc # *u ( string_data h )
        : i hlen ( string_len h )
        ( __csv_write_cell fh hsrc hlen delim quote )
        ? < hi - nh 1 { ( nurl_file_write_byte fh delim ) } {}
        = hi + hi 1
    }
    ? crlf { ( nurl_file_write_byte fh 13 ) } {}
    ( nurl_file_write_byte fh 10 )

    : i nr ( csv_table_n_rows t )
    : *u cd # *u ( string_data . t content )
    : *u eb ( vec_data [u] . t escape_buf )
    : *i fcp ( vec_data [i] . t flat_cells )
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : ~ i ri 0
    ~ < ri nr {
        : i row_first . rsp ri
        : i row_count . rlp ri
        : ~ i ci 0
        ~ < ci row_count {
            : i cell_idx + row_first ci
            : i off . fcp * cell_idx 2
            : i len . fcp + * cell_idx 2 1
            : ~ * u sp # *u 0
            ? >= off 0 { = sp # *u + # i cd off }
            { = sp # *u + # i eb - 0 + off 1 }
            ( __csv_write_cell fh sp len delim quote )
            ? < ci - row_count 1 { ( nurl_file_write_byte fh delim ) } {}
            = ci + ci 1
        }
        ? crlf { ( nurl_file_write_byte fh 13 ) } {}
        ( nurl_file_write_byte fh 10 )
        = ri + ri 1
    }
    ( nurl_file_close fh )
    ^ T
}

// ── Sort / filter / truncate ───────────────────────────────────────
//
// Sort and filter are O(n_rows) in arena-land — they only permute or
// truncate the (row_starts, row_lens) parallel vecs. flat_cells and
// content are never touched, never copied.

// Permute (row_starts, row_lens) in place by `order`.
@ __csv_permute_rows * CSVTable t ( Vec i ) order → v {
    : i n ( vec_len [i] order )
    : ( Vec i ) new_starts ( vec_with_cap [i] n )
    : ( Vec i ) new_lens ( vec_with_cap [i] n )
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : *i op ( vec_data [i] order )
    : ~ i k 0
    ~ < k n {
        : i src . op k
        ( vec_push [i] new_starts . rsp src )
        ( vec_push [i] new_lens . rlp src )
        = k + k 1
    }
    ( vec_free [i] . t row_starts )
    ( vec_free [i] . t row_lens )
    = . t row_starts new_starts
    = . t row_lens new_lens
}

// Numeric int sort: 1 parse per row + i64 sort over a permutation.
// Parses cell at `col` as a signed decimal integer; unparseable cells
// compare as 0.
@ csv_table_sort_by_int * CSVTable t i col b asc → v {
    : i n ( csv_table_n_rows t )
    ? > n 1 {
        : b ascending asc
        : ( Vec i ) keys ( vec_with_cap [i] n )
        : *u cd # *u ( string_data . t content )
        : *u eb ( vec_data [u] . t escape_buf )
        : *i fcp ( vec_data [i] . t flat_cells )
        : *i rsp ( vec_data [i] . t row_starts )
        : *i rlp ( vec_data [i] . t row_lens )
        : ~ i ri 0
        ~ < ri n {
            : i row_first . rsp ri
            : i row_count . rlp ri
            : ~ i v 0
            ? & >= col 0 < col row_count {
                : i cell_idx + row_first col
                : i off . fcp * cell_idx 2
                : i len . fcp + * cell_idx 2 1
                ? > len 0 {
                    : ~ s src # s 0
                    ? >= off 0 { = src # s + # i cd off }
                    { = src # s + # i eb - 0 + off 1 }
                    = v ( nurl_parse_int_range src len )
                } {}
            } {}
            ( vec_push [i] keys v )
            = ri + ri 1
        }

        : ( Vec i ) order ( vec_iota 0 n )
        : *i kp ( vec_data [i] keys )
        ( sort_by [i] order \ i a i b → i {
            : i ka . kp a
            : i kb . kp b
            : i c ( cmp_int ka kb )
            ? ascending { ^ c } { ^ - 0 c }
        } )

        ( __csv_permute_rows t order )
        ( vec_free [i] keys )
        ( vec_free [i] order )
    } {}
}

// Numeric float sort. Unparseable cells compare as 0.0.
@ csv_table_sort_by_float * CSVTable t i col b asc → v {
    : i n ( csv_table_n_rows t )
    ? > n 1 {
        : b ascending asc
        : ( Vec f ) keys ( vec_with_cap [f] n )
        : *u cd # *u ( string_data . t content )
        : *u eb ( vec_data [u] . t escape_buf )
        : *i fcp ( vec_data [i] . t flat_cells )
        : *i rsp ( vec_data [i] . t row_starts )
        : *i rlp ( vec_data [i] . t row_lens )
        : ~ i ri 0
        ~ < ri n {
            : i row_first . rsp ri
            : i row_count . rlp ri
            : ~ f v 0.0
            ? & >= col 0 < col row_count {
                : i cell_idx + row_first col
                : i off . fcp * cell_idx 2
                : i len . fcp + * cell_idx 2 1
                ? > len 0 {
                    : ~ s src # s 0
                    ? >= off 0 { = src # s + # i cd off }
                    { = src # s + # i eb - 0 + off 1 }
                    = v ( nurl_parse_float_range src len )
                } {}
            } {}
            ( vec_push [f] keys v )
            = ri + ri 1
        }

        : ( Vec i ) order ( vec_iota 0 n )
        : *f kp ( vec_data [f] keys )
        ( sort_by [i] order \ i a i b → i {
            : f ka . kp a
            : f kb . kp b
            : i c ( cmp_float ka kb )
            ? ascending { ^ c } { ^ - 0 c }
        } )

        ( __csv_permute_rows t order )
        ( vec_free [f] keys )
        ( vec_free [i] order )
    } {}
}

// String sort by raw bytes (memcmp + tiebreak by length). Out-of-range
// cells sort to the end.
@ csv_table_sort_by_string * CSVTable t i col b asc → v {
    : i n ( csv_table_n_rows t )
    ? > n 1 {
        : b ascending asc
        // Two parallel arrays: per-row byte pointer + length. Avoids
        // the NUL-terminator dance of a borrowed `s`.
        : ( Vec i ) k_off ( vec_with_cap [i] n )
        : ( Vec i ) k_len ( vec_with_cap [i] n )
        : *u cd # *u ( string_data . t content )
        : *i fcp ( vec_data [i] . t flat_cells )
        : *i rsp ( vec_data [i] . t row_starts )
        : *i rlp ( vec_data [i] . t row_lens )
        : ~ i ri 0
        ~ < ri n {
            : i row_first . rsp ri
            : i row_count . rlp ri
            ? & >= col 0 < col row_count {
                : i cell_idx + row_first col
                ( vec_push [i] k_off . fcp * cell_idx 2 )
                ( vec_push [i] k_len . fcp + * cell_idx 2 1 )
            } {
                ( vec_push [i] k_off 0 )
                ( vec_push [i] k_len -1 )  // -1 = sentinel: sort to end
            }
            = ri + ri 1
        }

        : ( Vec i ) order ( vec_iota 0 n )
        : *i kop ( vec_data [i] k_off )
        : *i klp ( vec_data [i] k_len )
        : *u eb ( vec_data [u] . t escape_buf )
        ( sort_by [i] order \ i a i b → i {
            : i la . klp a
            : i lb . klp b
            // Sentinel handling: missing cells sort to the end.
            : ~ b done F
            : ~ i res 0
            ? < la 0 {
                ? < lb 0 { = res 0 = done T } { = res 1 = done T }
            } {
                ? < lb 0 { = res -1 = done T } {}
            }
            ? done { ^ res } {}
            : i oa . kop a
            : i ob . kop b
            : ~ s pa # s 0
            : ~ s pb # s 0
            ? >= oa 0 { = pa # s + # i cd oa }
            { = pa # s + # i eb - 0 + oa 1 }
            ? >= ob 0 { = pb # s + # i cd ob }
            { = pb # s + # i eb - 0 + ob 1 }
            : i c ( nurl_memcmp_lex pa la pb lb )
            ? ascending { ^ c } { ^ - 0 c }
        } )

        ( __csv_permute_rows t order )
        ( vec_free [i] k_off )
        ( vec_free [i] k_len )
        ( vec_free [i] order )
    } {}
}

// Filter in place: keep rows for which `pred` returns T. Predicate
// receives the source table + row index; reads cells via
// csv_table_view / csv_table_view_len (or directly via cached
// data pointers for hot loops — see the per-call HOT-PATH note below).
//
// HOT-PATH PERF NOTE: each `csv_table_view` call internally does
// three `vec_data` FFI calls (rsp, rlp, fcp) — non-inlinable without
// LTO, ~30 ns each. For million-row predicates, prefetch the data
// pointers OUTSIDE the call and capture them into the closure:
//
//     : *i fcp ( vec_data [i] . t flat_cells )
//     : *i rsp ( vec_data [i] . t row_starts )
//     : *i rlp ( vec_data [i] . t row_lens )
//     : *u cd  # *u ( string_data . t content )
//     ( csv_table_filter t \ *CSVTable tt i row → b {
//         : i row_first . rsp row
//         : i cell_idx + row_first MY_COL
//         : i off . fcp * cell_idx 2
//         : i len . fcp + * cell_idx 2 1
//         : *u v # *u + # i cd off
//         ... } )
//
// Pointers are valid for the duration of the filter call: filter only
// rewrites the row index Vecs, never reloads flat_cells/content.
@ csv_table_filter * CSVTable t ( @ b * CSVTable i ) pred → v {
    : i n ( csv_table_n_rows t )
    : ( Vec i ) new_starts ( vec_new [i] )
    : ( Vec i ) new_lens ( vec_new [i] )
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : ~ i ri 0
    ~ < ri n {
        ? ( pred t ri ) {
            ( vec_push [i] new_starts . rsp ri )
            ( vec_push [i] new_lens . rlp ri )
        } {}
        = ri + ri 1
    }
    ( vec_free [i] . t row_starts )
    ( vec_free [i] . t row_lens )
    = . t row_starts new_starts
    = . t row_lens new_lens
}

// ── Typed predicate filters (fast path) ──────────────────────────
//
// `csv_table_filter` (above) takes a NURL closure, dispatches it per
// row, and each cell access pays a per-row arena indirection. For a
// 1 M-row table that's ~150 ms even with all the hot data cached.
//
// `csv_table_filter_float_gt` / `csv_table_filter_str_contains`
// route the entire filter through a tight C inner loop
// (`nurl_csv_filter_*` in runtime.c) — one FFI call total, scalar
// loop running at native speed, no closure dispatch, no per-row
// arena pointer reload. ~10-30 ms for 1 M rows on the same hardware.
//
// Each operates on ONE column. Chain them: the second call sees
// only the survivors of the first (row_starts/row_lens are narrowed
// in place; the underlying arena content / flat_cells stay intact).
//
// Both are no-ops when `col` is out of range. Negative cell offsets
// (`""`-escaped cells in `escape_buf`) are honoured.

@ csv_table_filter_float_gt * CSVTable t i col f threshold → v {
    : i n ( csv_table_n_rows t )
    ? > n 0 {
        : *u cd # *u ( string_data . t content )
        : *u eb ( vec_data [u] . t escape_buf )
        : *i fcp ( vec_data [i] . t flat_cells )
        : *i rsp ( vec_data [i] . t row_starts )
        : *i rlp ( vec_data [i] . t row_lens )
        : i kept ( nurl_csv_filter_float_gt # s cd # s eb fcp rsp rlp n col threshold )
        : b _a ( vec_set_len [i] . t row_starts kept )
        : b _b ( vec_set_len [i] . t row_lens kept )
    } {}
}

@ csv_table_filter_str_contains * CSVTable t i col s needle → v {
    : i n ( csv_table_n_rows t )
    ? > n 0 {
        : i nlen ( nurl_str_len needle )
        : *u cd # *u ( string_data . t content )
        : *u eb ( vec_data [u] . t escape_buf )
        : *i fcp ( vec_data [i] . t flat_cells )
        : *i rsp ( vec_data [i] . t row_starts )
        : *i rlp ( vec_data [i] . t row_lens )
        : i kept ( nurl_csv_filter_str_contains # s cd # s eb fcp rsp rlp n col needle nlen )
        : b _a ( vec_set_len [i] . t row_starts kept )
        : b _b ( vec_set_len [i] . t row_lens kept )
    } {}
}

// In-place truncate to first `n` rows.
@ csv_table_truncate * CSVTable t i n → v {
    : i nr ( csv_table_n_rows t )
    : ~ i keep n
    ? < keep 0 { = keep 0 } {}
    ? < keep nr {
        : b _a ( vec_set_len [i] . t row_starts keep )
        : b _b ( vec_set_len [i] . t row_lens keep )
    } {}
}

// ── Find / count ───────────────────────────────────────────────────

// First row whose cell at `col` matches `target` byte-for-byte. None
// if no match.
@ csv_table_find_first * CSVTable t i col s target → ?i {
    : i nr ( csv_table_n_rows t )
    : i tlen ( nurl_str_len target )
    : *u cd # *u ( string_data . t content )
    : *u eb ( vec_data [u] . t escape_buf )
    : *i fcp ( vec_data [i] . t flat_cells )
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : ~ i ri 0
    ~ < ri nr {
        : i row_first . rsp ri
        : i row_count . rlp ri
        ? & >= col 0 < col row_count {
            : i cell_idx + row_first col
            : i off . fcp * cell_idx 2
            : i len . fcp + * cell_idx 2 1
            ? == len tlen {
                : ~ s sp # s 0
                ? >= off 0 { = sp # s + # i cd off }
                { = sp # s + # i eb - 0 + off 1 }
                ? == ( nurl_memcmp_lex sp len target tlen ) 0 {
                    ^ @ ?i { T ri }
                } {}
            } {}
        } {}
        = ri + ri 1
    }
    ^ @ ?i { F 0 }
}

// All row indices whose cell at `col` matches `target`. Caller frees
// the returned Vec.
@ csv_table_find_all * CSVTable t i col s target → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i nr ( csv_table_n_rows t )
    : i tlen ( nurl_str_len target )
    : *u cd # *u ( string_data . t content )
    : *u eb ( vec_data [u] . t escape_buf )
    : *i fcp ( vec_data [i] . t flat_cells )
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : ~ i ri 0
    ~ < ri nr {
        : i row_first . rsp ri
        : i row_count . rlp ri
        ? & >= col 0 < col row_count {
            : i cell_idx + row_first col
            : i off . fcp * cell_idx 2
            : i len . fcp + * cell_idx 2 1
            ? == len tlen {
                : ~ s sp # s 0
                ? >= off 0 { = sp # s + # i cd off }
                { = sp # s + # i eb - 0 + off 1 }
                ? == ( nurl_memcmp_lex sp len target tlen ) 0 {
                    ( vec_push [i] out ri )
                } {}
            } {}
        } {}
        = ri + ri 1
    }
    ^ out
}

// Count rows whose cell at `col` equals `target`.
@ csv_table_count_where * CSVTable t i col s target → i {
    : ~ i count 0
    : i nr ( csv_table_n_rows t )
    : i tlen ( nurl_str_len target )
    : *u cd # *u ( string_data . t content )
    : *u eb ( vec_data [u] . t escape_buf )
    : *i fcp ( vec_data [i] . t flat_cells )
    : *i rsp ( vec_data [i] . t row_starts )
    : *i rlp ( vec_data [i] . t row_lens )
    : ~ i ri 0
    ~ < ri nr {
        : i row_first . rsp ri
        : i row_count . rlp ri
        ? & >= col 0 < col row_count {
            : i cell_idx + row_first col
            : i off . fcp * cell_idx 2
            : i len . fcp + * cell_idx 2 1
            ? == len tlen {
                : ~ s sp # s 0
                ? >= off 0 { = sp # s + # i cd off }
                { = sp # s + # i eb - 0 + off 1 }
                ? == ( nurl_memcmp_lex sp len target tlen ) 0 {
                    = count + count 1
                } {}
            } {}
        } {}
        = ri + ri 1
    }
    ^ count
}

// ── Project ────────────────────────────────────────────────────────

// New CSVTable containing only the columns named in `cols` (in the
// given order). Missing column names are silently skipped. Cells are
// materialized into a fresh content buffer via the writer + parser —
// O(n_rows × n_selected_cols) bytes copied.
@ csv_table_select_cols * CSVTable src ( Vec String ) cols → *CSVTable {
    : i ncols ( vec_len [String] cols )
    : ( Vec i ) idx ( vec_with_cap [i] ncols )
    : *String cp ( vec_data [String] cols )
    : ~ i ci 0
    ~ < ci ncols {
        : String name . cp ci
        : ?i col_opt ( csv_table_col_index src ( string_data name ) )
        ?? col_opt {
            T col → ( vec_push [i] idx col )
            F → {}
        }
        = ci + ci 1
    }
    : i nidx ( vec_len [i] idx )
    : *i ip ( vec_data [i] idx )

    // Emit a new CSV (header + body) using the default dialect, then
    // parse it back into a fresh table. This reuses the writer's
    // RFC 4180 quoting and the arena parser — straightforward and
    // correct, at the cost of one full byte copy.
    : String buf ( string_new )
    : CSVDialect dia ( csv_dialect_default )
    : i delim . dia delimiter
    : i quote . dia quote_char

    // headers
    : ( Vec String ) hs . src headers
    : ~ i hi 0
    ~ < hi nidx {
        : i sc . ip hi
        : ?String h_opt ( vec_get [String] hs sc )
        ?? h_opt {
            T h → ( __csv_buf_write_cell buf ( string_data h ) ( string_len h ) delim quote )
            F → {}
        }
        ? < hi - nidx 1 { ( string_push_char buf delim ) } {}
        = hi + hi 1
    }
    ( string_push_char buf 10 )

    : i nr ( csv_table_n_rows src )
    : *u cd # *u ( string_data . src content )
    : *u eb ( vec_data [u] . src escape_buf )
    : *i fcp ( vec_data [i] . src flat_cells )
    : *i rsp ( vec_data [i] . src row_starts )
    : *i rlp ( vec_data [i] . src row_lens )
    : ~ i ri 0
    ~ < ri nr {
        : i row_first . rsp ri
        : i row_count . rlp ri
        : ~ i j 0
        ~ < j nidx {
            : i sc . ip j
            ? & >= sc 0 < sc row_count {
                : i cell_idx + row_first sc
                : i off . fcp * cell_idx 2
                : i len . fcp + * cell_idx 2 1
                : ~ * u sp # *u 0
                ? >= off 0 { = sp # *u + # i cd off }
                { = sp # *u + # i eb - 0 + off 1 }
                ( __csv_buf_write_cell buf # s sp len delim quote )
            } {}
            ? < j - nidx 1 { ( string_push_char buf delim ) } {}
            = j + j 1
        }
        ( string_push_char buf 10 )
        = ri + ri 1
    }

    ( vec_free [i] idx )
    ^ ( csv_table_from_string buf )
}

// Internal: append one cell to a String buffer, applying RFC 4180
// quoting when needed. Mirrors __csv_write_cell but writes into a
// growable String instead of a FILE*.
@ __csv_buf_write_cell String out s data i len i delim i quote → v {
    ? == quote 0 {
        ( __csv_buf_push_range out data len )
    } {
        : *u src # *u data
        : ~ b needs_quote F
        : ~ i j 0
        ~ & ! needs_quote < j len {
            : i c # i . src j
            ? == c delim { = needs_quote T } {
                ? == c quote { = needs_quote T } {
                    ? == c 10 { = needs_quote T } {
                        ? == c 13 { = needs_quote T } { = j + j 1 }
                    }
                }
            }
        }
        ? ! needs_quote {
            ( __csv_buf_push_range out data len )
        } {
            ( string_push_char out quote )
            : ~ i k 0
            ~ < k len {
                : i c # i . src k
                ? == c quote { ( string_push_char out quote ) } {}
                ( string_push_char out c )
                = k + k 1
            }
            ( string_push_char out quote )
        }
    }
}

@ __csv_buf_push_range String out s data i len → v {
    : *u src # *u data
    : ~ i k 0
    ~ < k len {
        ( string_push_char out # i . src k )
        = k + k 1
    }
}

// ── High-level row-collection API ──────────────────────────────────
//
// `csv_parse` / `csv_write` operate on `Vec[Vec[String]]` (per-row
// nested vectors). Distinct from CSVTable's arena layout — useful
// when you want to mutate cells in place or pass row vectors around
// independently. Backed by CSVReader / CSVWriter internals.

// Parse the whole content into a nested vector of rows.
@ csv_parse String content → !( Vec ( Vec String ) ) ParseErr {
    : ( Vec ( Vec String ) ) rows ( vec_new [( Vec String )] )
    : *CSVReader r ( csv_reader_new content )
    : ~ b done F
    ~ ! done {
        : ?( Vec String ) row_opt ( csv_reader_next r )
        ?? row_opt {
            T row → ( vec_push [( Vec String )] rows row )
            F → { = done T }
        }
    }
    ( csv_reader_free r )
    ^ @ !( Vec ( Vec String ) ) ParseErr { T rows }
}

@ csv_parse_dialect String content CSVDialect dia → !( Vec ( Vec String ) ) ParseErr {
    : ( Vec ( Vec String ) ) rows ( vec_new [( Vec String )] )
    : *CSVReader r ( csv_reader_new_dialect content dia )
    : ~ b done F
    ~ ! done {
        : ?( Vec String ) row_opt ( csv_reader_next r )
        ?? row_opt {
            T row → ( vec_push [( Vec String )] rows row )
            F → { = done T }
        }
    }
    ( csv_reader_free r )
    ^ @ !( Vec ( Vec String ) ) ParseErr { T rows }
}

// Write a nested vector of rows into a single CSV String.
@ csv_write ( Vec ( Vec String ) ) rows → String {
    ^ ( csv_write_dialect rows ( csv_dialect_default ) )
}

@ csv_write_dialect ( Vec ( Vec String ) ) rows CSVDialect dia → String {
    : String out ( string_new )
    : i delim . dia delimiter
    : i quote . dia quote_char
    : b crlf . dia crlf_terminator

    : i nr ( vec_len [( Vec String )] rows )
    : ~ i i 0
    ~ < i nr {
        : ?( Vec String ) row_opt ( vec_get [( Vec String )] rows i )
        ?? row_opt {
            T row → {
                : i nc ( vec_len [String] row )
                : ~ i j 0
                ~ < j nc {
                    : ?String s_opt ( vec_get [String] row j )
                    ?? s_opt {
                        T s → ( __csv_format_field out ( string_data s ) delim quote )
                        F → {}
                    }
                    ? < j - nc 1 { ( string_push_char out delim ) } {}
                    = j + j 1
                }
                ? crlf { ( string_push_str out `\r\n` ) } { ( string_push_char out 10 ) }
            }
            F → {}
        }
        = i + i 1
    }
    ^ out
}

@ __csv_format_field String out s data i delim i quote → v {
    : ~ b need_quote F
    ? != quote 0 {
        : i len ( nurl_str_len data )
        : ~ i i 0
        ~ & ! need_quote < i len {
            : i c ( nurl_str_get data i )
            ? | | | == c delim == c quote == c 10 == c 13 { = need_quote T } {}
            = i + i 1
        }
    } {}

    ? need_quote {
        ( string_push_char out quote )
        : i len ( nurl_str_len data )
        : ~ i i 0
        ~ < i len {
            : i c ( nurl_str_get data i )
            ? == c quote { ( string_push_char out quote ) } {}
            ( string_push_char out c )
            = i + i 1
        }
        ( string_push_char out quote )
    } {
        ( string_push_str out data )
    }
}
