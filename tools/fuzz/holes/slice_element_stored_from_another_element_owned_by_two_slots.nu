// slice_element_stored_from_another_element_owned_by_two_slots: agora #545 — `= . a z . a o`, an element store whose value is read out of an element (the same slice's, another's) or a struct field: the value was moved as it was, so two slots owned one buffer.
// Closed: the store takes a copy: the slot it is read from keeps its value and the element the store replaces is dropped; a value that cannot be copied is refused there.
// main (before this PR): AddressSanitizer, heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #545: an element store from another element or a field left two slots owning one buffer (double free, UAF)
$ `stdlib/core/string.nu`

: Hold { [i items i n }

@ show [i a → v { ~ x a { ( nurl_println ( nurl_str_int x ) ) } }

@ main → i {
    : ~ [[i nn [[i | [i | 1 2] [i | 7]]
    : [[i mm [[i | [i | 5 6 7]]
    : i z 0 : i o 1
    = . nn z . nn o
    = . nn z . nn z
    = . nn o . mm z
    ~ r nn { ( show r ) }
    ~ r mm { ( show r ) }
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two` )]
    : [String b [String | ( string_from `a long enough string to be on the heap, three` )]
    = . a z . a o
    = . a o . b z
    ~ x a { ( nurl_println ( string_data x ) ) }
    ~ x b { ( nurl_println ( string_data x ) ) }
    : Hold g @ Hold { [i | 3 4 5] 3 }
    = . nn z . g items
    ~ r nn { ( show r ) }
    ( show . g items )
    ^ 0
}
