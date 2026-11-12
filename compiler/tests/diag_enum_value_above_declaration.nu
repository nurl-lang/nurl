// diag_enum_value_above_declaration.nu — an enum used BY VALUE above its
// declaration keeps the "declared LATER" rule (a struct no longer does,
// struct_value_above_declaration.nu): what releases the payloads an enum
// value holds is decided where the enum is declared (agora #752).

: Pt { i x i y }

@ main → i {
    : Shade s ( mk )
    ^ 0
}

@ mk → Shade { ^ @ Shade { Mix @ Pt { 40 0 } } }

: | Shade { Light Dark Mix Pt }
