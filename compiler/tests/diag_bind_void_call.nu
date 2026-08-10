// diag_bind_void_call.nu — binding the result of a call that returns 'v'.
@ nothing → v {}

@ main → i {
    : i n ( nothing )
    ^ n
}
