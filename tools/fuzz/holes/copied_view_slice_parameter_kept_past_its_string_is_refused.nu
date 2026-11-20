// copied_view_slice_parameter_kept_past_its_string_is_refused: `: [s v [s | ( string_data a )]  : SBag b ( wraps v )`, then `a` given a new value and `b` read: the copy's elements still view the String
// Guard (agora #935): a copied slice of views holds what its elements view (`^0`), so the binding of its result depends on the String they point into, as the slice did.
// main 08e56f54: refused.
// map: §7.6 | A2 | rejected | - | agora #935: a copied slice of views read after the String its elements view was given a new value
$ `stdlib/core/string.nu`

: SBag { [s t i n }

@ wraps [s t → SBag { ^ @ SBag { t 2 } }

@ main → i {
    : ~ String a ( string_from `xy` )
    : [s v [s | ( string_data a )]
    : SBag b ( wraps v )
    = a ( string_from `zz` )
    ~ x . b t { ( nurl_println x ) }
    ^ 0
}
