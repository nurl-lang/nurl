// loop_condition_binds_owners.nu — what a loop's condition binds is the
// round's (agora #674, #628). A value block in a condition binds in the
// scope around it, and around a loop's condition that is the function:
// its owners were released once, at the function's exit, and every round
// wrote over the slot of the round before. They are released where the
// round's condition has its value:
//   drops    a struct with a destructor: one `drop` per evaluation;
//   join     a String out of a `?` join;
//   moved    …not one the block handed on;
//   nested   a condition block in an inner loop too;
//   leaves   a `^` out of the condition block itself;
//   closure  a closure over the block's String, called in the condition.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String name i id }

% Drop R { @ drop R r → v { ( nurl_print `drop ` ) ( nurl_println_int . r id ) } }

@ mk i k → String { : ~ String r ( string_from `g: a loop string long enough for a heap buffer ` ) ( string_push_int r k ) ^ r }

@ drops i n → i {
    : ~ i k 0
    ~ < { : R r @ R { ( mk k ) k } . r id } n { = k + k 1 }
    ^ k
}

@ join i n → i {
    : ~ i k 0
    ~ < { : String s ? == % k 2 0 ( mk k ) ( string_from `odd: a string long enough for a heap buffer too` ) ? > ( string_len s ) 10 k 99 } n { = k + k 1 }
    ^ k
}

@ moved i n → i {
    : ~ ( Vec String ) keep ( vec_new [String] )
    : ~ i k 0
    ~ < { : String s ( mk k ) ( vec_push [String] keep s ) k } n { = k + k 1 }
    ^ ( vec_len [String] keep )
}

@ nested i n → i {
    : ~ i a 0
    : ~ i t 0
    ~ < { : String o ( mk a ) + a - ( string_len o ) ( string_len o ) } n {
        : ~ i b 0
        ~ < { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk b ) ) + b - ( vec_len [String] v ) 1 } 3 { = b + b 1 = t + t 1 }
        = a + a 1
    }
    ^ t
}

@ leaves i n → i {
    : ~ i k 0
    ~ < { : String s ( mk k ) ? == k 2 { ^ 77 } {} + k - ( string_len s ) ( string_len s ) } n { = k + k 1 }
    ^ k
}

@ closure i n → i {
    : ~ i k 0
    ~ < { : String s ( mk k ) : ( @ i i ) c \ i x → i { ^ + x ( string_len s ) } - ( c k ) ( string_len s ) } n { = k + k 1 }
    ^ k
}

@ main → i {
    ( nurl_println_int ( drops 3 ) )
    ( nurl_println_int ( join 3 ) )
    ( nurl_println_int ( moved 3 ) )
    ( nurl_println_int ( nested 2 ) )
    ( nurl_println_int ( leaves 9 ) )
    ( nurl_println_int ( closure 3 ) )
    ^ 0
}
