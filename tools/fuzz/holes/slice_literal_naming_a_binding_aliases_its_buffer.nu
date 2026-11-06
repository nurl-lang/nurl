// slice_literal_naming_a_binding_aliases_its_buffer: agora #485 — a slice literal that names a String binding (`[ String | a ]`) held a's very buffer, a second owner no rule knew of: `a` handed to a keeper and released (`( vec_push keep a ) ( vec_clear keep )`) left the slice reading freed memory, and a loop element of the slice handed to a `sink` (`~ x sl { ( eat x ) }`) released `a` under its owner, which released it again.
// Closed: a slice owns its elements; one that is not a fresh value — a binding, a parameter, a field, a borrowing call's result — is copied in (gen_slice_literal), and an element store does the same (mem_slice_store_val).
// main (before this PR): AddressSanitizer, heap-use-after-free in each shape.
// map: §7.6 | A2 | runs-clean | - | agora #485: a slice literal naming a binding aliased its buffer; the binding released, the slice read on, or a sink of its element released the binding (UAF)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink String s → v { ( nurl_println ( string_data s ) ) }

@ main → i {
    : ( Vec String ) keep ( vec_new [String] )
    : String a ( string_from `a string binding put into a slice literal, heap sized` )
    : [String sl [String | a]
    ( vec_push [String] keep a )
    ( vec_clear [String] keep )
    ~ x sl { ( nurl_println ( string_data x ) ) }
    : String b ( string_from `a binding whose slice element is handed to a sink` )
    {
        : [String sb [String | b]
        ~ x sb { ( eat x ) }
    }
    ( nurl_println ( string_data b ) )
    ^ 0
}
