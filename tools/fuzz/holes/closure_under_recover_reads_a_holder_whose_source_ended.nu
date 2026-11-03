// closure_under_recover_reads_a_holder_whose_source_ended: the same closure handed to recover.
// Closed: making a closure reads what it captures by name, where it is made (A2's Rhs.pack, CapsOK): a capture whose borrow ended, or one moved away, is refused there as a direct read is. A capture the body only gives a new value is not read (agora #358).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #358: the same closure handed to recover
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `a block-local string, freed at its end` )
        = w @ W { ( string_data b ) }
    }
    : !v PanicInfo r ( recover \ → v { ( nurl_println . w v ) } )
    ^ 0
}
