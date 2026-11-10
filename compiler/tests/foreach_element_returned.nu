// A `~` loop's element returned out of the loop is the caller's own value
// when the container is dropped on the way out: taken out of its slot (a
// slice, a String), copied where it cannot be taken (a struct element, under
// a `;` defer), and still a lend the caller copies when the container is a
// parameter. Each was a use after free or a double free: the element went
// back as lent while the frame dropped the container it was read out of.
$ `stdlib/core/string.nu`

: Rec { String name i n }
: Hold { [[i items i n }

@ show [i a → v { ~ x a { ( nurl_println ( nurl_str_int x ) ) } }

// a slice out of a local slice of slices
@ pick_slice i n → [i {
    : [[i nest [[i | [i | 1] [i | 2 3] [i | 4 5 6]]
    : ~ i k 0
    ~ r nest { ? == k n { ^ r } {} = k + k 1 }
    ^ [i | 0]
}

// a String out of a local slice of Strings
@ pick_str i n → String {
    : [String ss [String | ( string_from `a long enough string to be on the heap, one` ) ( string_from `a long enough string to be on the heap, two` )]
    : ~ i k 0
    ~ x ss { ? == k n { ^ x } {} = k + k 1 }
    ^ ( string_from `none of them, in a string long enough for the heap` )
}

// a struct that holds a String
@ pick_rec i n → Rec {
    : [Rec rs [Rec | @ Rec { ( string_from `a long enough string to be on the heap, rec one` ) 1 } @ Rec { ( string_from `a long enough string to be on the heap, rec two` ) 2 }]
    ~ r rs { ? == . r n n { ^ r } {} }
    ^ @ Rec { ( string_from `no such record, in a string long enough for the heap` ) 0 }
}

// through a value block
@ pick_block i n → String {
    : [String ss [String | ( string_from `a long enough string to be on the heap, block one` ) ( string_from `a long enough string to be on the heap, block two` )]
    : ~ i k 0
    ~ x ss { ? == k n { ^ { x } } {} = k + k 1 }
    ^ ( string_from `none of them, in a string long enough for the heap` )
}

// an inner loop's element
@ pick_inner i n → String {
    : [[String nest [[String | [String | ( string_from `a long enough string to be on the heap, inner a` )] [String | ( string_from `a long enough string to be on the heap, inner b` ) ( string_from `a long enough string to be on the heap, inner c` )]]
    : ~ i k 0
    ~ row nest { ~ x row { ? == k n { ^ x } {} = k + k 1 } }
    ^ ( string_from `none of them, in a string long enough for the heap` )
}

// the container a field of a local
@ pick_field → [i {
    : Hold h @ Hold { [[i | [i | 7] [i | 8 9]] 2 }
    : ~ i k 0
    ~ r . h items { ? == k 1 { ^ r } {} = k + k 1 }
    ^ [i | 0]
}

// under a defer that reads the container: the element is copied
@ pick_defer → [i {
    : [[i nest [[i | [i | 1] [i | 2 3]]
    ; { ~ q nest { ( show q ) } }
    ~ r nest { ^ r }
    ^ [i | 0]
}

// the container a parameter: the caller keeps all of it
@ pick_param [String ss → String {
    ~ x ss { ^ x }
    ^ ( string_from `none of them, in a string long enough for the heap` )
}

@ main → i {
    : [i a ( pick_slice 1 ) : [i b ( pick_slice 7 )
    ( show a ) ( show b )
    : String s1 ( pick_str 1 ) : String s2 ( pick_str 5 )
    ( nurl_println ( string_data s1 ) ) ( nurl_println ( string_data s2 ) )
    : Rec r1 ( pick_rec 2 ) : Rec r2 ( pick_rec 9 )
    ( nurl_println ( string_data . r1 name ) ) ( nurl_println ( string_data . r2 name ) )
    : String s3 ( pick_block 0 )
    ( nurl_println ( string_data s3 ) )
    : String s4 ( pick_inner 2 ) : String s5 ( pick_inner 0 )
    ( nurl_println ( string_data s4 ) ) ( nurl_println ( string_data s5 ) )
    : [i f ( pick_field )
    ( show f )
    : [i d ( pick_defer )
    ( show d )
    : [String keep [String | ( string_from `a long enough string to be on the heap, kept` )]
    : String s6 ( pick_param keep )
    ( nurl_println ( string_data s6 ) )
    ~ x keep { ( nurl_println ( string_data x ) ) }
    ^ 0
}
