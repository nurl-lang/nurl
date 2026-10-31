// match_try_owned_join: a fresh handle try-unwrapped in a braced `??` arm lost ownership at the join and leaked after storage.
// Closed: each `??` arm publishes its own ownership-lattice element (borrowed, owned, or an i1 for mixed paths) and the join phis them; a try-unwrapped fresh value stays owned through a braced arm.
// v0.77.2: accepted; ASan reported the fresh String (32 B) leaked.
// map: §7.6 | A2 | runs-clean | h320 | a fresh handle try-unwrapped in a braced ?? arm lost its ownership at the join and leaked after storage; every arm now contributes an explicit ownership-lattice element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { Bad }

@ mk → !String E { ^ @ !String E { T ( string_from `fresh` ) } }

@ take inout ( Vec String ) values → !i E {
    : ~ String value ?? ( vec_pop [String] values ) {
        T cached → cached
        F → { \ ( mk ) }
    }
    ( vec_push [String] values value )
    ^ @ !i E { T 0 }
}

@ main → i {
    : ~ ( Vec String ) values ( vec_new [String] )
    : !i E result ( take values )
    ^ 0
}
