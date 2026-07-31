// dce_reachability.nu — every indirect route into the live set.
//
// nurlc emits only the functions `main` can reach (`--no-dce` turns the
// pass off). Reachability is computed over the FINAL IR text, so a
// function survives exactly when some emitted `@name` names it. Most
// calls are a plain `call @f` and need no thought; the four routes below
// are the ones where nothing in the source looks like a call to the
// function that ends up running, and each would leave an undefined
// symbol at link time if the pass missed it:
//
//   1. a dyn trait object — `@__dynm.<Trait>.<Impl>.<method>` thunks are
//      named ONLY by the `@__vt.…` vtable constant, which lives at
//      module scope rather than inside any function body;
//   2. a `% Drop` impl — called from compiler-inserted auto-drop, plus
//      the `@__jdrop_…` panic-unwind thunk in the vtable's slot 0;
//   3. a closure value — reached through the `@__closure_N` the
//      compiler lifts out of the enclosing body;
//   4. a generic monomorphisation, whose mangled name exists only after
//      instantiation.
//
// `dead_weight` below is called by nothing and must NOT reach the
// output; tools/dcegate.sh checks that end of the contract, and this
// test checks that everything else still runs.

$ `stdlib/core/string.nu`

% Shape [T] {
    @ area T self → i
}

: Square { i side }
: Circle { i r }

% Shape Square { @ area Square s → i { ^ * . s side . s side } }

% Shape Circle { @ area Circle c → i { ^ * 3 * . c r . c r } }

// 2. A user destructor: never called by name anywhere in this file.
: Tracked { i id }

% Drop Tracked {
    @ drop Tracked t → v {
        ( nurl_print `dropped ` ) ( nurl_print ( nurl_str_int . t id ) ) ( nurl_print `\n` )
    }
}

// 4. Generic over a type parameter — `twice__i64` only exists once
// something instantiates it.
@ twice [T] T v → T { ^ v }

@ report %Shape s → v {
    ( nurl_print `area=` ) ( nurl_print ( nurl_str_int ( area s ) ) ) ( nurl_print `\n` )
}

// 3. Takes a closure and invokes it.
@ apply ( @ i i ) f i x → i { ^ ( f x ) }

// Unreachable: nothing names it. The pass must drop it.
@ dead_weight i n → i { ^ * n 1000 }

@ main → i {
    : Square sq @ Square { 4 }
    : Circle ci @ Circle { 2 }
    ( report ( dyn Shape sq ) )
    ( report ( dyn Shape ci ) )
    ( nurl_print `twice=` ) ( nurl_print ( nurl_str_int ( twice [i] 21 ) ) ) ( nurl_print `\n` )
    ( nurl_print `apply=` )
    ( nurl_print ( nurl_str_int ( apply \ i n → i { ^ + n 5 } 37 ) ) )
    ( nurl_print `\n` )
    : Tracked t @ Tracked { 7 }
    ^ 0
}
