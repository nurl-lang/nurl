// slice_test.nu — Structs, slice literals, and foreach borrowing
// Demonstrates:
//   - Struct declaration and instantiation (@ Name { ... })
//   - Slice literals ([ T | ... ])
//   - Foreach element borrowing (~ IDENT expr { body })
//   - Member access (. obj field)

: Point { i x i y }

@ dist_squared Point p → i {
    ^ + * . p x . p x 
        * . p y . p y
}

@ main → i {
    // Luodaan slice-literaali Point-structeista
    : [ Point points [ Point |
        @ Point { 3 4 }    // 3^2 + 4^2 = 25
        @ Point { 5 12 }   // 5^2 + 12^2 = 169
        @ Point { 8 15 }   // 8^2 + 15^2 = 289
    ]

    : ~ i total_dist 0

    ( nurl_print `Calculating squared distances:\n` )

    // Foreach-silmukka lainaa (borrow) elementin 'p'
    ~ p points {
        : i d ( dist_squared p )
        
        ( nurl_print `- Point (` )
        ( nurl_print ( nurl_str_int . p x ) )
        ( nurl_print `, ` )
        ( nurl_print ( nurl_str_int . p y ) )
        ( nurl_print `) -> ` )
        ( nurl_print ( nurl_str_int d ) )
        ( nurl_print `\n` )

        = total_dist + total_dist d
    }

    ( nurl_print `\nTotal sum: ` )
    ( nurl_print ( nurl_str_int total_dist ) )
    ( nurl_print `\n` )

    ^ 0
}