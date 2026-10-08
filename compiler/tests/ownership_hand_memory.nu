// Ownership at the boundary between compiler-managed values and memory the
// program manages by hand (structs behind `nurl_malloc` pointers, globals
// holding an address). Every case is a legacy spelling the package sweep
// for memory model v1 found crashing (docs/MEMORY.md §7.6); each returns 0
// when the values it hands around are still intact.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: FF { String path ( Vec i ) xs }

// Free each element's fields through a vec_get payload, then the Vec: the
// payload's slot is emptied field by field, so vec_free skips them.
@ free_fields ( Vec FF ) files → v {
    : i n ( vec_len [FF] files )
    : ~ i i 0
    ~ < i n {
        ?? ( vec_get [FF] files i ) {
            T f → { ( string_free . f path ) ( vec_free [i] . f xs ) }
            F _ → {}
        }
        = i + i 1
    }
    ( vec_free [FF] files )
}

@ case_vget_fields → i {
    : ( Vec FF ) v ( vec_new [FF] )
    ( vec_push [FF] v @ FF { ( string_from `a` ) ( vec_new [i] ) } )
    ( vec_push [FF] v @ FF { ( string_from `b` ) ( vec_new [i] ) } )
    ( free_fields v )
    ^ 0
}

// A job keeps VIEWS of Vecs its caller owns (arima's _ar_job_new): handing
// it a vec_get payload or a field read through a pointer must not empty
// the source, and the constructor must not drop them on any path.
: Job { ( Vec f ) raw i idx }

unsafe @ job_new ( Vec f ) raw i idx → i {
    : *Job j # *Job ( nurl_malloc Z Job )
    = . j raw raw
    = . j idx idx
    ^ # i j
}

// Stores its parameter by hand on one path only.
: Lane { ( Vec i ) jobs }

