// json_writer: the streaming writer (stdlib/ext/json.nu, Agora #270)
// writes JSON straight into a ( Vec u ) — the same text json_stringify
// gives the same document, byte for byte — and refuses a misuse
// (a value where an object wants a key, an end with nothing open, …) by
// writing nothing and reporting jw_ok F, instead of emitting text that is
// not JSON. Safe code only.
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`

@ show s label ( Vec u ) out → v {
    ( nurl_print label )
    ( nurl_print `: ` )
    ( write_slice ( slice_from_vec [u] out ) )
    ( nurl_print `\n` )
}

// The same, with DEL (which JSON passes through) spelled out, so the
// expected output holds no raw control byte.
@ show_visible s label ( Vec u ) out → v {
    : ( Vec u ) vis ( vec_new [u] )
    : i n ( vec_len [u] out )
    : ~ i k 0
    ~ < k n {
        : u c ( vec_at [u] out k )
        ? == # i c 127 { ( bytes_extend_str vis `<DEL>` ) } { ( vec_push [u] vis c ) }
        = k + k 1
    }
    ( show label vis )
}

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `: ok\n` `: FAILED\n` )
}

// The writer's bytes against json_stringify's String.
@ same_text ( Vec u ) out String want → b {
    ^ ( slice_bytes_eq ( slice_from_vec [u] out ) ( string_bytes want ) )
}

// Every byte the escaper treats differently: `"` and `\`, the control
// bytes with a named escape (tab, newline, CR, backspace, form feed),
// others (0x01, 0x1f, an embedded NUL) as \u00XX, and DEL and multi-byte
// UTF-8 as they are.
@ tricky_text → String {
    : String t ( string_from `say "hi" \\ ` )
    ( string_push_char t 9 )
    ( string_push_char t 10 )
    ( string_push_char t 13 )
    ( string_push_char t 8 )
    ( string_push_char t 12 )
    ( string_push_char t 1 )
    ( string_push_char t 31 )
    ( string_push_char t 0 )
    ( string_push_char t 127 )
    ( string_push_str t ` é 😀` )
    ^ t
}

// A DOM with every kind of value.
@ sample_dom → Json {
    : ( Vec Json ) tags ( vec_new [Json] )
    ( vec_push [Json] tags ( json_str_lit `a` ) )
    ( vec_push [Json] tags ( json_int -42 ) )
    ( vec_push [Json] tags ( json_float 85.0 ) )
    ( vec_push [Json] tags ( json_float 0.001 ) )
    ( vec_push [Json] tags ( json_null ) )
    ( vec_push [Json] tags ( json_bool F ) )
    ( vec_push [Json] tags ( json_arr_new ) )
    ( vec_push [Json] tags ( json_obj_new ) )
    : ( Vec Json ) kv ( vec_new [Json] )
    ( vec_push [Json] kv ( json_str_lit `id` ) )
    ( vec_push [Json] kv ( json_int 9223372036854775807 ) )
    ( vec_push [Json] kv ( json_str_lit `text` ) )
    ( vec_push [Json] kv @ Json { JStr ( tricky_text ) } )
    ( vec_push [Json] kv ( json_str_lit `key with "quote"` ) )
    ( vec_push [Json] kv ( json_bool T ) )
    ( vec_push [Json] kv ( json_str_lit `tags` ) )
    ( vec_push [Json] kv ( json_arr tags ) )
    ^ ( json_obj kv )
}

// The same document through the writer.
@ sample_written ( Vec u ) out → b {
    : JsonWriter w ( json_writer )
    ( jw_obj w out )
    ( jw_key w out `id` ) ( jw_int w out 9223372036854775807 )
    ( jw_key w out `text` ) ( jw_string w out ( tricky_text ) )
    ( jw_key w out `key with "quote"` ) ( jw_bool w out T )
    ( jw_key w out `tags` )
    ( jw_arr w out )
    ( jw_str w out `a` )
    ( jw_int w out -42 )
    ( jw_float w out 85.0 )
    ( jw_float w out 0.001 )
    ( jw_null w out )
    ( jw_bool w out F )
    ( jw_arr w out ) ( jw_end w out )
    ( jw_obj w out ) ( jw_end w out )
    ( jw_end w out )
    ( jw_end w out )
    ^ ( jw_ok w )
}

