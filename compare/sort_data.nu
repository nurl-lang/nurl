$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/csv.nu`

: Row {
    i id_v
    i val_int_v
    f val_float1_v
    f val_float2_v
    String id
    String val_int
    String val_float1
    String val_float2
    String text_simple
    String text_mixed
    String text_words
    String date
}

@ free_row Row r → v {
    ( string_free . r id )
    ( string_free . r val_int )
    ( string_free . r val_float1 )
    ( string_free . r val_float2 )
    ( string_free . r text_simple )
    ( string_free . r text_mixed )
    ( string_free . r text_words )
    ( string_free . r date )
}

@ cmp_row Row a Row b → i {
    : i c ( cmp_string . b date . a date )
    ? != c 0 { ^ c } {}

    : i c2 ( cmp_string . b text_words . a text_words )
    ? != c2 0 { ^ c2 } {}

    : i c3 ( cmp_string . b text_mixed . a text_mixed )
    ? != c3 0 { ^ c3 } {}

    : i c4 ( cmp_string . b text_simple . a text_simple )
    ? != c4 0 { ^ c4 } {}

    : i c5 ( cmp_float . b val_float2_v . a val_float2_v )
    ? != c5 0 { ^ c5 } {}

    : i c6 ( cmp_float . b val_float1_v . a val_float1_v )
    ? != c6 0 { ^ c6 } {}

    : i c7 ( cmp_int . b val_int_v . a val_int_v )
    ? != c7 0 { ^ c7 } {}

    ^ ( cmp_int . b id_v . a id_v )
}

// Parse a signed decimal i64 directly from a byte range [start, end) in
// a *u buffer. Stops on the first non-digit; returns 0 on empty/invalid
// input. No allocation.
@ parse_int_bytes *u src i start i end → i {
    : ~ i i start
    : ~ i sign 1
    ? < i end {
        : i c0 # i . src i
        ? == c0 45 { = sign -1 = i + i 1 } {
            ? == c0 43 { = i + i 1 } {}
        }
    } {}
    : ~ i n 0
    ~ < i end {
        : i c # i . src i
        : i d - c 48
        ? & >= d 0 <= d 9 {
            = n + * n 10 d
            = i + i 1
        } { = i end }
    }
    ^ * sign n
}

// Build the four-field composite sort_key for one Row from byte ranges
// in `src`. Layout: date \t text_words \t text_mixed \t text_simple
// (the cmp_row priority order). One malloc, no temporaries.
@ make_sort_key *u src i s7 i e7 i s6 i e6 i s5 i e5 i s4 i e4 → String {
    : i n7 - e7 s7
    : i n6 - e6 s6
    : i n5 - e5 s5
    : i n4 - e4 s4
    : i total + + + + + + n7 1 n6 1 n5 1 n4
    : ( Vec u ) tmp ( vec_with_cap [u] + total 1 )
    : *u dst ( vec_data [u] tmp )
    : u tab # u 9
    : u zero # u 0
    : ~ i off 0

    : *u p7 # *u + # i src s7
    ? > n7 0 { ( nurl_memcpy # *u + # i dst off p7 n7 ) = off + off n7 } {}
    = . dst off tab = off + off 1

    : *u p6 # *u + # i src s6
    ? > n6 0 { ( nurl_memcpy # *u + # i dst off p6 n6 ) = off + off n6 } {}
    = . dst off tab = off + off 1

    : *u p5 # *u + # i src s5
    ? > n5 0 { ( nurl_memcpy # *u + # i dst off p5 n5 ) = off + off n5 } {}
    = . dst off tab = off + off 1

    : *u p4 # *u + # i src s4
    ? > n4 0 { ( nurl_memcpy # *u + # i dst off p4 n4 ) = off + off n4 } {}

    = . dst off zero
    ( vec_set_len [u] tmp off )
    ^ @ String { . tmp ctl }
}

// Parse a decimal f64 from a byte range [start, end). Uses a small
// reusable Vec[u] buffer to NUL-terminate the slice, then atof. Caller
// owns `buf` and is responsible for freeing it once at end of the run.
@ parse_float_bytes *u src i start i end ( Vec u ) buf → f {
    : i n - end start
    ? <= n 0 { ^ 0.0 } {}
    ( vec_clear [u] buf )
    ( vec_reserve [u] buf + n 1 )
    : *u dst ( vec_data [u] buf )
    : *u src_at # *u + # i src start
    ( nurl_memcpy dst src_at n )
    : u zero # u 0
    = . dst n zero
    ( vec_set_len [u] buf n )
    : s c_str # s dst
    ^ ( nurl_str_to_float c_str )
}

@ main → i {
    : s input_path `test_data.csv`
    : s output_path `nurl_sorted_data.csv`

    ? ( file_exists output_path ) {
        ( file_delete output_path )
        ( nurl_print `Removed existing ` ) ( nurl_print output_path ) ( nurl_print `\n` )
    } {}

    : i start_time ( monotonic_ns )
    ( nurl_print `Starting NURL sort process...\n` )

    : ! String IoErr res ( read_file input_path )
    ?? res {
        F e → { ( nurl_print `Failed to read file\n` ) ^ 1 }
        T content → {
            : i read_done_time ( monotonic_ns )
            ( nurl_print `Read file in ` )
            ( nurl_print ( nurl_str_int ( elapsed_ms_since start_time ) ) )
            ( nurl_print `ms\n` )

            ( nurl_print `Parsing rows...\n` )
            : ( Vec Row ) rows ( vec_new [Row] )
            : ~ i count 0

            : *u cd # *u ( string_data content )
            : i clen ( string_len content )
            : ( Vec u ) num_buf ( vec_with_cap [u] 32 )
            : ( Vec i ) marks ( vec_with_cap [i] 16 )
            : *i mp ( vec_data [i] marks )

            // Skip header line.
            : ~ i pos 0
            : ~ b in_header T
            ~ in_header {
                ? >= pos clen { = in_header F } {
                    : i hc # i . cd pos
                    = pos + pos 1
                    ? == hc 10 { = in_header F } {}
                }
            }

            : ~ b parsing T
            ~ parsing {
                ? >= pos clen { = parsing F } {
                    : ~ i field_start pos
                    : ~ i field_idx 0
                    : ~ b in_row T
                    ~ in_row {
                        ? >= pos clen {
                            ? < field_idx 8 {
                                = . mp * field_idx 2 field_start
                                = . mp + * field_idx 2 1 pos
                                = field_idx + field_idx 1
                            } {}
                            = in_row F
                        } {
                            : i c # i . cd pos
                            ? == c 44 {
                                ? < field_idx 8 {
                                    = . mp * field_idx 2 field_start
                                    = . mp + * field_idx 2 1 pos
                                    = field_idx + field_idx 1
                                } {}
                                = pos + pos 1
                                = field_start pos
                            } {
                                ? | == c 10 == c 13 {
                                    ? < field_idx 8 {
                                        = . mp * field_idx 2 field_start
                                        = . mp + * field_idx 2 1 pos
                                        = field_idx + field_idx 1
                                    } {}
                                    = pos + pos 1
                                    ? == c 13 {
                                        ? < pos clen {
                                            : i nx # i . cd pos
                                            ? == nx 10 { = pos + pos 1 } {}
                                        } {}
                                    } {}
                                    = in_row F
                                } {
                                    = pos + pos 1
                                }
                            }
                        }
                    }

                    ? == field_idx 8 {
                        // Strip trailing CR from each field end (already skipped during scan,
                        // but defensive). Field ranges in `marks` are byte offsets into `cd`.
                        : i v0 ( parse_int_bytes cd . mp 0 . mp 1 )
                        : i v1 ( parse_int_bytes cd . mp 2 . mp 3 )
                        : f v2 ( parse_float_bytes cd . mp 4 . mp 5 num_buf )
                        : f v3 ( parse_float_bytes cd . mp 6 . mp 7 num_buf )

                        : *u src0 # *u + # i cd . mp 0
                        : *u src1 # *u + # i cd . mp 2
                        : *u src2 # *u + # i cd . mp 4
                        : *u src3 # *u + # i cd . mp 6
                        : *u src4 # *u + # i cd . mp 8
                        : *u src5 # *u + # i cd . mp 10
                        : *u src6 # *u + # i cd . mp 12
                        : *u src7 # *u + # i cd . mp 14

                        : String s0 ( string_from_bytes src0 - . mp 1 . mp 0 )
                        : String s1 ( string_from_bytes src1 - . mp 3 . mp 2 )
                        : String s2 ( string_from_bytes src2 - . mp 5 . mp 4 )
                        : String s3 ( string_from_bytes src3 - . mp 7 . mp 6 )
                        : String s4 ( string_from_bytes src4 - . mp 9 . mp 8 )
                        : String s5 ( string_from_bytes src5 - . mp 11 . mp 10 )
                        : String s6 ( string_from_bytes src6 - . mp 13 . mp 12 )
                        : String s7 ( string_from_bytes src7 - . mp 15 . mp 14 )

                        : Row r @ Row { v0 v1 v2 v3 s0 s1 s2 s3 s4 s5 s6 s7 }
                        ( vec_push [Row] rows r )
                        = count + count 1
                        ? == % count 10000 0 {
                            ( nurl_print `Parsed ` ) ( nurl_print ( nurl_str_int count ) ) ( nurl_print ` rows...\n` )
                        } {}
                    } {}
                }
            }

            ( vec_free [u] num_buf )
            ( vec_free [i] marks )
            ( string_free content )

            : i parse_done_time ( monotonic_ns )
            ( nurl_print `Parsed ` ) ( nurl_print ( nurl_str_int ( vec_len [Row] rows ) ) ) ( nurl_print ` rows in ` )
            ( nurl_print ( nurl_str_int ( elapsed_ms_since read_done_time ) ) )
            ( nurl_print `ms\n` )

            ( nurl_print `Starting sort...\n` )
            ( sort_by [Row] rows \ Row a Row b → i { ^ ( cmp_row a b ) } )

            : i sort_done_time ( monotonic_ns )
            ( nurl_print `Sort completed in ` )
            ( nurl_print ( nurl_str_int ( elapsed_ms_since parse_done_time ) ) )
            ( nurl_print `ms\n` )

            : *v fh ( nurl_file_open output_path `w` )
            ( nurl_file_write fh `id,val_int,val_float1,val_float2,text_simple,text_mixed,text_words,date\n` )

            : *Row rdata ( vec_data [Row] rows )
            : ~ i j 0
            : i n_rows ( vec_len [Row] rows )
            ~ < j n_rows {
                : Row r . rdata j
                ( nurl_file_write fh ( string_data . r id ) )
                ( nurl_file_write fh `,` )
                ( nurl_file_write fh ( string_data . r val_int ) )
                ( nurl_file_write fh `,` )
                ( nurl_file_write fh ( string_data . r val_float1 ) )
                ( nurl_file_write fh `,` )
                ( nurl_file_write fh ( string_data . r val_float2 ) )
                ( nurl_file_write fh `,` )
                ( nurl_file_write fh ( string_data . r text_simple ) )
                ( nurl_file_write fh `,` )
                ( nurl_file_write fh ( string_data . r text_mixed ) )
                ( nurl_file_write fh `,` )
                ( nurl_file_write fh ( string_data . r text_words ) )
                ( nurl_file_write fh `,` )
                ( nurl_file_write fh ( string_data . r date ) )
                ( nurl_file_write fh `\n` )
                = j + j 1
            }
            ( nurl_file_close fh )

            : i write_done_time ( monotonic_ns )
            ( nurl_print `Write completed in ` )
            ( nurl_print ( nurl_str_int ( elapsed_ms_since sort_done_time ) ) )
            ( nurl_print `ms\n` )

            ( nurl_print `\nTotal time elapsed: ` )
            ( nurl_print ( nurl_str_int ( elapsed_ms_since start_time ) ) )
            ( nurl_print `ms\n` )

            : (@ v Row) r_free \ Row r → v { ( free_row r ) }
            ( vec_free_with [Row] rows r_free )
        }
    }

    ^ 0
}
