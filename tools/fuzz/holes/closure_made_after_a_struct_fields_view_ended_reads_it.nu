// closure_made_after_a_struct_fields_view_ended_reads_it: a holder viewing a block-local struct's String field, captured by a closure made after the block.
// Closed: making a closure reads what it captures by name, where it is made (A2's Rhs.pack, CapsOK): a capture whose borrow ended, or one moved away, is refused there as a direct read is. A capture the body only gives a new value is not read (agora #358).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #358: a holder viewing a block-local struct's String field, captured by a closure made after the block
$ `stdlib/core/string.nu`

: P { String name }
: W { s v }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : P p @ P { ( string_from `a block-local struct's string, freed at its end` ) }
        = w @ W { ( string_data . p name ) }
    }
    : ( @ v ) f \ → v { ( nurl_println . w v ) }
    ( f )
    ^ 0
}
