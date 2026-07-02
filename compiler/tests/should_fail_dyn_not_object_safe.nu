// should_fail_dyn_not_object_safe.nu
// A trait with an associated type is NOT object-safe: a `%Boxed` value could not
// know the concrete `Elem` behind the i8* self, so `unwrap`'s return type is
// undispatchable. Using it as a dynamic object (docs/spec.md §4.9) must be
// rejected with a precise diagnostic, not produce broken IR.
$ `stdlib/core/string.nu`

% Boxed [T] {
    type Elem
    @ unwrap T self → Elem
}

: IB { i v }

% Boxed IB { type Elem i @ unwrap IB self → i { ^ . self v } }

@ take %Boxed b → i { ^ 0 }

@ main → i {
    : IB a @ IB { 5 }
    : %Boxed o ( dyn Boxed a )
    ^ ( take o )
}
