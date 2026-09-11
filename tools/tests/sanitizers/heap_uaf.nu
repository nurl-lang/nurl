// Deliberate raw-memory violation, compiled with --no-borrowck.
@ main → i {
    : *u p # *u ( nurl_alloc 8 )
    = . p 0 # u 42
    ( nurl_free # s p )
    ( nurl_println_int # i . p 0 )
    ^ 0
}
