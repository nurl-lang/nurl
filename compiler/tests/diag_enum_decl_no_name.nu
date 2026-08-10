// diag_enum_decl_no_name.nu — a top-level sum type with no name.
//
// gen_enum_decl took the name on trust, so this registered whatever '{'
// renders as and then failed at the brace it had already eaten — as
// "expected '{' but found 'A'", blaming the fixed-arity operand trap,
// which is not what happened. parse_type_enum had carried the right
// message all along, but it only sees ': |' in TYPE position; the
// top-level declaration is a different path and never consulted it.
: | { A B }

@ main → i { ^ 0 }
