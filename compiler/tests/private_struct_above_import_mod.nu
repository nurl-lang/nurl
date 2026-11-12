// fixture: module; private_struct_above_import_mod.nu — a module with a
// public and a private struct (diag_private_struct_above_import.nu).

pub : Open { i a }

: Hidden { i b }

pub @ mk_open → Open { ^ @ Open { 1 } }
