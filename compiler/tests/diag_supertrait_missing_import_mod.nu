// fixture: module; diag_supertrait_missing_import_mod.nu — an impl of a
// trait with a supertrait, with no impl of the supertrait anywhere.
// diag_supertrait_missing_import.nu imports it.
: Meter { i v }

% Ord Meter {
    @ cmp Meter a Meter b → i { ^ - . a v . b v }
}
