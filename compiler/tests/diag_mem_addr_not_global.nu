// `( mem_addr x )` is the address of a mutable module global, whose storage
// lasts the whole run; a local's address would dangle once its frame ends.
unsafe @ main → i {
    : ~ i local 7
    : *i p ( mem_addr local )
    ^ . p 0
}
