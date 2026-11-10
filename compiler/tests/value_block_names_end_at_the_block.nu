// value_block_names_end_at_the_block.nu — what stays valid around a value
// block's names (agora #575). A block in value position that is no scope
// of its own binds in the enclosing scope, and what it binds lives to
// that scope's end; its names end at its `}`. Naming one after the block
// is refused (diag_value_block_name_used_after_the_block and
// diag_value_block_name_shadowing_an_outer_one). Everything here names
// only what is in scope.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ add i a i b → i { ^ + a b }

// The block's value views the block's own binding: the binding outlives
// its name.
@ view_kept → i {
    : s e { : String s ( string_from `a view of the block's own String` ) ( string_data s ) }
    ( nurl_println e )
    ^ 0
}

// The `:` that takes the block's value binds the name the block used: the
// new binding is what the name means.
@ same_name → i {
    : String s { : String s ( string_from `moved out of the block` ) s }
    ( nurl_println ( string_data s ) )
    : ( Vec i ) v { : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ( vec_push [i] v 8 ) v }
    ( nurl_println_int ( vec_len [i] v ) )
    ^ 0
}

// A `:` of the name made after the block is a binding of its own.
@ bound_again → i {
    : String e { : String t ( string_from `in the block` ) ( string_concat t t ) }
    : String t ( string_from `after the block` )
    ( nurl_println ( string_data t ) )
    ( nurl_println ( string_data e ) )
    ^ 0
}

// Two blocks of one statement, each with its own `s`; a payload and a loop
// variable named as an earlier block's binding was.
@ newer_bindings → i {
    ( nurl_println_int ( add { : String s ( string_from `first` ) ( string_len s ) } { : String s ( string_from `second!` ) ( string_len s ) } ) )
    : ?String opt @ ?String { T ( string_from `payload` ) }
    ( nurl_println_int ?? opt { T s → ( string_len s ) F → 0 } )
    : ~ ( Vec String ) all ( vec_new [String] )
    ( vec_push [String] all ( string_from `element` ) )
    ~ s all { ( nurl_println ( string_data s ) ) }
    ^ 0
}

// In a loop body and in an arm: each run of the statement binds anew, and
// a `:` in an inner scope is that scope's.
@ in_scopes → i {
    : ~ i k 0
    : ~ i total 0
    ~ < k 3 {
        : String e { : String s ( string_from `xx` ) ( string_concat s s ) }
        = total + total ( string_len e )
        ? == k 1 {
            : String s ( string_from `an arm's own` )
            = total + total ( string_len s )
        } {}
        = k + k 1
    }
    ( nurl_println_int total )
    ^ 0
}

@ main → i {
    ( view_kept )
    ( same_name )
    ( bound_again )
    ( newer_bindings )
    ( in_scopes )
    ^ 0
}
