// fixture: module; alias_field_names_mod.nu — a module whose struct fields
// are named like its own functions (alias_field_names.nu, agora #729).
// Imported under an alias, the module's `x`, `first`, `len` and `name`
// become `fl__x` …, but the FIELDS of the same names stay `x`, `len` and
// `name`: an importer reads them with its own `. p x`.

: Pt { i x i y }

: Named { s name i len }

: Line { Pt a Pt b }

@ x Pt p → i { ^ . p x }

@ name Named n → s { ^ . n name }

// A local named like a module function is an index here, not a field: the
// rewrite spells it as it spells every other use of that local.
@ len [i ns → i {
    : i x 1
    ^ . ns x
}

@ moved Pt p → Pt {
    : ~ Pt q p
    = . q x + . q x 10
    ^ q
}

@ stretch Line l → i {
    : ~ Line m l
    = . . m b x 7
    ^ + . . m a x . . m b x
}
