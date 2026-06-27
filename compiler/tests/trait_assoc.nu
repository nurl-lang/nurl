// trait_assoc.nu
// Associated types: a trait declares `type Elem`, each impl binds it to a
// concrete type, and the trait's default methods name `Elem` — substituted
// per impl. Here Boxed has an associated element type bound to i for IntBox
// and to f for FloatBox, and the default `first` returns an Elem, so its
// specialised copies have return type i and f respectively (the float copy
// must really return a double — an unsubstituted `Elem` would not compile).

: IntBox   { i v }
: FloatBox { f v }

% Boxed [T] {
    type Elem
    @ unwrap T self → Elem              // required, returns the associated type
    @ first T self Elem d → Elem {      // default: signature names Elem twice
        ^ ( unwrap self )               // dispatches to the impl's unwrap
    }
}

% Boxed IntBox {
    type Elem i
    @ unwrap IntBox self → i { ^ . self v }
    // `first` defaulted → @ first__IntBox IntBox self i d → i
}

% Boxed FloatBox {
    type Elem f
    @ unwrap FloatBox self → f { ^ . self v }
    // `first` defaulted → @ first__FloatBox FloatBox self f d → f
}

@ main → i {
    : IntBox   a @ IntBox   { 7 }
    : FloatBox b @ FloatBox { 2.5 }

    : i x ( first a 0 )         // → i 7   (default specialised to i)
    : f y ( first b 0.0 )       // → f 2.5 (default specialised to f — real double)

    : i yi # i * y 2.0          // 2.5 * 2.0 = 5.0 → 5
    : i total + x yi            // 7 + 5 = 12

    ( nurl_print `total: ` )
    ( nurl_print ( nurl_str_int total ) )
    ( nurl_print `\n` )
    ^ ? == total 12 0 1
}
