// join_view_inside_statement_ok.nu — a `?` / `??` join with an arm that owns
// its value, viewed (`string_data`) inside the call that consumes the view,
// is released after that call by the join's ownership bit; bound first, it
// is the binding's (agora #181, h731). The live allocation count is where
// it started after each loop.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `kept` ) )
    : i before ( live )
    : ~ i n 0
    : ~ i k 0
    ~ < k 6 {
        = n + n ( nurl_str_len ( string_data ?? ( vec_get [String] v % k 2 ) { T x → x F _ → ( string_from `fresh` ) } ) )
        = n + n ( nurl_str_len ( string_data ? == 0 % k 3 ( string_from `made` ) ( string_from `other` ) ) )
        : String b ?? ( vec_get [String] v % k 2 ) { T x → x F _ → ( string_from `bound` ) }
        : s bv ( string_data b )
        = n + n ( nurl_str_len bv )
        = k + k 1
    }
    ( nurl_println_int n )
    ( nurl_println_int - ( live ) before )
    ^ 0
}
