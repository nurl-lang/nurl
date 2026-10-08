// method_impl_summaries.nu — a method call is a call of the impl its
// receiver's type dispatches to, and every question about the callee is
// asked of that impl: what it keeps, consumes, lends back or hands back.
// Asked of the trait's bare name, which has a declared contract and no
// body, an impl that kept its argument had it dropped under it by the
// caller (a use after free, h106), and a temporary handed to a method
// leaked — a raw `s`, a String, a Vec, the receiver itself. Each shape
// below runs the same body spelled as a method, LSan-clean in the
// sanitizer corpus; the sums would differ if a value were read freed.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i n → s {
    : ~ s out ( nurl_str_cat `` `` )
    : ~ i k 0
    ~ < k n { = out ( nurl_str_cat out `x` ) = k + k 1 }
    ^ out
}

@ mkv i n → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v k ) = k + k 1 }
    ^ v
}

% Ops [T] {
    @ s_len T self s x → i
    @ s_cat T self s x → s
    @ s_same T self s x → s
    @ str_len T self String x → i
    @ str_copy T self String x → String
    @ str_take T self sink String x → String
    @ vec_len_of T self ( Vec i ) x → i
    @ vec_take T self sink ( Vec i ) x → ( Vec i )
}

: Lens { i k }

% Ops Lens {
    @ s_len Lens l s x → i { ^ + . l k ( nurl_str_len x ) }
    @ s_cat Lens l s x → s { ^ ( nurl_str_cat x `!` ) }
    @ s_same Lens l s x → s { ^ x }
    @ str_len Lens l String x → i { ^ + . l k ( string_len x ) }
    @ str_copy Lens l String x → String { ^ ( string_from ( string_data x ) ) }
    @ str_take Lens l sink String x → String { ^ x }
    @ vec_len_of Lens l ( Vec i ) x → i { ^ + . l k ( vec_len [i] x ) }
    @ vec_take Lens l sink ( Vec i ) x → ( Vec i ) { ^ x }
}

// An impl that keeps what it is handed: its caller hands the value over.
% Keep [T] {
    @ keep T self String x → i
}

: Keeper { ( Vec String ) kept }

% Keep Keeper { @ keep Keeper k String x → i { ( vec_push [String] . k kept x ) ^ ( vec_len [String] . k kept ) } }

// A temporary receiver, and one whose field the method lends back.
% Named [T] {
    @ label T self → String
    @ size T self → i
}

: Pair { String a String b }

% Named Pair {
    @ label Pair p → String { ^ . p a }
    @ size Pair p → i { ^ + ( string_len . p a ) ( string_len . p b ) }
}

@ mkpair → Pair { ^ @ Pair { ( string_from `first` ) ( string_from `second` ) } }

@ temps i n → i {
    : Lens l @ Lens { 1 }
    : ~ i t ( s_len l ( mk n ) )
    = t + t ( nurl_str_len ( s_cat l ( mk n ) ) )
    = t + t ( nurl_str_len ( s_same l ( mk n ) ) )
    : s same ( s_same l ( mk n ) )
    = t + t ( nurl_str_len same )
    = t + t ( str_len l ( string_from `abcd` ) )
    = t + t ( string_len ( str_copy l ( string_from `abcd` ) ) )
    = t + t ( string_len ( str_take l ( string_from `abcd` ) ) )
    = t + t ( vec_len_of l ( mkv n ) )
    = t + t ( vec_len [i] ( vec_take l ( mkv n ) ) )
    ^ t
}

@ bound i n → i {
    : Lens l @ Lens { 1 }
    : String a ( string_from `abcd` )
    : ~ i t ( str_len l a )
    : String c ( str_copy l a )
    = t + t ( string_len c )
    : String b ( string_from `wxyz` )
    : String r ( str_take l b )
    = t + t ( string_len r )
    : ( Vec i ) v ( mkv n )
    : ( Vec i ) w ( vec_take l v )
    = t + t ( vec_len [i] w )
    ^ t
}

@ kept → i {
    : Keeper k @ Keeper { ( vec_new [String] ) }
    : String a ( string_from `abcd` )
    : ~ i t ( keep k a )
    = t + t ( keep k ( string_from `efgh` ) )
    ^ + t + ( string_len ( vec_at [String] . k kept 0 ) ) ( string_len ( vec_at [String] . k kept 1 ) )
}

@ receivers → i {
    : ~ i t ( size ( mkpair ) )
    = t + t ( string_len ( label ( mkpair ) ) )
    ^ t
}

@ main → i {
    ( nurl_print_int ( temps 5 ) ) ( nurl_print `\n` )
    ( nurl_print_int ( bound 3 ) ) ( nurl_print `\n` )
    ( nurl_print_int ( kept ) ) ( nurl_print `\n` )
    ( nurl_print_int ( receivers ) ) ( nurl_print `\n` )
    ^ 0
}
