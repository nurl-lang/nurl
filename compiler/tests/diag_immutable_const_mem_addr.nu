// diag_immutable_const_mem_addr.nu — even an `unsafe` function cannot
// take the address of an immutable module constant: a store through it
// would change a value every read takes as an immediate (AGORA-855).
: i LIMIT 100

unsafe @ main → i {
    : *i p ( mem_addr LIMIT )
    = . p 0 7
    ^ LIMIT
}
