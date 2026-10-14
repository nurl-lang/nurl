// A handle's state changed in place without raw memory: checked out of an
// Rc (rc_take) or a Locked (locked_take) into a local, changed through
// `inout` helpers, and checked back in (docs/MEMORY.md §7.6).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

: CacheImpl {
    ( Vec String ) keys
    i hits
    String last
}

: Cache { ( Rc CacheImpl ) a }

@ Cache_share Cache h → Cache { ^ @ Cache { ( rc_clone [CacheImpl] . h a ) } }

@ Cache_drop sink Cache h → v {}

@ cache_new → Cache { ^ @ Cache { ( rc_new [CacheImpl] @ CacheImpl { ( vec_new [String] ) 0 ( string_new ) } ) } }

@ cache_hits Cache h → i { ^ . ( rc_get [CacheImpl] . h a ) hits }

@ __cache_put inout CacheImpl c s key → v {
    ( vec_push [String] . c keys ( string_from key ) )
    = . c hits + . c hits 1
    = . c last ( string_from key )
}

@ cache_put Cache h s key → v {
    : ~ CacheImpl c ( rc_take [CacheImpl] . h a )
    ( __cache_put c key )
    ( rc_restore [CacheImpl] . h a c )
}

@ counter_bump ( Locked CacheImpl ) l → v {
    : ~ CacheImpl c ( locked_take [CacheImpl] l )
    = . c hits + . c hits 1
    ( locked_restore [CacheImpl] l c )
}

@ main → i {
    : Cache c ( cache_new )
    : Cache c2 ( Cache_share c )
    ( cache_put c `alpha, a key long enough to own a buffer` )
    ( cache_put c2 `beta` )
    ( nurl_println_int ( cache_hits c ) )
    : CacheImpl v ( rc_get [CacheImpl] . c a )
    ( nurl_println ( string_data . v last ) )
    ( nurl_println_int ( vec_len [String] . v keys ) )

    : ( Locked CacheImpl ) l ( locked_new [CacheImpl] @ CacheImpl { ( vec_new [String] ) 0 ( string_new ) } )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i k 0
    ~ < k 4 {
        : ( Locked CacheImpl ) lc ( Locked_share [CacheImpl] l )
        : ( @ v ) body \ → v { : ~ i j 0 ~ < j 1000 { ( counter_bump lc ) = j + j 1 } }
        ?? ( thread_spawn body ) { T t → { ( vec_push [Thread] ts t ) } F _ → {} }
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [Thread] ts ) { ( thread_join ( vec_at [Thread] ts k ) ) = k + k 1 }
    ( nurl_println_int . ( locked_get [CacheImpl] l ) hits )
    ^ 0
}
