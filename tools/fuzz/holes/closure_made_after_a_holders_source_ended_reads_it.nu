// closure_made_after_a_holders_source_ended_reads_it: a holder viewing a block's local String, captured by a closure made after the block and called.
// Closed: making a closure reads what it captures by name, where it is made (A2's Rhs.pack, CapsOK): a capture whose borrow ended, or one moved away, is refused there as a direct read is. A capture the body only gives a new value is not read (agora #358).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #358: a holder viewing a block's local String, captured by a closure made after the block and called
$ `stdlib/core/string.nu`

: W { s v }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        = w @ W { ( string_data b ) }
    }
    : ( @ v ) f \ → v { ( nurl_println . w v ) }
    ( f )
    ^ 0
}
