// diag_assoc_name_trait.nu — 'type = Elem' in a TRAIT declaration.
//
// This is the program a model writes after reading the old message,
// which told it the binding form was 'type Name = ConcreteType'. The
// declaration side takes no concrete type at all — it is 'type Name',
// two tokens — so the '=' lands where the name belongs.
: IntBox { i v }

% Boxed [T] {
    type = Elem
    @ unwrap T self → Elem
}

@ main → i { ^ 0 }
