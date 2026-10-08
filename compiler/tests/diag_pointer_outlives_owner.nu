// diag_pointer_outlives_owner.nu — a view into a value cannot be read
// after the block that drops the value has ended.
//
// `( string_data x )` / `( vec_data v )` point into x's buffer. Assigned to
// a binding of an outer scope, or pushed into an outer `( Vec s )`, the
// view outlived x — dropped at the end of its block — and every later read
// was a use-after-free with nothing said (packages/wasmbuilder's link argv
// carried freed strings this way). The borrow walk ends a block's bindings
// at its `}`: a view of one ends there, and a container a view was pushed
// into holds a view of it (depends on it). A view read from a vector
// element (`T x → ( string_data x )`) points into the vector's element.
// The controls compile: an owner declared in the outer scope, an owner
// moved into a container that outlives the view, a use inside the owner's
// block.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ split s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( string_from text ) )
    ^ out
}

@ assigned → i {
    : ~ s p ``
    ? T { : String x ( string_from `abc` ) = p ( string_data x ) } {}
    ^ ( nurl_str_len p )
}

@ pushed → i {
    : ( Vec s ) args ( vec_new [s] )
    ? T { : String x ( string_from `abc` ) ( vec_push [s] args ( string_data x ) ) } {}
    ^ ( vec_len [s] args )
}

@ pushed_from_element → i {
    : ( Vec s ) args ( vec_new [s] )
    ? T {
        : ( Vec String ) parts ( split `abc` )
        ?? ( vec_get [String] parts 0 ) { T x → { ( vec_push [s] args ( string_data x ) ) } F _ → {} }
    } {}
    ^ ( vec_len [s] args )
}

@ owner_outside → i {
    : ( Vec s ) args ( vec_new [s] )
    : String x ( string_from `abc` )
    ? T { ( vec_push [s] args ( string_data x ) ) } {}
    ^ ( vec_len [s] args )
}

@ owner_moved_on → i {
    : ( Vec String ) hold ( vec_new [String] )
    : ( Vec s ) args ( vec_new [s] )
    ? T {
        : String seg ( string_from `abc` )
        ( vec_push [s] args ( string_data seg ) )
        ( vec_push [String] hold seg )
    } {}
    ^ ( vec_len [s] args )
}

@ used_inside → i {
    : ~ i n 0
    ? T { : String x ( string_from `abc` ) : s p ( string_data x ) = n ( nurl_str_len p ) } {}
    ^ n
}

@ main → i { ^ + + + + + ( assigned ) ( pushed ) ( pushed_from_element ) ( owner_outside ) ( owner_moved_on ) ( used_inside ) }
