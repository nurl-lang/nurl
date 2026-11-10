// value_block_ending_in_a_call_owned.nu — a value block that ends in a call
// hands its taker the call's own result (agora #613): a `:` binding and an
// assignment both own what the call made, and keep borrowing what it lent.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick String a String b → String { ^ ? > ( string_len a ) 3 a b }

@ main → i {
    : String c { : String t ( string_from `ab` ) ( string_concat t t ) }
    ( nurl_println ( string_data c ) )
    : ~ String a ( string_from `old` )
    = a { : String t ( string_from `cd` ) ( string_concat t t ) }
    ( nurl_println ( string_data a ) )
    = a { ( string_from `fresh` ) }
    ( nurl_println ( string_data a ) )
    : String outer ( string_from `an outer string` )
    = a { : String t ( string_from `tt` ) ( pick outer t ) }
    ( nurl_println ( string_data a ) )
    : ~ i total 0
    : ~ i k 0
    ~ < k 3 {
        : String l { : String t ( string_from `loop` ) ( string_concat t ( string_from `!` ) ) }
        = a { ( string_concat l l ) }
        = total + total ( string_len a )
        = k + k 1
    }
    ( nurl_println_int total )
    ( nurl_println ( string_data outer ) )
    ^ 0
}
