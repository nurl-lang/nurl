// alias_closure_type.nu — a module imported under an alias keeps its
// closure types (docs/spec.md §2, imports; found by Agora #659).
//
// The alias rewrite collects the names a module declares at its top
// level: an `@` there starts a function. It took the `@` of a closure
// TYPE in a signature for one too — `@ run_it ( @ v ) body → v` declared
// "a function named `v`" — and renamed every such word in the module:
// `run_it` then returned `m__v`, and compiling the module failed with
// "the function body ends without a return value (expected m__v)". Any
// module with a closure-typed parameter or result broke under an alias;
// stdlib/core/mem.nu became one of them. Parentheses nest for the
// collector now, as braces do.

$ `compiler/tests/alias_closure_type_mod.nu` m

@ main → i {
    : ~ i hits 0
    ( m::run_it \ → v { = hits + hits 1 } )
    : ( @ i i ) add2 ( m::adder 2 )
    ( nurl_println ( nurl_str_int ( m::apply_twice add2 m::BASE ) ) )
    ( nurl_println ( nurl_str_int hits ) )
    ^ 0
}
