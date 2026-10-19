// closure_type_args.nu — a closure type, and a trait object, as a generic
// type argument: `( Vec ( @ i i ) )`, `vec_new [( @ i i )]`, `( Rc ( @ i ) )`,
// `( HashMap i ( @ i i ) )`, `( Vec ?( @ i i ) )`, a generic struct of one,
// `( Vec %Show )`. The type travels as one word (its slug, __clo_slug); the
// container owns each element's env, as a struct field owns a closure's
// (docs/MEMORY.md §7.4): a literal's env moves in, a binding's is copied,
// and dropping or clearing the container releases them.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ mk String s i k → ( @ i i ) {
    : String c ( string_clone s )
    ^ \ i x → i { ^ + * x k ( string_len c ) }
}

// Every Vec operation over capturing closures.
@ vec_ops String a → v {
    : ( Vec ( @ i i ) ) vs ( vec_new [( @ i i )] )
    ( vec_push [( @ i i )] vs ( mk a 1 ) )
    ( vec_push [( @ i i )] vs ( mk a 2 ) )
    ( vec_push [( @ i i )] vs \ i x → i { ^ - x ( string_len a ) } )
    : b ins ( vec_insert [( @ i i )] vs 1 ( mk a 10 ) )
    : b st ( vec_set [( @ i i )] vs 0 ( mk a 100 ) )
    ( vec_put [( @ i i )] vs 2 ( mk a 1000 ) )
    ?? ( vec_replace [( @ i i )] vs 3 ( mk a 7 ) ) { T old → { ( nurl_println_int ( old 1 ) ) } F → {} }
    ?? ( vec_remove [( @ i i )] vs 1 ) { T r → { ( nurl_println_int ( r 1 ) ) } F → {} }
    ?? ( vec_pop [( @ i i )] vs ) { T r → { ( nurl_println_int ( r 1 ) ) } F → {} }
    ?? ( vec_get [( @ i i )] vs 0 ) { T g → { ( nurl_println_int ( g 1 ) ) } F → {} }
    ~ h vs { ( nurl_println_int ( h 2 ) ) }
    : ( Vec ( @ i i ) ) w ( vec_clone [( @ i i )] vs )
    ( vec_clear [( @ i i )] vs )
    ( nurl_println_int ( vec_len [( @ i i )] vs ) )
    : b tr ( vec_truncate [( @ i i )] w 1 )
    : ( @ i i ) w0 ( vec_at [( @ i i )] w 0 )
    ( nurl_println_int ( w0 5 ) )
}

// A closure binding pushed is copied: it stays the binding's own.
@ binding_push String a → v {
    : ( Vec ( @ i i ) ) vs ( vec_new [( @ i i )] )
    : ( @ i i ) g \ i x → i { ^ * x ( string_len a ) }
    ( vec_push [( @ i i )] vs g )
    ( vec_push [( @ i i )] vs g )
    : ~ i tot 0
    ~ h vs { = tot + tot ( h 1 ) }
    ( nurl_println_int + tot ( g 1 ) )
}

// The higher-order functions, and closures that make closures.
@ hof String a → v {
    : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] )
    ( vec_push [( @ i i )] fs \ i x → i { ^ + x ( string_len a ) } )
    ( vec_push [( @ i i )] fs \ i x → i { ^ * x 3 } )
    ( vec_each [( @ i i )] fs \ ( @ i i ) f → v { ( nurl_println_int ( f 10 ) ) } )
    ( nurl_println_int ( vec_fold [( @ i i ) i] fs 0 \ i acc ( @ i i ) f → i { ^ + acc ( f 1 ) } ) )
    : ( Vec i ) outs ( vec_map [( @ i i ) i] fs \ ( @ i i ) f → i { ^ ( f 2 ) } )
    : ( Vec ( @ i i ) ) adders ( vec_map [i ( @ i i )] outs \ i k → ( @ i i ) { ^ \ i x → i { ^ + x k } } )
    ~ m adders { ( nurl_println_int ( m 100 ) ) }
}

