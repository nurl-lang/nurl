// bare_view_of_a_loop_element_handed_on_through_a_trait_object_by_a_forwarder_below: agora #471 — `@ via %Firsty o → s { ^ ( firsty o ) }` below its caller, the impl handing back `( string_data x )` from `~ x . b items`; the object ends, then the view is read
// Closed: a caller waits for a callee not walked yet that may hand back a view of a loop element over a parameter of any type but a number, a view, a String or an option of one (__rv_plain_param; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a loop element handed on through a trait object by a forwarder below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Firsty [T] { @ firsty T self → s }

: Bag { ( Vec String ) items i n }

% Firsty Bag { @ firsty Bag b → s { ~ x . b items { ^ ( string_data x ) } ^ `none` } }

@ main → i {
    : String base ( string_from `the outer string, which outlives everything here` )
    : ~ s v ( string_data base )
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string inside a trait object, freed with it` ) )
        : %Firsty o ( dyn Firsty @ Bag { t 1 } )
        = v ( via o )
    }
    ( nurl_println v )
    ^ 0
}

@ via %Firsty o → s { ^ ( firsty o ) }
