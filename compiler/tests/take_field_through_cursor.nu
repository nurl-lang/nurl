// take_field_through_cursor.nu — a field taken out of a cursor over a
// payload leaves the payload's own slot too.
//
// `?? ( mk ) { T e0 → { : ~ E e e0 … : ( Vec u ) out . e out ( mem_take out )
// ^ out } }`: `e` is a cursor over the payload `e0`, which still drops its
// own slot at the end of the arm. mem_take emptied the field in `e` only, so
// `e0`'s drop freed the Vec handed to the caller (packages/audio's MP3
// encoder state).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: E { ( Vec u ) out i n }

@ mk i k → !E String {
    ? < k 0 { ^ @ !E String { F ( string_from `neg` ) } } {}
    : ~ E e @ E { ( vec_new [u] ) 1 }
    ( vec_push [u] . e out # u 1 )
    ^ @ !E String { T e }
}

@ __put inout E e i b → v { ( vec_push [u] . e out # u b ) }

@ enc i k → ( Vec u ) {
    ?? ( mk k ) {
        T e0 → {
            : ~ E e e0
            ( __put e 2 )
            : ( Vec u ) out . e out
            ( mem_take out )
            ^ out
        }
        F _ → { ^ ( vec_new [u] ) }
    }
}

@ main → i {
    : i l0 ( live )
    : ~ i k 0
    : ~ i acc 0
    ~ < k 10 {
        : ( Vec u ) r ( enc - k 2 )
        = acc + acc ( vec_len [u] r )
        ?? ( vec_get [u] r 1 ) { T b → { = acc + acc # i b } F → {} }
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}
