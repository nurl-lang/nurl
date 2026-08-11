// diag_generic_fn_unclosed.nu — a generic function template whose
// body brace count never reaches zero (the inner '?' arm is missing
// its '}', so the function's own '}' closes the arm instead and EOF
// arrives at depth 1). Same collect_fn_body EOF hang as the generic
// struct twin; same cure in the message.

@ pick [T] T a T b i which → T {
    ? > which 0 { ^ a
        ^ b
    }

    @ main → i {
        ^ ( pick [i] 1 2 0 )
    }
