// free_suffix_query.nu — a `_free`-suffixed QUERY is not a destructor.
//
// The borrow checker's move rule keys on a `_free` callee suffix. On the
// suffix alone, any function whose name ends in `_free` is read as a
// destructor that consumes its first argument, so the second use of that
// argument is reported as a use-after-move. That is a false positive
// with no workaround except renaming a correctly-named function:
// "how many free slots?" is naturally `_num_free`, and asking it twice
// is not a double free.
//
// A real destructor releases the value and has nothing left to report —
// every `_free` in the stdlib returns `v`. A `_free`-suffixed function
// that returns a value is a query about free space, not a destructor.
// That return-type test is what this pins.
//
// Both halves matter, so both are here: the query compiles, and a real
// destructor still consumes (the last block would be a use-after-free
// if the checker had gone blind).

$ `stdlib/core/vec.nu`

: Pool { i cap ( Vec i ) slots }

@ pool_new i cap → *Pool {
    : *Pool p # *Pool ( nurl_alloc Z Pool )
    = . p cap cap
    = . p slots ( vec_new [i] )
    : ~ i k 0
    ~ < k cap { ( vec_push [i] . p slots k ) = k + k 1 }
    ^ p
}

// The query. Returns a count, so it is not a destructor.
@ pool_num_free * Pool p → i { ^ ( vec_len [i] . p slots ) }

// A second shape: takes an extra argument, still returns a value.
@ pool_bytes_free * Pool p i unit → i { ^ * ( pool_num_free p ) unit }

// The real destructor: returns v, consumes the pool.
@ pool_free * Pool p → v {
    ( vec_free [i] . p slots )
    ( free p )
}

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ main → i {
    : *Pool p ( pool_new 4 )
    // Calling the query repeatedly must not move `p`.
    : i a ( pool_num_free p )
    : i b ( pool_num_free p )
    : i c ( pool_bytes_free p 8 )
    ( pb `query is callable twice: ` == a b )
    ( pb `query returns the count: ` == a 4 )
    ( pb `second query shape works: ` == c 32 )
    // …and the pool is still usable afterwards.
    ( vec_push [i] . p slots 99 )
    ( pb `pool still usable after queries: ` == ( pool_num_free p ) 5 )
    // The real destructor consumes it; nothing touches `p` after this.
    ( pool_free p )

    // The same distinction for a stdlib handle: a query on the vector
    // does not move it, the destructor does.
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : i n1 ( vec_len [i] v )
    : i n2 ( vec_len [i] v )
    ( pb `vec query repeatable: ` && == n1 n2 == n1 1 )
    ( vec_free [i] v )
    ^ 0
}
