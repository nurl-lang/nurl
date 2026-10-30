// trait_object_vec_captured_closure_returned_in_a_struct: as h680, the capture a ( Vec %Show ) — trait objects have no Clone.
// Closed: the capture is tagged `\~!(…)` (gen_closure_expr), its handle
// copy marked one no owner can copy in (`nch_`): adopting the closure keeps
// it, so the escape is the view of a released binding it is (agora #161).
// v0.80.0: HOLE (heap-use-after-free).
// map: §2.11 | A2 | rejected | h688 | agora #161: as h680, the capture a ( Vec %Show )
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Show [T] { @ show T self → i }

: P { String s i n }

% Show P { @ show P p → i { ^ . p n } }

: H { ( @ i ) cb i pad }

@ make → H {
    : ( Vec % Show ) v ( vec_new [% Show] )
    ( vec_push [% Show] v ( dyn Show @ P { ( string_from `a string long enough to own a heap buffer here` ) 7 } ) )
    : ( @ i ) f \ → i { ^ ( vec_len [% Show] v ) }
    ^ @ H { f 0 }
}

@ main → i { : H h ( make ) : ( @ i ) c . h cb ( nurl_println_int ( c ) ) ^ 0 }
