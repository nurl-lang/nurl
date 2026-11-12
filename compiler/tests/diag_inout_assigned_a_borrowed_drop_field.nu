// diag_inout_assigned_a_borrowed_drop_field.nu — an `inout` parameter
// given a field of a parameter it only borrows, of a type with a `% Drop`
// of its own and no clone (Agora #697). The caller still owns that field,
// so the `inout` binding would need a copy of it, and there is none: the
// two would both run its destructor. Refused where the field is read, with
// what to pass instead.

$ `stdlib/core/string.nu`

: Bomb { String tag }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( string_data . b tag ) ) } }

: H { Bomb b i n }

@ take inout Bomb dst H x → v { = dst . x b }

@ main → i {
    : H h @ H { @ Bomb { ( string_from `inner bomb` ) } 1 }
    : ~ Bomb c @ Bomb { ( string_from `outer bomb` ) }
    ( take c h )
    ^ 0
}
