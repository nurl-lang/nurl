// borrow_call_args_move.nu — a move made by one argument of a call counts
// for the call's other arguments. The moves of a statement reach the borrow
// walk only after the statement, so before this check `( f m m )` handed
// `m` to a `sink` and, already released, to a borrowed parameter as well.
// Each function below has one error; the CONTROLs are legal and must stay
// silent.
$ `stdlib/core/string.nu`

@ eat sink String t → i { ^ ( string_len t ) }

@ both sink String x String y → i { ^ + ( string_len x ) ( string_len y ) }

@ view_then_eat s x i n → i { ^ + n ( strlen x ) }

@ take sink String t i n → i { ^ + n ( string_len t ) }

@ add i a i b → i { ^ + a b }

// One owner to a `sink` and to a borrowed parameter of the same call.
@ twice → i {
    : String m ( string_from `abcd` )
    ^ ( both m m )
}

// A view of the String in argument 1, the String consumed by argument 2:
// the callee reads the view after the move released its buffer.
@ view_before → i {
    : String s ( string_from `hello` )
    ^ ( view_then_eat ( string_data s ) ( eat s ) )
}

// Argument 1 releases the String as it runs; argument 2 then reads it.
@ read_after → i {
    : String s ( string_from `hello` )
    ^ ( add ( eat s ) ( string_len s ) )
}

// CONTROL: a scalar computed before a later argument releases the value.
@ scalar_before → i {
    : String s ( string_from `hello` )
    ^ ( add ( string_len s ) ( eat s ) )
}

// CONTROL: the callee takes `s` only when it runs, after argument 2 read it.
@ scalar_after_own_move → i {
    : String s ( string_from `hello` )
    ^ ( take s + ( string_len s ) 1 )
}

@ main → i {
    ( nurl_println_int + + ( twice ) ( view_before ) ( read_after ) )
    ( nurl_println_int + ( scalar_before ) ( scalar_after_own_move ) )
    ^ 0
}
