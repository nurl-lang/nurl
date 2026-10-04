// symtab_redefine.nu — stdlib/core/symtab.nu: a re-definition replaces
// the value in place, the bucket array grows with the table, and
// nurl_sym_free releases everything (the sanitizer run checks that
// nothing is left behind).
//
// The table used to push a new entry for every re-definition — entries
// nothing could read or free again — and to keep 4096 buckets however
// large it grew, so a long-running user that re-defines the same keys
// (the language server) grew without bound.

$ `stdlib/core/string.nu`
$ `stdlib/core/symtab.nu`

@ main → i {
    : i h ( nurl_sym_new )
    // Many distinct keys: past the first rehash (8192 entries).
    : ~ i k 0
    ~ < k 20000 {
        : s key ( nurl_str_cat `k` ( nurl_str_int k ) )
        : s val ( nurl_str_int * k 3 )
        ( nurl_sym_def h key val )
        = k + k 1
    }
    // Re-define one key many times: the value is replaced.
    = k 0
    ~ < k 1000 {
        ( nurl_sym_def h `k7` ( nurl_str_int k ) )
        = k + k 1
    }
    : ~ i sum 0
    = k 0
    ~ < k 20000 {
        : s key ( nurl_str_cat `k` ( nurl_str_int k ) )
        = sum + sum ( nurl_str_to_int ( nurl_sym_get h key ) )
        = k + k 1
    }
    ( nurl_println_int sum )
    ( nurl_println ( nurl_sym_get h `k7` ) )
    // An absent key reads as the empty string.
    ( nurl_println_int ( nurl_str_len ( nurl_sym_get h `absent` ) ) )
    // A key that is a prefix of another is its own entry.
    ( nurl_sym_def h `k` `short` )
    ( nurl_println ( nurl_sym_get h `k` ) )
    ( nurl_println ( nurl_sym_get h `k1` ) )
    ( nurl_sym_free h )
    ^ 0
}
