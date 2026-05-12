// stdlib/ext/csv.nu — CSV reader/writer + bulk CSVTable
//
// MVP-level mirror of Python's csv module:
//   reader      ↔  CSVReader      (per-row stream, owns its lines vec)
//   writer      ↔  CSVWriter      (per-row stream over a FILE*)
//   DictReader  ↔  CSVDictReader  (header-mapped HashMap rows)
//   DictWriter  ↔  CSVDictWriter
//   Dialect     ↔  CSVDialect     (delimiter, line-terminator)
//
// On top of those: `CSVTable` — an in-memory bulk container with one
// allocation pass and high-level operations (sort_by / sort_with /
// find_first / find_all / filter / select_cols / write). Use CSVTable
// when you load the whole file into RAM and want pandas-style queries
// without writing the byte-level parser yourself.
//
// Quoting: the arena loader (`CSVTableA`) implements RFC 4180 quoting
// — `"..."` wraps a field, `""` inside encodes a literal `"`, and a
// quoted field may contain the delimiter and embedded LF/CRLF.
// Bytes from quoted cells without escapes stay zero-copy in
// `content`; cells that needed `""` unescaping land in `escape_buf`
// and are addressed via negative offsets in `flat_cells`. Use
// `csv_dialect_unquoted` (`quote_char = 0`) on data that's known
// quote-free to bypass the per-cell quote-byte branch in both reader
// and writer. The legacy `CSVTable` reader (`csv_reader_*`) does NOT
// do quoting — use `csv_table_a_*` for RFC-4180 input.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/hashmap.nu`

// ── Dialect ────────────────────────────────────────────────────────

: CSVDialect {
    i delimiter         // byte value, e.g. 44 (',') or 9 ('\t')
    b crlf_terminator   // T = write '\r\n', F = write '\n'
    i quote_char        // RFC 4180 quote byte (34 = `"`); 0 disables quoting
}

@ csv_dialect_default → CSVDialect { ^ @ CSVDialect { 44 F 34 } }
@ csv_dialect_excel → CSVDialect { ^ @ CSVDialect { 44 T 34 } }
@ csv_dialect_excel_tab → CSVDialect { ^ @ CSVDialect { 9 T 34 } }
@ csv_dialect_unix → CSVDialect { ^ @ CSVDialect { 44 F 34 } }
// Unquoted dialect: every byte except delim/CR/LF is content. Use for
// data sets that NEVER contain quoted fields — skips the per-cell
// branch on the quote byte and matches Phase 2a/2b speed exactly.
@ csv_dialect_unquoted → CSVDialect { ^ @ CSVDialect { 44 F 0 } }

// ── Internal helpers ───────────────────────────────────────────────

@ __csv_drop_string String s → v { ( string_free s ) }

@ __csv_row_free ( Vec String ) row → v {
    ( vec_free_with [String] row \ String s → v { ( string_free s ) } )
}

