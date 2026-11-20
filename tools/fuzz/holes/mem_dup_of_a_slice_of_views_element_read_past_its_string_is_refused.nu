// mem_dup_of_a_slice_of_views_element_read_past_its_string_is_refused: `: [s w ( dups v )` with `dups` handing back `( mem_dup t )` of a `[s` of `( string_data a )`, then `a` given a new value and one element of `w` read (`. w 0`): the copy's element still views the String
// Guard (agora #938): a copy of a slice of views holds the views at its elements (`__nurl_slice_copy_v`: `*` to `*`), so a read of one element is a use of the String they point into, as a read of the whole copy is.
// main 3ad3d7c8: refused.
// map: §7.6 | A2 | rejected | - | agora #938: one element of a mem_dup of a slice of views read after the String its elements view was given a new value
$ `stdlib/core/string.nu`

@ dups [s t → [s { ^ ( mem_dup t ) }

@ main → i {
    : ~ String a ( string_from `xy` )
    : [s v [s | ( string_data a )]
    : [s w ( dups v )
    = a ( string_from `zz` )
    ( nurl_println . w 0 )
    ^ 0
}
