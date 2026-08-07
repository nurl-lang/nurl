// arity_strict_nary.nu — the n-ary `&` trap, as an error.
//
// `&` and `|` take exactly TWO operands. Four conditions therefore need
// three of them. Written with one, `?` takes `& a b` as the condition
// and then consumes the remaining two comparisons as its bare then/else
// values — after which the `{ … } { … }` blocks run as ordinary
// statements. The conditional logic is wrong and the program still
// compiles, which is the entire reason this needs a flag and a gate:
// nothing downstream of the compiler can tell.
//
// Baselined for the diagnostic TEXT, because where it points is the
// point. The trap can only be DETECTED once the `{` after the
// conditional is reached, and reporting the lexer's position at that
// moment put the caret on the closing `} {}` — below the mistake,
// pointing at the consequence. It must name the `?` on line 20.
//
// Expected: COMPILE FAIL under --strict-arity, caret at 20:5.

@ f i a i b i c i d → i {
    ? & >= a 0 < a b >= c 0 < c d {
        ^ 1
        // A body long enough that the closing brace is nowhere near the
        // `?` — which is exactly when a caret on the brace misleads.
    } {}
    ^ 0
}

@ main → i { ^ ( f 1 2 3 4 ) }
