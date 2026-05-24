// call_arity_ok.nu — calls that match their callee's declared arity
// compile and run cleanly across a range of parameter shapes
// (zero-param, base types, a named-struct parameter). Guards the
// call-arity check against false positives. Expect 51.

$ `stdlib/core/string.nu`

: Point { i x  i y }

@ zero → i { ^ 7 }
@ one i a → i { ^ * a 2 }
@ three i a i b i c → i { ^ + + a b c }
@ takes_struct Point pt → i { ^ + . pt x . pt y }

@ main → i {
    : i z ( zero )
    : i o ( one 4 )
    : i t ( three 1 2 3 )
    : Point pt @ Point { 10 20 }
    : i sm ( takes_struct pt )
    ( nurl_print ( nurl_str_cat ( nurl_str_int + + + z o t sm ) `\n` ) )
    ^ 0
}
