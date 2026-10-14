// A field that owns something, read out of a call's result (h266): the
// rest of the result is dropped where the field is read, and the field is
// its reader's — a binding, a return, an argument, a literal — exactly
// when the call handed the result over. Out of a lent result (`arc_get`,
// `vec_at`) it stays a view of the owner.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Stat { b ok String backend String device i n }
: W { String s }
: Bx { ( Vec i ) items i n }

@ mk → Stat { ^ @ Stat { T ( string_from `cpu` ) ( string_from `host` ) 3 } }

@ backend → String { ^ . ( mk ) backend }

@ shared_name ( Arc Stat ) a → String { ^ . ( arc_get [Stat] a ) backend }

@ first_items ( Vec Bx ) bxs → ( Vec i ) { ^ . ( vec_at [Bx] bxs 0 ) items }

@ len String x → i { ^ ( string_len x ) }

@ main → i {
    : String b ( backend )
    : String c . ( mk ) device
    : W w @ W { . ( mk ) device }
    : ~ String d ( string_new )
    = d . ( mk ) backend
    ( nurl_println_int ( string_len b ) )
    ( nurl_println_int ( string_len c ) )
    ( nurl_println_int ( string_len . w s ) )
    ( nurl_println_int ( string_len d ) )
    ( nurl_println_int ( len . ( mk ) backend ) )
    : ( Arc Stat ) a ( arc_new [Stat] ( mk ) )
    : String e ( shared_name a )
    ( nurl_println_int + ( string_len e ) ( string_len . ( arc_get [Stat] a ) device ) )
    // a lent field handed back is the owner's own: the push lands there
    : ( Vec Bx ) bxs ( vec_new [Bx] )
    : ( Vec i ) s3 ( vec_new [i] )
    ( vec_push [i] s3 8 )
    ( vec_push [Bx] bxs @ Bx { s3 1 } )
    ( vec_push [i] ( first_items bxs ) 1 )
    ( nurl_println_int ( vec_len [i] . ( vec_at [Bx] bxs 0 ) items ) )
    ^ 0
}
