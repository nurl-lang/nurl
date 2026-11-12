// struct_value_above_declaration.nu — a named struct used BY VALUE before
// its declaration (agora #772). Refused as "declared LATER" — before that,
// clang's "Cannot allocate unsized type %Later", and a field read said
// "type 'Later' has no field 'a'". Every struct's layout — its fields'
// names and types — is read before any body compiles, and the type is
// emitted at the top of the module, so a value of it works anywhere.

$ `stdlib/core/vec.nu`

@ use_it → i {
    : Later x ( make )
    : i v . x a
    ( vec_free [i] . x xs )
    ^ v
}

: Later {
    i a
    ( Vec i ) xs
}

@ make → Later { ^ @ Later { 7 ( vec_new [i] ) } }

@ main → i { ^ - ( use_it ) 7 }
