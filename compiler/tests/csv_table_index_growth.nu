// csv_table_index_growth.nu — the CSVTable cell index past its estimate.
//
// The parser sizes its index once, from the newline count and the
// header's column count (Agora #551), and grows it only past that. Each
// case below is a file the estimate misses, so every growth path runs:
//   - a header row wider than the first reservation (400 columns), and
//     body rows as wide: before #551 a row of more than 256 cells wrote
//     past the index (heap-buffer-overflow under ASan);
//   - body rows wider than the header (ragged);
//   - bare-CR line ends: no '\n' at all, so the row estimate is 1;
//   - a typed-float load on the same bare-CR text (its cache is sized
//     from the same count).
// Every cell is read back through view_len and get.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`
$ `stdlib/ext/csv.nu`

@ say s tag i v → v {
    : String line ( string_from tag )
    ( string_push_int line v )
    ( nurl_println ( string_data line ) )
}

// rows × cols cells "r.c", rows ending in `eol`.
@ grid i rows i cols s eol → String {
    : String out ( string_new )
    : ~ i r 0
    ~ < r rows {
        : ~ i c 0
        ~ < c cols {
            ? > c 0 { ( string_push_char out 44 ) } {}
            ( string_push_int out r )
            ( string_push_char out 46 )
            ( string_push_int out c )
            = c + c 1
        }
        ( string_push_str out eol )
        = r + r 1
    }
    ^ out
}

// The sum of every cell's length, and how many cells read back as the
// text the grid wrote.
@ check s tag CSVTable t → v {
    : i nr ( csv_table_n_rows t )
    : ~ i bytes 0
    : ~ i right 0
    : ~ i r 0
    ~ < r nr {
        : i nc ( csv_table_n_cells_in_row t r )
        : ~ i c 0
        ~ < c nc {
            = bytes + bytes ( csv_table_view_len t r c )
            : String want ( string_new )
            ( string_push_int want + r 1 )
            ( string_push_char want 46 )
            ( string_push_int want c )
            ?? ( csv_table_get t r c ) {
                T got → { ? ( string_eq got want ) { = right + right 1 } {} }
                F → {}
            }
            = c + c 1
        }
        = r + r 1
    }
    ( nurl_print tag ) ( nurl_print `\n` )
    ( say `  rows=` nr )
    ( say `  cols=` ( csv_table_n_cols t ) )
    ( say `  bytes=` bytes )
    ( say `  right=` right )
    ( say `  out_of_range=` ( csv_table_view_len t nr 0 ) )
}

@ main → i {
    ( check `wide` ( csv_table_from_string ( grid 4 400 `\n` ) ) )

    // A 2-column header over rows of 300 cells.
    : String ragged ( string_from `a,b\n` )
    : String body ( grid 3 300 `\r\n` )
    ( string_push_str ragged ( string_data body ) )
    : CSVTable rt ( csv_table_from_string ragged )
    ( say `ragged_row_cells=` ( csv_table_n_cells_in_row rt 1 ) )
    ( say `ragged_last_len=` ( csv_table_view_len rt 1 299 ) )

    ( check `bare_cr` ( csv_table_from_string ( grid 50 3 `\r` ) ) )

    : CSVTable ft ( csv_table_from_string_typed_f ( grid 50 3 `\r` ) 1 )
    ( say `typed_rows=` ( csv_table_n_rows ft ) )
    ( say `typed_floats=` ( vec_len [f] ( csv_table_typed_floats ft ) ) )
    ^ 0
}
