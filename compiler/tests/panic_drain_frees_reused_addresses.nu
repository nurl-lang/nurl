// panic_drain_frees_reused_addresses.nu — what a destructor allocates and
// frees while a panic's drops run is freed (Agora #622; docs/MEMORY.md
// §7.2, the drain).
//
// A panic's drain records every address it frees and skips a second free
// of one: a binding's slot can hold an address another registration also
// reaches. The record held addresses only, and the buffers went back to
// the allocator at once — so the message the next destructor built came
// back from malloc at an address already in the record, and its own free
// was skipped: a hundred live elements leaked ninety-nine messages. The
// drain now keeps what it frees until it ends, so an address in its
// record names one block for as long as the record lasts.
//
// Each row is the count of live allocations (nurl_alloc_count −
// nurl_free_count) after a recovered panic, less the count before it. The
// first panic is not a row: a thread keeps its last panic's message until
// the next one.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: ~ i g_bytes 0

: Bomb { String tag i boom }

// The destructor allocates: a message of its own, freed before it returns.
% Drop Bomb {
    @ drop Bomb b → v {
        : s msg ( nurl_str_cat `drop ` ( string_data . b tag ) )
        = g_bytes + g_bytes ( nurl_str_len msg )
        ? == . b boom 1 { ( panic ( nurl_str_cat `panic in ` msg ) ) } {}
    }
}

// A hundred of them; `boom` names the ones whose destructor panics (-1:
// none).
@ hundred i boom → ( Vec Bomb ) {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    : ~ i k 0
    ~ < k 100 {
        ( vec_push [Bomb] v @ Bomb { ( string_from `bomb` ) ? == % k 50 boom 1 0 } )
        = k + k 1
    }
    ^ v
}

// The panic's drain drops the Vec.
@ plain → v {
    : ( Vec Bomb ) v ( hundred -1 )
    ( panic `the cause` )
}

// The Vec's own drop, and its first element's destructor panics: the
// drain goes on with the ninety-nine after it (the fifty-first panics
// too, inside the drain).
@ first_panics → v {
    : ( Vec Bomb ) v ( hundred 0 )
}

// A Vec in a Vec: the inner Vecs are dropped by the drain's own loop.
@ nested → v {
    : ~ ( Vec ( Vec Bomb ) ) vv ( vec_new [( Vec Bomb )] )
    ( vec_push [( Vec Bomb )] vv ( hundred -1 ) )
    ( vec_push [( Vec Bomb )] vv ( hundred 7 ) )
    ( vec_push [( Vec Bomb )] vv ( hundred -1 ) )
    ( panic `the cause` )
}

@ quiet → v {
    : ( Vec Bomb ) v ( hundred -1 )
}

@ attempt s name ( @ v ) f → v {
    : !v PanicInfo r ( recover f )
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat name `: no panic` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 name `: recovered: ` ( string_data . e msg ) ) ) }
    }
}

@ row s name ( @ v ) f → v {
    : i before ( live )
    ( attempt name f )
    ( nurl_println ( nurl_str_cat3 name `: live delta ` ( nurl_str_int - ( live ) before ) ) )
}

@ main → i {
    ( attempt `first` \ → v { ( panic `the thread's first panic` ) } )
    ( row `plain` \ → v { ( plain ) } )
    ( row `first_panics` \ → v { ( first_panics ) } )
    ( row `nested` \ → v { ( nested ) } )
    ( row `quiet` \ → v { ( quiet ) } )
    // Each destructor ran once: 9 bytes of message for each of 600 elements.
    ( nurl_println ( nurl_str_cat `message bytes: ` ( nurl_str_int g_bytes ) ) )
    // The thread's frees are ordinary again after all of that.
    : i before ( live )
    : ~ i k 0
    : ~ i n 0
    ~ < k 100000 {
        : String s ( string_from `abcdefghijklmnop` )
        = n + n ( string_len s )
        = k + k 1
    }
    ( nurl_println ( nurl_str_cat `bytes: ` ( nurl_str_int n ) ) )
    ( nurl_println ( nurl_str_cat `after: live delta ` ( nurl_str_int - ( live ) before ) ) )
    ^ 0
}
