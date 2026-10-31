// packages/psql/src/pgwire.nu — the PostgreSQL v3 protocol as messages.
//
// The codec, with no socket and no lock in it: frontend messages are
// appended to a byte buffer, backend messages are framed and decoded out
// of one, and a collector folds the messages answering one request (up
// to its ReadyForQuery) into a result. pg.nu runs it over a connection;
// a writer that coalesces several requests into one write and a reader
// that hands each Sync-delimited answer to the request that sent it can
// run the same functions.
//
//   frontend   pgw_query  pgw_parse  pgw_describe  pgw_bind  pgw_execute
//              pgw_close  pgw_sync  pgw_terminate         → append to a ( Vec u )
//   framing    ( pgw_frame buf off )        → i   bytes of the complete message
//                                                  at off, 0 = need more, -1 = bad
//   answer     ( pgw_collect_new )  ( pgw_collect_feed c type buf off end )
//              → PgCollect: the result, the server's error, the
//                transaction status, done at ReadyForQuery
//   values     PgVal (a typed parameter) → binary or text per the type the
//              server inferred; a result cell ← text or binary per column
//
// Results are a flat table: every DataRow's payload is appended to one
// byte buffer as it arrived, and each cell is an (offset, length) span
// into it (length -1 = NULL) — one copy per row, nothing per cell. The
// typed accessors (pg_row_i, pg_row_f, pg_row_b, pg_row_s, …) decode a
// span in the column's format; a NULL, or a value the accessor's type
// does not hold, is F.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/arc.nu`

// ── type OIDs (pg_type.oid) ───────────────────────────────────────
: i PG_BOOL 16
: i PG_BYTEA 17
: i PG_INT8 20
: i PG_INT2 21
: i PG_INT4 23
: i PG_TEXT 25
: i PG_OID 26
: i PG_FLOAT4 700
: i PG_FLOAT8 701
: i PG_VARCHAR 1043
: i PG_DATE 1082
: i PG_TIME 1083
: i PG_TIMESTAMP 1114
: i PG_TIMESTAMPTZ 1184
: i PG_NUMERIC 1700
: i PG_UUID 2950

// Microseconds and days between the Unix epoch and PostgreSQL's
// (2000-01-01), the origin of its binary date and timestamp.
: i PG_EPOCH_US 946684800000000
: i PG_EPOCH_DAYS 10957

// A typed parameter. pg_query_params sends each in the format the type
// the server inferred for its `$n` takes best: binary where the
// representation is exact (integers, floats, bool, bytea, uuid,
// timestamps, date), the text form otherwise — which the server then
// parses as that type, so `PgText` serves any type and `PgInt` a
// numeric. Never interpolated into the SQL.
: | PgVal {
    PgNull
    PgInt i
    PgFloat f
    PgBool b
    PgText String
    PgBytes ( Vec u )  // bytea; or 16 bytes for a uuid
    PgTimestamp i  // microseconds since 1970-01-01 00:00:00 UTC
    PgDate i  // days since 1970-01-01
}

// A result column: its name, its type, and the format its cells came in
// (0 text, 1 binary).
: PgCol {
    String name
    i oid
    i fmt
}

// Row-major result table. Cell (r, c) is the span at index 2*(r*ncols+c)
// in `spans`: an offset into `data` and a length, -1 for NULL. The
// columns are shared, frozen, with the statement that made them — every
// result of a cached statement holds the one description — and the
// CommandComplete tag is a span of `data` too: a result is its two
// buffers and nothing else to allocate.
: PgResult {
    i ncols
    i nrows
    ( Arc ( Vec PgCol ) ) cols
    ( Vec u ) data
    ( Vec i ) spans
    i tag_off  // CommandComplete's tag (e.g. "SELECT 3", "INSERT 0 1"):
    i tag_len  // bytes [tag_off, tag_off + tag_len) of data
}

// An ErrorResponse / NoticeResponse, the fields a caller acts on.
: PgNotice {
    String severity  // ERROR, FATAL, …
    String code  // SQLSTATE
    String message
    String detail
    String hint
}

@ pg_result_empty → PgResult {
    ^ ( pgw_result_with ( arc_new [( Vec PgCol )] ( vec_new [PgCol] ) ) )
}

// An empty result whose rows will come in these columns (one share more
// of them, not a copy).
@ pgw_result_with ( Arc ( Vec PgCol ) ) cols → PgResult {
    : i n ( vec_len [PgCol] ( arc_get [( Vec PgCol )] cols ) )
    ^ @ PgResult { n 0 ( arc_clone [( Vec PgCol )] cols ) ( vec_new [u] ) ( vec_new [i] ) 0 0 }
}

// The result's columns, lent.
@ _pg_cols PgResult r → ( Vec PgCol ) { ^ ( arc_get [( Vec PgCol )] . r cols ) }

@ pgw_notice_empty → PgNotice {
    ^ @ PgNotice { ( string_new ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) }
}

// ── byte helpers ──────────────────────────────────────────────────
@ pgw_put16 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

