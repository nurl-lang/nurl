// return_cast_word_vec_is_view.nu — a Vec or String rebuilt from a word and
// returned (`^ # ( Vec T ) . e inits_ref`) is a view of whatever holds the
// word, as for a library handle (return_cast_word_is_view.nu).
//
// Counted as a value made from a number, the result was the caller's to
// drop: every call released the holder's Vec, and the next read was a
// use-after-free (packages/onnx __rt_inits — every model with a Split node).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Engine { i inits_ref i name_ref }

// The engine's initializers (lent: the caller's graph holds them).
unsafe @ inits Engine e → ( Vec i ) { ^ # ( Vec i ) . e inits_ref }

unsafe @ name Engine e → String { ^ # String . e name_ref }

@ find Engine e i want → i {
    : ( Vec i ) v ( inits e )
    : ~ i k 0
    ~ < k ( vec_len [i] v ) {
        ?? ( vec_get [i] v k ) { T x → ? == x want { ^ k } {} F _ → {} }
        = k + k 1
    }
    ^ -1
}

@ main → i {
    : ( Vec i ) tab ( vec_new [i] )
    ( vec_push [i] tab 7 ) ( vec_push [i] tab 9 ) ( vec_push [i] tab 11 )
    : String nm ( string_from `graph` )
    : Engine e @ Engine { # i tab # i nm }
    : ~ i acc 0
    : ~ i k 0
    ~ < k 20 {
        = acc + acc ( find e 11 )
        = acc + acc ( vec_len [i] ( inits e ) )
        = acc + acc ( string_len ( name e ) )
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print ` ` ) ( nurl_print_int ( vec_len [i] tab ) ) ( nurl_print ` ` ) ( nurl_print ( string_data nm ) ) ( nurl_print `\n` )
    ^ 0
}
