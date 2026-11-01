// json_packed_containers.nu — a parsed array or object is ONE allocation
// (Agora #291): the parser moves a container's members off its stack into
// a Vec whose buffer shares its handle's block (core/vec.nu,
// vec_split_off_packed). Such a Vec must stay an ordinary Vec for whoever
// takes it apart — popped, shrunk, pushed past its room, set, dropped —
// with nothing left behind. Then the two packed constructors on owning
// elements, and bytes_push_int at its edges.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/json.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ allocs → i { ^ ( nurl_alloc_count ) }

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `: ok\n` `: FAILED\n` )
}

@ say3 s label i a i b i c → v {
    ( nurl_print label )
    ( nurl_print `: ` ) ( nurl_print_int a )
    ( nurl_print ` / ` ) ( nurl_print_int b )
    ( nurl_print ` / ` ) ( nurl_print_int c ) ( nurl_print `\n` )
}

// The allocations a parse of `text` makes (its stack's included), how many
// the value keeps, and how many are left once it is dropped.
@ count_parse s text → v {
    : i a0 ( allocs )
    : i l0 ( live )
    : i kept ?? ( json_parse text ) {
        T j → - ( live ) l0
        F _ → -1
    }
    : i made - ( allocs ) a0
    : i left - ( live ) l0
    ( nurl_print text ) ( say3 `  made / kept / left` made kept left )
}

// A parsed array taken apart through its Vec: what used to hand realloc
// and free a pointer into the middle of the handle's block.
@ take_apart Json j → s {
    ?? j {
        JArr v → {
            : ?Json a ( vec_pop [Json] v )
            ( vec_shrink_to_fit [Json] v )  // two left in room for three
            : ?Json b ( vec_pop [Json] v )
            : ?Json c ( vec_pop [Json] v )
            ( vec_shrink_to_fit [Json] v )  // empty
            ~ < ( vec_len [Json] v ) 5 { ( vec_push [Json] v ( json_int ( vec_len [Json] v ) ) ) }
            ( vec_shrink_to_fit [Json] v )
            ^ `taken apart`
        }
        _ → { ^ `not an array` }
    }
}

@ packed_containers → v {
    : i l0 ( live )
    ?? ( json_parse `[10,20,30]` ) {
        T j → {
            ( nurl_print ( take_apart j ) ) ( nurl_print `: ` )
            : String back ( json_stringify j )
            ( nurl_print ( string_data back ) ) ( nurl_print `\n` )
        }
        F _ → ( nurl_print `parse: FAILED\n` )
    }
    ?? ( json_parse `{"a":["x"],"b":1}` ) {
        T j → {
            ?? ( json_get j `a` ) {
                T arr → {
                    ( check `json_arr_push onto a parsed array` ( json_arr_push arr ( json_str_lit `y` ) ) )
                    ( check `…and again, past its room` ( json_arr_push arr ( json_null ) ) )
                }
                F → ( nurl_print `get: FAILED\n` )
            }
            ( check `json_obj_set on a parsed object` ( json_obj_set j `b` ( json_bool T ) ) )
            ( check `…and a member it did not have` ( json_obj_set j `c` ( json_arr_new ) ) )
            : String back ( json_stringify j )
            ( nurl_print ( string_data back ) ) ( nurl_print `\n` )
        }
        F _ → ( nurl_print `parse: FAILED\n` )
    }
    ( check `nothing left behind` == ( live ) l0 )
}

// The constructors themselves, on elements that own something.
unsafe @ split_strings → v {
    : ( Vec String ) v ( vec_new [String] )
    : ~ i k 0
    ~ < k 5 {
        : String e ( string_with_cap 4 )
        ( string_push_str e `s` ) ( string_push_int e k )
        ( vec_push [String] v e )
        = k + k 1
    }
    : ( Vec String ) tail ( vec_split_off_packed [String] v 2 )
    ( say3 `split at 2: kept / moved / room` ( vec_len [String] v ) ( vec_len [String] tail ) ( vec_cap [String] tail ) )
    ( vec_push [String] tail ( string_from `s5` ) )  // past its room: moves out
    ( vec_shrink_to_fit [String] tail )
    : ( Vec String ) none ( vec_split_off_packed [String] v 9 )
    ( say3 `split past the end: kept / moved / room` ( vec_len [String] v ) ( vec_len [String] none ) ( vec_cap [String] none ) )
    : ( Vec String ) scratch ( vec_with_cap_packed [String] 4 )
    = k 0
    ~ < k 6 {
        ( vec_push [String] scratch ( string_from `t` ) )
        = k + k 1
    }
    : ?String gone ( vec_pop [String] scratch )
    ( vec_shrink_to_fit [String] scratch )
    : ( Vec String ) whole ( vec_split_off_packed [String] scratch 0 )
    ( say3 `scratch: left / moved / room` ( vec_len [String] scratch ) ( vec_len [String] whole ) ( vec_cap [String] whole ) )
    ( nurl_print `tail:` )
    : ~ i j 0
    ~ < j ( vec_len [String] tail ) {
        ?? ( vec_get [String] tail j ) {
            T s → { ( nurl_print ` ` ) ( nurl_print ( string_data s ) ) }
            F → {}
        }
        = j + j 1
    }
    ( nurl_print `\n` )
}

unsafe @ ints_into ( Vec u ) out → v {
    ( bytes_push_int out 0 ) ( vec_push [u] out # u 32 )
    ( bytes_push_int out 9 ) ( vec_push [u] out # u 32 )
    ( bytes_push_int out 10 ) ( vec_push [u] out # u 32 )
    ( bytes_push_int out 99 ) ( vec_push [u] out # u 32 )
    ( bytes_push_int out 100 ) ( vec_push [u] out # u 32 )
    ( bytes_push_int out -1 ) ( vec_push [u] out # u 32 )
    ( bytes_push_int out -10 ) ( vec_push [u] out # u 32 )
    ( bytes_push_int out 9223372036854775807 ) ( vec_push [u] out # u 32 )
    ( bytes_push_int out - -9223372036854775807 1 )
}

unsafe @ push_ints → v {
    // Room for nothing: every write grows the buffer.
    : ( Vec u ) out ( vec_new [u] )
    ( ints_into out )
    : String s ( string_from_vec out )
    ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
    // A borrowed view: the first write detaches it, the source untouched.
    : s src `abc`
    : ( Vec u ) view ( vec_borrow_raw [u] # *u src 3 )
    ( bytes_push_int view -42 )
    : String vs ( string_from_vec view )
    ( nurl_print ( string_data vs ) ) ( nurl_print ` ` ) ( nurl_print src ) ( nurl_print `\n` )
}

unsafe @ main → i {
    ( count_parse `["tag3", "tag5"]` )
    ( count_parse `{"id":17,"tags":["a","b"],"r":{}}` )
    ( count_parse `[]` )
    ( count_parse `"x"` )
    ( count_parse `[[[[1]]]]` )
    ( count_parse `[1,` )
    ( packed_containers )
    : i l0 ( live )
    ( split_strings )
    ( check `the packed constructors leave nothing behind` == ( live ) l0 )
    ( push_ints )
    ^ 0
}