// One misuse after a valid prefix: the prefix stays, the misuse adds
// nothing, and everything after it adds nothing either.
@ misuse s label i which → v {
    : ( Vec u ) out ( vec_new [u] )
    : JsonWriter w ( json_writer )
    ? == which 0 { ( jw_obj w out ) ( jw_int w out 1 ) } {}
    ? == which 1 { ( jw_arr w out ) ( jw_key w out `k` ) } {}
    ? == which 2 { ( jw_key w out `k` ) } {}
    ? == which 3 { ( jw_end w out ) } {}
    ? == which 4 { ( jw_obj w out ) ( jw_key w out `a` ) ( jw_key w out `b` ) } {}
    ? == which 5 { ( jw_obj w out ) ( jw_key w out `a` ) ( jw_end w out ) } {}
    ? == which 6 { ( jw_int w out 1 ) ( jw_int w out 2 ) } {}
    ? == which 7 { ( jw_arr w out ) ( jw_end w out ) ( jw_end w out ) } {}
    : i before ( vec_len [u] out )
    // Sticky: once bad, nothing more is written, even what would be right.
    ( jw_null w out ) ( jw_end w out ) ( jw_end w out )
    ( nurl_print label )
    ( nurl_print `: ` )
    ( write_slice ( slice_from_vec [u] out ) )
    ( nurl_print ? ( jw_ok w ) `  jw_ok T` `  jw_ok F` )
    ( nurl_print ? == before ( vec_len [u] out ) `, nothing after the misuse\n` `, WROTE AFTER THE MISUSE\n` )
}

