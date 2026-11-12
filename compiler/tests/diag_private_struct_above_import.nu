// diag_private_struct_above_import.nu — agora #772: a struct may be used
// above its declaration, and above the import that declares it — but a
// private struct of another file stays private there too: its visibility
// is known with its layout, before any body compiles.

@ main → i {
    : Open o ( mk_open )
    : Hidden h @ Hidden { 3 }
    ^ - + . o a . h b 4
}

$ `compiler/tests/private_struct_above_import_mod.nu`
