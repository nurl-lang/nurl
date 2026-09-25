// ownership_results_and_temps.nu — values a caller owns without naming
// them: a tried call's payload, the locals a failed try leaves behind, a
// discarded `?T` / `!T E` temporary, a result's error, and a `?`/`??`
// arm's tail call. The sanitizer corpus runs this with leak detection:
// each shape used to leak (or copy and leak the original).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/heap.nu`

: Item { i id String name }
: Holder { Item item }
: Err { i code String msg }
: Out { i n }

@ make_item i n → !Item i {
    ? < n 0 { ^ @ !Item i { F n } } {}
    ^ @ !Item i { T @ Item { n ( string_from `made` ) } }
}

@ item_free sink Item it → v { ( string_free . it name ) }

@ check_n i n → !i i {
    ? < n 0 { ^ @ !i i { F n } } {}
    ^ @ !i i { T n }
}

// `\ ( call )` binds the call's payload: stored into a field it moves.
@ refill inout Holder h i n → !v i {
    : Item it \ ( make_item n )
    : i m ?? ( check_n n ) { T v → v F e → { ( item_free it ) ^ @ !v i { F e } } }
    ( item_free . h item )
    = . h item it
    ^ @ !v i { T 0 }
}

// A failed try leaves the function: what it owns so far is dropped.
@ tried i n → !i i {
    : String kept ( string_from `kept` )
    : i v \ ( check_n n )
    : i total + v ( string_len kept )
    ^ @ !i i { T total }
}

@ fail_op i n → !v Err {
    ? < n 0 { ^ @ !v Err { F @ Err { n ( string_from `bad input` ) } } } {}
    ^ @ !v Err { T 0 }
}

// A result's error is owned: ignored, it is dropped; handed on, it moves.
@ ignore_error i n → i {
    : !v Err r ( fail_op n )
    ^ 1
}

@ pass_error i n → !Out Err {
    : !v Err r ( fail_op n )
    ?? r { T _ → {} F e → { ^ @ !Out Err { F e } } }
    ^ @ !Out Err { T @ Out { n } }
}

@ fill ( Vec Item ) v i n → v {
    : ~ i k 0
    ~ < k n { ( vec_push [Item] v @ Item { k ( string_from `x` ) } ) = k + k 1 }
}

@ cmp_str String a String b → i { ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) ) }

@ main → i {
    : ~ Holder h @ Holder { @ Item { 0 ( string_from `init` ) } }
    : !v i r1 ( refill h 3 )
    : !v i r2 ( refill h -1 )
    ( nurl_print ( string_data . . h item name ) ) ( nurl_print `\n` )
    ( item_free . h item )
    ( mem_forget h )

    ?? ( tried 2 ) { T v → { ( nurl_print_int v ) ( nurl_print `\n` ) } F _ → {} }
    ?? ( tried -2 ) { T _ → {} F e → { ( nurl_print `tried failed ` ) ( nurl_print_int e ) ( nurl_print `\n` ) } }

    : i ignored ( ignore_error -1 )
    ?? ( pass_error -3 ) {
        T _ → {}
        F e → { ( nurl_print ( string_data . e msg ) ) ( nurl_print `\n` ) }
    }

    // Discarded element-returning calls drop the element they hand back;
    // a discarded borrow (vec_get) does not.
    : ( Vec Item ) v ( vec_new [Item] )
    ( fill v 8 )
    ( vec_get [Item] v 1 )
    ( vec_remove [Item] v 0 )
    ( vec_pop [Item] v )
    // …in an arm tail whose value nothing consumes…
    ? > ( vec_len [Item] v ) 0 { ( vec_remove [Item] v 0 ) } {}
    ?? ( vec_len [Item] v ) { 5 → { : ?Item gone ( vec_remove [Item] v 0 ) } _ → {} }
    // …and consumed by a binding through the join.
    : ?Item a ? > ( vec_len [Item] v ) 2 { ( vec_remove [Item] v 0 ) } { ( vec_remove [Item] v 1 ) }
    ?? a { T x → { ( nurl_print ( string_data . x name ) ) ( nurl_print_int . x id ) ( nurl_print `\n` ) } F → {} }
    ( nurl_print_int ( vec_len [Item] v ) ) ( nurl_print `\n` )

    // heap_pop hands out the root it took and forgets the moved tail slot.
    : ( Heap String ) hp ( heap_new [String] )
    ( heap_push [String] hp ( string_from `d` ) \ String a String b → i { ^ ( cmp_str a b ) } )
    ( heap_push [String] hp ( string_from `b` ) \ String a String b → i { ^ ( cmp_str a b ) } )
    ( heap_push [String] hp ( string_from `a` ) \ String a String b → i { ^ ( cmp_str a b ) } )
    ( heap_push [String] hp ( string_from `c` ) \ String a String b → i { ^ ( cmp_str a b ) } )
    : ~ i k 0
    ~ < k 3 {
        ?? ( heap_pop [String] hp \ String a String b → i { ^ ( cmp_str a b ) } ) { T s → { ( nurl_print ( string_data s ) ) } F → {} }
        = k + k 1
    }
    ( heap_pop [String] hp \ String a String b → i { ^ ( cmp_str a b ) } )
    ( nurl_print `\n` )
    ^ 0
}
