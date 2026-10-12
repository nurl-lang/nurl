// A mutable global may hold a value that owns something — a String, a Vec,
// a struct of them, a library handle (docs/MEMORY.md §1). It starts as the
// zero value; an assignment to it, or to one of its fields, drops what it
// replaces; and only an `unsafe` function reaches it, since every thread
// can. Run under LeakSanitizer: each replaced value is released once.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`

: State { String name ( Vec i ) xs ? String note }

: ~ String g_name 0
: ~ ( Vec i ) g_v 0
: ~ State g_st 0
: ~ ( HashMap i i ) g_m 0

unsafe @ set_name s n → v { = g_name ( string_from n ) }

unsafe @ setup → v {
    = g_v ( vec_new [i] )
    = g_st @ State { ( string_from `the state's name, long enough for the heap` ) ( vec_new [i] ) @ ?String { F } }
    = g_m ( map_new [i i] )
}

unsafe @ work → i {
    ( vec_push [i] g_v 3 )
    ( vec_push [i] g_v 4 )
    ( vec_push [i] . g_st xs 9 )
    = . g_st name ( string_from `a new name for the state, long enough for the heap` )
    = . g_st note @ ?String { T ( string_from `a note long enough for the heap` ) }
    = . g_st note @ ?String { T ( string_from `another note long enough for the heap` ) }
    : ?i _o ( map_set [i i] g_m 1 2 \ i x → i { ^ x } \ i a i b → b { ^ == a b } )
    ^ + + ( vec_len [i] g_v ) ( vec_len [i] . g_st xs ) ( map_len [i i] g_m )
}

// The safe accessor the rest of a program uses.
unsafe @ name_len → i { ^ ( string_len g_name ) }

unsafe @ main → i {
    ( set_name `the first name, long enough for the heap` )
    ( set_name `the second name, long enough for the heap` )
    ( setup )
    ( nurl_println_int ( work ) )
    ( nurl_println ( string_data g_name ) )
    ( nurl_println ( string_data . g_st name ) )
    ( setup )
    ( nurl_println_int ( work ) )
    ( nurl_println_int ( name_len ) )
    ^ 0
}
