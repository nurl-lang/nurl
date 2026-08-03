// should_fail_defer_return.nu — `^` inside a `;` defer body is
// rejected: the defer chain runs DURING return; a return from inside
// it would branch back into the chain it is executing.

$ `stdlib/core/string.nu`

@ main → i {
    ; { ^ 1 }
    ^ 0
}