// The escaping rules spelled out one byte at a time — what the writer's
// escaper must produce, byte for byte.
@ ref_escape ( Vec u ) out ( Vec u ) text → v {
    ( vec_push [u] out # u 34 )
    : i n ( vec_len [u] text )
    : ~ i k 0
    ~ < k n {
        : i c # i ( vec_at [u] text k )
        ? == c 34 { ( bytes_extend_str out `\\"` ) } {
            ? == c 92 { ( bytes_extend_str out `\\\\` ) } {
                ? == c 10 { ( bytes_extend_str out `\\n` ) } {
                    ? == c 9 { ( bytes_extend_str out `\\t` ) } {
                        ? == c 13 { ( bytes_extend_str out `\\r` ) } {
                            ? == c 8 { ( bytes_extend_str out `\\b` ) } {
                                ? == c 12 { ( bytes_extend_str out `\\f` ) } {
                                    ? < c 32 {
                                        ( bytes_extend_str out `\\u00` )
                                        ( vec_push [u] out # u ? < >> c 4 10 + 48 >> c 4 + 87 >> c 4 )
                                        ( vec_push [u] out # u ? < & c 15 10 + 48 & c 15 + 87 & c 15 )
                                    } { ( vec_push [u] out # u c ) }
                                } } } } } } }
        = k + k 1
    }
    ( vec_push [u] out # u 34 )
}

// Strings of every byte value and length 0..300, from a fixed LCG; one in
// four mostly escapes (the escaper's room is re-reserved again and again),
// written after a prefix of varying length so the buffer's own length and
// capacity vary too. Each must be the reference's bytes and parse back
// to the string it came from.
@ escape_stress → b {
    : ~ i seed 12345
    : ~ i round 0
    ~ < round 2000 {
        = seed & + * seed 6364136223846793005 1442695040888963407 9223372036854775807
        : i len % >> seed 20 301
        : b dense == 0 % >> seed 40 4
        : ( Vec u ) text ( vec_with_cap [u] len )
        : ~ i k 0
        ~ < k len {
            = seed & + * seed 6364136223846793005 1442695040888963407 9223372036854775807
            : i r & >> seed 24 255
            ( vec_push [u] text # u ? & dense < r 200 & r 31 r )
            = k + k 1
        }
        : ( Vec u ) got ( vec_with_cap [u] % round 7 )
        : ( Vec u ) want ( vec_new [u] )
        : ~ i p 0
        ~ < p % round 13 { ( vec_push [u] got # u 120 ) ( vec_push [u] want # u 120 ) = p + p 1 }
        : JsonWriter w ( json_writer )
        ( jw_str_slice w got ( slice_from_vec [u] text ) )
        ( ref_escape want text )
        ? ! ( slice_bytes_eq ( slice_from_vec [u] got ) ( slice_from_vec [u] want ) ) { ^ F } {}
        : ( Vec u ) doc ( bytes_slice got % round 13 ( vec_len [u] got ) )
        ?? ( json_parse_bytes doc ) {
            T j → {
                ?? j {
                    JStr back → { ? ! ( slice_bytes_eq ( string_bytes back ) ( slice_from_vec [u] text ) ) { ^ F } {} }
                    _ → { ^ F }
                }
            }
            F _ → { ^ F }
        }
        = round + round 1
    }
    ^ T
}

@ main → i {
    // 1. byte-identical to json_stringify, and it parses back to the DOM
    : Json dom ( sample_dom )
    : String want ( json_stringify dom )
    : ( Vec u ) out ( vec_new [u] )
    : b whole ( sample_written out )
    ( show_visible `written` out )
    ( check `one whole value (jw_ok)` whole )
    ( check `same bytes as json_stringify` ( same_text out want ) )
    ?? ( json_parse_bytes out ) {
        T back → ( check `parses back to the same Json` ( json_eq back dom ) )
        F _ → ( check `parses back to the same Json` F )
    }

    // 2. json_write appends compact text to what the buffer holds
    : ( Vec u ) two ( vec_new [u] )
    ( bytes_extend_str two `[` )
    ( json_write two dom )
    ( bytes_extend_str two `,` )
    ( json_write two ( json_int 7 ) )
    ( bytes_extend_str two `]` )
    ?? ( json_parse_bytes two ) {
        T j → ( check `json_write appends` & == ( json_arr_len j ) 2 ( same_text out ( json_stringify dom ) ) )
        F _ → ( check `json_write appends` F )
    }

    // 3. a Json value, raw JSON text, a window of bytes
    : ( Vec u ) mix ( vec_new [u] )
    : JsonWriter w ( json_writer )
    : ( Slice u ) src ( slice_of_str `--a "slice"--` )
    ( jw_obj w mix )
    ( jw_key w mix `dom` ) ( jw_json w mix dom )
    ( jw_key w mix `raw` ) ( jw_raw w mix `["tag1", "tag2"]` )
    ( jw_key w mix `raw slice` ) ( jw_raw_slice w mix ( slice_of_str `{"x": 1}` ) )
    ( jw_key w mix `window` ) ( jw_str_slice w mix ( slice_window [u] src 2 9 ) )
    ( jw_key w mix `string` ) ( jw_string w mix want )
    ( jw_key w mix `nan` ) ( jw_float w mix / 0.0 0.0 )
    ( jw_key w mix `inf` ) ( jw_float w mix / -1.0 0.0 )
    ( jw_end w mix )
    ( check `mixed document whole` ( jw_ok w ) )
    ?? ( json_parse_bytes mix ) {
        T j → {
            ?? ( json_obj_get j `window` ) {
                T v → ( check `a window as a string` != 0 ( nurl_str_eq ( json_str_data v ) `a "slice"` ) )
                F → ( check `a window as a string` F )
            }
            ?? ( json_obj_get j `string` ) {
                T v → ( check `a String holding JSON stays a string` != 0 ( nurl_str_eq ( json_str_data v ) ( string_data want ) ) )
                F → ( check `a String holding JSON stays a string` F )
            }
            ?? ( json_obj_get j `dom` ) {
                T v → ( check `a Json value embedded` ( json_eq v dom ) )
                F → ( check `a Json value embedded` F )
            }
            ( check `NaN and -inf as null` & ( json_is_null ?? ( json_obj_get j `nan` ) { T v → v F → ( json_bool T ) } ) ( json_is_null ?? ( json_obj_get j `inf` ) { T v → v F → ( json_bool T ) } ) )
        }
        F _ → ( check `mixed document parses` F )
    }

    // 4. an unfinished document is not whole, but nothing was misused
    : ( Vec u ) open ( vec_new [u] )
    : JsonWriter w2 ( json_writer )
    ( jw_arr w2 open ) ( jw_int w2 open 1 )
    ( check `an open array is not whole` ! ( jw_ok w2 ) )
    ( jw_end w2 open )
    ( check `closed, it is` ( jw_ok w2 ) )
    ( show `closed` open )

    // 5. the escaper against the rules, on 2000 strings of every byte
    ( check `2000 strings of every byte: the reference's bytes, parsed back whole` ( escape_stress ) )

    // 6. misuse
    ( misuse `value where a key goes` 0 )
    ( misuse `key in an array` 1 )
    ( misuse `key at the top level` 2 )
    ( misuse `end with nothing open` 3 )
    ( misuse `key after a key` 4 )
    ( misuse `end after a key` 5 )
    ( misuse `second top-level value` 6 )
    ( misuse `end past the top` 7 )
    ^ 0
}
