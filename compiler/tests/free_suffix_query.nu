// Names do not imply ownership. Queries borrow the pool; the actual
// release API declares a consuming parameter. Void borrowing functions
// and consuming functions that return values are in sink_contract_names.

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

// A borrowing query.
@ pool_num_free * Pool p → i { ^ ( vec_len [i] . p slots ) }

// A second shape: takes an extra argument, still returns a value.
@ pool_bytes_free * Pool p i unit → i { ^ * ( pool_num_free p ) unit }

// The release contract consumes the pool.
@ pool_free sink * Pool p → v {
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
