// mem_dup_of_a_slice_of_views_kept_past_its_string_is_refused: `: [s w ( dups v )` with `dups` handing back `( mem_dup t )` of a `[s` of `( string_data a )`, then `a` given a new value and `w` read: the copy's elements still view the String
// Guard (agora #938): a copy of a slice of views holds what its elements view (`__nurl_slice_copy`, `^0`), so it depends on the String they point into, as the slice did.
// main 3ad3d7c8: refused.
// map: §7.6 | A2 | rejected | - | agora #938: mem_dup of a slice of views read after the String its elements view was given a new value
$ `stdlib/core/string.nu`

@ dups [s t → [s { ^ ( mem_dup t ) }

@ main → i {
    : ~ String a ( string_from `xy` )
    : [s v [s | ( string_data a )]
    : [s w ( dups v )
    = a ( string_from `zz` )
    ~ x w { ( nurl_println x ) }
    ^ 0
}
