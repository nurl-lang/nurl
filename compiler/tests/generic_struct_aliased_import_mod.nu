// fixture: module; generic_struct_aliased_import_mod.nu — generic structs (one
// holding an instance of another), a struct with an instance as its field,
// and functions that make and read instances. Imported under an alias,
// every one of these names is spelled `<alias>__name`, the templates
// included (agora #724).
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Pair [T] { T a T b }

: Nest [T] { ( Pair T ) inner i depth }

: Bag [T] { ( Vec T ) items i extra }

: Tagged { ( Pair i ) p i tag }

@ pair_of i x i y → ( Pair i ) { ^ @ ( Pair i ) { x y } }

@ pair_sum ( Pair i ) p → i { ^ + . p a . p b }

@ nest_sum ( Nest i ) n → i { ^ + ( pair_sum . n inner ) . n depth }

@ tagged_sum Tagged t → i { ^ + ( pair_sum . t p ) . t tag }

@ bag_len ( Bag String ) b → i { ^ + ( vec_len [String] . b items ) . b extra }
