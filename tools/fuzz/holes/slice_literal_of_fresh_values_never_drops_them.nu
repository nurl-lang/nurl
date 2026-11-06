// slice_literal_of_fresh_values_never_drops_them: agora #485 — a slice literal of values that own something (`[ String | ( string_from … ) ]`, `[ ( Vec i ) | ( vec_new … ) ]`, `[ P | @ P { ( string_from … ) 1 } ]`, `[ Tok | @ Tok { Word ( string_from … ) } … ]`), its slice reassigned (`= sl [ … ]`) or kept in a struct's field: the fresh values were moved into the slice's buffer, and freeing the buffer released none of them.
// Closed: an owned slice owns its elements when they own something (__slice_owns_elems); freeing its buffer drops them first (mem_emit_slice_elems_drop, __slice_drop__<T>), for a binding, a reassignment and a struct's slice field alike.
// main (before this PR): LeakSanitizer, every element of every shape.
// map: §7.1 | A2 | runs-clean | - | agora #485: a slice literal of fresh Strings, Vecs, struct and enum literals never dropped its elements (leak)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }
: H { [String names i n }
: | Tok { Word String Num i }

@ main → i {
    {
        : [String sl [String | ( string_from `a string in an owned slice literal, freed with it` ) ( string_from `the second string of the same slice literal` )]
        ~ x sl { ( nurl_println ( string_data x ) ) }
    }
    {
        : [( Vec i ) vs [( Vec i ) | ( vec_new [i] )]
        ~ v vs { ( nurl_println ( nurl_str_int ( vec_len [i] v ) ) ) }
    }
    {
        : [P ps [P | @ P { ( string_from `a struct literal's String in a slice literal` ) 1 }]
        ~ p ps { ( nurl_println ( string_data . p name ) ) }
    }
    {
        : [Tok ts [Tok | @ Tok { Word ( string_from `an enum payload String in a slice literal` ) } @ Tok { Num 3 }]
        ~ t ts { ?? t { Word w → ( nurl_println ( string_data w ) ) Num n → ( nurl_println ( nurl_str_int n ) ) } }
    }
    {
        : ~ [String rs [String | ( string_from `the first slice literal's string, replaced` )]
        = rs [String | ( string_from `the second slice literal's string, kept` )]
        ~ x rs { ( nurl_println ( string_data x ) ) }
    }
    {
        : H h @ H { [String | ( string_from `a string in a slice literal field of a struct` )] 1 }
        ~ x . h names { ( nurl_println ( string_data x ) ) }
    }
    ^ 0
}
