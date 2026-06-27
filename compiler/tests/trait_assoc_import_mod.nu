// trait_assoc_import_mod.nu — helper module for trait_assoc_import.nu.
// Declares a trait with an associated type AND a default method, so the
// importer exercises: (1) associated-type substitution across a `$` import,
// and (2) the cross-import default-method emission path — which double-emitted
// the default (LLVM "invalid redefinition") until scan_trait_body's __defaults
// append was made idempotent (a `$`-imported trait body is scanned twice).
% Boxed [T] {
    type Elem
    @ unwrap T self → Elem
    @ first T self Elem d → Elem { ^ ( unwrap self ) }
}
