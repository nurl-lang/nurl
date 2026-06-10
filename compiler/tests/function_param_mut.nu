// Test: field-store on a function-parameter multi-field struct.
//
// Before 2026-05-14: `= . p field val` inside `@ f T p → R { … }` emitted
// `getelementptr %T, %T* , i32 0, i32 N` with an EMPTY pointer operand
// because gen_fn_param registered the parameter type but never backed
// it with an alloca, and gen_field_store's "struct by value" branch
// reads `<obj>__ptr` as the GEP base.
//
// Fix: gen_fn_decl_concrete now invokes `__alloca_struct_params` right
// after the `entry:` label is emitted. The helper walks the param
// roster collected by gen_fn_param and emits
//
//   %p_ptr = alloca %T
//   store %T %p, %T* %p_ptr
//
// then registers `<p>__ptr = %p_ptr`. Predicate: multi-field named
// struct (`%T` with `__idx_1__type` set, not an enum). Single-field
// handle structs (%String, %Vec) are skipped — their f0 IS already a
// pointer.
//
// Semantics: VALUE semantics still apply. The function mutates a
// LOCAL copy of the struct; the caller's binding is unchanged. To
// share mutation, return the modified struct (or pass `*T`).
//
// Closes the parameter half (struct by-value / inout mutation).

: Counter { i n i max }

@ inc Counter c → v {
    = . c n + . c n 1
    // Read inside the same function call sees the local mutation:
    ( nurl_print `inside inc: n=` )
    ( nurl_print ( nurl_str_int . c n ) )
    ( nurl_print `\n` )
}

// Return the modified struct so the caller can rebind:
@ inc_returning Counter c → Counter {
    = . c n + . c n 1
    ^ c
}

@ main → i {
    : ~ Counter c @ Counter { 0 10 }

    // Three calls of `inc` — each mutates a separate local copy.
    // Compiles cleanly (was invalid IR before the fix).
    ( inc c )
    ( inc c )
    ( inc c )

    // Caller's c is untouched: value semantics.
    ( nurl_print `caller after inc x3: n=` )
    ( nurl_print ( nurl_str_int . c n ) )
    ( nurl_print `\n` )

    // Returning-pattern threads the mutation back through the return value.
    = c ( inc_returning c )
    = c ( inc_returning c )
    ( nurl_print `caller after inc_returning x2: n=` )
    ( nurl_print ( nurl_str_int . c n ) )
    ( nurl_print `\n` )

    ^ 0
}
