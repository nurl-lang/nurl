// generic_struct_declared_below_a_global_of_a_trait_object_type_handed_to_a_thread: `: ~ ( @ i %Show ) g 0` right above `: Wrap [T] { ( Rc T ) r }`, an instance of which (named above both) a thread_spawn closure captures while the spawner keeps a share
// Closed: the template pre-scan reads a global's type whole, and a `%` written against a name (`%Show`) is a trait object, not a trait or impl header: it no longer steps over the template's body (agora #716).
// main 3b63ee3b: accepted — the instance had no fields (ASan: double-free).
// map: §6.5 | A3 | rejected | - | a generic struct declared below a global whose type names a trait object, its instance captured by a thread (agora #716)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

@ race sink ( Rc i ) a sink ( Rc i ) b → v {
    : ( Wrap i ) h2 ( mk a )
    : ( Wrap i ) h3 ( mk b )
    ?? ( thread_spawn \ → v { ( churn h3 20000 ) } ) {
        T t → { ( churn h2 20000 ) ( thread_join t ) }
        F _ → {}
    }
}

@ mk sink ( Rc i ) r → ( Wrap i ) { ^ @ ( Wrap i ) { r } }

@ churn ( Wrap i ) h i n → i {
    : ~ i k 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 {
            ( vec_push [( Rc i )] cs ( share [i] h ) )
            = j + j 1
        }
        = k + k 1
    }
    ^ 0
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] + 5 ( mkd ) )
    ( race ( rc_clone [i] r ) ( rc_clone [i] r ) )
    ^ 0
}

@ share [A] ( Wrap A ) w → ( Rc A ) { ^ ( rc_clone [A] . w r ) }

% Show [T] { @ show T s → i }

: Num { i v }

% Show Num { @ show Num s → i { ^ . s v } }

@ mkd → i {
    : Num n @ Num { 0 }
    : %Show d ( dyn Show n )
    ^ ( show d )
}

: ~ ( @ i % Show ) g 0 : Wrap [T] { ( Rc T ) r }
