// struct_with_an_option_of_an_enum_declared_below_its_first_user_released_runs_clean: `: S { ? E e i n }` bound in a function above `: | E { EA String EB i }`, and again below it with a String payload
// Closed: an enum's compiler drop is known once the layouts are read (read_type_layouts), not when its declaration is reached, so a struct holding `?E` is dropped with its payload wherever it is first asked about (agora #744).
// main 3b63ee3b: accepted — and leaked: the String payload of the second binding.
// map: §7.1 | A2 | runs-clean | - | agora #744: a struct holding an option of an enum declared below its first user released
$ `stdlib/core/string.nu`

: S { ? E e i n }

@ f1 i k → i {
    : S s @ S { @ ?E { F } k }
    ^ . s n
}

: | E { EA String EB i }

@ f2 i k → i {
    : S s @ S { @ ?E { T @ E { EA ( string_from `hello world, long enough to sit on the heap` ) } } k }
    ^ . s n
}

@ main → i {
    ( nurl_println_int + ( f1 1 ) ( f2 2 ) )
    ^ 0
}
