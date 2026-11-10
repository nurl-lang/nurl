// An element store whose value is read out of an element — the same slice's,
// another slice's — or out of a struct field stores a copy: the slot it is
// read from keeps its value, and the element the store replaces is dropped.
// The value was moved as it was, so two slots owned one buffer (a double
// free, or a use after free once one of them was replaced).
$ `stdlib/core/string.nu`

: Rec { String name i n }
: Hold { [i items i n }

@ show [i a → v { ~ x a { ( nurl_println ( nurl_str_int x ) ) } }

// a slice of slices: from the same slice, from itself, from another slice
@ run_slices → v {
    : ~ [[i nn [[i | [i | 1 2] [i | 7]]
    : [[i mm [[i | [i | 5 6 7]]
    : i z 0 : i o 1
    = . nn z . nn o
    = . nn z . nn z
    = . nn o . mm z
    ~ r nn { ( show r ) }
    ~ r mm { ( show r ) }
}

// a slice of Strings
@ run_strings → v {
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two` )]
    : [String b [String | ( string_from `a long enough string to be on the heap, three` )]
    : i z 0 : i o 1
    = . a z . a o
    = . a o . a o
    = . a o . b z
    ~ x a { ( nurl_println ( string_data x ) ) }
    ~ x b { ( nurl_println ( string_data x ) ) }
}

// a struct element that holds a String
@ run_structs → v {
    : ~ [Rec rs [Rec | @ Rec { ( string_from `a long enough string to be on the heap, rec one` ) 1 } @ Rec { ( string_from `a long enough string to be on the heap, rec two` ) 2 }]
    : i z 0 : i o 1
    = . rs z . rs o
    ~ r rs { ( nurl_println ( string_data . r name ) ) ( nurl_println ( nurl_str_int . r n ) ) }
}

// a struct's field, and a field of another slice's element
@ run_fields → v {
    : ~ [[i nn [[i | [i | 1 2] [i | 7]]
    : Hold g @ Hold { [i | 3 4 5] 3 }
    : [Hold hs [Hold | @ Hold { [i | 8] 1 } @ Hold { [i | 9 9] 2 }]
    : i z 0 : i o 1
    = . nn z . g items
    = . nn o . . hs o items
    ~ r nn { ( show r ) }
    ( show . g items )
    ~ h hs { ( show . h items ) }
}

// through an `inout` slice
@ shift inout [String d [String src i k → v { = . d k . src k }
@ run_inout → v {
    : ~ [String a [String | ( string_from `a long enough string to be on the heap, in one` ) ( string_from `a long enough string to be on the heap, in two` )]
    : [String b [String | ( string_from `a long enough string to be on the heap, in three` )]
    ( shift a b 0 )
    ~ x a { ( nurl_println ( string_data x ) ) }
    ~ x b { ( nurl_println ( string_data x ) ) }
}

// plain data moves as before
@ run_ints → v {
    : ~ [i a [i | 1 2 3]
    : i z 0 : i o 1
    = . a z . a o
    ( show a )
}

@ main → i {
    ( run_slices ) ( run_strings ) ( run_structs ) ( run_fields ) ( run_inout ) ( run_ints )
    ^ 0
}
