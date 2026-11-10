// csv_row_wider_than_256_cells_overruns_the_index: `( csv_table_from_string s )`
// of a CSV whose rows have more than 256 cells: the parser reserved a fixed
// 256-cell slack per row and wrote each cell's (offset, length) pair into
// the index through a raw pointer with no capacity check, so the 257th cell
// of a row wrote past the buffer.
// Closed (agora #551): every cell store checks the index capacity first
// and grows it (doubling) when the row runs past it.
// main 2026-11-09: accepted; AddressSanitizer reported heap-buffer-overflow
// (WRITE of size 8 in __csv_parse_content).
// map: §3.3d | B | runs-clean | - | `( csv_table_from_string s )` of a CSV with rows of more than 256 cells: the parser's per-row slack was a fixed 256 cells and its raw index stores had no capacity check, so the 257th cell wrote past the buffer.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`
$ `stdlib/ext/csv.nu`

@ main → i {
    : String s ( string_new )
    : ~ i r 0
    ~ < r 3 {
        : ~ i c 0
        ~ < c 400 {
            ? > c 0 { ( string_push_char s 44 ) } {}
            ( string_push_char s 120 )
            = c + c 1
        }
        ( string_push_char s 10 )
        = r + r 1
    }
    : CSVTable t ( csv_table_from_string s )
    ? != ( csv_table_n_cells_in_row t 1 ) 400 { ^ 1 } {}
    ? != ( csv_table_view_len t 1 399 ) 1 { ^ 1 } {}
    ^ 0
}
