// fresh_into_borrowed_copy.nu — a value stored into a field of a binding
// that only borrows its value is that binding's own.
//
// `: ~ Rec r ?? ( vec_get rs 0 ) { … }` (or `: ~ Rec q p` of a by-value
// parameter) copies a value whose fields belong to someone else. A fresh
// value stored into one of its fields (`= . r name ( string_from … )`)
// belonged to nobody and leaked per call. It is now owned by the field
// (a flag of its own): dropped with the binding, replaced on the next
// store, and handed to the slot when the binding is written back (`= . p k
// r`, or through a helper that puts it back) — the value it replaced, the
// slot's own, goes then, unless the program took it out first. Handed
// back, a binding the caller is not to own is copied.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Rec { String name i n }

@ rename_copy ( Vec Rec ) rs → i {
    : ~ Rec r ?? ( vec_get [Rec] rs 0 ) { T x → x F → @ Rec { ( string_from `` ) 0 } }
    = . r name ( string_from `new` )
    ^ ( string_len . r name )
}

@ rename_param Rec p → i {
    : ~ Rec q p
    = . q name ( string_from `zz` )
    = . q name ( string_from `zzz` )
    ^ ( string_len . q name )
}

unsafe

@ rename_put_back ( Vec Rec ) rs → v {
    : *Rec p ( vec_data [Rec] rs )
    : ~ Rec item . p 0
    = . item name ( string_from `put` )
    = . item n + . item n 1
    = . p 0 item
}

unsafe

@ put_slot ( Vec Rec ) rs i k Rec r → v {
    : *Rec p ( vec_data [Rec] rs )
    ( mem_put_back r )
    = . p k r
}

unsafe

@ rename_via_helper ( Vec Rec ) rs → v {
    : *Rec p ( vec_data [Rec] rs )
    : ~ Rec item . p 0
    = . item name ( string_from `helper` )
    ( put_slot rs 0 item )
}

unsafe

@ rename_taken_first ( Vec Rec ) rs → v {
    : *Rec p ( vec_data [Rec] rs )
    : ~ Rec item . p 0
    : String old . item name
    ( mem_take old )
    = . item name ( string_from `taken` )
    = . p 0 item
}

@ rename_set ( Vec Rec ) rs → v {
    : ~ Rec r ?? ( vec_get [Rec] rs 0 ) { T x → x F → @ Rec { ( string_from `` ) 0 } }
    = . r name ( string_from `set` )
    : b _o ( vec_set [Rec] rs 0 r )
}

@ renamed ( Vec Rec ) rs → Rec {
    : ~ Rec r ?? ( vec_get [Rec] rs 0 ) { T x → x F → @ Rec { ( string_from `` ) 0 } }
    = . r name ( string_from `ret` )
    ^ r
}

// The early return comes before the store in the text: its drop is filled
// in at the function's end.
@ loop_exit ( Vec Rec ) rs i m → i {
    : ~ Rec r ?? ( vec_get [Rec] rs 0 ) { T x → x F → @ Rec { ( string_from `` ) 0 } }
    : ~ i k 0
    ~ < k 5 {
        ? == k m { ^ ( string_len . r name ) } {}
        = . r name ( string_from `loop` )
        = k + k 1
    }
    ^ 0
}

@ name_of ( Vec Rec ) rs → String {
    ^ ?? ( vec_get [Rec] rs 0 ) { T x → ( string_clone . x name ) F → ( string_new ) }
}

@ main → i {
    : ( Vec Rec ) rs ( vec_new [Rec] )
    ( vec_push [Rec] rs @ Rec { ( string_from `old` ) 1 } )
    : Rec keep @ Rec { ( string_from `p` ) 2 }
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        = acc + acc ( rename_copy rs )
        = acc + acc ( rename_param keep )
        ( rename_put_back rs )
        ( rename_via_helper rs )
        ( rename_taken_first rs )
        ( rename_set rs )
        : Rec x ( renamed rs )
        = acc + acc ( string_len . x name )
        = acc + acc ( loop_exit rs 3 )
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print ` live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    : String nm ( name_of rs )
    ( nurl_print ( string_data nm ) ) ( nurl_print ` ` ) ( nurl_print ( string_data . keep name ) ) ( nurl_print `\n` )
    ^ 0
}
