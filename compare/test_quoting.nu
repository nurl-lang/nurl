// test_quoting.nu — RFC 4180 quoted-cell unit tests for CSVTable.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/csv.nu`

@ check_cell *CSVTable t i row i col s want s label → i {
    : s got ( csv_table_view t row col )
    ? == # i got 0 {
        ( nurl_print label ) ( nurl_print `: NULL view\n` )
        ^ 1
    } {}
    : i glen ( csv_table_view_len t row col )
    : i wlen ( nurl_str_len want )
    ? != ( nurl_memcmp_lex got glen want wlen ) 0 {
        : String gs ( string_from_bytes # *u got glen )
        ( nurl_print label ) ( nurl_print `: got=[` )
        ( nurl_print ( string_data gs ) ) ( nurl_print `] (len=` )
        ( nurl_print ( nurl_str_int glen ) ) ( nurl_print `) want=[` )
        ( nurl_print want ) ( nurl_print `] (len=` )
        ( nurl_print ( nurl_str_int wlen ) ) ( nurl_print `)\n` )
        ( string_free gs )
        ^ 1
    } {}
    ^ 0
}

@ main → i {
    : ~ i fails 0

    // Test 1: simple quoted cells, no escapes
    ( nurl_print `Test 1: simple quoted ─────\n` )
    : *CSVTable t1 ( csv_table_from_string ( string_from `name,city\n"alice","new york"\n"bob","la"\n` ) )
    ? != ( csv_table_n_rows t1 ) 2 {
        ( nurl_print `  expected 2 rows, got ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t1 ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    = fails + fails ( check_cell t1 0 0 `alice` `  t1[0][0]` )
    = fails + fails ( check_cell t1 0 1 `new york` `  t1[0][1]` )
    = fails + fails ( check_cell t1 1 0 `bob` `  t1[1][0]` )
    = fails + fails ( check_cell t1 1 1 `la` `  t1[1][1]` )
    ( csv_table_free t1 )

    // Test 2: embedded delimiter inside quoted field
    ( nurl_print `Test 2: embedded comma ─────\n` )
    : *CSVTable t2 ( csv_table_from_string ( string_from `name,note\n"smith, jr","greets, warmly"\nplain,unquoted\n` ) )
    ? != ( csv_table_n_rows t2 ) 2 {
        ( nurl_print `  expected 2 rows, got ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t2 ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    = fails + fails ( check_cell t2 0 0 `smith, jr` `  t2[0][0]` )
    = fails + fails ( check_cell t2 0 1 `greets, warmly` `  t2[0][1]` )
    = fails + fails ( check_cell t2 1 0 `plain` `  t2[1][0]` )
    = fails + fails ( check_cell t2 1 1 `unquoted` `  t2[1][1]` )
    ( csv_table_free t2 )

    // Test 3: embedded newline inside quoted field
    ( nurl_print `Test 3: embedded newline ───\n` )
    : *CSVTable t3 ( csv_table_from_string ( string_from `a,b\n"line1\nline2","x"\nplain,y\n` ) )
    ? != ( csv_table_n_rows t3 ) 2 {
        ( nurl_print `  expected 2 rows, got ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t3 ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    = fails + fails ( check_cell t3 0 0 `line1\nline2` `  t3[0][0]` )
    = fails + fails ( check_cell t3 0 1 `x` `  t3[0][1]` )
    ( csv_table_free t3 )

    // Test 4: doubled-quote escape (`""` → `"`)
    ( nurl_print `Test 4: doubled-quote escape ──\n` )
    : *CSVTable t4 ( csv_table_from_string ( string_from `q,r\n"say ""hi""","done"\n` ) )
    ? != ( csv_table_n_rows t4 ) 1 {
        ( nurl_print `  expected 1 row, got ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t4 ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    = fails + fails ( check_cell t4 0 0 `say "hi"` `  t4[0][0]` )
    = fails + fails ( check_cell t4 0 1 `done` `  t4[0][1]` )
    ( csv_table_free t4 )

    // Test 5: only-escape cell (`""""` → one `"` byte)
    ( nurl_print `Test 5: lone escape cell ───\n` )
    : *CSVTable t5 ( csv_table_from_string ( string_from `x,y\n"""","ok"\n` ) )
    = fails + fails ( check_cell t5 0 0 `"` `  t5[0][0]` )
    = fails + fails ( check_cell t5 0 1 `ok` `  t5[0][1]` )
    ( csv_table_free t5 )

    // Test 6: empty quoted cell
    ( nurl_print `Test 6: empty quoted cell ──\n` )
    : *CSVTable t6 ( csv_table_from_string ( string_from `a,b\n"","value"\n` ) )
    = fails + fails ( check_cell t6 0 0 `` `  t6[0][0]` )
    = fails + fails ( check_cell t6 0 1 `value` `  t6[0][1]` )
    ( csv_table_free t6 )

    // Test 7: CRLF line ending with quoted cell
    ( nurl_print `Test 7: CRLF terminator ────\n` )
    : *CSVTable t7 ( csv_table_from_string ( string_from `a,b\r\n"aa","bb"\r\n"cc","dd"\r\n` ) )
    ? != ( csv_table_n_rows t7 ) 2 {
        ( nurl_print `  expected 2 rows, got ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t7 ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    = fails + fails ( check_cell t7 0 0 `aa` `  t7[0][0]` )
    = fails + fails ( check_cell t7 0 1 `bb` `  t7[0][1]` )
    = fails + fails ( check_cell t7 1 0 `cc` `  t7[1][0]` )
    = fails + fails ( check_cell t7 1 1 `dd` `  t7[1][1]` )
    ( csv_table_free t7 )

    // Test 8: round-trip — write quoted, re-parse, expect same cells.
    ( nurl_print `Test 8: round-trip ─────────\n` )
    : *CSVTable t8 ( csv_table_from_string ( string_from `a,b,c\n"x,y","say ""hi""","line1\nline2"\nplain,unquoted,plain\n` ) )
    ? != ( csv_table_n_rows t8 ) 2 {
        ( nurl_print `  expected 2 rows, got ` ) ( nurl_print ( nurl_str_int ( csv_table_n_rows t8 ) ) ) ( nurl_print `\n` )
        = fails + fails 1
    } {}
    : b w_ok ( csv_table_write t8 `/tmp/test_quoting_roundtrip.csv` ( csv_dialect_default ) )
    ? ! w_ok {
        ( nurl_print `  write failed\n` )
        = fails + fails 1
    } {}
    ( csv_table_free t8 )

    : *CSVTable t8b ( csv_table_load `/tmp/test_quoting_roundtrip.csv` )
    ? == # i t8b 0 {
        ( nurl_print `  reload failed\n` )
        = fails + fails 1
    } {
        = fails + fails ( check_cell t8b 0 0 `x,y` `  t8b[0][0]` )
        = fails + fails ( check_cell t8b 0 1 `say "hi"` `  t8b[0][1]` )
        = fails + fails ( check_cell t8b 0 2 `line1\nline2` `  t8b[0][2]` )
        = fails + fails ( check_cell t8b 1 0 `plain` `  t8b[1][0]` )
        = fails + fails ( check_cell t8b 1 1 `unquoted` `  t8b[1][1]` )
        = fails + fails ( check_cell t8b 1 2 `plain` `  t8b[1][2]` )
        ( csv_table_free t8b )
    }

    ( nurl_print `\n` )
    ? == fails 0 {
        ( nurl_print `ALL QUOTING TESTS PASSED\n` )
        ^ 0
    } {
        ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` failures\n` )
        ^ 1
    }
}
