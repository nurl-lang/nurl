// dyn_impl_calls_its_own_method_through_a_dyn_field_in_order_runs_clean: as dyn_impl_calls_its_own_method_through_a_dyn_field_swapped, Node hands its arguments down in order, so the result views x, which lives
// AGORA-481 guard: accepted - the component's least answer is "views a", not every argument
// map: §2.10 | A2 | runs-clean | - | AGORA-481
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Lex [T] { @ toks T self String a String b i d → ( Vec s ) }

: Leaf { i k }
: Node { % Lex child }

% Lex Leaf {
    @ toks Leaf self String a String b i d → ( Vec s ) {
        : ~ ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h ( string_data a ) )
        ^ h
    }
}

% Lex Node {
    @ toks Node self String a String b i d → ( Vec s ) { ^ ( toks . self child a b - d 1 ) }
}

@ main → i {
    : %Lex t ( dyn Lex @ Node { ( dyn Lex @ Leaf { 1 } ) } )
    : String x ( string_from `the first argument string, long enough to own a heap buffer` )
    : ~ ( Vec s ) r ( vec_new [s] )
    {
        : String y ( string_from `the second argument string, freed at the end of the inner block` )
        = r ( toks t x y 1 )
    }
    ( nurl_println ( vec_at [s] r 0 ) )
    ^ 0
}
