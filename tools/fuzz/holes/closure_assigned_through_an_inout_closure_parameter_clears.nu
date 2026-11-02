// closure_assigned_through_an_inout_closure_parameter_clears: a clearing closure given to a local closure binding through a callee's inout closure parameter, then called; the caller's borrow of an element of the Vec it cleared was read afterwards.
// Closed: a closure literal's drop is noted on its own summary and, as before, on the enclosing function's parameter of the same name, so a literal reaching its call by a route no node follows (a field, an `inout` closure parameter, a kwargs call, a call's result, a join, a closure literal's parameter) keeps main's refusal (agora #359, formal's HOLD on github#1532).
// main's compiler: rejected (by the parameter's name); github#1532 before this fix: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #359 (formal's HOLD on github#1532): a clearing closure given to a local closure binding through a callee's inout closure parameter, then called
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ setf inout ( @ v ( Vec String ) ) f ( @ v ( Vec String ) ) src → v { = f src }

@ outer ( Vec String ) xs → i { : ~ ( @ v ( Vec String ) ) g \ ( Vec String ) y → v {} ( setf g \ ( Vec String ) xs → v { ( vec_clear [String] xs ) } ) ( g xs ) ^ ( vec_len [String] xs ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : String e ( vec_at [String] v 0 )
    ( nurl_println_int ( outer v ) )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
