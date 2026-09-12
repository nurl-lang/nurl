// diag_try_option_in_result_fn.nu — '\' on an option inside a function
// that returns a result.
//
// Both shapes start `{ i1, `, so the "can this function carry a failure"
// check accepts either one. What it cannot see is that the fail path then
// falls to `zeroinitializer` of the OTHER shape.
//
// This direction INVENTS an error: the enclosing `!i i` returns
// `{ false, 0, 0 }` — Err with an error payload of 0 that no callee ever
// produced. The other direction discards one: a result tried inside a
// `?T` function returns None and the Err payload is gone.
//
// '\' propagates "the error value unchanged", and neither direction can.
// Both conversions are real and the stdlib spells them: ( res_ok r )
// turns a result into an option by dropping the error, ( opt_ok_or o err )
// turns an option into a result with an error the author chose.
@ maybe i a → ?i {
    ^ @ ?i { F }
}

@ fetch → !i i {
    : i v \ ( maybe 1 )
    ^ @ !i i { T v }
}

@ main → i {
    : !i i r ( fetch )
    ^ ?? r { T v → v F e → e }
}
