// map: §2.10 | A2 | rejected | - | AGORA-481: a dyn impl hands back its own method called through a dyn field with its view arguments swapped
// AGORA-481: refused - the impl asks its own answer through the virtual callee, so its walk settles with its fellows as a component (main 393d7473: accepted, heap-use-after-free)
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
    @ toks Node self String a String b i d → ( Vec s ) { ^ ( toks . self child b a - d 1 ) }
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
