// option_taken_from_locked_stays_in_slot: an option that owns something, taken out of a Locked (`: ?K t ( locked_take [?K] g )` … `( locked_restore [?K] g t )`), was left in its slot: mem_take parsed where the value came from as `<addr> <type> <depth>` split on spaces, and an option's type `{ i1, %K }` has spaces of its own — so the slot kept its copy, and the restore, which drops what the slot holds, dropped the value the taker was handing back. The next take read freed memory (whisper's server: the tokenizer, on the second request).
// Closed: the type is everything between the address and the depth; the slot is emptied for every type that owns something.
// main's compiler: AddressSanitizer, heap-use-after-free on the Arc's count.
// map: §6.5 | A3 | runs-clean | h267 | option taken from Locked left in slot; restore drops value handed back
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: K { ( Arc String ) a }

@ main → i {
    : K k @ K { ( arc_new [String] ( string_from `hello` ) ) }
    : ( Locked ? K ) g ( locked_new [? K] @ ?K { T @ K { ( arc_clone [String] . k a ) } } )
    : ~ i n 0
    ~ < n 3 {
        : ?K t ( locked_take [? K] g )
        ( locked_restore [? K] g t )
        = n + n 1
    }
    ( nurl_println_int ( arc_strong [String] . k a ) )
    ^ 0
}
