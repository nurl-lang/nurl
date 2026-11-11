// diag_generic_struct_holds_itself_by_value.nu — a generic struct whose
// instance holds itself by value (agora #661) is refused where a type
// names the instance: its fields are known only once it is made.

: Cell [T] { T v ? ( Cell T ) next }

@ main → i {
    : ( Cell i ) c @ ( Cell i ) { 1 @ ?( Cell i ) { F } }
    ^ . c v
}
