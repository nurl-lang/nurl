// symtab_owned.nu — a SymTab releases its table, every key and every
// value when it goes: nothing here frees by hand (the sanitizer run checks
// that nothing is left behind).

$ `stdlib/core/string.nu`
$ `stdlib/core/symtab.nu`

@ fill i n → SymTab {
    : SymTab t ( symtab_new )
    : ~ i k 0
    ~ < k n {
        ( symtab_def t ( nurl_str_cat `k` ( nurl_str_int k ) ) ( nurl_str_int * k 2 ) )
        = k + k 1
    }
    ^ t
}

@ main → i {
    : ~ i round 0
    ~ < round 3 {
        : SymTab t ( fill 10000 )
        ( symtab_def t `k5` `replaced` )
        ( nurl_println ( symtab_get t `k9999` ) )
        ( nurl_println ( symtab_get t `k5` ) )
        ( nurl_println_int ( nurl_str_len ( symtab_get t `absent` ) ) )
        = round + round 1
    }
    ^ 0
}
