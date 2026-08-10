// diag_assoc_type_eq_form.nu — an associated-type binding written with
// '=', the form all three of the compiler's own messages used to teach.
//
// The binding is three tokens, 'type Name Concrete' (docs/spec.md §4,
// docs/LIMITATIONS.md, and __parse_assoc_binding's own comment). Every
// message about it said 'type Name = ConcreteType', so a model that hit
// this error and did exactly what the message asked hit the SAME error
// again — the diagnostic described a syntax the compiler rejects, and
// rejected the input with it. Nothing exercised any of the three.
: IntBox { i v }

% Boxed [T] {
    type Elem
    @ unwrap T self → Elem
}

% Boxed IntBox {
    type Elem = i
    @ unwrap IntBox self → i { ^ . self v }
}

@ main → i {
    : IntBox b @ IntBox { 7 }
    ^ ( unwrap b )
}
