// dyn_call_ownership.nu — a call through a trait object reaches whichever
// impl the object holds, so what it does with each argument is what any
// impl of the method may: the method's virtual callee carries the union
// of their summaries. Before, the call asked the trait's bare name, which
// has no body: a temporary handed to a method leaked, an impl that kept
// its argument had it dropped under it by the caller (a use after free),
// and a `sink` parameter in the trait made every call a compile error.
// A handle result is owned per call: each impl's thunk says whether it
// handed over a fresh value or lent one.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i n → s {
    : ~ s out ( nurl_str_cat `` `` )
    : ~ i k 0
    ~ < k n { = out ( nurl_str_cat out `x` ) = k + k 1 }
    ^ out
}

% Ops [T] {
    @ s_len T self s x → i
    @ s_cat T self s x → s
    @ str_len T self String x → i
    @ str_copy T self String x → String
    @ str_take T self sink String x → String
    @ keep T self String x → i
    @ tag T self → String
}

: Lens { i k ( Vec String ) kept String name }

: Mirror { i k ( Vec String ) kept String name }

% Ops Lens {
    @ s_len Lens l s x → i { ^ + . l k ( nurl_str_len x ) }
    @ s_cat Lens l s x → s { ^ ( nurl_str_cat x `!` ) }
    @ str_len Lens l String x → i { ^ + . l k ( string_len x ) }
    @ str_copy Lens l String x → String { ^ ( string_from ( string_data x ) ) }
    @ str_take Lens l sink String x → String { ^ x }
    @ keep Lens l String x → i { ( vec_push [String] . l kept x ) ^ ( vec_len [String] . l kept ) }
    @ tag Lens l → String { ^ ( string_from `lens` ) }
}

// Every impl must take each argument the same way (keep is kept by both).
% Ops Mirror {
    @ s_len Mirror m s x → i { ^ - ( nurl_str_len x ) . m k }
    @ s_cat Mirror m s x → s { ^ ( nurl_str_cat `!` x ) }
    @ str_len Mirror m String x → i { ^ - ( string_len x ) . m k }
    @ str_copy Mirror m String x → String { ^ ( string_from `mirror` ) }
    @ str_take Mirror m sink String x → String { ^ ( string_from ( string_data x ) ) }
    @ keep Mirror m String x → i { ( vec_push [String] . m kept x ) ^ 0 }
    @ tag Mirror m → String { ^ . m name }
}

@ run %Ops d i n → i {
    : ~ i t ( s_len d ( mk n ) )
    = t + t ( nurl_str_len ( s_cat d ( mk n ) ) )
    = t + t ( str_len d ( string_from `abcd` ) )
    = t + t ( string_len ( str_copy d ( string_from `abcd` ) ) )
    = t + t ( string_len ( str_take d ( string_from `abcd` ) ) )
    : String a ( string_from `named` )
    = t + t ( str_len d a )
    : String r ( str_take d ( string_from `taken` ) )
    = t + t ( string_len r )
    = t + t ( keep d ( string_from `kept` ) )
    : String b ( string_from `handed` )
    = t + t ( keep d b )
    : String g ( tag d )
    ^ + t ( string_len g )
}

@ main → i {
    : Lens l @ Lens { 1 ( vec_new [String] ) ( string_from `lens` ) }
    : %Ops dl ( dyn Ops l )
    ( nurl_print_int ( run dl 5 ) ) ( nurl_print `\n` )
    : Mirror m @ Mirror { 1 ( vec_new [String] ) ( string_from `mirror` ) }
    : %Ops dm ( dyn Ops m )
    ( nurl_print_int ( run dm 5 ) ) ( nurl_print `\n` )
    ^ 0
}
