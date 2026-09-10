// Deliberate raw-memory violation: the sanitizer must detect the write.
@ main → i {
    : *u p # *u ( nurl_alloc 8 )
    = . p 16 # u 42
    ( nurl_println_int # i . p 16 )
    ( nurl_free # s p )
    ^ 0
}
