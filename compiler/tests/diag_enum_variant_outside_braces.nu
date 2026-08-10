// diag_enum_variant_outside_braces.nu — the variant named between the
// enum name and the brace, as in 'E::A(1)'.
//
// NURL writes it inside: '@ E { A 1 }'. The generic parser message
// ("expected '{' but found 'A'") named the token and not the rule, and
// blamed the arity trap — which is not what happened. The check fires
// only when the ident really is a declared variant, so a genuine stray
// token still gets the arity message it deserves.
: | E { A i B }

@ main → i {
    : E e @ E A 1
    ^ 0
}
