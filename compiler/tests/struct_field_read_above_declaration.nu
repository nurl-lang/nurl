// struct_field_read_above_declaration.nu — agora #769: a field read of a
// struct declared below the function, through a by-value parameter and
// through a `??` payload, said "type 'R' has no field 'n'". The field
// names are read with the layout, before any body compiles.

@ f1 E e → i { ^ ?? e { EA r → . r n EB j → j } }

@ g1 R r → i { ^ . r n }

: R { i n }

: | E { EA R EB i }

@ main → i { ^ - + ( f1 @ E { EA @ R { 3 } } ) ( g1 @ R { 4 } ) 7 }
