// owned_slice_elements_released_by_a_panic_under_recover: a panic under recover unwinds over a function holding an owned `[String` slice, a slice of closures over a String, a struct whose field is a `[String` slice (a literal and a moved binding), and a slice a callee returned; each runs once without the panic too.
// Closed (agora #509): the panic journal registered an owned slice by its raw buffer only (mem_journal_push_slice, the struct-field slice kind), so the unwind freed the buffer and leaked every element it owned. A slice that owns its elements is now registered with its length and its element drop (nurl_journal_push_slice): still keyed by the buffer, so whichever path frees it ends the registration, and a panic's drain drops the elements before it releases the buffer.
// main (before this PR): LeakSanitizer reported the Strings (one per element), and the closure's captured String.
// map: §7.2 | A2 | runs-clean | - | a panic under recover over an owned slice freed its buffer and leaked the elements it owns
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: H { [String sl i n }

@ hs → String { ^ ( string_from `a string in a slice when a panic unwinds over it` ) }

@ mk → [String { ^ [String | ( hs ) ( hs )] }

@ b1 i k → i {
    : [String sl [String | ( hs )]
    ? > k 0 { ( panic `boom` ) } {}
    ^ 0
}

@ b2 i k → i {
    : String s ( hs )
    : [( @ i ) cl [( @ i ) | \ → i { ^ ( string_len s ) }]
    ? > k 0 { ( panic `boom` ) } {}
    ^ 0
}

@ b3 i k → i {
    : H h @ H { [String | ( hs ) ( hs )] 2 }
    ? > k 0 { ( panic `boom` ) } {}
    ^ - . h n 2
}

@ b4 i k → i {
    : [String sl [String | ( hs )]
    : H h @ H { sl 1 }
    ? > k 0 { ( panic `boom` ) } {}
    ^ - . h n 1
}

@ b5 i k → i {
    : [String sl ( mk )
    ? > k 0 { ( panic `boom` ) } {}
    ^ 0
}

@ main → i {
    : !v PanicInfo r1 ( recover \ → v { : i x ( b1 1 ) } )
    : !v PanicInfo r2 ( recover \ → v { : i x ( b2 1 ) } )
    : !v PanicInfo r3 ( recover \ → v { : i x ( b3 1 ) } )
    : !v PanicInfo r4 ( recover \ → v { : i x ( b4 1 ) } )
    : !v PanicInfo r5 ( recover \ → v { : i x ( b5 1 ) } )
    ^ + + + + ( b1 0 ) ( b2 0 ) ( b3 0 ) ( b4 0 ) ( b5 0 )
}