unsafe @ jobs_run ( Vec i ) jobs b par → i {
    ? par {
        : *Lane ln # *Lane ( nurl_malloc Z Lane )
        = . ln jobs jobs
        : i n ( vec_len [i] . ln jobs )
        ( nurl_free # s ln )
        ^ n
    } {}
    ^ ( vec_len [i] jobs )
}

unsafe @ case_views → i {
    : ( Vec ( Vec f ) ) raws ( vec_new [( Vec f )] )
    ( vec_push [( Vec f )] raws ( vec_zeroed [f] 3 ) )
    ( vec_push [( Vec f )] raws ( vec_zeroed [f] 4 ) )
    : ( Vec i ) jobs ( vec_new [i] )
    : ~ i k 0
    ~ < k 2 {
        ?? ( vec_get [( Vec f )] raws k ) { T rw → { ( vec_push [i] jobs ( job_new rw k ) ) } F _ → {} }
        = k + k 1
    }
    : ~ i t 0
    = k 0
    ~ < k 2 {
        : *Job j # *Job ?? ( vec_get [i] jobs k ) { T p → p F → 0 }
        = t + t ( vec_len [f] . j raw )
        ( nurl_free # s j )
        = k + k 1
    }
    ? != t 7 { ^ 1 } {}
    ? != ( jobs_run jobs F ) 2 { ^ 2 } {}
    ? != ( jobs_run jobs T ) 2 { ^ 3 } {}
    ( vec_free [i] jobs )
    ^ 0
}

// A field of an owned local stored through a pointer: the hand-managed
// struct gets its own copy, and the local stays readable.
: Arma { i r ( Vec f ) phi }
: Prep { ( Vec f ) phi i r }

@ arma → Arma { ^ @ Arma { 3 ( vec_zeroed [f] 3 ) } }

unsafe @ fill * Prep p → i {
    : Arma am ( arma )
    = . p phi . am phi
    = . p r . am r
    ^ ( vec_len [f] . am phi )
}

unsafe @ case_local_field → i {
    : *Prep p # *Prep ( nurl_zalloc Z Prep )
    : i still ( fill p )
    : i n ( vec_len [f] . p phi )
    ( vec_free [f] . p phi )
    ( nurl_free # s p )
    ? | != n 3 != still 3 { ^ 1 } {}
    ^ 0
}

// A parameter's fields moved onto the heap (grad's _g_heap): the caller
// hands the value in, the parameter's own drop skips the moved fields.
: Tq { i dt ( Vec i ) shape ( Vec f ) data }

unsafe @ heap Tq t → s {
    : *Tq p # *Tq ( nurl_alloc Z Tq )
    = . p dt . t dt
    = . p shape . t shape
    = . p data . t data
    ^ # s p
}

unsafe @ case_param_fields → i {
    : Tq x @ Tq { 1 ( vec_zeroed [i] 2 ) ( vec_zeroed [f] 3 ) }
    : *Tq p # *Tq ( heap x )
    : i n + ( vec_len [i] . p shape ) ( vec_len [f] . p data )
    ( vec_free [i] . p shape ) ( vec_free [f] . p data ) ( nurl_free # s p )
    ? != n 5 { ^ 1 } {}
    ^ 0
}

// A binding over an owned local's field, stored by hand (anomaly's
// `: ~ AeModel nae . out ae … = . mo ae nae`): it takes the field over.
: M { b ok ( Vec f ) w }
: Out { M m String err }
: Hold { M m }

@ train → Out { ^ @ Out { @ M { T ( vec_zeroed [f] 4 ) } ( string_new ) } }

unsafe @ put * Hold h → i {
    : Out out ( train )
    : ~ M nm . out m
    ? . nm ok { = . h m nm ^ 0 } { ^ 1 }
}

unsafe @ case_field_alias → i {
    : *Hold h # *Hold ( nurl_zalloc Z Hold )
    ? != ( put h ) 0 { ^ 1 } {}
    : i n ( vec_len [f] . . h m w )
    ( vec_free [f] . . h m w ) ( nurl_free # s h )
    ? != n 4 { ^ 2 } {}
    ^ 0
}

// A parameter returned inside a struct inside a wrap, where another path
// releases it (tensor_reshape): the success path must not drop it.
: Tt { i dt ( Vec i ) shape }

@ reshape ( Vec i ) shape → ?Tt {
    ? == ( vec_len [i] shape ) 0 {
        ( vec_free [i] shape )
        ^ @ ?Tt { F }
    } {}
    ^ @ ?Tt { T @ Tt { 1 shape } }
}

@ case_nested_wrap → i {
    : ( Vec i ) s ( vec_zeroed [i] 1 )
    ?? ( reshape s ) { T r → { ? != ( vec_len [i] . r shape ) 1 { ^ 1 } {} } F _ → { ^ 2 } }
    ^ 0
}

// A global holding a handle's address, handed out cast back: a view of a
// table the program keeps, never dropped by whoever asked for it.
: ~ i g_names 0

unsafe @ names → ( Vec String ) {
    ? != g_names 0 { ^ # ( Vec String ) g_names } {}
    : ( Vec String ) v ( vec_new [String] )
    = g_names # i v
    ^ v
}

@ has_name s k → b {
    : ( Vec String ) v ( names )
    : ~ b found F
    : ~ i i 0
    ~ < i ( vec_len [String] v ) {
        ?? ( vec_get [String] v i ) { T x → { ? != 0 ( nurl_str_eq ( string_data x ) k ) { = found T } {} } F _ → {} }
        = i + i 1
    }
    ^ found
}

@ case_global_view → i {
    ( vec_push [String] ( names ) ( string_from `a` ) )
    ? ! ( has_name `a` ) { ^ 1 } {}
    ? ! ( has_name `a` ) { ^ 2 } {}
    ( vec_push [String] ( names ) ( string_from `b` ) )
    ? != ( vec_len [String] ( names ) ) 2 { ^ 3 } {}
    ^ 0
}

// An owned raw string placed in a returned struct literal (lingbot-map's
// option parser): it leaves with the struct, the scope does not free it.
: Opt { s model i bad }

@ parse_opt i which → Opt {
    : ~ s model ``
    ? > which 0 { : s v ( nurl_str_cat `model-` `path` ) = model v } {}
    ^ @ Opt { model 0 }
}

@ case_raw_string → i {
    : Opt o ( parse_opt 1 )
    ? == 0 ( nurl_str_eq . o model `model-path` ) { ^ 1 } {}
    ^ 0
}

// A field of a call's `? T` payload stored by hand (the relay server's
// `= . p clients . rs clients`): it moves — the same buffer, not a copy.
: RsS { ( Vec s ) clients i n }
: RsP { ( Vec s ) clients i n }

@ rs_start → ?RsS { ^ @ ?RsS { T @ RsS { ( vec_with_cap [s] 8 ) 0 } } }

unsafe @ case_payload_field → i {
    : ~ i got 0
    ?? ( rs_start ) {
        T rs → {
            : *RsP p # *RsP ( nurl_zalloc Z RsP )
            = . p clients . rs clients
            ( vec_push [s] . p clients `a` )
            = got ( vec_len [s] . p clients )
            ( vec_free [s] . p clients ) ( nurl_free # s p )
        }
        F → {}
    }
    ? != got 1 { ^ 1 } {}
    ^ 0
}

@ main → i {
    : i a ( case_vget_fields )
    : i b ( case_views )
    : i c ( case_local_field )
    : i d ( case_param_fields )
    : i e ( case_field_alias )
    : i f ( case_nested_wrap )
    : i g ( case_global_view )
    : i h ( case_raw_string )
    : i m ( case_payload_field )
    ? | | | | | | | | != m 0 != a 0 != b 0 != c 0 != d 0 != e 0 != f 0 != g 0 != h 0 {
        ( nurl_println ( nurl_str_cat4 ( nurl_str_int a ) ( nurl_str_int b ) ( nurl_str_int c ) ( nurl_str_cat4 ( nurl_str_int d ) ( nurl_str_int e ) ( nurl_str_int f ) ( nurl_str_cat ( nurl_str_int g ) ( nurl_str_int h ) ) ) ) )
        ^ 1
    } {}
    ( nurl_println `hand memory ok` )
    ^ 0
}
