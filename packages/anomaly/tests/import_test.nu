// import_test.nu — a file of history becomes a stream of points.
//
//   parse   — CSV with a header, quoted cells, an odd delimiter; JSON as
//             an array or wrapped in one; JSONL; and what each does with a
//             row it cannot read.
//   sniff   — a body that does not say what it is.
//   ingest  — timestamps from the FILE, merged into the ring in order,
//             evicted from the oldest end, trained once at the end.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_import_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `src/importer.nu`
$ `src/dynamic.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: i T0 1700000000

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_fail + g_fail 1
    }
}

@ streq String a s b → b { ^ == ( nurl_str_eq ( string_data a ) b ) 1 }

// The value of `key` in row `idx`, as text ("" when absent).
@ cell ImportParse ip i idx s key → String {
    ?? ( vec_get [Json] . ip rows idx ) {
        T row → {
            ?? ( json_obj_get row key ) {
                T v → {
                    ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {}
                    : String out ( string_new )
                    ( string_push_int out ( json_as_int v ) )
                    ^ out
                }
                F _ → { ^ ( string_new ) }
            }
        }
        F _ → { ^ ( string_new ) }
    }
}

@ has_key ImportParse ip i idx s key → b {
    ?? ( vec_get [Json] . ip rows idx ) {
        T row → { ^ ( json_obj_has row key ) }
        F _ → { ^ F }
    }
}

@ test_csv → v {
    : ImportParse ip ( import_parse `temp,room,when
21.5,kitchen,2026-01-01T00:00:00Z
22.0,"living, room",2026-01-01T00:01:00Z
` `csv` )
    ( check == ( string_len . ip err ) 0 `csv: it parses` )
    ( check ( streq . ip format `csv` ) `csv: reported as csv` )
    ( check == ( vec_len [Json] . ip rows ) 2 `csv: two rows` )
    : String t0 ( cell ip 0 `room` )
    ( check ( streq t0 `kitchen` ) `csv: a text cell stays text` )
    ( string_free t0 )
    // A delimiter inside quotes is data, not a column break — the row would
    // otherwise have one field too many and be thrown away.
    : String t1 ( cell ip 1 `room` )
    ( check ( streq t1 `living, room` ) `csv: a quoted delimiter is data` )
    ( string_free t1 )
    ( check ( has_key ip 0 `temp` ) `csv: the numeric column is there` )
    ( import_parse_free ip )

    // Semicolons, because that is what a spreadsheet in half of Europe
    // writes and its author has no reason to know.
    : ImportParse semi ( import_parse `a;b
1;2
` `csv` )
    ( check == ( vec_len [Json] . semi rows ) 1 `csv: a semicolon file parses` )
    ( check ( has_key semi 0 `b` ) `csv: with both columns` )
    ( import_parse_free semi )

    // A blank cell contributes no field rather than an empty category.
    : ImportParse blank ( import_parse `a,b
1,
` `csv` )
    ( check ( has_key blank 0 `a` ) `csv: the filled column is present` )
    ( check ! ( has_key blank 0 `b` ) `csv: a blank cell yields no field` )
    ( import_parse_free blank )

    // One bad row does not fail a file.
    : ImportParse ragged ( import_parse `a,b
