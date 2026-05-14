// group_d_lib.nu — library imported by group_d.nu
// Tests import_decl: these functions must be callable from the importer.

@ lib_mul i a i b → i { ^ * a b }

@ lib_greet → s { ^ `imported` }
