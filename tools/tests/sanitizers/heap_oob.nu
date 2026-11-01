// Deliberate raw-memory violation: the sanitizer must detect the write.
// The allocation, the write past its end and the read are three functions,
// so a split build (--split=3) puts them in parts of their own and the
// violation crosses a part boundary.
unsafe @ grab → *u { ^ # *u ( nurl_alloc 8 ) }

unsafe @ poke * u p → v { = . p 16 # u 42 }

unsafe @ show * u p → v { ( nurl_println_int # i . p 16 ) }

unsafe @ main → i {
    : *u p ( grab )
    ( poke p )
    ( show p )
    ( nurl_free # s p )
    ^ 0
}
