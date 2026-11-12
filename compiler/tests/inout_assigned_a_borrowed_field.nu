// inout_assigned_a_borrowed_field.nu — an `inout` parameter given a field
// of a value it does not own (Agora #697): a by-value parameter, a field
// two deep, an `inout` one, a cursor over a parameter, a field of a
// generic struct, an option field, a field of a Vec element lent by
// `vec_at`, in a loop and on one path. Each is copied into the caller's
// binding, whose old value goes: the caller's binding and the field's
// owner each own their own buffer, so growing one leaves the other as it
// was, and the sanitizer run shows no double free, no read of freed
// memory and no leak. A field taken out of a fresh temporary is the
// caller's own and is not copied.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v String name ? String o i n }
: Out { App inner i k }
: G [T] { T v i n }

@ mka → App {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ^ @ App { v ( string_from `an app name long enough for the heap buffer` ) @ ?String { T ( string_from `an option payload long enough for the heap` ) } 1 }
}

@ refill inout ( Vec i ) dst App x → v { = dst . x v }

@ rename inout String dst App x → v { = dst . x name }

@ deep inout String dst Out x → v { = dst . . x inner name }

@ fromio inout ( Vec i ) dst inout App x → v { = dst . x v }

@ viacur inout String dst App x → v {
    : App y x
    = dst . y name
}

@ gen inout ( Vec i ) dst ( G ( Vec i ) ) x → v { = dst . x v }

@ opt inout ? String dst App x → v { = dst . x o }

@ elem inout ( Vec i ) dst ( Vec App ) xs → v { = dst . ( vec_at [App] xs 0 ) v }

@ maybe inout String dst App x b c → v { ? c { = dst . x name } {} }

@ fresh inout String dst → v { = dst . ( mka ) name }

@ main → i {
    : ~ App a ( mka )
    : ~ ( Vec i ) c ( vec_new [i] )
    ( refill c a )
    ( vec_push [i] c 1 )
    ( nurl_println_int + ( vec_len [i] c ) ( vec_len [i] . a v ) )
    : ~ String s ( string_from `an old value, long enough for a heap buffer` )
    ( rename s a )
    ( string_push_str s `!` )
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data . a name ) )
    : Out ou @ Out { ( mka ) 2 }
    ( deep s ou )
    ( fromio c a )
    ( vec_push [i] c 2 )
    ( nurl_println_int + ( vec_len [i] c ) ( vec_len [i] . a v ) )
    ( viacur s a )
    : ~ ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 3 )
    : ( G ( Vec i ) ) g @ ( G ( Vec i ) ) { w 1 }
    ( gen c g )
    ( vec_push [i] c 9 )
    ( nurl_println_int + ( vec_len [i] c ) ( vec_len [i] . g v ) )
    : ~ ? String os @ ?String { T ( string_from `an old option value long enough for heap` ) }
    ( opt os a )
    ( nurl_println ?? os { T p → ( string_data p ) F → `none` } )
    : ~ ( Vec App ) xs ( vec_new [App] )
    ( vec_push [App] xs ( mka ) )
    ( elem c xs )
    ( vec_push [i] c 4 )
    ( nurl_println_int + ( vec_len [i] c ) ( vec_len [i] . ( vec_at [App] xs 0 ) v ) )
    : ~ i k 0
    ~ < k 30 {
        ( maybe s a == % k 2 0 )
        = k + k 1
    }
    ( fresh s )
    ( nurl_println ( string_data s ) )
    ^ 0
}
