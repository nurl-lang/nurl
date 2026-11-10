// returned_literal_lending_a_field_that_cannot_be_copied_beside_an_owned_one_is_refused: agora #635, #545 — `^ @ P { . h r ( fresh ) }`, r a `% Drop` value with no clone: the literal holds a value of its own, so the caller must own it whole, and the lent field has no copy to give it. Lent with the rest, the literal's own field leaked.
// Closed: refused where the lent field stands, naming the type: return the value its owner gives up (a `sink` parameter), not a borrow of it.
// main (before this PR): accepted; LeakSanitizer, the literal's own String.
// map: §7.6 | A2 | rejected | - | agora #635: a returned literal lending a `% Drop` field beside an owned field leaked the owned one
$ `stdlib/core/string.nu`

: R { String name }
% Drop R { @ drop R r → v { ( nurl_println `drop R` ) } }

: P { R r String extra }

@ mix P h → P { ^ @ P { . h r ( string_from `a long enough string to be on the heap, extra` ) } }

@ main → i {
    : P h @ P { @ R { ( string_from `a long enough string to be on the heap, one` ) } ( string_from `a long enough string to be on the heap, two` ) }
    : P g ( mix h )
    ( nurl_println ( string_data . . g r name ) )
    ^ 0
}
