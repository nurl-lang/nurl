### Security

- **A CSVTable row of more than 256 cells no longer writes past the cell
  index** (Agora #551). `csv_table_from_string` / `csv_table_load*` gave
  each row a fixed 256-cell slack and stored every cell's (offset, length)
  pair through a raw pointer with no capacity check, so the 257th cell of a
  row was a heap-buffer-overflow, reachable from safe code. Every cell and
  row store now checks the index's capacity and grows it when the file runs
  past the estimate (wide or ragged rows, bare-CR line ends). Probe
  `csv_row_wider_than_256_cells_overruns_the_index`, test
  `csv_table_index_growth`.

### Performance

- **CSVTable sizes its cell index once** (Agora #551). The parser counts the
  newlines and, after the header row, reserves one (offset, length) pair per
  header column for each row, instead of re-reserving `len + len + 512`
  slots on every row (`vec_reserve` takes an additional count, so the index
  doubled ahead of need and was moved again and again). `csv_table_view`,
  `csv_table_view_len` and `csv_table_get` bounds-check (row, column) once.
  `bench/csv_table_pipeline`, same host, min of 7: page faults 25.7k → 9.0k
  at ×1 and 107.8k → 9.0k at ×4 (C: 11.3k), system time 99.7 → 12.1 ms and
  wall 326 → 217 ms at ×4 (C: 221 ms), peak RSS 26 → 20 MB; checksum
  unchanged.
