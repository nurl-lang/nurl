// thread_own_types_named_like_the_library.nu — a type's name grants and
// costs nothing at a thread's edge (agora #714, as #639 for a handle named
// `Arc`). A program's own struct named `Weak` holding a PNCounter share is
// walked by its fields: it crosses with every owner of that state or the
// crossing panics, as the same struct named `Holder` does. The run-time
// crossing check skipped it by name, and eight threads changed one counter.
// A program's own `Rc` of numbers, and its own generic `Arc` holding a
// Cell moved into the thread, are whatever their fields make them: the
// compile-time walk read the names and refused both.
$ `stdlib/core/vec.nu`
$ `stdlib/core/cell.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/dist/crdt.nu`

: Weak { PNCounter c i n }

: GWeak [T] { T c i n }

: Rc { i a i b }

: Arc [T] { T v i n }

@ say s what ! v PanicInfo r → v {
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat what `: crossed` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 what `: ` ( string_data . e msg ) ) ) }
    }
}

@ spawn_join ( @ v ) body → v {
    ?? ( thread_spawn body ) { T t → { ( thread_join t ) } F _ → {} }
}

@ weak_only_owner → v {
    : Weak wk @ Weak { ( pncounter_new ) 1 }
    ( spawn_join \ → v { ( pncounter_inc . wk c 1 1 ) } )
}

@ weak_share_kept → v {
    : PNCounter hits ( pncounter_new )
    : Weak wk @ Weak { ( PNCounter_share hits ) 1 }
    ( spawn_join \ → v { ( pncounter_inc . wk c 1 1 ) } )
    ( pncounter_inc hits 2 1 )
}

@ gweak_share_kept → v {
    : PNCounter hits ( pncounter_new )
    : ( GWeak PNCounter ) wk @ ( GWeak PNCounter ) { ( PNCounter_share hits ) 1 }
    ( spawn_join \ → v { ( pncounter_inc . wk c 1 1 ) } )
    ( pncounter_inc hits 2 1 )
}

@ main → i {
    ( say `own Weak, only owner` ( recover \ → v { ( weak_only_owner ) } ) )
    ( say `own Weak, share kept` ( recover \ → v { ( weak_share_kept ) } ) )
    ( say `own generic Weak, share kept` ( recover \ → v { ( gweak_share_kept ) } ) )
    : Rc r @ Rc { 3 4 }
    ( spawn_join \ → v { ( nurl_println_int + . r a . r b ) } )
    : ( Arc Cell ) a @ ( Arc Cell ) { ( cell_zero 8 ) 1 }
    : ( @ v ) body \ → v { ( nurl_println_int ( cell_size . a v ) ) }
    ?? ( thread_spawn_owned body ) { T th → { : i j ( thread_join th ) } F _ → {} }
    ^ 0
}
