// packages/psql/tests/wire_test.nu — the protocol codec (src/pgwire.nu)
// with no server: frontend messages byte for byte, framing, the answer
// collector over hand-built backend streams, parameter encoding per
// inferred type, and every typed decoder and renderer. Build and run from
// the package root:
//
//   NURL_STDLIB=<repo-root> ../../nurl.sh tests/wire_test.nu /tmp/wire_test && /tmp/wire_test
//
// Exit status 0 = every check passed.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/pgwire.nu`
$ `stdlib/core/slice.nu`

: ~ i g_fail 0

@ ok s name b cond → v {
    ? cond { ( nurl_print `ok   ` ) } { ( nurl_print `FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

// `v` holds exactly the bytes listed (decimal, space separated).
@ bytes_are ( Vec u ) v s list → b {
    : ( Slice u ) l ( slice_of_str list )
    : i n ( slice_len [u] l )
    : ~ i k 0
    : ~ i at 0
    ~ < k n {
        ~ & < k n == ( slice_byte l k ) 32 { = k + k 1 }
        ? >= k n { break } {}
        : ~ i x 0
        ~ & < k n != ( slice_byte l k ) 32 { = x + * x 10 - ( slice_byte l k ) 48 = k + k 1 }
        ? >= at ( vec_len [u] v ) { ^ F } {}
        ? != # i ( vec_at [u] v at ) x { ^ F } {}
        = at + at 1
    }
    ^ == at ( vec_len [u] v )
}

@ str_is String s s want → b { ^ != 0 ( nurl_str_eq ( string_data s ) want ) }

@ opt_str_is ? String o s want → b {
    ?? o { T s → { ^ != 0 ( nurl_str_eq ( string_data s ) want ) } F → { ^ F } }
}

@ opt_i_is ? i o i want → b { ?? o { T x → { ^ == x want } F → { ^ F } } }

// A backend message: type, length, body.
@ backend ( Vec u ) out i mtype ( Vec u ) body → v {
    ( vec_push [u] out # u mtype )
    ( pgw_put32 out + 4 ( vec_len [u] body ) )
    ( bytes_extend_bytes out body )
}

// RowDescription field: name, then table oid, column, type, size, typmod, format.
@ col_desc ( Vec u ) body s name i oid i fmt → v {
    ( pgw_put_cstr body name )
    ( pgw_put32 body 0 ) ( pgw_put16 body 0 ) ( pgw_put32 body oid ) ( pgw_put16 body 4 ) ( pgw_put32 body -1 ) ( pgw_put16 body fmt )
}

// Feed every whole message of `wire` to a fresh collector, as pg.nu's
// reader does.
@ collect ( Vec u ) wire → PgCollect {
    : ~ PgCollect c ( pgw_collect_new )
    : ~ i at 0
    ~ ! . c done {
        : i n ( pgw_frame wire at )
        ? <= n 0 { break } {}
        ( pgw_collect_feed c # i ( vec_at [u] wire at ) wire + at 5 + at n )
        = at + at n
    }
    ^ c
}

// A one-column binary result holding `cell` (type `oid`), for the decoders.
@ one_cell i oid ( Vec u ) cell → PgResult {
    : ( Vec u ) wire ( vec_new [u] )
    : ( Vec u ) rd ( vec_new [u] )
    ( pgw_put16 rd 1 )
    ( col_desc rd `c` oid 1 )
    ( backend wire 84 rd )
    : ( Vec u ) dr ( vec_new [u] )
    ( pgw_put16 dr 1 )
    ( pgw_put32 dr ( vec_len [u] cell ) )
    ( bytes_extend_bytes dr cell )
    ( backend wire 68 dr )
    : ( Vec u ) z ( vec_new [u] )
    ( vec_push [u] z # u 73 )
    ( backend wire 90 z )
    : PgCollect c ( collect wire )
    ^ . c res
}

@ be ( Vec u ) v i x i n → v {
    : ~ i k - n 1
    ~ >= k 0 { ( vec_push [u] v # u & >> x * k 8 255 ) = k - k 1 }
}

@ cell_of i x i n → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( be v x n )
    ^ v
}

@ render i oid ( Vec u ) cell → String {
    ^ ( pgw_render oid ( slice_from_vec [u] cell ) )
}

@ main → i {
    // ── frontend messages ──
    : ( Vec u ) q ( vec_new [u] )
    ( pgw_query q `select 1` )
    ( ok `Query` ( bytes_are q `81 0 0 0 13 115 101 108 101 99 116 32 49 0` ) )

    : ( Vec u ) p ( vec_new [u] )
    ( pgw_parse p `s1` `select $1` )
    ( ok `Parse (no OIDs)` ( bytes_are p `80 0 0 0 19 115 49 0 115 101 108 101 99 116 32 36 49 0 0 0` ) )

    : ( Vec u ) d ( vec_new [u] )
    ( pgw_describe d 83 `s1` )
    ( pgw_sync d )
    ( pgw_execute d `` 0 )
    ( pgw_close d 83 `s1` )
    ( ok `Describe Sync Execute Close` ( bytes_are d `68 0 0 0 8 83 115 49 0 83 0 0 0 4 69 0 0 0 9 0 0 0 0 0 67 0 0 0 8 83 115 49 0` ) )

    // Bind: int4 42 binary, text `hi`, NULL, float8 1.5 binary, bool T
    // binary, 7 into a numeric as text; results all binary.
    : ( Vec PgVal ) ps ( vec_new [PgVal] )
    ( vec_push [PgVal] ps @ PgVal { PgInt 42 } )
    ( vec_push [PgVal] ps @ PgVal { PgText ( string_from `hi` ) } )
    ( vec_push [PgVal] ps @ PgVal { PgNull } )
    ( vec_push [PgVal] ps @ PgVal { PgFloat 1.5 } )
    ( vec_push [PgVal] ps @ PgVal { PgBool T } )
    ( vec_push [PgVal] ps @ PgVal { PgInt 7 } )
    : ( Vec i ) oids ( vec_new [i] )
    ( vec_push [i] oids PG_INT4 ) ( vec_push [i] oids PG_TEXT ) ( vec_push [i] oids PG_INT8 )
    ( vec_push [i] oids PG_FLOAT8 ) ( vec_push [i] oids PG_BOOL ) ( vec_push [i] oids PG_NUMERIC )
    : ( Vec i ) rf ( vec_new [i] )
    ( vec_push [i] rf 1 )
    : ( Vec u ) bd ( vec_new [u] )
    ( pgw_bind bd `` `s1` ps oids rf )
    ( ok `Bind typed parameters` ( bytes_are bd `66 0 0 0 68 0 115 49 0 0 6 0 1 0 0 0 0 0 1 0 1 0 0 0 6 0 0 0 4 0 0 0 42 0 0 0 2 104 105 255 255 255 255 0 0 0 8 63 248 0 0 0 0 0 0 0 0 0 1 1 0 0 0 1 55 0 1 0 1` ) )

    // The format a value takes, per inferred type.
    ( ok `int into int2 in range: binary` == ( pgw_param_fmt @ PgVal { PgInt 300 } PG_INT2 ) 1 )
    ( ok `int into int2 out of range: text (the server says why)` == ( pgw_param_fmt @ PgVal { PgInt 70000 } PG_INT2 ) 0 )
    ( ok `int into numeric: text` == ( pgw_param_fmt @ PgVal { PgInt 1 } PG_NUMERIC ) 0 )
    ( ok `text into anything: text` == ( pgw_param_fmt @ PgVal { PgText ( string_from `x` ) } PG_INT4 ) 0 )
    ( ok `16 bytes into uuid: binary` == ( pgw_param_fmt @ PgVal { PgBytes ( vec_zeroed [u] 16 ) } PG_UUID ) 1 )
    ( ok `timestamp into timestamptz: binary` == ( pgw_param_fmt @ PgVal { PgTimestamp 0 } PG_TIMESTAMPTZ ) 1 )
    : ( Vec u ) tsv ( vec_new [u] )
    ( pgw_put_param tsv @ PgVal { PgTimestamp 946684800000001 } PG_TIMESTAMPTZ )
    ( ok `timestamp binary is microseconds since 2000` ( bytes_are tsv `0 0 0 8 0 0 0 0 0 0 0 1` ) )
    : ( Vec u ) dv ( vec_new [u] )
    ( pgw_put_param dv @ PgVal { PgDate 10958 } PG_DATE )
    ( ok `date binary is days since 2000` ( bytes_are dv `0 0 0 4 0 0 0 1` ) )
    : ( Vec u ) tt ( vec_new [u] )
    ( pgw_put_param tt @ PgVal { PgTimestamp 1709210096500000 } PG_TEXT )
    ( ok `timestamp into text: its text form` ( bytes_are tt `0 0 0 21 50 48 50 52 45 48 50 45 50 57 32 49 50 58 51 52 58 53 54 46 53` ) )

    // ── framing ──
    : ( Vec u ) fr ( vec_new [u] )
    ( vec_push [u] fr # u 90 ) ( pgw_put32 fr 5 )
    ( ok `frame: not whole yet` == ( pgw_frame fr 0 ) 0 )
    ( vec_push [u] fr # u 73 )
    ( ok `frame: whole` == ( pgw_frame fr 0 ) 6 )
    : ( Vec u ) bad ( vec_new [u] )
    ( vec_push [u] bad # u 90 ) ( pgw_put32 bad 2 ) ( vec_push [u] bad # u 0 )
    ( ok `frame: a length below 4 is the stream lost` == ( pgw_frame bad 0 ) -1 )

    // ── an answer: two columns, a NULL, the tag, the status ──
    : ( Vec u ) w ( vec_new [u] )
    : ( Vec u ) rd ( vec_new [u] )
    ( pgw_put16 rd 2 )
    ( col_desc rd `id` PG_INT4 1 )
    ( col_desc rd `name` PG_TEXT 0 )
    ( backend w 84 rd )
    : ( Vec u ) r1 ( vec_new [u] )
    ( pgw_put16 r1 2 ) ( pgw_put32 r1 4 ) ( be r1 -7 4 ) ( pgw_put32 r1 3 ) ( pgw_put_raw r1 `ann` )
    ( backend w 68 r1 )
    : ( Vec u ) r2 ( vec_new [u] )
    ( pgw_put16 r2 2 ) ( pgw_put32 r2 4 ) ( be r2 1000000 4 ) ( pgw_put32 r2 -1 )
    ( backend w 68 r2 )
    : ( Vec u ) cc ( vec_new [u] )
    ( pgw_put_cstr cc `SELECT 2` )
    ( backend w 67 cc )
    : ( Vec u ) zz ( vec_new [u] )
    ( vec_push [u] zz # u 84 )
    ( backend w 90 zz )
    : PgCollect col ( collect w )
    : PgResult res . col res
    ( ok `collect: done` . col done )
    ( ok `collect: rc 0` == . col rc 0 )
    ( ok `collect: in a transaction` == . col txn 84 )
    ( ok `collect: 2 rows 2 cols` & == ( pg_result_nrows res ) 2 == ( pg_result_ncols res ) 2 )
    ( ok `collect: column names` & ( str_is ( pg_result_col res 0 ) `id` ) ( str_is ( pg_result_col res 1 ) `name` ) )
    ( ok `collect: column type` == ( pg_result_col_type res 0 ) PG_INT4 )
    ( ok `collect: column by name` ( opt_i_is ( pg_result_col_index res `name` ) 1 ) )
    ( ok `row_i binary negative` ( opt_i_is ( pg_row_i res 0 0 ) -7 ) )
    ( ok `row_i binary` ( opt_i_is ( pg_row_i res 1 0 ) 1000000 ) )
    ( ok `row_s text` ( opt_str_is ( pg_row_s res 0 1 ) `ann` ) )
    ( ok `row_s of a binary int renders it` ( opt_str_is ( pg_row_s res 0 0 ) `-7` ) )
    ( ok `NULL is F` ?? ( pg_row_s res 1 1 ) { T _ → F F → T } )
    ( ok `is_null` & ( pg_row_is_null res 1 1 ) ! ( pg_row_is_null res 0 1 ) )
    ( ok `text that is no integer is F` ?? ( pg_row_i res 0 1 ) { T _ → F F → T } )
    ( ok `outside the table is F` ?? ( pg_row_i res 5 0 ) { T _ → F F → T } )
    ( ok `tag` ( str_is ( pg_result_tag res ) `SELECT 2` ) )
    ( ok `affected` == ( pg_result_affected res ) 2 )

    // A script's later result set replaces the earlier one.
    : ( Vec u ) w2 ( vec_new [u] )
    : ( Vec u ) rda ( vec_new [u] )
    ( pgw_put16 rda 1 ) ( col_desc rda `a` PG_TEXT 0 )
    ( backend w2 84 rda )
    : ( Vec u ) da ( vec_new [u] )
    ( pgw_put16 da 1 ) ( pgw_put32 da 1 ) ( pgw_put_raw da `x` )
    ( backend w2 68 da )
    ( backend w2 68 da )
    : ( Vec u ) rdb ( vec_new [u] )
    ( pgw_put16 rdb 1 ) ( col_desc rdb `b` PG_TEXT 0 )
    ( backend w2 84 rdb )
    ( backend w2 68 da )
    ( backend w2 90 zz )
    : PgCollect c2 ( collect w2 )
    ( ok `script: the last result set` & == ( pg_result_nrows . c2 res ) 1 ( str_is ( pg_result_col . c2 res 0 ) `b` ) )

    // A row of the wrong width is the stream out of step.
    : ( Vec u ) w3 ( vec_new [u] )
    ( backend w3 84 rda )
    ( backend w3 68 r1 )
    ( backend w3 90 zz )
    : PgCollect c3 ( collect w3 )
    ( ok `row of another width: rc 1` == . c3 rc 1 )

    // ErrorResponse, then ReadyForQuery.
    : ( Vec u ) w4 ( vec_new [u] )
    : ( Vec u ) er ( vec_new [u] )
    ( vec_push [u] er # u 83 ) ( pgw_put_cstr er `ERROR` )
    ( vec_push [u] er # u 86 ) ( pgw_put_cstr er `ERROR` )
    ( vec_push [u] er # u 67 ) ( pgw_put_cstr er `42P01` )
    ( vec_push [u] er # u 77 ) ( pgw_put_cstr er `relation "nope" does not exist` )
    ( vec_push [u] er # u 72 ) ( pgw_put_cstr er `check the name` )
    ( vec_push [u] er # u 0 )
    ( backend w4 69 er )
    : ( Vec u ) zi ( vec_new [u] )
    ( vec_push [u] zi # u 69 )
    ( backend w4 90 zi )
    : PgCollect c4 ( collect w4 )
    ( ok `error: rc 3` == . c4 rc 3 )
    ( ok `error: failed transaction` == . c4 txn 69 )
    ?? . c4 err {
        T e → {
            ( ok `error: SQLSTATE` ( str_is . e code `42P01` ) )
            ( ok `error: hint` ( str_is . e hint `check the name` ) )
            ( ok `error: one line` ( str_is ( pgw_notice_text e ) `[42P01] relation "nope" does not exist` ) )
        }
        F → { ( ok `error: the notice is there` F ) }
    }

    // ParameterDescription + RowDescription answer a Describe.
    : ( Vec u ) w5 ( vec_new [u] )
    : ( Vec u ) one ( vec_new [u] )
    ( backend w5 49 one )
    : ( Vec u ) pd ( vec_new [u] )
    ( pgw_put16 pd 2 ) ( pgw_put32 pd PG_INT8 ) ( pgw_put32 pd PG_TEXT )
    ( backend w5 116 pd )
    ( backend w5 110 one )
    ( backend w5 90 zz )
    : PgCollect c5 ( collect w5 )
    ( ok `describe: parameter types` ?? . c5 param_oids { T po → & == ( vec_len [i] po ) 2 == ( vec_at [i] po 0 ) PG_INT8 F → F } )
    ( ok `describe: NoData` & . c5 described == ( pg_result_ncols . c5 res ) 0 )

    // ── binary decoders and renderers ──
    : PgResult rs ( one_cell PG_INT2 ( cell_of 65535 2 ) )
    ( ok `int2 -1` ( opt_i_is ( pg_row_i rs 0 0 ) -1 ) )
    : PgResult r8 ( one_cell PG_INT8 ( cell_of -9223372036854775807 8 ) )
    ( ok `int8 near min` ( opt_i_is ( pg_row_i r8 0 0 ) -9223372036854775807 ) )
    : PgResult rf8 ( one_cell PG_FLOAT8 ( cell_of 4609434218613702656 8 ) )
    ( ok `float8 1.5` ?? ( pg_row_f rf8 0 0 ) { T x → == x 1.5 F → F } )
    ( ok `float8 renders` ( opt_str_is ( pg_row_s rf8 0 0 ) `1.5` ) )
    : PgResult rf4 ( one_cell PG_FLOAT4 ( cell_of 1036831949 4 ) )
    ( ok `float4 0.1 renders shortest` ( opt_str_is ( pg_row_s rf4 0 0 ) `0.1` ) )
    ( ok `float4 0.1 as f` ?? ( pg_row_f rf4 0 0 ) { T x → & > x 0.0999999 < x 0.1000001 F → F } )
    ( ok `float8 NaN` ( str_is ( render PG_FLOAT8 ( cell_of 9221120237041090560 8 ) ) `NaN` ) )
    ( ok `float8 -Infinity` ( str_is ( render PG_FLOAT8 ( cell_of -4503599627370496 8 ) ) `-Infinity` ) )
    : PgResult rb ( one_cell PG_BOOL ( cell_of 1 1 ) )
    ( ok `bool` ?? ( pg_row_b rb 0 0 ) { T x → x F → F } )
    ( ok `bool renders t` ( opt_str_is ( pg_row_s rb 0 0 ) `t` ) )
    : ( Vec u ) uu ( vec_new [u] )
    ( be uu 81985529216486895 8 ) ( be uu -81985529216486896 8 )
    ( ok `uuid renders` ( str_is ( render PG_UUID uu ) `01234567-89ab-cdef-fedc-ba9876543210` ) )
    // 2024-02-29 12:34:56.5 = 762525296500000 µs after 2000-01-01.
    ( ok `timestamp renders` ( str_is ( render PG_TIMESTAMP ( cell_of 762525296500000 8 ) ) `2024-02-29 12:34:56.5` ) )
    ( ok `timestamptz renders in UTC` ( str_is ( render PG_TIMESTAMPTZ ( cell_of 0 8 ) ) `2000-01-01 00:00:00+00` ) )
    ( ok `timestamp before 2000` ( str_is ( render PG_TIMESTAMP ( cell_of -1 8 ) ) `1999-12-31 23:59:59.999999` ) )
    ( ok `timestamp infinity` ( str_is ( render PG_TIMESTAMP ( cell_of 9223372036854775807 8 ) ) `infinity` ) )
    : PgResult rts ( one_cell PG_TIMESTAMPTZ ( cell_of 762525296500000 8 ) )
    ( ok `row_ts is unix microseconds` ( opt_i_is ( pg_row_ts rts 0 0 ) 1709210096500000 ) )
    ( ok `row_date of a timestamp` ( opt_i_is ( pg_row_date rts 0 0 ) 19782 ) )
    ( ok `date renders` ( str_is ( render PG_DATE ( cell_of 8825 4 ) ) `2024-02-29` ) )
    ( ok `date BC` ( str_is ( render PG_DATE ( cell_of -730120 4 ) ) `0001-12-31 BC` ) )
    : PgResult rdt ( one_cell PG_DATE ( cell_of 8825 4 ) )
    ( ok `row_date is unix days` ( opt_i_is ( pg_row_date rdt 0 0 ) 19782 ) )
    ( ok `time renders` ( str_is ( render PG_TIME ( cell_of 45296000001 8 ) ) `12:34:56.000001` ) )
    : ( Vec u ) by ( vec_new [u] )
    ( vec_push [u] by # u 0 ) ( vec_push [u] by # u 171 ) ( vec_push [u] by # u 255 )
    ( ok `bytea renders` ( str_is ( render PG_BYTEA by ) `\\x00abff` ) )
    : PgResult rby ( one_cell PG_BYTEA by )
    ( ok `row_bytes binary` ?? ( pg_row_bytes rby 0 0 ) { T v → ( bytes_are v `0 171 255` ) F → F } )

    // ── text forms ──
    ( ok `parse_int` ( opt_i_is ( pgw_parse_int ( slice_of_str `-42` ) ) -42 ) )
    ( ok `parse_int rejects 12a` ?? ( pgw_parse_int ( slice_of_str `12a` ) ) { T _ → F F → T } )
    ( ok `parse_int rejects a bare sign` ?? ( pgw_parse_int ( slice_of_str `-` ) ) { T _ → F F → T } )
    ( ok `parse_float` ?? ( pgw_parse_float ( slice_of_str `2.5e3` ) ) { T x → == x 2500.0 F → F } )
    ( ok `parse_float Infinity` ?? ( pgw_parse_float ( slice_of_str `-Infinity` ) ) { T x → < x -1.0e308 F → F } )
    ( ok `parse_float rejects 1.2.x` ?? ( pgw_parse_float ( slice_of_str `1x` ) ) { T _ → F F → T } )
    ( ok `parse_timestamp` ( opt_i_is ( pgw_parse_timestamp ( slice_of_str `2024-02-29 12:34:56.5` ) ) 1709210096500000 ) )
    ( ok `parse_timestamp with offset` ( opt_i_is ( pgw_parse_timestamp ( slice_of_str `2024-02-29 14:34:56.5+02` ) ) 1709210096500000 ) )
    ( ok `parse_timestamp date only` ( opt_i_is ( pgw_parse_timestamp ( slice_of_str `1970-01-02` ) ) 86400000000 ) )
    ( ok `parse_timestamp rejects garbage` ?? ( pgw_parse_timestamp ( slice_of_str `2024/02/29` ) ) { T _ → F F → T } )
    ( ok `float text` ( str_is ( pgw_float_text 0.25 ) `0.25` ) )
    ( ok `civil round trip` == ( pgw_days_from_civil 2024 2 29 ) 8825 )

    ? > g_fail 0 {
        ( nurl_print ( nurl_str_int g_fail ) ) ( nurl_print ` FAILED\n` )
        ^ 1
    } {}
    ( nurl_print `all passed\n` )
    ^ 0
}
