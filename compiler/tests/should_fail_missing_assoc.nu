// should_fail_missing_assoc.nu
// A trait with an associated type requires every impl to bind it. This impl
// of Boxed omits `type Elem`, so it is not total over the trait's associated
// types — the compiler must reject it, naming the missing associated type.

: IntBox { i v }

% Boxed [T] {
    type Elem
    @ unwrap T self → Elem
}

% Boxed IntBox {
    // missing `type Elem i` → coherence error
    @ unwrap IntBox self → i { ^ . self v }
}

@ main → i { ^ 0 }
