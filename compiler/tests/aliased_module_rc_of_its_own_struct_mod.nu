// fixture: module; aliased_module_rc_of_its_own_struct_mod.nu — a struct
// holding an `( Rc T )` of another struct of the module. Imported under an
// alias both are spelled `<alias>__name`, and so is the instance `( Rc Pt )`
// the module's code names (agora #724).
$ `stdlib/std/rc.nu`

: Pt { i x i y }

: Hold { ( Rc Pt ) r }

@ hold_new i x → Hold { ^ @ Hold { ( rc_new [Pt] @ Pt { x x } ) } }

@ hold_sum Hold h → i { ^ + . ( rc_get [Pt] . h r ) x . ( rc_get [Pt] . h r ) y }
