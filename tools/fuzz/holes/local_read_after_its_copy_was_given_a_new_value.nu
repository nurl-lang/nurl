// local_read_after_its_copy_was_given_a_new_value: a local of a type with a `% Drop` copied into a `: ~` binding — which takes the local's drop flag — handed `inout` to a callee that gives a field a new value, then the local read: the callee had released the String the local still pointed at.
// Closed: such a copy (`tborrow`) becomes the owner at a replacing call, and the local is moved there; reading it is a use of a moved value (bck_inout_borrow_check, agora #135).
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | h370 | a local of a % Drop type copied into a : ~ binding (which took its drop flag), handed inout to a replacing callee, then the local read: the copy becomes the owner and the local is moved at the call
$ `stdlib/core/string.nu`

: Res { String name }

% Drop Res { @ drop Res r → v {} }

@ rename inout Res r → v { = . r name ( string_from `a renamed resource, long enough for the heap` ) }

@ main → i {
    : Res s0 @ Res { ( string_from `a local resource, long enough for the heap` ) }
    : ~ Res r s0
    ( rename r )
    ( nurl_println ( string_data . s0 name ) )
    ^ 0
}
