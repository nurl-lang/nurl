// should_fail_recursive_struct.nu — a struct that contains itself by value
// has infinite size (`: Node { i v  Node next }`). gen_struct_decl now
// diagnoses it at the declaration with the box-it-as-a-pointer cure, instead
// of a cryptic insertvalue IR error at the first construction.
: Node { i v  Node next }
@ main → i { ^ 0 }
