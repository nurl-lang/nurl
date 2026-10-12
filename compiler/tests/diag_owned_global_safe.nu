// A global that owns what it holds is reached only from `unsafe` code: two
// threads may reach it at once, and a read could see a value another is
// replacing and dropping.
$ `stdlib/core/string.nu`

: ~ String g_name 0

@ peek → i { ^ ( string_len g_name ) }

@ poke s n → v { = g_name ( string_from n ) }

unsafe @ main → i { ^ ( peek ) }