@ pgw_put32 ( Vec u ) v i n → v {
    ( vec_push [u] v # u & >> n 24 255 )
    ( vec_push [u] v # u & >> n 16 255 )
    ( vec_push [u] v # u & >> n 8 255 )
    ( vec_push [u] v # u & n 255 )
}

@ pgw_put64 ( Vec u ) v i n → v {
    ( pgw_put32 v & >> n 32 4294967295 )
    ( pgw_put32 v & n 4294967295 )
}

@ pgw_put_slice ( Vec u ) v ( Slice u ) b → v {
    : i n ( slice_len [u] b )
    ( vec_reserve [u] v n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( slice_byte b k ) ) = k + k 1 }
}

@ pgw_put_raw ( Vec u ) v s raw → v { ( pgw_put_slice v ( slice_of_str raw ) ) }

@ pgw_put_cstr ( Vec u ) v s raw → v {
    ( pgw_put_raw v raw )
    ( vec_push [u] v # u 0 )
}

// Big-endian reads off a view; 0 past its end, like slice_byte.
@ pgw_u16 ( Slice u ) b i off → i {
    ^ | << ( slice_byte b off ) 8 ( slice_byte b + off 1 )
}

@ pgw_u32 ( Slice u ) b i off → i {
    ^ | | << ( slice_byte b off ) 24 << ( slice_byte b + off 1 ) 16 | << ( slice_byte b + off 2 ) 8 ( slice_byte b + off 3 )
}

@ pgw_i16 ( Slice u ) b i off → i {
    : i x ( pgw_u16 b off )
    ^ ? >= x 32768 - x 65536 x
}

@ pgw_i32 ( Slice u ) b i off → i {
    : i x ( pgw_u32 b off )
    ^ ? >= x 2147483648 - x 4294967296 x
}

@ pgw_i64 ( Slice u ) b i off → i {
    ^ | << ( pgw_u32 b off ) 32 ( pgw_u32 b + off 4 )
}

// The bytes [from, to) of a view as a String.
@ __pgw_str ( Slice u ) b i from i to → String {
    : i n ? > to from - to from 0
    : String out ( string_with_cap n )
    ? > n 0 { ( string_push_window out b from n ) } {}
    ^ out
}

// The NUL that ends the C string at `off`, or `end` when there is none.
@ __pgw_cstr_end ( Slice u ) b i off i end → i {
    : ~ i e off
    ~ & < e end != ( slice_byte b e ) 0 { = e + e 1 }
    ^ e
}

// ── frontend messages ─────────────────────────────────────────────
// A message is its type byte, a length word counting itself and the
// body, and the body: begin writes the first two (the length a
// placeholder), end patches the length once the body is in.
@ pgw_begin ( Vec u ) out i mtype → i {
    ( vec_push [u] out # u mtype )
    : i at ( vec_len [u] out )
    ( pgw_put32 out 0 )
    ^ at
}

@ pgw_end ( Vec u ) out i at → v {
    : i n - ( vec_len [u] out ) at
    : b _a ( vec_set [u] out at # u & >> n 24 255 )
    : b _b ( vec_set [u] out + at 1 # u & >> n 16 255 )
    : b _c ( vec_set [u] out + at 2 # u & >> n 8 255 )
    : b _d ( vec_set [u] out + at 3 # u & n 255 )
}

// Query: the simple protocol — any number of statements, text results.
@ pgw_query ( Vec u ) out s sql → v {
    : i at ( pgw_begin out 81 )
    ( pgw_put_cstr out sql )
    ( pgw_end out at )
}

// Parse a named statement ("" = the unnamed one), letting the server
// infer every parameter's type (no OIDs given).
@ pgw_parse ( Vec u ) out s name s sql → v {
    : i at ( pgw_begin out 80 )
    ( pgw_put_cstr out name )
    ( pgw_put_cstr out sql )
    ( pgw_put16 out 0 )
    ( pgw_end out at )
}

// Describe (kind 83 'S' a statement: ParameterDescription + RowDescription
// or NoData; kind 80 'P' a portal: RowDescription or NoData).
@ pgw_describe ( Vec u ) out i kind s name → v {
    : i at ( pgw_begin out 68 )
    ( vec_push [u] out # u kind )
    ( pgw_put_cstr out name )
    ( pgw_end out at )
}

// Close a statement (83 'S') or a portal (80 'P').
@ pgw_close ( Vec u ) out i kind s name → v {
    : i at ( pgw_begin out 67 )
    ( vec_push [u] out # u kind )
    ( pgw_put_cstr out name )
    ( pgw_end out at )
}

@ pgw_execute ( Vec u ) out s portal i max_rows → v {
    : i at ( pgw_begin out 69 )
    ( pgw_put_cstr out portal )
    ( pgw_put32 out max_rows )
    ( pgw_end out at )
}

@ pgw_sync ( Vec u ) out → v {
    ( vec_push [u] out # u 83 )
    ( pgw_put32 out 4 )
}

@ pgw_terminate ( Vec u ) out → v {
    ( vec_push [u] out # u 88 )
    ( pgw_put32 out 4 )
}

// Bind `params` to statement `stmt` as portal `portal`. `oids` are the
// parameter types the server inferred (ParameterDescription); each value
// goes in the format pgw_param_fmt picks for it. `rfmts` are the result
// columns' formats: none = all text, one = all that format, else one per
// column.
@ pgw_bind ( Vec u ) out s portal s stmt ( Vec PgVal ) params ( Vec i ) oids ( Vec i ) rfmts → v {
    : i np ( vec_len [PgVal] params )
    : i at ( pgw_begin out 66 )
    ( pgw_put_cstr out portal )
    ( pgw_put_cstr out stmt )
    ( pgw_put16 out np )
    : ~ i k 0
    ~ < k np {
        : i oid ?? ( vec_get [i] oids k ) { T o → o F → 0 }
        ( pgw_put16 out ( pgw_param_fmt ( vec_at [PgVal] params k ) oid ) )
        = k + k 1
    }
    ( pgw_put16 out np )
    = k 0
    ~ < k np {
        : i oid ?? ( vec_get [i] oids k ) { T o → o F → 0 }
        ( pgw_put_param out ( vec_at [PgVal] params k ) oid )
        = k + k 1
    }
    : i nr ( vec_len [i] rfmts )
    ( pgw_put16 out nr )
    = k 0
    ~ < k nr { ( pgw_put16 out ( vec_at [i] rfmts k ) ) = k + k 1 }
    ( pgw_end out at )
}

// ── parameter encoding ────────────────────────────────────────────
// 1 (binary) where the value's own representation is exactly what the
// type's binary form holds, 0 (its text form, which the server parses
// as the inferred type) everywhere else.
@ pgw_param_fmt PgVal v i oid → i {
    ^ ?? v {
        PgNull → 0
        PgInt n → ? | | | == oid PG_INT8 == oid PG_FLOAT8 == oid PG_FLOAT4 | | == oid PG_BOOL & == oid PG_INT4 & >= n -2147483648 <= n 2147483647 | & == oid PG_INT2 & >= n -32768 <= n 32767 & == oid PG_OID & >= n 0 <= n 4294967295 1 0
        PgFloat x → ? | == oid PG_FLOAT8 == oid PG_FLOAT4 1 0
        PgBool x → ? == oid PG_BOOL 1 0
        PgText t → 0
        PgBytes bs → ? | == oid PG_BYTEA & == oid PG_UUID == ( vec_len [u] bs ) 16 1 0
        PgTimestamp us → ? | | == oid PG_TIMESTAMP == oid PG_TIMESTAMPTZ == oid PG_DATE 1 0
        PgDate d → ? | | == oid PG_DATE == oid PG_TIMESTAMP == oid PG_TIMESTAMPTZ 1 0
    }
}

// Days (since 1970) holding the instant `us` (µs since 1970): floor.
@ __pgw_floor_div i a i b → i {
    : i q / a b
    ^ ? & != * q b a < a 0 - q 1 q
}

// The value's length word and bytes, in the format pgw_param_fmt picked.
@ pgw_put_param ( Vec u ) out PgVal v i oid → v {
    : i fmt ( pgw_param_fmt v oid )
    ?? v {
        PgNull → { ( pgw_put32 out -1 ) }
        PgInt n → {
            ? == fmt 1 {
                ? == oid PG_INT2 { ( pgw_put32 out 2 ) ( pgw_put16 out n ) ^ } {}
                ? | == oid PG_INT4 == oid PG_OID { ( pgw_put32 out 4 ) ( pgw_put32 out n ) ^ } {}
                ? == oid PG_BOOL { ( pgw_put32 out 1 ) ( vec_push [u] out # u ? != n 0 1 0 ) ^ } {}
                ? == oid PG_FLOAT8 { ( pgw_put32 out 8 ) ( pgw_put64 out ( f64_to_bits # f n ) ) ^ } {}
                ? == oid PG_FLOAT4 { ( pgw_put32 out 4 ) ( pgw_put32 out ( f32_to_bits # f32 # f n ) ) ^ } {}
                ( pgw_put32 out 8 ) ( pgw_put64 out n )
            } {
                : String t ( string_with_cap 24 )
                ( string_push_int t n )
                ( __pgw_put_text out t )
            }
        }
        PgFloat x → {
            ? == fmt 1 {
                ? == oid PG_FLOAT4 { ( pgw_put32 out 4 ) ( pgw_put32 out ( f32_to_bits # f32 x ) ) } { ( pgw_put32 out 8 ) ( pgw_put64 out ( f64_to_bits x ) ) }
            } {
                ( __pgw_put_text out ( pgw_float_text x ) )
            }
        }
        PgBool x → {
            ? == fmt 1 { ( pgw_put32 out 1 ) ( vec_push [u] out # u ? x 1 0 ) } {
                : String t ( string_from ? x `true` `false` )
                ( __pgw_put_text out t )
            }
        }
        PgText t → { ( __pgw_put_text out t ) }
        PgBytes bs → {
            ( pgw_put32 out ( vec_len [u] bs ) )
            ( bytes_extend_bytes out bs )
        }
        PgTimestamp us → {
            ? == fmt 1 {
                ? == oid PG_DATE {
                    ( pgw_put32 out 4 ) ( pgw_put32 out - ( __pgw_floor_div us 86400000000 ) PG_EPOCH_DAYS )
                } { ( pgw_put32 out 8 ) ( pgw_put64 out - us PG_EPOCH_US ) }
            } {
                : String t ( string_with_cap 32 )
                ( pgw_push_timestamp t - us PG_EPOCH_US F )
                ( __pgw_put_text out t )
            }
        }
        PgDate d → {
            ? == fmt 1 {
                ? == oid PG_DATE { ( pgw_put32 out 4 ) ( pgw_put32 out - d PG_EPOCH_DAYS ) } {
                    ( pgw_put32 out 8 ) ( pgw_put64 out * - d PG_EPOCH_DAYS 86400000000 )
                }
            } {
                : String t ( string_with_cap 16 )
                ( pgw_push_date t - d PG_EPOCH_DAYS )
                ( __pgw_put_text out t )
            }
        }
    }
}

@ __pgw_put_text ( Vec u ) out String t → v {
    ( pgw_put32 out ( string_len t ) )
    ( pgw_put_slice out ( string_bytes t ) )
}

// ── framing ───────────────────────────────────────────────────────
// The largest backend message accepted: a 1 GiB field (the most a
// PostgreSQL value holds) plus room for its row.
: i PGW_MAX_MSG 1090519040

// How many bytes the backend message starting at `off` takes, once all
// of it is in `buf`: 0 while it is not, -1 when its length word is not a
// length (fewer than 4, or past PGW_MAX_MSG — the stream is lost).
@ pgw_frame ( Vec u ) buf i off → i {
    : i have - ( vec_len [u] buf ) off
    ? < have 5 { ^ 0 } {}
    : ( Slice u ) b ( slice_from_vec [u] buf )
    : i len ( pgw_u32 b + off 1 )
    ? | < len 4 > len PGW_MAX_MSG { ^ -1 } {}
    ? < have + len 1 { ^ 0 } {}
    ^ + len 1
}

// ── backend message bodies ────────────────────────────────────────
// ErrorResponse / NoticeResponse: (code byte, C string)* then a 0.
@ pgw_notice ( Vec u ) buf i off i end → PgNotice {
    : ( Slice u ) b ( slice_from_vec [u] buf )
    : ~ PgNotice n ( pgw_notice_empty )
    : ~ i k off
    ~ < k end {
        : i field ( slice_byte b k )
        ? == field 0 { break } {}
        : i e ( __pgw_cstr_end b + k 1 end )
        : String val ( __pgw_str b + k 1 e )
        ? == field 86 { = . n severity val } {
            ? & == field 83 == ( string_len . n severity ) 0 { = . n severity val } {
                ? == field 67 { = . n code val } {
                    ? == field 77 { = . n message val } {
                        ? == field 68 { = . n detail val } {
                            ? == field 72 { = . n hint val } {}
                        }
                    }
                }
            }
        }
        = k + e 1
    }
    ^ n
}

@ pgw_notice_clone PgNotice n → PgNotice {
    ^ @ PgNotice {
        ( string_clone . n severity )
        ( string_clone . n code )
        ( string_clone . n message )
        ( string_clone . n detail )
        ( string_clone . n hint )
    }
}

// "[SQLSTATE] message" — the one-line form lasterr keeps.
@ pgw_notice_text PgNotice n → String {
    : String out ( string_with_cap + 16 ( string_len . n message ) )
    ( string_push_str out `[` )
    ( string_append out . n code )
    ( string_push_str out `] ` )
    ( string_append out . n message )
    ^ out
}

// RowDescription: the columns, with the format each will arrive in.
@ pgw_row_desc ( Vec u ) buf i off i end → ( Vec PgCol ) {
    : ( Slice u ) b ( slice_from_vec [u] buf )
    : i n ( pgw_u16 b off )
    : ( Vec PgCol ) cols ( vec_with_cap [PgCol] n )
    : ~ i k + off 2
    : ~ i c 0
    ~ & < c n < k end {
        : i e ( __pgw_cstr_end b k end )
        : String name ( __pgw_str b k e )
        // after the name: table oid(4) column(2) type oid(4) size(2) modifier(4) format(2)
        : i oid ( pgw_u32 b + e 7 )
        : i fmt ( pgw_u16 b + e 17 )
        ( vec_push [PgCol] cols @ PgCol { name oid fmt } )
        = k + e 19
        = c + c 1
    }
    ^ cols
}

// ParameterDescription: the type the server inferred for each `$n`.
@ pgw_param_desc ( Vec u ) buf i off i end → ( Vec i ) {
    : ( Slice u ) b ( slice_from_vec [u] buf )
    : i n ( pgw_u16 b off )
    : ( Vec i ) oids ( vec_with_cap [i] n )
    : ~ i k 0
    ~ & < k n <= + off + 2 * + k 1 4 end {
        ( vec_push [i] oids ( pgw_u32 b + off + 2 * k 4 ) )
        = k + k 1
    }
    ^ oids
}

// ── the answer to one request ─────────────────────────────────────
// What the backend says between a request and its ReadyForQuery, folded
// as it arrives. rc: 0 ok, 3 the server reported an error (`err`), 1 the
// stream broke (a message out of place, a row of the wrong width). What
// only some answers carry — an error, a statement's parameter types — is
// absent until one does, so an answer costs its result's buffers alone.
: PgCollect {
    PgResult res
    ? ( Vec i ) param_oids  // ParameterDescription (a Describe of a statement)
    b described  // a RowDescription or NoData answered a Describe
    i rc
    ? PgNotice err  // the ErrorResponse, when rc is 3
    i txn  // ReadyForQuery's status: 73 'I' idle, 84 'T' in a transaction, 69 'E' failed one
    b done
}

@ pgw_collect_new → PgCollect { ^ ( pgw_collect_for ( pg_result_empty ) ) }

// An answer whose rows come in the columns `res` already has — a cached
// statement, executed without a Describe (pgw_result_with) — or in the
// columns its own RowDescription will say.
@ pgw_collect_for sink PgResult res → PgCollect {
    ^ @ PgCollect { res @ ?( Vec i ) { F # ( Vec i ) 0 } F 0 @ ?PgNotice { F # PgNotice 0 } 0 F }
}

// One backend message, type `mtype`, body [off, end) of `buf`.
@ pgw_collect_feed inout PgCollect c i mtype ( Vec u ) buf i off i end → v {
    ? == mtype 68 {
        ( __pgw_data_row c buf off end )
        ^
    } {}
    ? == mtype 84 {
        // RowDescription: a new result set (the simple protocol runs each
        // statement of a script in turn; the last one's rows are kept).
        = . c res ( pgw_result_with ( arc_new [( Vec PgCol )] ( pgw_row_desc buf off end ) ) )
        = . c described T
        ^
    } {}
    ? == mtype 67 {
        // The tag goes onto the table's buffer, after the rows it counts.
        : i e ( __pgw_cstr_end ( slice_from_vec [u] buf ) off end )
        = . . c res tag_off ( vec_len [u] . . c res data )
        = . . c res tag_len - e off
        ( vec_extend_range [u] . . c res data buf off - e off )
        ^
    } {}
    ? == mtype 90 {
        = . c txn ( slice_byte ( slice_from_vec [u] buf ) off )
        = . c done T
        ^
    } {}
    ? == mtype 69 {
        = . c err @ ?PgNotice { T ( pgw_notice buf off end ) }
        = . c rc 3
        ^
    } {}
    ? == mtype 116 { = . c param_oids @ ?( Vec i ) { T ( pgw_param_desc buf off end ) } ^ } {}
    ? == mtype 110 { = . c described T ^ } {}
    // 49 ParseComplete, 50 BindComplete, 51 CloseComplete, 73
    // EmptyQueryResponse, 115 PortalSuspended, 78 NoticeResponse, 83
    // ParameterStatus, 65 NotificationResponse, 75 BackendKeyData: nothing
    // to fold.
}

// DataRow: the payload goes onto the table's buffer as one copy, and each
// field's span is read off the message.
@ __pgw_data_row inout PgCollect c ( Vec u ) buf i off i end → v {
    : ( Slice u ) b ( slice_from_vec [u] buf )
    : i nf ( pgw_u16 b off )
    ? != nf . . c res ncols {
        // (A row of another width than its RowDescription: a stream out of step.)
        ? == . c rc 0 { = . c rc 1 } {}
        ^
    } {}
    : i base ( vec_len [u] . . c res data )
    ( vec_extend_range [u] . . c res data buf off - end off )
    : ~ i k + off 2
    : ~ i f 0
    ~ < f nf {
        : i len ( pgw_i32 b k )
        ? < len 0 {
            ( vec_push [i] . . c res spans 0 )
            ( vec_push [i] . . c res spans -1 )
            = k + k 4
        } {
            ? > + + k 4 len end {
                ? == . c rc 0 { = . c rc 1 } {}
                ^
            } {}
            ( vec_push [i] . . c res spans + base - + k 4 off )
            ( vec_push [i] . . c res spans len )
            = k + + k 4 len
        }
        = f + f 1
    }
    = . . c res nrows + . . c res nrows 1
}

// ── result accessors ──────────────────────────────────────────────
@ pg_result_ncols PgResult r → i { ^ . r ncols }

@ pg_result_nrows PgResult r → i { ^ . r nrows }

// CommandComplete's tag ("SELECT 3", "UPDATE 2", …).
@ pg_result_tag PgResult r → String {
    : String out ( string_with_cap . r tag_len )
    ? > . r tag_len 0 { ( string_push_window out ( slice_from_vec [u] . r data ) . r tag_off . r tag_len ) } {}
    ^ out
}

// The rows a command touched or returned — the tag's last number, 0 when
// it has none (CREATE TABLE).
@ pg_result_affected PgResult r → i {
    : ( Slice u ) b ( slice_window [u] ( slice_from_vec [u] . r data ) . r tag_off . r tag_len )
    : i n ( slice_len [u] b )
    : ~ i k n
    ~ & > k 0 & >= ( slice_byte b - k 1 ) 48 <= ( slice_byte b - k 1 ) 57 { = k - k 1 }
    ? == k n { ^ 0 } {}
    ^ ( slice_parse_int ( slice_window [u] b k - n k ) )
}

@ pg_result_col PgResult r i col → String {
    ?? ( vec_get [PgCol] ( _pg_cols r ) col ) { T c → ^ ( string_clone . c name ) F → ^ ( string_new ) }
}

// The column's type OID (PG_INT4, PG_TEXT, …), 0 out of range.
@ pg_result_col_type PgResult r i col → i {
    ?? ( vec_get [PgCol] ( _pg_cols r ) col ) { T c → ^ . c oid F → ^ 0 }
}

// The format the column's cells came in: 0 text, 1 binary (-1 out of range).
@ pg_result_col_fmt PgResult r i col → i {
    ?? ( vec_get [PgCol] ( _pg_cols r ) col ) { T c → ^ . c fmt F → ^ -1 }
}

// The index of the column called `name`, F when there is none.
@ pg_result_col_index PgResult r s name → ?i {
    : ( Vec PgCol ) cols ( _pg_cols r )
    : i n ( vec_len [PgCol] cols )
    : ~ i k 0
    ~ < k n {
        ? ( nurl_str_eq ( string_data . ( vec_at [PgCol] cols k ) name ) name ) { ^ @ ?i { T k } } {}
        = k + k 1
    }
    ^ @ ?i { F 0 }
}

// The span of cell (row, col): [offset, length]; length -1 = NULL, -2 =
// no such cell.
@ __pg_span PgResult r i row i col → i {
    ? | | < row 0 >= row . r nrows | < col 0 >= col . r ncols { ^ -1 } {}
    ^ * 2 + * row . r ncols col
}

@ __pg_len PgResult r i row i col → i {
    : i at ( __pg_span r row col )
    ? < at 0 { ^ -2 } {}
    ^ ( vec_at [i] . r spans + at 1 )
}

@ __pg_off PgResult r i row i col → i { ^ ( vec_at [i] . r spans ( __pg_span r row col ) ) }

@ __pg_fmt PgResult r i col → i { ^ . ( vec_at [PgCol] ( _pg_cols r ) col ) fmt }

// T for a NULL — and for a cell outside the table.
@ pg_row_is_null PgResult r i row i col → b { ^ < ( __pg_len r row col ) 0 }

// The cell's raw bytes, a view of the result (text, or the type's binary
// form — pg_result_col_type says which type, and pg_row_s renders
// either). F for NULL.
@ pg_row_view PgResult r i row i col → ?( Slice u ) {
    : i n ( __pg_len r row col )
    ? < n 0 { ^ @ ?( Slice u ) { F ( slice_empty [u] ) } } {}
    ^ @ ?( Slice u ) { T ( slice_window [u] ( slice_from_vec [u] . r data ) ( __pg_off r row col ) n ) }
}

// An integer: int2 / int4 / int8 / oid (bool as 0 / 1), or a text cell
// that is one.
@ pg_row_i PgResult r i row i col → ?i {
    : i n ( __pg_len r row col )
    ? < n 0 { ^ @ ?i { F 0 } } {}
    : ( Slice u ) b ( slice_from_vec [u] . r data )
    : i off ( __pg_off r row col )
    ? == ( __pg_fmt r col ) 1 {
        : i oid . ( vec_at [PgCol] ( _pg_cols r ) col ) oid
        ? & == oid PG_INT2 == n 2 { ^ @ ?i { T ( pgw_i16 b off ) } } {}
        ? & == oid PG_INT4 == n 4 { ^ @ ?i { T ( pgw_i32 b off ) } } {}
        ? & == oid PG_OID == n 4 { ^ @ ?i { T ( pgw_u32 b off ) } } {}
        ? & == oid PG_INT8 == n 8 { ^ @ ?i { T ( pgw_i64 b off ) } } {}
        ? & == oid PG_BOOL == n 1 { ^ @ ?i { T ( slice_byte b off ) } } {}
        ^ @ ?i { F 0 }
    } {}
    ^ ( pgw_parse_int ( slice_window [u] b off n ) )
}

// A float: float4 / float8, an integer column, or a text cell that is a
// number (numeric included — to the nearest double).
@ pg_row_f PgResult r i row i col → ?f {
    : i n ( __pg_len r row col )
    ? < n 0 { ^ @ ?f { F 0.0 } } {}
    : ( Slice u ) b ( slice_from_vec [u] . r data )
    : i off ( __pg_off r row col )
    ? == ( __pg_fmt r col ) 1 {
        : i oid . ( vec_at [PgCol] ( _pg_cols r ) col ) oid
        ? & == oid PG_FLOAT8 == n 8 { ^ @ ?f { T ( bits_to_f64 ( pgw_i64 b off ) ) } } {}
        ? & == oid PG_FLOAT4 == n 4 { ^ @ ?f { T # f ( bits_to_f32 ( pgw_u32 b off ) ) } } {}
        ?? ( pg_row_i r row col ) { T x → { ^ @ ?f { T # f x } } F → { ^ @ ?f { F 0.0 } } }
    } {}
    ^ ( pgw_parse_float ( slice_window [u] b off n ) )
}

// A bool: bool, or a text cell `t` / `f` (`true` / `false`).
@ pg_row_b PgResult r i row i col → ?b {
    : i n ( __pg_len r row col )
    ? < n 0 { ^ @ ?b { F F } } {}
    : ( Slice u ) b ( slice_from_vec [u] . r data )
    : i off ( __pg_off r row col )
    ? == ( __pg_fmt r col ) 1 {
        ? & == . ( vec_at [PgCol] ( _pg_cols r ) col ) oid PG_BOOL == n 1 { ^ @ ?b { T != 0 ( slice_byte b off ) } } {}
        ^ @ ?b { F F }
    } {}
    : i c0 ( slice_byte b off )
    ? | == c0 116 == c0 84 { ^ @ ?b { T T } } {}
    ? | == c0 102 == c0 70 { ^ @ ?b { T F } } {}
    ^ @ ?b { F F }
}

// The cell as text: a text cell as it came, a binary one rendered as
// PostgreSQL writes its type (a timestamptz in UTC, `+00`).
@ pg_row_s PgResult r i row i col → ?String {
    : i n ( __pg_len r row col )
    ? < n 0 { ^ @ ?String { F } } {}
    : ( Slice u ) b ( slice_from_vec [u] . r data )
    : i off ( __pg_off r row col )
    ? == ( __pg_fmt r col ) 1 {
        ^ @ ?String { T ( pgw_render . ( vec_at [PgCol] ( _pg_cols r ) col ) oid ( slice_window [u] b off n ) ) }
    } {}
    ^ @ ?String { T ( __pgw_str b off + off n ) }
}

// The cell's bytes: a bytea's value (binary, or decoded from its `\x`
// text form), a uuid's 16 bytes, any other cell's text.
@ pg_row_bytes PgResult r i row i col → ?( Vec u ) {
    : i n ( __pg_len r row col )
    ? < n 0 { ^ @ ?( Vec u ) { F } } {}
    : ( Slice u ) b ( slice_from_vec [u] . r data )
    : i off ( __pg_off r row col )
    : ( Slice u ) w ( slice_window [u] b off n )
    ? & == ( __pg_fmt r col ) 0 == . ( vec_at [PgCol] ( _pg_cols r ) col ) oid PG_BYTEA {
        ? & >= n 2 & == ( slice_byte w 0 ) 92 == ( slice_byte w 1 ) 120 {
            : ( Vec u ) out ( vec_with_cap [u] / - n 2 2 )
            : ~ i k 2
            ~ < + k 1 n {
                ( vec_push [u] out # u | << ( __pgw_unhex ( slice_byte w k ) ) 4 ( __pgw_unhex ( slice_byte w + k 1 ) ) )
                = k + k 2
            }
            ^ @ ?( Vec u ) { T out }
        } {}
    } {}
    ^ @ ?( Vec u ) { T ( slice_to_vec [u] w ) }
}

// A timestamp / timestamptz as microseconds since 1970-01-01 00:00 UTC
// (a date as its midnight), binary or text (`YYYY-MM-DD[ HH:MM:SS[.f]][±HH[:MM]]`).
@ pg_row_ts PgResult r i row i col → ?i {
    : i n ( __pg_len r row col )
    ? < n 0 { ^ @ ?i { F 0 } } {}
    : ( Slice u ) b ( slice_from_vec [u] . r data )
    : i off ( __pg_off r row col )
    : i oid . ( vec_at [PgCol] ( _pg_cols r ) col ) oid
    ? == ( __pg_fmt r col ) 1 {
        ? & | == oid PG_TIMESTAMP == oid PG_TIMESTAMPTZ == n 8 { ^ @ ?i { T + ( pgw_i64 b off ) PG_EPOCH_US } } {}
        ? & == oid PG_DATE == n 4 { ^ @ ?i { T * + ( pgw_i32 b off ) PG_EPOCH_DAYS 86400000000 } } {}
        ^ @ ?i { F 0 }
    } {}
    ^ ( pgw_parse_timestamp ( slice_window [u] b off n ) )
}

// A date as days since 1970-01-01 (a timestamp's day), binary or text.
@ pg_row_date PgResult r i row i col → ?i {
    : i n ( __pg_len r row col )
    ? < n 0 { ^ @ ?i { F 0 } } {}
    : ( Slice u ) b ( slice_from_vec [u] . r data )
    : i off ( __pg_off r row col )
    ? & & == ( __pg_fmt r col ) 1 == . ( vec_at [PgCol] ( _pg_cols r ) col ) oid PG_DATE == n 4 {
        ^ @ ?i { T + ( pgw_i32 b off ) PG_EPOCH_DAYS }
    } {}
    ?? ( pg_row_ts r row col ) {
        T us → { ^ @ ?i { T ( __pgw_floor_div us 86400000000 ) } }
        F → { ^ @ ?i { F 0 } }
    }
}

// ── text forms ────────────────────────────────────────────────────
// A whole view that is a decimal integer (an optional sign, digits).
@ pgw_parse_int ( Slice u ) b → ?i {
    : i n ( slice_len [u] b )
    : ~ i k 0
    ? & > n 0 | == ( slice_byte b 0 ) 45 == ( slice_byte b 0 ) 43 { = k 1 } {}
    ? >= k n { ^ @ ?i { F 0 } } {}
    : ~ i j k
    ~ < j n {
        : i ch ( slice_byte b j )
        ? | < ch 48 > ch 57 { ^ @ ?i { F 0 } } {}
        = j + j 1
    }
    ^ @ ?i { T ( slice_parse_int b ) }
}

// A whole view that is a number: digits with an optional point and
// exponent, or NaN / Infinity / -Infinity (PostgreSQL's spellings).
@ pgw_parse_float ( Slice u ) b → ?f {
    : i n ( slice_len [u] b )
    ? == n 0 { ^ @ ?f { F 0.0 } } {}
    : ~ i digits 0
    : ~ i k 0
    ~ < k n {
        : i ch ( slice_byte b k )
        ? & >= ch 48 <= ch 57 { = digits + digits 1 } {
            ? | | | == ch 46 == ch 45 == ch 43 | | == ch 101 == ch 69 | | | == ch 73 == ch 110 == ch 102 | | | == ch 105 == ch 116 == ch 121 | | == ch 78 == ch 97 == ch 78 {} { ^ @ ?f { F 0.0 } }
        }
        = k + k 1
    }
    : i c0 ( slice_byte b ? | == ( slice_byte b 0 ) 45 == ( slice_byte b 0 ) 43 1 0 )
    ? & == digits 0 & != c0 73 != c0 78 { ^ @ ?f { F 0.0 } } {}
    ^ @ ?f { T ( slice_parse_float b ) }
}

// `n` digits of `x` (zero-padded).
@ __pgw_push_digits String out i x i n → v {
    : ~ i d 1
    : ~ i k 1
    ~ < k n { = d * d 10 = k + k 1 }
    : ~ i v x
    ~ > d 0 {
        ( string_push_char out + 48 / v d )
        = v % v d
        = d / d 10
    }
}

// The civil date of `days` since 2000-01-01 (H. Hinnant's algorithm,
// proleptic Gregorian): year, month, day.
: PgCivil { i y i m i d }

@ pgw_civil i days → PgCivil {
    : i z + days + PG_EPOCH_DAYS 719468
    : i era / ? >= z 0 z - z 146096 146097
    : i doe - z * era 146097
    : i yoe / - - + doe / doe 36524 / doe 1460 / doe 146096 365
    : i doy - doe - + * 365 yoe / yoe 4 / yoe 100
    : i mp / + * 5 doy 2 153
    : i d + - doy / + * 153 mp 2 5 1
    : i m ? < mp 10 + mp 3 - mp 9
    : i y + + yoe * era 400 ? <= m 2 1 0
    ^ @ PgCivil { y m d }
}

// Days since 2000-01-01 of a civil date.
@ pgw_days_from_civil i y0 i m i d → i {
    : i y - y0 ? <= m 2 1 0
    : i era / ? >= y 0 y - y 399 400
    : i yoe - y * era 400
    : i mp ? > m 2 - m 3 + m 9
    : i doy - + / + * 153 mp 2 5 d 1
    : i doe - + + * yoe 365 / yoe 4 doy / yoe 100
    ^ - - + * era 146097 doe 719468 PG_EPOCH_DAYS
}

// YYYY-MM-DD (a year before 1 as PostgreSQL writes it: `… BC`).
@ pgw_push_date String out i pgdays → v {
    : PgCivil c ( pgw_civil pgdays )
    : b bc <= . c y 0
    ( __pgw_push_digits out ? bc - 1 . c y . c y 4 )
    ( string_push_char out 45 )
    ( __pgw_push_digits out . c m 2 )
    ( string_push_char out 45 )
    ( __pgw_push_digits out . c d 2 )
    ? bc { ( string_push_str out ` BC` ) } {}
}

// HH:MM:SS[.ffffff] (trailing zeros of the fraction dropped).
@ pgw_push_time String out i us0 → v {
    : i us % us0 86400000000
    : i secs / us 1000000
    : i frac % us 1000000
    ( __pgw_push_digits out / secs 3600 2 )
    ( string_push_char out 58 )
    ( __pgw_push_digits out % / secs 60 60 2 )
    ( string_push_char out 58 )
    ( __pgw_push_digits out % secs 60 2 )
    ? > frac 0 {
        ( string_push_char out 46 )
        : ~ i f frac
        : ~ i w 6
        ~ == % f 10 0 { = f / f 10 = w - w 1 }
        ( __pgw_push_digits out f w )
    } {}
}

// A timestamp, `us` since 2000-01-01: date and time, `+00` for a
// timestamptz; ±infinity as PostgreSQL writes them.
@ pgw_push_timestamp String out i us b tz → v {
    ? == us 9223372036854775807 { ( string_push_str out `infinity` ) ^ } {}
    ? == us - -9223372036854775807 1 { ( string_push_str out `-infinity` ) ^ } {}
    : i days ( __pgw_floor_div us 86400000000 )
    : i rest - us * days 86400000000
    : PgCivil c ( pgw_civil days )
    : b bc <= . c y 0
    ( __pgw_push_digits out ? bc - 1 . c y . c y 4 )
    ( string_push_char out 45 )
    ( __pgw_push_digits out . c m 2 )
    ( string_push_char out 45 )
    ( __pgw_push_digits out . c d 2 )
    ( string_push_char out 32 )
    ( pgw_push_time out rest )
    ? tz { ( string_push_str out `+00` ) } {}
    ? bc { ( string_push_str out ` BC` ) } {}
}

// `n` decimal digits at `k`, or -1.
@ __pgw_digits_at ( Slice u ) b i k i n → i {
    : ~ i v 0
    : ~ i j 0
    ~ < j n {
        : i ch ( slice_byte b + k j )
        ? | < ch 48 > ch 57 { ^ -1 } {}
        = v + * v 10 - ch 48
        = j + j 1
    }
    ^ v
}

// YYYY-MM-DD[( |T)HH:MM[:SS[.ffffff]]][Z|±HH[:MM]] → µs since 1970 UTC.
@ pgw_parse_timestamp ( Slice u ) b → ?i {
    : i n ( slice_len [u] b )
    ? < n 10 { ^ @ ?i { F 0 } } {}
    : i y ( __pgw_digits_at b 0 4 )
    : i mo ( __pgw_digits_at b 5 2 )
    : i d ( __pgw_digits_at b 8 2 )
    ? | | < y 0 < mo 1 | < d 1 | != ( slice_byte b 4 ) 45 != ( slice_byte b 7 ) 45 { ^ @ ?i { F 0 } } {}
    : ~ i us * + ( pgw_days_from_civil y mo d ) PG_EPOCH_DAYS 86400000000
    : ~ i k 10
    ? & >= n 16 | == ( slice_byte b 10 ) 32 == ( slice_byte b 10 ) 84 {
        : i hh ( __pgw_digits_at b 11 2 )
        : i mi ( __pgw_digits_at b 14 2 )
        ? | < hh 0 < mi 0 { ^ @ ?i { F 0 } } {}
        = us + us * + * hh 60 mi 60000000
        = k 16
        ? & >= n 19 == ( slice_byte b 16 ) 58 {
            : i ss ( __pgw_digits_at b 17 2 )
            ? < ss 0 { ^ @ ?i { F 0 } } {}
            = us + us * ss 1000000
            = k 19
            ? & < k n == ( slice_byte b k ) 46 {
                = k + k 1
                : ~ i scale 100000
                ~ & < k n & >= ( slice_byte b k ) 48 <= ( slice_byte b k ) 57 {
                    = us + us * - ( slice_byte b k ) 48 scale
                    = scale / scale 10
                    = k + k 1
                }
            } {}
        } {}
    } {}
    ? < k n {
        : i sg ( slice_byte b k )
        ? == sg 90 { ^ @ ?i { T us } } {}
        ? | == sg 43 == sg 45 {
            : i oh ( __pgw_digits_at b + k 1 2 )
            ? < oh 0 { ^ @ ?i { F 0 } } {}
            : ~ i om 0
            ? & < + k 4 n == ( slice_byte b + k 3 ) 58 { = om ( __pgw_digits_at b + k 4 2 ) } {}
            ? < om 0 { ^ @ ?i { F 0 } } {}
            : i shift * + * oh 60 om 60000000
            ^ @ ?i { T ? == sg 43 - us shift + us shift }
        } {}
    } {}
    ^ @ ?i { T us }
}

@ __pgw_hex i nib → i { ^ ? < nib 10 + 48 nib + 87 nib }

@ __pgw_unhex i ch → i {
    ? & >= ch 48 <= ch 57 { ^ - ch 48 } {}
    ? & >= ch 97 <= ch 102 { ^ - ch 87 } {}
    ? & >= ch 65 <= ch 70 { ^ - ch 55 } {}
    ^ 0
}

// A double as PostgreSQL writes one: the shortest digits that round-trip,
// NaN / Infinity / -Infinity spelled its way.
@ pgw_float_text f x → String {
    : String out ( string_with_cap 24 )
    ? != x x { ( string_push_str out `NaN` ) ^ out } {}
    ? > x 1.7976931348623157e308 { ( string_push_str out `Infinity` ) ^ out } {}
    ? < x -1.7976931348623157e308 { ( string_push_str out `-Infinity` ) ^ out } {}
    ( string_push_float out x )
    ^ out
}

// The shortest decimal (at most 9 significant digits) that reads back as
// the same single-precision float.
@ __pgw_float4_text i bits → String {
    : f32 v ( bits_to_f32 bits )
    : f x # f v
    ? | != x x | > x 3.4028234663852886e38 < x -3.4028234663852886e38 { ^ ( pgw_float_text x ) } {}
    ? == x 0.0 { ^ ( pgw_float_text x ) } {}
    : ~ i p 1
    ~ < p 9 {
        : String t ( string_with_cap 24 )
        ( string_push_float t ( __pgw_round_sig x p ) )
        : ?f back ( string_to_float t )
        ?? back {
            T y → { ? == ( f32_to_bits # f32 y ) ( f32_to_bits v ) { ^ t } {} }
            F → {}
        }
        = p + p 1
    }
    ^ ( pgw_float_text x )
}

// x rounded to p significant decimal digits (as a double).
@ __pgw_round_sig f x i p → f {
    : f ax ? < x 0.0 - 0.0 x x
    : ~ i e 0
    : ~ f s ax
    ~ >= s 10.0 { = s / s 10.0 = e + e 1 }
    ~ < s 1.0 { = s * s 10.0 = e - e 1 }
    // x = s * 10^e, 1 <= s < 10; keep p digits of s.
    : ~ f scale 1.0
    : ~ i k 1
    ~ < k p { = scale * scale 10.0 = k + k 1 }
    : f m # f # i + * s scale 0.5
    : ~ f r / m scale
    : ~ i j e
    ~ > j 0 { = r * r 10.0 = j - j 1 }
    ~ < j 0 { = r / r 10.0 = j + j 1 }
    ^ ? < x 0.0 - 0.0 r r
}

// A binary cell of type `oid` in PostgreSQL's text form.
@ pgw_render i oid ( Slice u ) b → String {
    : i n ( slice_len [u] b )
    : String out ( string_with_cap 32 )
    ? & == oid PG_BOOL == n 1 { ( string_push_str out ? != 0 ( slice_byte b 0 ) `t` `f` ) ^ out } {}
    ? & == oid PG_INT2 == n 2 { ( string_push_int out ( pgw_i16 b 0 ) ) ^ out } {}
    ? & == oid PG_INT4 == n 4 { ( string_push_int out ( pgw_i32 b 0 ) ) ^ out } {}
    ? & == oid PG_OID == n 4 { ( string_push_int out ( pgw_u32 b 0 ) ) ^ out } {}
    ? & == oid PG_INT8 == n 8 { ( string_push_int out ( pgw_i64 b 0 ) ) ^ out } {}
    ? & == oid PG_FLOAT8 == n 8 { ^ ( pgw_float_text ( bits_to_f64 ( pgw_i64 b 0 ) ) ) } {}
    ? & == oid PG_FLOAT4 == n 4 { ^ ( __pgw_float4_text ( pgw_u32 b 0 ) ) } {}
    ? & == oid PG_DATE == n 4 {
        : i d ( pgw_i32 b 0 )
        ? == d 2147483647 { ( string_push_str out `infinity` ) ^ out } {}
        ? == d -2147483648 { ( string_push_str out `-infinity` ) ^ out } {}
        ( pgw_push_date out d ) ^ out
    } {}
    ? & == oid PG_TIMESTAMP == n 8 { ( pgw_push_timestamp out ( pgw_i64 b 0 ) F ) ^ out } {}
    ? & == oid PG_TIMESTAMPTZ == n 8 { ( pgw_push_timestamp out ( pgw_i64 b 0 ) T ) ^ out } {}
    ? & == oid PG_TIME == n 8 { ( pgw_push_time out ( pgw_i64 b 0 ) ) ^ out } {}
    ? & == oid PG_UUID == n 16 {
        : ~ i k 0
        ~ < k 16 {
            ? | | | == k 4 == k 6 == k 8 == k 10 { ( string_push_char out 45 ) } {}
            : i x ( slice_byte b k )
            ( string_push_char out ( __pgw_hex >> x 4 ) )
            ( string_push_char out ( __pgw_hex & x 15 ) )
            = k + k 1
        }
        ^ out
    } {}
    ? == oid PG_BYTEA {
        ( string_push_str out `\\x` )
        : ~ i k 0
        ~ < k n {
            : i x ( slice_byte b k )
            ( string_push_char out ( __pgw_hex >> x 4 ) )
            ( string_push_char out ( __pgw_hex & x 15 ) )
            = k + k 1
        }
        ^ out
    } {}
    // (A type this codec requests in text never comes binary; its bytes as they are.)
    ? > n 0 { ( string_push_window out b 0 n ) } {}
    ^ out
}

// The result format to ask for a column of type `oid`: binary for the
// fixed-width types decoded here, text for the rest.
@ pgw_result_fmt i oid → i {
    ? | | | == oid PG_INT2 == oid PG_INT4 == oid PG_INT8 == oid PG_OID { ^ 1 } {}
    ? | | | == oid PG_FLOAT4 == oid PG_FLOAT8 == oid PG_BOOL == oid PG_UUID { ^ 1 } {}
    ? | | | | == oid PG_DATE == oid PG_TIME == oid PG_TIMESTAMP == oid PG_TIMESTAMPTZ == oid PG_BYTEA { ^ 1 } {}
    ^ 0
}
