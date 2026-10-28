// view_of_call_temporary_consumed.nu — a view of a call's temporary
// argument used inside the statement that made it (agora #138).
//
// `( first ( string_from … ) )` hands back a view of a String no binding
// owns. A call further out that returns nothing the view can point into
// drops the String once it is done — with the argument after it in
// between (`( pick ( first … ) 1 )`, the leftover carried past it),
// through a callee compiled after this one, whose summary decides at
// module end that it keeps nothing, and through a `?` join, which hands
// each arm's temporary on as a phi. A temporary the inner call only lent
// is not the caller's to drop, and a view of it may be bound. The
// sanitizer corpus holds each to no leak and no use after free.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first String s → s { ^ ( string_data s ) }

@ pick s a i n → s { ? > n 0 { ^ a } {} ^ `` }

@ text i n → String {
    : String s ( string_from `a string long enough to own a heap buffer, number ` )
    ( string_push_int s n )
    ^ s
}

@ main → i {
    ( nurl_println ( first ( text 1 ) ) )
    ( nurl_println ( pick ( first ( text 2 ) ) 1 ) )
    ( nurl_println_int ( later_len ( first ( text 3 ) ) ) )
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( text 4 ) )
    : s lent ( string_data ( vec_at [String] names 0 ) )
    ( nurl_println lent )
    : ~ i k 0
    ~ < k 3 {
        ( nurl_println_int ( later_len ( pick ( first ( text k ) ) 1 ) ) )
        ( nurl_println ? > k 1 `OK` ( string_data ( text k ) ) )
        ( nurl_println ? > k 1 ( first ( text k ) ) ( string_data ( text + k 10 ) ) )
        ( nurl_println ? > k 1 ? > k 0 `a` ( first ( text k ) ) `b` )
        = k + k 1
    }
    ^ 0
}

@ later_len s v → i { ^ ( nurl_str_len v ) }