1,2
3
4,5
` `csv` )
    ( check == ( vec_len [Json] . ragged rows ) 2 `csv: the good rows survive` )
    ( check == . ragged skipped 1 `csv: the ragged row is counted` )
    ( check > ( vec_len [String] . ragged notes ) 0 `csv: and described` )
    ( import_parse_free ragged )

    : ImportParse nohdr ( import_parse `` `csv` )
    ( check > ( string_len . nohdr err ) 0 `csv: an empty file is an error` )
    ( import_parse_free nohdr )
}

@ test_json → v {
    : ImportParse arr ( import_parse `[{"a":1},{"a":2}]` `json` )
    ( check == ( vec_len [Json] . arr rows ) 2 `json: a bare array` )
    ( import_parse_free arr )

    // What this service's own /data route emits, wrapped in its envelope.
    : ImportParse wrapped ( import_parse `{"status":"success","data":[{"a":1}]}` `json` )
    ( check == ( vec_len [Json] . wrapped rows ) 1 `json: an array under "data"` )
    ( import_parse_free wrapped )
    : ImportParse pts ( import_parse `{"points":[{"a":1},{"a":2}]}` `json` )
    ( check == ( vec_len [Json] . pts rows ) 2 `json: or under "points"` )
    ( import_parse_free pts )

    : ImportParse mixed ( import_parse `[{"a":1},5,{"a":2}]` `json` )
    ( check == ( vec_len [Json] . mixed rows ) 2 `json: a non-object is skipped` )
    ( check == . mixed skipped 1 `json: and counted` )
    ( import_parse_free mixed )

    : ImportParse bad ( import_parse `{ not json` `json` )
    ( check > ( string_len . bad err ) 0 `json: malformed is an error` )
    ( import_parse_free bad )
    : ImportParse noarr ( import_parse `{"a":1}` `json` )
    ( check > ( string_len . noarr err ) 0 `json: an object with no array is an error` )
    ( import_parse_free noarr )
}

@ test_jsonl → v {
    : ImportParse ip ( import_parse `{"a":1}
{"a":2}

{"a":3}
` `jsonl` )
    ( check == ( vec_len [Json] . ip rows ) 3 `jsonl: blank lines are not rows` )
    ( check == . ip skipped 0 `jsonl: and are not failures either` )
    ( import_parse_free ip )

    : ImportParse bad ( import_parse `{"a":1}
oops
{"a":2}
` `jsonl` )
    ( check == ( vec_len [Json] . bad rows ) 2 `jsonl: a bad line does not stop the file` )
    ( check == . bad skipped 1 `jsonl: it is counted` )
    ( import_parse_free bad )
}

@ test_sniff → v {
    : String a ( import_sniff `[{"a":1}]` )
    ( check ( streq a `json` ) `sniff: a leading bracket is json` )
    ( string_free a )
    : String b ( import_sniff `{"a":1}
{"a":2}` )
    ( check ( streq b `jsonl` ) `sniff: repeated objects are jsonl` )
    ( string_free b )
    : String c ( import_sniff `{"data":[{"a":1}]}` )
    ( check ( streq c `json` ) `sniff: one object is json` )
    ( string_free c )
    : String d ( import_sniff `a,b
1,2` )
    ( check ( streq d `csv` ) `sniff: anything else is csv` )
    ( string_free d )

    // auto is the same decision, made for a caller who did not say.
    : ImportParse ip ( import_parse `a,b
1,2
` `auto` )
    ( check ( streq . ip format `csv` ) `sniff: auto reports what it chose` )
    ( check == ( vec_len [Json] . ip rows ) 1 `sniff: and parses it` )
    ( import_parse_free ip )

    : ImportParse bad ( import_parse `a,b
1,2
` `wizard` )
    ( check > ( string_len . bad err ) 0 `sniff: an unknown format is refused` )
    ( import_parse_free bad )
}

// Build a JSONL body of `n` points, one per minute from `from`.
@ mk_jsonl i from i n → String {
    : String out ( string_new )
    : ~ i k 0
    ~ < k n {
        ( string_push_str out `{"temp":` )
        ( string_push_int out + 20 % k 5 )
        ( string_push_str out `,"timestamp":` )
        ( string_push_int out + from * k 60 )
        ( string_push_str out `}` )
        ( string_push_char out 10 )
        = k + k 1
    }
    ^ out
}

@ test_ingest Store st → v {
    : *Model mo ( model_open_at st `imported` T0 )
    ( model_set_limits mo 30 150000 )
    ( model_set_schedule mo 1000000 1000000 )

    : String body ( mk_jsonl T0 120 )
    : ImportParse ip ( import_parse ( string_data body ) `jsonl` )
    ( string_free body )
    ( check == ( vec_len [Json] . ip rows ) 120 `ingest: the file parses` )
    : ImportReport rep ( model_import_at mo . ip rows + T0 100000 )
    ( check == ( string_len . rep err ) 0 `ingest: it imports` )
    ( check == . rep accepted 120 `ingest: every row landed` )
    ( check == . rep stored 120 `ingest: and the ring holds them` )
    // Enough history arrived to train on, so it trains — once, at the end.
    ( check . rep trained `ingest: the model trained afterwards` )
    ( check ( model_is_trained mo ) `ingest: and is trained` )
    ( import_report_free rep )
    ( import_parse_free ip )

    // The timestamps came from the FILE. History that all landed at "now"
    // would make every time window see one instant.
    : ~ i first 0
    : ~ i last 0
    ?? ( vec_get [i] . mo times 0 ) { T x → { = first x } F _ → {} }
    ?? ( vec_get [i] . mo times 119 ) { T x → { = last x } F _ → {} }
    ( check == first T0 `ingest: the first point kept its own timestamp` )
    ( check == last + T0 * 119 60 `ingest: and so did the last` )

    // A second import of OLDER history must land before what is there, not
    // after it: the ring is read as a time sequence by every window.
    : String older ( mk_jsonl - T0 86400 30 )
    : ImportParse ip2 ( import_parse ( string_data older ) `jsonl` )
    ( string_free older )
    : ImportReport rep2 ( model_import_at mo . ip2 rows + T0 100000 )
    ( check == . rep2 accepted 30 `ingest: the older file imports` )
    ( check == . rep2 stored 150 `ingest: the ring holds both` )
    ( import_report_free rep2 )
    ( import_parse_free ip2 )
    : ~ b ordered T
    : ~ i prev -1
    : ~ i k 0
    ~ < k ( vec_len [i] . mo times ) {
        ?? ( vec_get [i] . mo times k ) {
            T x → { ? < x prev { = ordered F } {} = prev x }
            F _ → {}
        }
        = k + k 1
    }
    ( check ordered `ingest: the ring is still in time order` )
    : ~ i newfirst 0
    ?? ( vec_get [i] . mo times 0 ) { T x → { = newfirst x } F _ → {} }
    ( check == newfirst - T0 86400 `ingest: the older history is at the front` )
    ( model_free mo )
}

@ test_evict Store st → v {
    // A file bigger than the ring is a file whose TAIL the model keeps.
    : *Model mo ( model_open_at st `evicted` T0 )
    ( model_set_limits mo 30 40 )
    ( model_set_schedule mo 1000000 1000000 )
    : String body ( mk_jsonl T0 100 )
    : ImportParse ip ( import_parse ( string_data body ) `jsonl` )
    ( string_free body )
    : ImportReport rep ( model_import_at mo . ip rows + T0 100000 )
    ( check == . rep accepted 100 `evict: every row was read` )
    ( check == . rep stored 40 `evict: the ring keeps its cap` )
    : ~ i first 0
    ?? ( vec_get [i] . mo times 0 ) { T x → { = first x } F _ → {} }
    ( check == first + T0 * 60 60 `evict: and it is the newest 40 that stayed` )
    ( import_report_free rep )
    ( import_parse_free ip )
    ( model_free mo )
}

@ test_reject Store st → v {
    : *Model mo ( model_open_at st `rejected` T0 )
    ( model_set_limits mo 30 150000 )
    ( model_set_schedule mo 1000000 1000000 )
    : ( Vec Json ) none ( vec_new [Json] )
    : ImportReport empty ( model_import_at mo none T0 )
    ( check > ( string_len . empty err ) 0 `reject: an empty import is an error` )
    ( import_report_free empty )
    ( vec_free [Json] none )
    ( check == ( model_n_points mo ) 0 `reject: and changed nothing` )
    ( model_free mo )
}

@ main → i {
    : String root ( env_var_or `ANOMALY_TEST_DIR` `./anomaly_import_test` )
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    : Store st ( store_open ( string_data root ) )

    ( test_csv )
    ( test_json )
    ( test_jsonl )
    ( test_sniff )
    ( test_ingest st )
    ( test_evict st )
    ( test_reject st )

    ( store_free st )
    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )
    ( nurl_print `import_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
