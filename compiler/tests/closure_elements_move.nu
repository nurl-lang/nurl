// closure_elements_move.nu — a container that moves its elements moves
// closures too (Agora #706).
//
// A closure element is owned by the storage it sits in. Library code that
// moves elements read each one into a binding and stored the binding into
// its new slot; for every other type that is a move, but a closure stored
// as a plain binding is COPIED — the slot got a clone of its environment,
// and the environment it came with was nobody's. A `HashMap` of closures
// leaked every one its growth rehashed; `vec_swap`, `vec_reverse`,
// `vec_retain`, `sort_by` and a `Heap` leaked one per element moved.
//
// The moves are moves now: an element that changes places — in a rehash,
// a swap, a sort's shift — goes back into the buffer as it is
// (`mem_put_back`, which a closure element store honours like every other
// type's). Each closure is called after it moved, and LeakSanitizer
// (run_san_tests.sh) sees every environment released once.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/set.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/heap.nu`
$ `stdlib/std/btree.nu`

: Rec { i id ( @ i ) f }

@ rhash Rec r → i { ^ ( hash_int . r id ) }

@ req Rec a Rec b → b { ^ == . a id . b id }

@ mk i n → ( Vec ( @ i ) ) {
    : ~ ( Vec ( @ i ) ) v ( vec_new [( @ i )] )
    : ~ i k 0
    ~ < k n {
        : i kk % * k 7919 n
        ( vec_push [( @ i )] v \ → i { ^ kk } )
        = k + k 1
    }
    ^ v
}

@ total ( Vec ( @ i ) ) v → i {
    : ~ i t 0
    ~ f v { = t + t ( f ) }
    ^ t
}

// Two growths (8 → 16 → 32), then every closure is called.
@ map_values → i {
    : ( HashMap i ( @ i ) ) m ( map_new [i ( @ i )] )
    : ~ i k 0
    ~ < k 20 {
        : i kk k
        : ?( @ i ) _p ( map_set [i ( @ i )] m k \ → i { ^ + kk 1 } \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
        = k + k 1
    }
    : ~ i sum 0
    ( map_each [i ( @ i )] m \ i key ( @ i ) f → v { = sum + sum ( f ) } )
    ^ sum
}

// A struct that holds a closure, as a map's value and as a set's element.
@ records → i {
    : ( HashMap i Rec ) m ( map_new [i Rec] )
    : ( Set Rec ) st ( set_new [Rec] )
    : ~ i k 0
    ~ < k 20 {
        : i kk k
        : ?Rec _p ( map_set [i Rec] m k @ Rec { k \ → i { ^ * kk 2 } } \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
        : b _q ( set_add [Rec] st @ Rec { k \ → i { ^ * kk 3 } } \ Rec x → i { ^ ( rhash x ) } \ Rec x Rec y → b { ^ ( req x y ) } )
        = k + k 1
    }
    : ~ i sum 0
    ( map_each [i Rec] m \ i key Rec r → v { : ( @ i ) f . r f = sum + sum ( f ) } )
    ( set_each [Rec] st \ Rec r → v { : ( @ i ) f . r f = sum + sum ( f ) } )
    ^ sum
}

@ vec_moves → i {
    : ~ ( Vec ( @ i ) ) a ( mk 10 )
    : b _s ( vec_swap [( @ i )] a 0 9 )
    ( vec_reverse [( @ i )] a )
    ( vec_retain [( @ i )] a \ ( @ i ) f → b { ^ == % ( f ) 2 0 } )
    ^ ( total a )
}

// The quicksort, insertion-sort and heapsort paths.
@ sorted → i {
    : ~ ( Vec ( @ i ) ) a ( mk 500 )
    ( sort_by [( @ i )] a \ ( @ i ) x ( @ i ) y → i { ^ - ( x ) ( y ) } )
    : ~ i ok 1
    : ~ i k 0
    ~ < k 500 {
        : ( @ i ) f ( vec_at [( @ i )] a k )
        ? != ( f ) k { = ok 0 } {}
        = k + k 1
    }
    ^ ok
}

@ heaped → i {
    : ( Heap ( @ i ) ) h ( heap_new [( @ i )] )
    : ~ i k 0
    ~ < k 200 {
        : i kk % * k 7919 200
        ( heap_push [( @ i )] h \ → i { ^ kk } \ ( @ i ) x ( @ i ) y → i { ^ - ( x ) ( y ) } )
        = k + k 1
    }
    : ~ i sum 0
    = k 0
    ~ < k 100 {
        : ?( @ i ) top ( heap_pop [( @ i )] h \ ( @ i ) x ( @ i ) y → i { ^ - ( x ) ( y ) } )
        ?? top { T f → { = sum + sum ( f ) } F → {} }
        = k + k 1
    }
    ^ sum
}

// Closure values through a tree's splits, and its removals by
// predecessor, successor and merge.
@ treed → i {
    : ( BTree i ( @ i ) ) t ( btree_new [i ( @ i )] )
    : ~ i k 0
    ~ < k 400 {
        : i kk k
        : ?( @ i ) _p ( btree_set [i ( @ i )] t % * k 37 400 \ → i { ^ kk } \ i x i y → i { ^ - x y } )
        = k + k 1
    }
    = k 0
    ~ < k 400 {
        : ?( @ i ) _p ( btree_remove [i ( @ i )] t k \ i x i y → i { ^ - x y } )
        = k + k 3
    }
    : ~ i sum 0
    ( btree_each [i ( @ i )] t \ i key ( @ i ) f → v { = sum + sum ( f ) } )
    ^ + * ( btree_len [i ( @ i )] t ) 1000000 sum
}

@ main → i {
    ( nurl_println ( nurl_str_cat `map values: ` ( nurl_str_int ( map_values ) ) ) )
    ( nurl_println ( nurl_str_cat `records: ` ( nurl_str_int ( records ) ) ) )
    ( nurl_println ( nurl_str_cat `vec moves: ` ( nurl_str_int ( vec_moves ) ) ) )
    ( nurl_println ( nurl_str_cat `sorted: ` ( nurl_str_int ( sorted ) ) ) )
    ( nurl_println ( nurl_str_cat `heaped: ` ( nurl_str_int ( heaped ) ) ) )
    ( nurl_println ( nurl_str_cat `treed: ` ( nurl_str_int ( treed ) ) ) )
    ^ 0
}
