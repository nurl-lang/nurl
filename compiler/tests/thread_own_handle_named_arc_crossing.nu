// A handle's name grants nothing (agora #639). A program that imports no
// std/arc may declare a generic handle named `Arc` of its own; this one
// keeps its state in an rcbox its raw code writes, so copies of it are one
// state changed in place with no lock, and it crosses to another thread
// only with every owner of that state, as any such handle does
// (docs/MEMORY.md §6.5): the only owner crosses, a share left behind
// panics at the crossing. The thread rules used to read the name, take it
// for the standard library's Arc — whose payload is frozen — and let the
// share cross: two threads grew one Vec.
$ `stdlib/core/rcbox.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/panic.nu`

: TallyImpl [T] { ( Vec T ) v }

: Arc [T] { ( Shared ( TallyImpl T ) ) ctl }

@ Arc_share [T] ( Arc T ) h → ( Arc T ) { ^ @ ( Arc T ) { ( shared_clone [( TallyImpl T )] . h ctl ) } }

@ Arc_drop [T] sink ( Arc T ) h → v {}

unsafe @ own_new [T] → ( Arc T ) { ^ @ ( Arc T ) { ( shared_new [( TallyImpl T )] @ ( TallyImpl T ) { ( vec_new [T] ) } ) } }

unsafe @ own_add [T] ( Arc T ) h T x → v {
    : *( TallyImpl T ) p ( shared_ptr [( TallyImpl T )] . h ctl )
    ( vec_push [T] . p v x )
}

: Job { ( @ v ) run }

@ say s what ! v PanicInfo r → v {
    ?? r {
        T _ → { ( nurl_println ( nurl_str_cat what `: crossed` ) ) }
        F e → { ( nurl_println ( nurl_str_cat3 what `: ` ( string_data . e msg ) ) ) }
    }
}

@ spawn_join ( @ v ) body → v {
    ?? ( thread_spawn body ) { T t → { ( thread_join t ) } F _ → {} }
}

@ only_owner → v {
    : ( Arc i ) t ( own_new [i] )
    ( spawn_join \ → v { ( own_add [i] t 1 ) } )
}

@ share_kept → v {
    : ( Arc i ) t ( own_new [i] )
    : ( Arc i ) mine ( Arc_share [i] t )
    : Job j @ Job { \ → v { ( own_add [i] t 1 ) } }
    ( spawn_join . j run )
    ( own_add [i] mine 2 )
}

@ main → i {
    ( say `only owner` ( recover \ → v { ( only_owner ) } ) )
    ( say `share kept` ( recover \ → v { ( share_kept ) } ) )
    ^ 0
}