@ __csv_clone_row ( Vec String ) src → ( Vec String ) {
    : i n ( vec_len [String] src )
    : ( Vec String ) out ( vec_with_cap [String] n )
    : *String sp ( vec_data [String] src )
    : ~ i i 0
    ~ < i n {
        : String s . sp i
        ( vec_push [String] out ( string_from ( string_data s ) ) )
        = i + i 1
    }
    ^ out
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

@ csv_reader_free *CSVReader r → v {
    ( string_free . r content )
    ( nurl_free # s r )
}

@ csv_reader_next *CSVReader r → ? ( Vec String ) {
    : i clen ( string_len . r content )
    : ~ i p . r pos
    ? >= p clen { ^ @ ? ( Vec String ) { F # ( Vec String ) 0 } } {}

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
            = p + p 1 // skip opening quote
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
    
    ^ @ ? ( Vec String ) { T row }
}

// ── CSVDictReader ──────────────────────────────────────────────────

: CSVDictReader {
    ( Vec String ) header
    *CSVReader reader
}

@ csv_dict_reader_new *CSVReader r → *CSVDictReader {
    : ? ( Vec String ) h_opt ( csv_reader_next r )
    : ( Vec String ) h ( opt_unwrap_or [ ( Vec String ) ] h_opt ( vec_new [String] ) )
    : *CSVDictReader dr # *CSVDictReader ( nurl_malloc Z CSVDictReader )
    = . dr header h
    = . dr reader r
    ^ dr
}

@ csv_dict_reader_next *CSVDictReader dr → ? ( HashMap s String ) {
    : *CSVReader r . dr reader
    : ? ( Vec String ) row_opt ( csv_reader_next r )
    ?? row_opt {
        T row → {
            : ( HashMap s String ) map ( map_new [s String] )
            : ( Vec String ) hdr . dr header
            : i n_header ( vec_len [String] hdr )
            : i n_row ( vec_len [String] row )
            : i n ? < n_header n_row n_header n_row
            : ~ i i 0
            ~ < i n {
                : ? String k_opt ( vec_get [String] hdr i )
                : ? String v_opt ( vec_get [String] row i )
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
            ^ @ ? ( HashMap s String ) { T map }
        }
        F → { ^ @ ? ( HashMap s String ) { F # ( HashMap s String ) 0 } }
    }
}

@ csv_dict_reader_free *CSVDictReader dr → v {
    ( __csv_row_free . dr header )
    ( csv_reader_free . dr reader )
    ( nurl_free dr )
}

// ── CSVWriter (per-row stream over a FILE*) ───────────────────────

: CSVWriter {
    *v f
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

@ __csv_write_field *v file s data i delim i quote → v {
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

@ csv_writer_writerow *CSVWriter w ( Vec String ) row → v {
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
        : ? String s ( vec_get [String] row i )
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


@ csv_writer_close *CSVWriter w → v {
    ( nurl_file_close . w f )
    ( nurl_free w )
}

// ── CSVDictWriter ──────────────────────────────────────────────────

: CSVDictWriter {
    ( Vec String ) fieldnames
    *CSVWriter writer
}

@ csv_dict_writer_new *CSVWriter w ( Vec String ) fieldnames → *CSVDictWriter {
    : *CSVDictWriter dw # *CSVDictWriter ( nurl_malloc Z CSVDictWriter )
    = . dw fieldnames fieldnames
    = . dw writer w
    ^ dw
}

@ csv_dict_writer_writeheader *CSVDictWriter dw → v {
    ( csv_writer_writerow . dw writer . dw fieldnames )
}

@ csv_dict_writer_writerow *CSVDictWriter dw ( HashMap s String ) row → v {
    : ( Vec String ) fns . dw fieldnames
    : *CSVWriter wr . dw writer
    : i n ( vec_len [String] fns )
    : ( Vec String ) line ( vec_with_cap [String] n )
    : ~ i i 0
    ~ < i n {
        : ? String k_opt ( vec_get [String] fns i )
        ?? k_opt {
            T k → {
                : ? String v_opt ( map_get [s String] row ( string_data k ) \ s x → i { ^ ( hash_string x ) } \ s a s b → b { ^ ( eq_string a b ) } )
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

@ csv_dict_writer_close *CSVDictWriter dw → v {
    ( csv_writer_close . dw writer )
    ( nurl_free dw )
}

// ── CSVRow ─────────────────────────────────────────────────────────
// CSVRow is a one-field handle around the row's owned Vec[String] of
// cells. Same single-pointer shape as Vec[A] / String, so Vec[CSVRow]
// element copies move only the inner ctl pointer — sort/filter move
// 8 bytes per swap, not the whole cell list.

: CSVRow { ( Vec String ) cells }

@ __csv_row_make ( Vec String ) cells → CSVRow {
    ^ @ CSVRow { cells }
}

@ __csv_row_drop CSVRow r → v {
    ( __csv_row_free . r cells )
}

// ── CSVTable: bulk in-memory operations ───────────────────────────

: CSVTable {
    ( Vec String ) headers
    ( Vec CSVRow ) rows
}

@ csv_table_new → *CSVTable {
    : *CSVTable t # *CSVTable ( nurl_malloc Z CSVTable )
    = . t headers ( vec_new [String] )
    = . t rows ( vec_new [CSVRow] )
    ^ t
}

@ csv_table_free *CSVTable t → v {
    ( __csv_row_free . t headers )
    ( vec_free_with [CSVRow] . t rows \ CSVRow r → v { ( __csv_row_drop r ) } )
    ( nurl_free t )
}

@ csv_table_n_rows *CSVTable t → i { ^ ( vec_len [CSVRow] . t rows ) }
@ csv_table_n_cols *CSVTable t → i { ^ ( vec_len [String] . t headers ) }

// Borrow the cells of a row. Do NOT free; mutations propagate to the
// table. None if `row` is out of range.
@ csv_table_row_cells *CSVTable t i row → ? ( Vec String ) {
    : i nr ( csv_table_n_rows t )
    ? | < row 0 >= row nr { ^ @ ? ( Vec String ) { F # ( Vec String ) 0 } } {}
    : *CSVRow rp ( vec_data [CSVRow] . t rows )
    : CSVRow r . rp row
    ^ @ ? ( Vec String ) { T . r cells }
}

// Single cell. None if (row,col) out of range.
@ csv_table_get *CSVTable t i row i col → ? String {
    : ? ( Vec String ) cells_opt ( csv_table_row_cells t row )
    ?? cells_opt {
        T cells → { ^ ( vec_get [String] cells col ) }
        F → { ^ @ ? String { F # String 0 } }
    }
}

// Index of a named column. None if not present (case-sensitive).
@ csv_table_col_index *CSVTable t s name → ? i {
    : ( Vec String ) hs . t headers
    : i n ( vec_len [String] hs )
    : *String hp ( vec_data [String] hs )
    : ~ i i 0
    ~ < i n {
        : String h . hp i
        ? == ( nurl_str_eq ( string_data h ) name ) 1 {
            ^ @ ? i { T i }
        } {}
        = i + i 1
    }
    ^ @ ? i { F 0 }
}

// Cell by header name. None if the column is missing or out of range.
@ csv_table_get_by_name *CSVTable t i row s name → ? String {
    : ? i col_opt ( csv_table_col_index t name )
    ?? col_opt {
        T col → { ^ ( csv_table_get t row col ) }
        F → { ^ @ ? String { F # String 0 } }
    }
}

// ── Parsing ────────────────────────────────────────────────────────

// Internal row-scanner: consume one CSV record from `cd[pos..clen)`
// using `delim` and `quote` from the dialect. Returns the parsed Vec[String]
// and writes the new pos back through the mutable `pos_inout` Vec[i]
// (single i64 cell). LF and CRLF both terminate. Empty trailing lines
// are detected by the caller (a one-cell zero-length row when the file
// ends with a newline).
@ __csv_scan_row *u cd i clen ( Vec i ) pos_inout i delim i quote → ( Vec String ) {
    : *i pip ( vec_data [i] pos_inout )
    : ~ i p . pip 0
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
            = p + p 1 // skip opening quote
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

    = . pip 0 p
    ^ row
}

// Append rows parsed from `content` into `t`. The first record becomes
// the header (replacing any existing one). Subsequent records become
// rows. A solitary empty trailing line is dropped.
@ csv_table_parse_content *CSVTable t String content CSVDialect dia → v {
    : *u cd # *u ( string_data content )
    : i clen ( string_len content )
    : i delim . dia delimiter
    : i quote . dia quote_char

    : ( Vec i ) pos_box ( vec_with_cap [i] 1 )
    ( vec_push [i] pos_box 0 )
    : *i pp ( vec_data [i] pos_box )

    : ~ b first_row T
    ~ < . pp 0 clen {
        : i p_before . pp 0
        : ( Vec String ) row ( __csv_scan_row cd clen pos_box delim quote )
        : i n_cells ( vec_len [String] row )

        // skip a phantom 1-cell empty row from a trailing newline
        : b is_empty & == n_cells 1 == ( __csv_first_cell_len row ) 0
        ? & is_empty >= . pp 0 clen {
            ( __csv_row_free row )
        } {
            ? first_row {
                ( __csv_row_free . t headers )
                = . t headers row
                = first_row F
            } {
                ( vec_push [CSVRow] . t rows ( __csv_row_make row ) )
            }
        }
    }
    ( vec_free [i] pos_box )
}

@ __csv_first_cell_len ( Vec String ) row → i {
    : ? String s ( vec_get [String] row 0 )
    ?? s {
        T ss → { ^ ( string_len ss ) }
        F → { ^ 0 }
    }
}

@ csv_table_from_string String content → *CSVTable {
    : *CSVTable t ( csv_table_new )
    ( csv_table_parse_content t content ( csv_dialect_default ) )
    ^ t
}

@ csv_table_from_string_dialect String content CSVDialect dia → *CSVTable {
    : *CSVTable t ( csv_table_new )
    ( csv_table_parse_content t content dia )
    ^ t
}

// Load a CSV file using the default dialect. Returns NULL on read
// failure (use file_exists / read_file separately for diagnostics).
@ csv_table_load s path → *CSVTable {
    : ! String IoErr res ( read_file path )
    ?? res {
        F e → { ^ # *CSVTable 0 }
        T content → {
            : *CSVTable t ( csv_table_from_string content )
            ( string_free content )
            ^ t
        }
    }
}

@ csv_table_load_dialect s path CSVDialect dia → *CSVTable {
    : ! String IoErr res ( read_file path )
    ?? res {
        F e → { ^ # *CSVTable 0 }
        T content → {
            : *CSVTable t ( csv_table_from_string_dialect content dia )
            ( string_free content )
            ^ t
        }
    }
}

// ── Writing ────────────────────────────────────────────────────────

@ __csv_write_one_row *v fh ( Vec String ) row s sep s eol → v {
    : i n ( vec_len [String] row )
    : *String rp ( vec_data [String] row )
    : ~ i i 0
    ~ < i n {
        : String s . rp i
        ( nurl_file_write fh ( string_data s ) )
        ? < i - n 1 { ( nurl_file_write fh sep ) } {}
        = i + i 1
    }
    ( nurl_file_write fh eol )
}

// Write the table to `path`. Returns T on success, F if the file could
// not be opened.
@ csv_table_write *CSVTable t s path CSVDialect dia → b {
    : *v fh ( nurl_file_open path `w` )
    ? == # i fh 0 { ^ F } {}
    : i delim . dia delimiter
    : *u sep_buf # *u ( nurl_malloc 2 )
    = . sep_buf 0 # u delim
    = . sep_buf 1 # u 0
    : s sep # s sep_buf
    : s eol ? . dia crlf_terminator `\r\n` `\n`

    ( __csv_write_one_row fh . t headers sep eol )
    : i nr ( csv_table_n_rows t )
    : *CSVRow rp ( vec_data [CSVRow] . t rows )
    : ~ i i 0
    ~ < i nr {
        : CSVRow r . rp i
        ( __csv_write_one_row fh . r cells sep eol )
        = i + i 1
    }
    ( nurl_file_close fh )
    ( nurl_free sep_buf )
    ^ T
}

// ── Sorting ────────────────────────────────────────────────────────

// In-place sort by a single column, using string compare. asc=T sorts
// ascending, F sorts descending. Out-of-range cells sort to one end.
@ csv_table_sort_by *CSVTable t i col b asc → v {
    : i col_idx col
    : b ascending asc
    ( sort_by [CSVRow] . t rows
        \ CSVRow ra CSVRow rb → i {
            : ( Vec String ) ca . ra cells
            : ( Vec String ) cb . rb cells
            : ? String sa ( vec_get [String] ca col_idx )
            : ? String sb ( vec_get [String] cb col_idx )
            ?? sa {
                T x → {
                    ?? sb {
                        T y → {
                            : i c ( cmp_string x y )
                            ? ascending { ^ c } { ^ - 0 c }
                        }
                        F → { ^ 1 }
                    }
                }
                F → {
                    ?? sb {
                        T _ → { ^ -1 }
                        F → { ^ 0 }
                    }
                }
            }
        }
    )
}

// In-place sort with a custom row comparator. Comparator follows the
// 3-way compare contract: <0, 0, >0. Argument types are CSVRow so
// the comparator can read multiple cells without indirection.
@ csv_table_sort_with *CSVTable t (@ i CSVRow CSVRow) cmp → v {
    ( sort_by [CSVRow] . t rows cmp )
}

// Internal: permute t.rows according to `order`, where order[k] is the
// index of the source row that should land at position k. Old Vec[CSVRow]
// is released without dropping the CSVRow handles — ownership of every
// cell-buffer moves into the new vec via 8-byte ctl-pointer copies.
@ __csv_permute_rows *CSVTable t ( Vec i ) order → v {
    : i n ( vec_len [i] order )
    : ( Vec CSVRow ) new_rows ( vec_with_cap [CSVRow] n )
    : *CSVRow rp ( vec_data [CSVRow] . t rows )
    : *i op ( vec_data [i] order )
    : ~ i k 0
    ~ < k n {
        : i src . op k
        : CSVRow r . rp src
        ( vec_push [CSVRow] new_rows r )
        = k + k 1
    }
    // vec_free (NOT vec_free_with) — every CSVRow handle is now owned
    // by new_rows; freeing only the array of 8-byte pointers in the old
    // buffer is the correct ownership transfer.
    ( vec_free [CSVRow] . t rows )
    = . t rows new_rows
}

// Numeric sort: parses the cell at `col` as a signed decimal integer
// before comparing. Cells that fail to parse compare equal to 0.
//
// Indexed: 1 parse per row + sort over an i64 key vec. Total cost is
// O(N) parses + O(N log N) integer comparisons, vs. the naive
// O(N log N) parses of the per-comparator approach.
@ csv_table_sort_by_int *CSVTable t i col b asc → v {
    : i n ( csv_table_n_rows t )
    ? > n 1 {
        : i col_idx col
        : b ascending asc

        // Parse keys into a flat Vec[i] — one parse per row.
        : ( Vec i ) keys ( vec_with_cap [i] n )
        : *CSVRow rp ( vec_data [CSVRow] . t rows )
        : ~ i ri 0
        ~ < ri n {
            : CSVRow r . rp ri
            : ? String s_opt ( vec_get [String] . r cells col_idx )
            : ~ i v 0
            ?? s_opt {
                T s → {
                    : ! i ParseErr p ( string_to_int s )
                    ?? p { T pv → { = v pv } F → {} }
                }
                F → {}
            }
            ( vec_push [i] keys v )
            = ri + ri 1
        }

        // Sort an index permutation. Comparator does only integer compares.
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

// Numeric sort by f64. Cells that fail to parse compare equal to 0.0.
// NaN cells fall to the end (cmp_float treats NaN as "greater").
@ csv_table_sort_by_float *CSVTable t i col b asc → v {
    : i n ( csv_table_n_rows t )
    ? > n 1 {
        : i col_idx col
        : b ascending asc

        : ( Vec f ) keys ( vec_with_cap [f] n )
        : *CSVRow rp ( vec_data [CSVRow] . t rows )
        : ~ i ri 0
        ~ < ri n {
            : CSVRow r . rp ri
            : ? String s_opt ( vec_get [String] . r cells col_idx )
            : ~ f v 0.0
            ?? s_opt {
                T s → {
                    : ? f p ( string_to_float s )
                    ?? p { T pv → { = v pv } F → {} }
                }
                F → {}
            }
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

// String sort by a single column with borrowed-pointer keys: same
// indexed pattern, but keys are raw `s` (NUL-terminated borrows into
// the existing cell buffers) so the comparator skips the option-unwrap
// and Vec[String] indirection on every call. Cells that are missing
// (out-of-range column) sort to the end regardless of asc.
@ csv_table_sort_by_string *CSVTable t i col b asc → v {
    : i n ( csv_table_n_rows t )
    ? > n 1 {
        : i col_idx col
        : b ascending asc

        : ( Vec s ) keys ( vec_with_cap [s] n )
        : *CSVRow rp ( vec_data [CSVRow] . t rows )
        : ~ i ri 0
        ~ < ri n {
            : CSVRow r . rp ri
            : ? String s_opt ( vec_get [String] . r cells col_idx )
            : ~ s v `\xff`
            ?? s_opt {
                T ss → { = v ( string_data ss ) }
                F → {}
            }
            ( vec_push [s] keys v )
            = ri + ri 1
        }

        : ( Vec i ) order ( vec_iota 0 n )
        : *s kp ( vec_data [s] keys )
        ( sort_by [i] order \ i a i b → i {
            : s ka . kp a
            : s kb . kp b
            : i c ( nurl_str_cmp ka kb )
            ? ascending { ^ c } { ^ - 0 c }
        } )

        ( __csv_permute_rows t order )
        ( vec_free [s] keys )
        ( vec_free [i] order )
    } {}
}

// Return a fresh table with deep copies of the first `n` rows. Headers
// are deep-copied. n is clamped to [0, n_rows].
@ csv_table_head *CSVTable src i n → *CSVTable {
    : *CSVTable out ( csv_table_new )
    ( __csv_row_free . out headers )
    = . out headers ( __csv_clone_row . src headers )
    : i nr ( csv_table_n_rows src )
    : ~ i take n
    ? < take 0 { = take 0 } {}
    ? > take nr { = take nr } {}
    : *CSVRow rp ( vec_data [CSVRow] . src rows )
    : ~ i i 0
    ~ < i take {
        : CSVRow r . rp i
        : ( Vec String ) cpy ( __csv_clone_row . r cells )
        ( vec_push [CSVRow] . out rows ( __csv_row_make cpy ) )
        = i + i 1
    }
    ^ out
}

// In-place truncate: keep only the first `n` rows, dropping (and
// freeing) the rest. n is clamped to [0, current row count].
@ csv_table_truncate *CSVTable t i n → v {
    : i nr ( csv_table_n_rows t )
    : ~ i keep n
    ? < keep 0 { = keep 0 } {}
    ? < keep nr {
        : *CSVRow rp ( vec_data [CSVRow] . t rows )
        : ~ i i keep
        ~ < i nr {
            : CSVRow r . rp i
            ( __csv_row_drop r )
            = i + i 1
        }
        : b _ok ( vec_set_len [CSVRow] . t rows keep )
    } {}
}

// ── Find / filter / select ─────────────────────────────────────────

@ csv_table_find_first *CSVTable t i col s target → ? i {
    : i nr ( csv_table_n_rows t )
    : *CSVRow rp ( vec_data [CSVRow] . t rows )
    : ~ i i 0
    ~ < i nr {
        : CSVRow r . rp i
        : ? String s_opt ( vec_get [String] . r cells col )
        ?? s_opt {
            T s → {
                ? == ( nurl_str_eq ( string_data s ) target ) 1 {
                    ^ @ ? i { T i }
                } {}
            }
            F → {}
        }
        = i + i 1
    }
    ^ @ ? i { F 0 }
}

@ csv_table_find_all *CSVTable t i col s target → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i nr ( csv_table_n_rows t )
    : *CSVRow rp ( vec_data [CSVRow] . t rows )
    : ~ i i 0
    ~ < i nr {
        : CSVRow r . rp i
        : ? String s_opt ( vec_get [String] . r cells col )
        ?? s_opt {
            T s → {
                ? == ( nurl_str_eq ( string_data s ) target ) 1 {
                    ( vec_push [i] out i )
                } {}
            }
            F → {}
        }
        = i + i 1
    }
    ^ out
}

// Count rows whose cell at `col` equals `target`.
@ csv_table_count_where *CSVTable t i col s target → i {
    : ~ i count 0
    : i nr ( csv_table_n_rows t )
    : *CSVRow rp ( vec_data [CSVRow] . t rows )
    : ~ i i 0
    ~ < i nr {
        : CSVRow r . rp i
        : ? String s_opt ( vec_get [String] . r cells col )
        ?? s_opt {
            T s → {
                ? == ( nurl_str_eq ( string_data s ) target ) 1 {
                    = count + count 1
                } {}
            }
            F → {}
        }
        = i + i 1
    }
    ^ count
}

// New CSVTable holding deep copies of headers and the rows where
// `pred` returns T. Source remains valid.
@ csv_table_filter *CSVTable src (@ b CSVRow) pred → *CSVTable {
    : *CSVTable out ( csv_table_new )
    ( __csv_row_free . out headers )
    = . out headers ( __csv_clone_row . src headers )

    : i nr ( csv_table_n_rows src )
    : *CSVRow rp ( vec_data [CSVRow] . src rows )
    : ~ i i 0
    ~ < i nr {
        : CSVRow r . rp i
        ? ( pred r ) {
            : ( Vec String ) cpy ( __csv_clone_row . r cells )
            ( vec_push [CSVRow] . out rows ( __csv_row_make cpy ) )
        } {}
        = i + i 1
    }
    ^ out
}

// New CSVTable containing only the columns named in `cols` (in the
// given order). Missing column names are silently skipped.
@ csv_table_select_cols *CSVTable src ( Vec String ) cols → *CSVTable {
    : *CSVTable out ( csv_table_new )

    // Resolve column names → source indices, dropping unknown columns.
    : i k ( vec_len [String] cols )
    : ( Vec i ) idx ( vec_with_cap [i] k )
    : ( Vec String ) new_h ( vec_with_cap [String] k )
    : *String cp ( vec_data [String] cols )
    : ~ i ci 0
    ~ < ci k {
        : String name . cp ci
        : ? i col_opt ( csv_table_col_index src ( string_data name ) )
        ?? col_opt {
            T col → {
                ( vec_push [i] idx col )
                ( vec_push [String] new_h ( string_from ( string_data name ) ) )
            }
            F → {}
        }
        = ci + ci 1
    }
    ( __csv_row_free . out headers )
    = . out headers new_h

    : i nr ( csv_table_n_rows src )
    : i nidx ( vec_len [i] idx )
    : *i ip ( vec_data [i] idx )
    : *CSVRow rp ( vec_data [CSVRow] . src rows )
    : ~ i ri 0
    ~ < ri nr {
        : CSVRow r . rp ri
        : ( Vec String ) src_cells . r cells
        : ( Vec String ) new_cells ( vec_with_cap [String] nidx )
        : ~ i j 0
        ~ < j nidx {
            : i col . ip j
            : ? String s_opt ( vec_get [String] src_cells col )
            ?? s_opt {
                T s → ( vec_push [String] new_cells ( string_from ( string_data s ) ) )
                F → ( vec_push [String] new_cells ( string_new ) )
            }
            = j + j 1
        }
        ( vec_push [CSVRow] . out rows ( __csv_row_make new_cells ) )
        = ri + ri 1
    }
    ( vec_free [i] idx )
    ^ out
}

// ── High-level API ─────────────────────────────────────────────────

// Parse the whole content into a nested vector of rows.
@ csv_parse String content → ! ( Vec ( Vec String ) ) ParseErr {
    : ( Vec ( Vec String ) ) rows ( vec_new [ ( Vec String ) ] )
    : *CSVReader r ( csv_reader_new content )
    : ~ b done F
    ~ ! done {
        : ? ( Vec String ) row_opt ( csv_reader_next r )
        ?? row_opt {
            T row → ( vec_push [ ( Vec String ) ] rows row )
            F → { = done T }
        }
    }
    ( csv_reader_free r )
    ^ @ ! ( Vec ( Vec String ) ) ParseErr { T rows }
}

@ csv_parse_dialect String content CSVDialect dia → ! ( Vec ( Vec String ) ) ParseErr {
    : ( Vec ( Vec String ) ) rows ( vec_new [ ( Vec String ) ] )
    : *CSVReader r ( csv_reader_new_dialect content dia )
    : ~ b done F
    ~ ! done {
        : ? ( Vec String ) row_opt ( csv_reader_next r )
        ?? row_opt {
            T row → ( vec_push [ ( Vec String ) ] rows row )
            F → { = done T }
        }
    }
    ( csv_reader_free r )
    ^ @ ! ( Vec ( Vec String ) ) ParseErr { T rows }
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
    
    : i nr ( vec_len [ ( Vec String ) ] rows )
    : ~ i i 0
    ~ < i nr {
        : ? ( Vec String ) row_opt ( vec_get [ ( Vec String ) ] rows i )
        ?? row_opt {
            T row → {
                : i nc ( vec_len [String] row )
                : ~ i j 0
                ~ < j nc {
                    : ? String s_opt ( vec_get [String] row j )
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

// ── Arena-backed table (CSVTableA): zero-per-cell-malloc loader ─────
//
// CSVTableA holds the entire file content in one buffer (`content`)
// and represents every cell as a (offset, length) pair into that
// buffer. All cells of all rows live in a single flat `Vec[i]`
// (`flat_cells`, layout: off0,len0,off1,len1,...). Per-row boundary
// info lives in `row_starts`, where row r occupies cells
// [row_starts[r] .. row_starts[r+1]) (cell index, NOT i64 index).
// `row_starts` always has length n_rows + 1; the trailing sentinel
// is the total cell count.
//
// Allocation profile vs CSVTable v1:
//   CSVTable     : 9 M calloc + 9 M realloc (per-cell String alloc).
//   CSVTableA    : ~10 calloc/realloc total (file buf + flat_cells +
//                  row_starts grows + headers). 1000× fewer mallocs.
//
// Cell content access yields a *borrowed* `s` pointing into the
// content buffer. **Borrows are NOT NUL-terminated** — they are not
// substrings, just pointers; combine with `csv_table_a_view_len` if
// you need a length, or call `csv_table_a_get_string` for a freshly
// allocated owned String copy.

: CSVTableA {
    String content
    ( Vec String ) headers
    ( Vec i ) flat_cells       // [off0,len0,off1,len1,...]
    ( Vec i ) row_starts       // length = n_rows; cell-index of row r
    ( Vec i ) row_lens         // length = n_rows; cell count of row r
    ( Vec u ) escape_buf       // unescaped quoted-cell bytes
                               // off ≥ 0 → into content[]
                               // off  < 0 → into escape_buf[-off-1..]
}

@ csv_table_a_new → *CSVTableA {
    : *CSVTableA t # *CSVTableA ( nurl_malloc Z CSVTableA )
    = . t content ( string_new )
    = . t headers ( vec_new [String] )
    = . t flat_cells ( vec_new [i] )
    = . t row_starts ( vec_new [i] )
    = . t row_lens ( vec_new [i] )
    = . t escape_buf ( vec_new [u] )
    ^ t
}

@ csv_table_a_free *CSVTableA t → v {
    ( string_free . t content )
    ( __csv_row_free . t headers )
    ( vec_free [i] . t flat_cells )
    ( vec_free [i] . t row_starts )
    ( vec_free [i] . t row_lens )
    ( vec_free [u] . t escape_buf )
    ( nurl_free t )
}

@ csv_table_a_n_rows *CSVTableA t → i { ^ ( vec_len [i] . t row_starts ) }

@ csv_table_a_n_cols *CSVTableA t → i { ^ ( vec_len [String] . t headers ) }

@ csv_table_a_n_cells_in_row *CSVTableA t i row → i {
    : i nr ( csv_table_a_n_rows t )
    ? | < row 0 >= row nr { ^ 0 } {}
    : *i rlp ( vec_data [i] . t row_lens )
    ^ . rlp row
}

// Borrowed `s` view of (row, col). NOT NUL-terminated; pair with
// csv_table_a_view_len. `# s 0` (NULL) when (row, col) is out of range.
//
// Cells whose underlying offset is < 0 came from a quoted field with
// embedded `""` escapes — the materialized bytes live in
// `t.escape_buf` at index `-off - 1`. Unquoted cells and quoted cells
// without escapes both stay zero-copy into `t.content`.
@ csv_table_a_view *CSVTableA t i row i col → s {
    : i nr ( csv_table_a_n_rows t )
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

@ csv_table_a_view_len *CSVTableA t i row i col → i {
    : i nr ( csv_table_a_n_rows t )
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
@ csv_table_a_get_string *CSVTableA t i row i col → ? String {
    : s view ( csv_table_a_view t row col )
    ? == # i view 0 { ^ @ ? String { F # String 0 } } {}
    : i len ( csv_table_a_view_len t row col )
    ^ @ ? String { T ( string_from_bytes # *u view len ) }
}

// Index of a column by header name (case-sensitive). None if absent.
@ csv_table_a_col_index *CSVTableA t s name → ? i {
    : ( Vec String ) hs . t headers
    : i n ( vec_len [String] hs )
    : *String hp ( vec_data [String] hs )
    : ~ i i 0
    ~ < i n {
        : String h . hp i
        ? == ( nurl_str_eq ( string_data h ) name ) 1 {
            ^ @ ? i { T i }
        } {}
        = i + i 1
    }
    ^ @ ? i { F 0 }
}

// Borrowed `s` view by column name. `# s 0` (NULL) on miss.
@ csv_table_a_view_by_name *CSVTableA t i row s name → s {
    : ? i col_opt ( csv_table_a_col_index t name )
    ?? col_opt {
        T col → { ^ ( csv_table_a_view t row col ) }
        F → { ^ # s 0 }
    }
}

// Internal: scan one row, pushing each cell's (off, len) onto
// flat_cells. Returns the new `pos` (advanced past the LF/CRLF or
// past clen). Cells are NOT copied; only their byte ranges into
// `cd` are recorded.
@ __csv_a_scan_row *CSVTableA t *u cd i clen i pos i delim → i {
    : ~ i p pos
    : ~ i field_start p
    : ~ b in_row T
    ~ in_row {
        ? >= p clen {
            ( vec_push [i] . t flat_cells field_start )
            ( vec_push [i] . t flat_cells - p field_start )
            = in_row F
        } {
            : i c # i . cd p
            ? == c delim {
                ( vec_push [i] . t flat_cells field_start )
                ( vec_push [i] . t flat_cells - p field_start )
                = p + p 1
                = field_start p
            } {
                ? | == c 10 == c 13 {
                    ( vec_push [i] . t flat_cells field_start )
                    ( vec_push [i] . t flat_cells - p field_start )
                    = p + p 1
                    ? == c 13 {
                        ? < p clen {
                            : i nx # i . cd p
                            ? == nx 10 { = p + p 1 } {}
                        } {}
                    } {}
                    = in_row F
                } { = p + p 1 }
            }
        }
    }
    ^ p
}

// Parse `t.content` into headers + flat_cells using the bulk C parser
// (`nurl_csv_parse_arena`). One C call replaces the entire NURL-side
// scan loop; cells and row indices land directly in pre-sized Vec[i]
// buffers, which the parser populates via raw `i64*` writes — no
// per-cell vec_push, no per-byte branch dispatch in NURL bytecode.
// Phase 2b: raw-pointer parser. The byte loop is the same scalar
// branchy code as before — LLVM-O2 already turns it into a tight
// native loop. The key change: cells are written via direct pointer
// arithmetic instead of `vec_push`. Each `vec_push` calls
// `nurl_peek`/`nurl_poke` (external C, not inlined without LTO),
// costing ~30 ns per push × 16 M pushes = ~480 ms. By calling
// `vec_reserve` + `vec_data` once per ROW (≤ 2 FFI × 1 M = ~30 ms)
// and doing cell stores as raw memory writes, we trade 32 M FFI
// calls for 2 M.
//
// Earlier failed approaches kept here as cautionary tale:
//   • bulk-C parser (`nurl_csv_parse_arena`): 510 ms — large up-
//     front reservation page-faulted across the buffer, and the
//     savings from "no NURL bytecode" were illusory (the NURL byte
//     loop compiles to native via LLVM-O2 anyway).
//   • per-row C scanner (`nurl_csv_scan_row_pairs`): 700 ms — 1 M
//     FFI calls + transfer copy from C buffer to flat_cells via
//     `vec_push` brought back the FFI cost we were trying to avoid.
// Both helpers stay in `stdlib/runtime.c` as Phase 3 infrastructure
// for the typed-schema reader, where per-row FFI is amortized over
// useful per-row typed parsing.
@ __csv_a_parse_content *CSVTableA t CSVDialect dia → v {
    : *u cd # *u ( string_data . t content )
    : i clen ( string_len . t content )
    : i delim . dia delimiter
    : i quote . dia quote_char

    // Worst-case slack per row, so the row's writes never overrun
    // the buffer between reserve calls. 256 cells/row is far above
    // any realistic CSV.
    : i max_row_i64 * 256 2

    // Pre-size the row index vectors. They hold ONE pair (start,len)
    // per body row, so geometric growth is cheap; we still raw-write
    // them through `rsp_w`/`rlp_w` to skip vec_push's FFI per push.
    : i row_est / clen 100
    ? < row_est 16 { = row_est 16 } {}
    ( vec_reserve [i] . t row_starts row_est )
    ( vec_reserve [i] . t row_lens   row_est )

    : ~ i row_w 0           // committed body-row count

    : ~ i pos 0
    : ~ b first_row T

    ~ < pos clen {
        : i row_first_i64 ( vec_len [i] . t flat_cells )
        : i row_first_cell / row_first_i64 2

        // Reserve once per row; if cap already suffices vec_reserve
        // is a fast no-op (one ctl read). We re-arm row_starts /
        // row_lens too so a single grow per ~2× row budget keeps
        // their pointers stable for the inner body of this row.
        ( vec_reserve [i] . t flat_cells + row_first_i64 max_row_i64 )
        ( vec_reserve [i] . t row_starts + row_w 1 )
        ( vec_reserve [i] . t row_lens   + row_w 1 )
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
                = p + p 1                   // skip opening quote
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
                    : ~ *u src # *u 0
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
    : b _r2 ( vec_set_len [i] . t row_lens   row_w )
}

@ csv_table_a_from_string String content → *CSVTableA {
    : *CSVTableA t ( csv_table_a_new )
    ( string_free . t content )
    = . t content content
    ( __csv_a_parse_content t ( csv_dialect_default ) )
    ^ t
}

@ csv_table_a_from_string_dialect String content CSVDialect dia → *CSVTableA {
    : *CSVTableA t ( csv_table_a_new )
    ( string_free . t content )
    = . t content content
    ( __csv_a_parse_content t dia )
    ^ t
}

// Load a CSV file using the default dialect, returning an arena
// table. NULL on read failure.
@ csv_table_a_load s path → *CSVTableA {
    : ! String IoErr res ( read_file path )
    ?? res {
        F e → { ^ # *CSVTableA 0 }
        T content → { ^ ( csv_table_a_from_string content ) }
    }
}

@ csv_table_a_load_dialect s path CSVDialect dia → *CSVTableA {
    : ! String IoErr res ( read_file path )
    ?? res {
        F e → { ^ # *CSVTableA 0 }
        T content → { ^ ( csv_table_a_from_string_dialect content dia ) }
    }
}

// Promote an arena table to v1 CSVTable (deep-copies every cell).
// Use only when independent lifetimes are needed; the per-cell malloc
// cost is paid here.
@ csv_table_a_to_table *CSVTableA src → *CSVTable {
    : *CSVTable out ( csv_table_new )
    ( __csv_row_free . out headers )
    : i nh ( vec_len [String] . src headers )
    : ( Vec String ) new_h ( vec_with_cap [String] nh )
    : *String hp ( vec_data [String] . src headers )
    : ~ i k 0
    ~ < k nh {
        : String h . hp k
        ( vec_push [String] new_h ( string_from ( string_data h ) ) )
        = k + k 1
    }
    = . out headers new_h

    : i nr ( csv_table_a_n_rows src )
    ( vec_reserve [CSVRow] . out rows nr )
    : *u cd # *u ( string_data . src content )
    : *u eb ( vec_data [u] . src escape_buf )
    : *i fcp ( vec_data [i] . src flat_cells )
    : *i rsp ( vec_data [i] . src row_starts )
    : *i rlp ( vec_data [i] . src row_lens )
    : ~ i ri 0
    ~ < ri nr {
        : i row_first . rsp ri
        : i row_count . rlp ri
        : ( Vec String ) cells ( vec_with_cap [String] row_count )
        : ~ i ci 0
        ~ < ci row_count {
            : i cell_idx + row_first ci
            : i off . fcp * cell_idx 2
            : i len . fcp + * cell_idx 2 1
            : ~ *u src_p # *u 0
            ? >= off 0 { = src_p # *u + # i cd off }
            { = src_p # *u + # i eb - 0 + off 1 }
            ( vec_push [String] cells ( string_from_bytes src_p len ) )
            = ci + ci 1
        }
        ( vec_push [CSVRow] . out rows ( __csv_row_make cells ) )
        = ri + ri 1
    }
    ^ out
}

// ── Arena: sort / filter / head / write ────────────────────────────
//
// Sort/filter/head are O(n_rows) in arena-land — they only permute or
// truncate the (row_starts, row_lens) parallel vecs. flat_cells and
// content are never touched, never copied. This is the whole point of
// the arena: everything downstream of load is essentially free.

// Permute (row_starts, row_lens) in place by `order`.
@ __csv_a_permute_rows *CSVTableA t ( Vec i ) order → v {
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
@ csv_table_a_sort_by_int *CSVTableA t i col b asc → v {
    : i n ( csv_table_a_n_rows t )
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

        ( __csv_a_permute_rows t order )
        ( vec_free [i] keys )
        ( vec_free [i] order )
    } {}
}

// Numeric float sort. Unparseable cells compare as 0.0.
@ csv_table_a_sort_by_float *CSVTableA t i col b asc → v {
    : i n ( csv_table_a_n_rows t )
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

        ( __csv_a_permute_rows t order )
        ( vec_free [f] keys )
        ( vec_free [i] order )
    } {}
}

// String sort by raw bytes (memcmp + tiebreak by length). Out-of-range
// cells sort to the end.
@ csv_table_a_sort_by_string *CSVTableA t i col b asc → v {
    : i n ( csv_table_a_n_rows t )
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

        ( __csv_a_permute_rows t order )
        ( vec_free [i] k_off )
        ( vec_free [i] k_len )
        ( vec_free [i] order )
    } {}
}

// Filter: keeps rows for which `pred` returns T. The arena keeps
// flat_cells + content untouched; only (row_starts, row_lens) shrink.
// Predicate receives the source table + row index; reads cells via
// csv_table_a_view / csv_table_a_view_len.
//
// HOT-PATH PERF NOTE: each `csv_table_a_view` call internally does
// three `vec_data` FFI calls (rsp, rlp, fcp) — non-inlinable without
// LTO, ~30 ns each. For million-row predicates, prefetch the data
// pointers OUTSIDE the call and capture them into the closure:
//
//     : *i fcp ( vec_data [i] . t flat_cells )
//     : *i rsp ( vec_data [i] . t row_starts )
//     : *i rlp ( vec_data [i] . t row_lens )
//     : *u cd  # *u ( string_data . t content )
//     ( csv_table_a_filter t \ *CSVTableA tt i row → b {
//         : i row_first . rsp row
//         : i cell_idx + row_first MY_COL
//         : i off . fcp * cell_idx 2
//         : i len . fcp + * cell_idx 2 1
//         : *u v # *u + # i cd off
//         ... }  )
//
// Pointers are valid for the duration of the filter call: filter only
// rewrites the row index Vecs, never reloads flat_cells/content.
// `compare/nurl_analysis_arena.nu` benchmarks at 157 ms (was 185 ms)
// using this pattern — savings 12 M FFI calls per million rows.
@ csv_table_a_filter *CSVTableA t (@ b *CSVTableA i) pred → v {
    : i n ( csv_table_a_n_rows t )
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

// In-place truncate to first `n` rows.
@ csv_table_a_truncate *CSVTableA t i n → v {
    : i nr ( csv_table_a_n_rows t )
    : ~ i keep n
    ? < keep 0 { = keep 0 } {}
    ? < keep nr {
        : b _a ( vec_set_len [i] . t row_starts keep )
        : b _b ( vec_set_len [i] . t row_lens keep )
    } {}
}

// Internal: write a single cell to `fh`, applying RFC 4180 quoting if
// the cell contains delim, quote_char, CR, or LF. Cells whose bytes
// live in `escape_buf` (off < 0, only ever produced by the parser
// for cells that contained `""` escapes) are ALWAYS emitted quoted —
// they had embedded quotes by definition.
@ __csv_a_write_cell *v fh *u src i len i delim i quote → v {
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

// Write the arena table to `path` using `dia`. Returns T on success.
// Cells are emitted as raw byte ranges from `content` (zero-copy)
// unless RFC 4180 quoting is required, in which case `__csv_a_write_cell`
// emits a quoted form with `""` escapes. Set `dia.quote_char = 0`
// (`csv_dialect_unquoted`) to bypass the quote-detection scan and
// match Phase 2a/2b raw-write speed exactly.
@ csv_table_a_write *CSVTableA t s path CSVDialect dia → b {
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
        ( __csv_a_write_cell fh hsrc hlen delim quote )
        ? < hi - nh 1 { ( nurl_file_write_byte fh delim ) } {}
        = hi + hi 1
    }
    ? crlf { ( nurl_file_write_byte fh 13 ) } {}
    ( nurl_file_write_byte fh 10 )

    : i nr ( csv_table_a_n_rows t )
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
            : ~ *u sp # *u 0
            ? >= off 0 { = sp # *u + # i cd off }
            { = sp # *u + # i eb - 0 + off 1 }
            ( __csv_a_write_cell fh sp len delim quote )
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
