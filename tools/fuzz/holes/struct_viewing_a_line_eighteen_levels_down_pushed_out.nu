// struct_viewing_a_line_eighteen_levels_down_pushed_out: a struct whose view sits eighteen struct levels down, pushed out past its String.
// Closed: `__ty_holds_view` walks a named type once per question, a type met again inside its own walk answering no while it is in progress, instead of stopping 16 levels down (agora #338).
// main 24e95a81: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #338: a struct whose view sits eighteen struct levels down, pushed out past its String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: L0 { L1 n String o0 }
: L1 { L2 n String o1 }
: L2 { L3 n String o2 }
: L3 { L4 n String o3 }
: L4 { L5 n String o4 }
: L5 { L6 n String o5 }
: L6 { L7 n String o6 }
: L7 { L8 n String o7 }
: L8 { L9 n String o8 }
: L9 { L10 n String o9 }
: L10 { L11 n String o10 }
: L11 { L12 n String o11 }
: L12 { L13 n String o12 }
: L13 { L14 n String o13 }
: L14 { L15 n String o14 }
: L15 { L16 n String o15 }
: L16 { L17 n String o16 }
: L17 { s v String o17 }

@ main → i {
    : ( Vec L0 ) tops ( vec_new [L0] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        ( vec_push [L0] tops @ L0 { @ L1 { @ L2 { @ L3 { @ L4 { @ L5 { @ L6 { @ L7 { @ L8 { @ L9 { @ L10 { @ L11 { @ L12 { @ L13 { @ L14 { @ L15 { @ L16 { @ L17 { ( string_data line ) ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } ( string_from `o` ) } )
    }
    : L0 top ( vec_at [L0] tops 0 )
    ( nurl_println . . . . . . . . . . . . . . . . . . top n n n n n n n n n n n n n n n n n v )
    ^ 0
}
