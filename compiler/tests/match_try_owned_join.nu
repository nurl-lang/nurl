// A try-unwrapped fresh value in one `??` arm contributes owned to that
// arm's ownership lattice element. Binding the join and storing it must not
// leak the fresh String.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | JoinErr { JoinBad }

@ make_fresh → !String JoinErr {
    ^ @ !String JoinErr { T ( string_from `fresh` ) }
}

@ take_or_make inout ( Vec String ) values → !i JoinErr {
    : ~ String value ?? ( vec_pop [String] values ) {
        T cached → cached
        F → { \ ( make_fresh ) }
    }
    ( vec_push [String] values value )
    ^ @ !i JoinErr { T ( vec_len [String] values ) }
}

@ main → i {
    : ~ ( Vec String ) values ( vec_new [String] )
    ?? ( take_or_make values ) {
        T n → {
            ( nurl_print ( nurl_str_int n ) )
            ( nurl_print `\n` )
        }
        F _ → { ( nurl_print `error\n` ) }
    }
    ^ 0
}