// Parts with no one-word spelling of their own: an inout parameter, a
// result, a closure parameter, an unsigned return.
@ odd_parts → v {
    : ( Vec ( @ v inout i ) ) incs ( vec_new [( @ v inout i )] )
    ( vec_push [( @ v inout i )] incs \ inout i x → v { = x + x 1 } )
    ( vec_push [( @ v inout i )] incs \ inout i x → v { = x * x 10 } )
    : ~ i acc 1
    ~ h incs { ( h acc ) }
    ( nurl_println_int acc )
    : ( Vec ( @ !i s i ) ) chk ( vec_new [( @ !i s i )] )
    ( vec_push [( @ !i s i )] chk \ i x → !i s { ? > x 0 { ^ @ !i s { T x } } {} ^ @ !i s { F `negative` } } )
    ~ c chk {
        ?? ( c 5 ) { T n → { ( nurl_println_int n ) } F e → { ( nurl_println e ) } }
        ?? ( c -1 ) { T n → { ( nurl_println_int n ) } F e → { ( nurl_println e ) } }
    }
    : ( Vec ( @ i ( @ i i ) i ) ) twice ( vec_new [( @ i ( @ i i ) i )] )
    ( vec_push [( @ i ( @ i i ) i )] twice \ ( @ i i ) g i x → i { ^ ( g ( g x ) ) } )
    : i k 7
    ~ t twice { ( nurl_println_int ( t \ i y → i { ^ + y k } 1 ) ) }
    : ( Vec ( @ u ) ) us ( vec_new [( @ u )] )
    ( vec_push [( @ u )] us \ → u { ^ # u 200 } )
    ~ q us { ( nurl_println_int # i ( q ) ) }
}

// Options of closures as elements; a Vec of Vecs of closures, copied.
@ nested String a → v {
    : String a2 ( string_clone a )
    : ( Vec ? ( @ i i ) ) os ( vec_new [? ( @ i i )] )
    ( vec_push [? ( @ i i )] os @ ?( @ i i ) { T \ i x → i { ^ + x ( string_len a2 ) } } )
    ( vec_push [? ( @ i i )] os @ ?( @ i i ) { F } )
    ~ o os { ?? o { T h → { ( nurl_println_int ( h 2 ) ) } F → { ( nurl_println `none` ) } } }
    : ( Vec ( Vec ( @ i ) ) ) vv ( vec_new [( Vec ( @ i ) )] )
    : ( Vec ( @ i ) ) row ( vec_new [( @ i )] )
    ( vec_push [( @ i )] row \ → i { ^ ( string_len a ) } )
    ( vec_push [( Vec ( @ i ) )] vv row )
    : ( Vec ( Vec ( @ i ) ) ) ww ( vec_clone [( Vec ( @ i ) )] vv )
    ~ r ww { ~ h r { ( nurl_println_int ( h ) ) } }
}

: Holder [A] { A x i n }

// A generic struct of a closure, and its copy.
@ generic_struct String a → v {
    : ( Holder ( @ i i ) ) hd @ ( Holder ( @ i i ) ) { \ i x → i { ^ + x ( string_len a ) } 3 }
    : ( @ i i ) f . hd x
    ( nurl_println_int ( f . hd n ) )
    : ( Holder ( @ i i ) ) h2 ( mem_dup hd )
    : ( @ i i ) f2 . h2 x
    ( nurl_println_int ( f2 1 ) )
}

// A map of closures.
@ map_of String a → v {
    : ( @ i i ) hi \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) ei \ i p i q → b { ^ == p q }
    : ( HashMap i ( @ i i ) ) m ( map_new [i ( @ i i )] )
    ?? ( map_set [i ( @ i i )] m 1 \ i x → i { ^ + x ( string_len a ) } hi ei ) { T o → {} F → {} }
    ?? ( map_set [i ( @ i i )] m 1 \ i x → i { ^ - x ( string_len a ) } hi ei ) { T o → { ( nurl_println_int ( o 1 ) ) } F → {} }
    ?? ( map_get [i ( @ i i )] m 1 hi ei ) { T f → { ( nurl_println_int ( f 2 ) ) } F → {} }
    ( nurl_println_int ( map_len [i ( @ i i )] m ) )
}

// An Rc of a closure — and one holding a closure that captured it: a cycle
// the collector releases.
@ rc_cycle → v {
    : ( Rc ( @ i ) ) r ( rc_new [( @ i )] \ → i { ^ 0 } )
    : ( Rc ( @ i ) ) cap ( rc_clone [( @ i )] r )
    ( rc_set [( @ i )] r \ → i { ^ ( rc_strong [( @ i )] cap ) } )
}

@ rc_of String a → v {
    : ( Rc ( @ i i ) ) r ( rc_new [( @ i i )] \ i x → i { ^ + x ( string_len a ) } )
    : ( Rc ( @ i i ) ) r2 ( rc_clone [( @ i i )] r )
    : ( @ i i ) g ( rc_get [( @ i i )] r2 )
    ( nurl_println_int ( g 1 ) )
    : ( @ i i ) old ( rc_replace [( @ i i )] r \ i x → i { ^ - x 1 } )
    ( nurl_println_int ( old 3 ) )
    : i b0 ( live )
    ( rc_cycle ) ( rc_cycle )
    ( rc_collect )
    ( nurl_println_int - ( live ) b0 )
}

% Show [T] { @ show T self → i }

: P { String s }
: Q { i n }

% Show P { @ show P self → i { ^ ( string_len . self s ) } }

% Show Q { @ show Q self → i { ^ . self n } }

// A Vec of trait objects.
@ dyn_vec → v {
    : ( Vec % Show ) vs ( vec_new [% Show] )
    ( vec_push [% Show] vs ( dyn Show @ P { ( string_from `twelve-chars` ) } ) )
    ( vec_push [% Show] vs ( dyn Show @ Q { 42 } ) )
    ~ x vs { ( nurl_println_int ( show x ) ) }
    ?? ( vec_pop [% Show] vs ) { T y → { ( nurl_println_int ( show y ) ) } F → {} }
    ( nurl_println_int ( vec_len [% Show] vs ) )
}

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    ( vec_ops a )
    ( binding_push a )
    ( hof a )
    ( odd_parts )
    ( nested a )
    ( generic_struct a )
    ( map_of a )
    ( rc_of a )
    ( dyn_vec )
    ^ 0
}
