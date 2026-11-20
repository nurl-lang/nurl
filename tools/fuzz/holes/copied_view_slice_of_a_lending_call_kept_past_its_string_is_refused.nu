// copied_view_slice_of_a_lending_call_kept_past_its_string_is_refused: `: SBag b ( wraps ( viewsof a ) )` with `viewsof` lending views of its String, then `a` given a new value and `b` read: the temporary is released, but what its elements view is not
// Guard (agora #935): the temporary of elements that own nothing goes after the call (`__rv_views_arg`), and the result stays tied to the temporary's own sources through its elements.
// main 08e56f54: refused.
// map: §7.6 | A2 | rejected | - | agora #935: a copied slice of a lending call's views read after the String they view was given a new value
$ `stdlib/core/string.nu`

: SBag { [s t i n }

@ viewsof String a → [s { ^ [s | ( string_data a )] }
@ wraps [s t → SBag { ^ @ SBag { t 2 } }

@ main → i {
    : ~ String a ( string_from `xy` )
    : SBag b ( wraps ( viewsof a ) )
    = a ( string_from `zz` )
    ~ x . b t { ( nurl_println x ) }
    ^ 0
}
