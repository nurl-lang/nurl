// H370: a local of a type with a `% Drop` copied into a `: ~` binding — which takes the local's drop flag — handed `inout` to a callee that gives a field a new value, then the local read: the callee had released the String the local still pointed at.
// Closed: such a copy (`tborrow`) becomes the owner at a replacing call, and the local is moved there; reading it is a use of a moved value (bck_inout_borrow_check, agora #135).
// v0.78.0: accepted; ASan reported heap-use-after-free.
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
