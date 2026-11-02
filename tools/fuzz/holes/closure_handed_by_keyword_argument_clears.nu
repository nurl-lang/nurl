// closure_handed_by_keyword_argument_clears: a clearing closure handed to a function by keyword argument; the caller's borrow of an element of the Vec it cleared was read afterwards.
// Closed: a closure literal's drop is noted on its own summary and, as before, on the enclosing function's parameter of the same name, so a literal reaching its call by a route no node follows (a field, an `inout` closure parameter, a kwargs call, a call's result, a join, a closure literal's parameter) keeps main's refusal (agora #359, formal's HOLD on github#1532).
// main's compiler: rejected (by the parameter's name); github#1532 before this fix: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #359 (formal's HOLD on github#1532): a clearing closure handed to a function by keyword argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ apply ( Vec String ) v ( @ v ( Vec String ) ) f → v { ( f v ) }

@ outer ( Vec String ) xs → i { : ( @ v ( Vec String ) ) clr \ ( Vec String ) xs → v { ( vec_clear [String] xs ) } ( apply f : clr v : xs ) ^ ( vec_len [String] xs ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : String e ( vec_at [String] v 0 )
    ( nurl_println_int ( outer v ) )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
