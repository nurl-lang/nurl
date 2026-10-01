// lend_through_enum_param.nu — a value found inside a borrowed enum
// parameter is lent back, also when the caller walks with a cursor.
//
// `get` returns `@ ?Tv { T . ev value }`, a part of its parameter `v`.
// Every auto-dropped enum parameter has a registered owner slot (holding a
// zero value when the caller keeps the enum), and a rule meant for a
// parameter the function OWNS (a `sink ?T` whose payload it returns) read
// that registration as ownership: `get`'s result was taken for the
// caller's own, `walk` dropped each step's value, and the next step read
// freed memory (toml_get_path did exactly this). Separately, an Err path
// spelled `F # E Variant` had made every such function count as returning
// a view, which hid it — and leaked the Ok payload of every function with
// that Err path.
//
// `get_bound` binds the element first (`: ?Ent ek ( vec_get … )`): its
// payload binding is a cursor over `ek`, which owns nothing, so the field
// it returns is still lent — the function says so per call. It was taken
// for moved out of an owned struct, and the caller dropped the table's
// own value (toml_get did this).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Ent { String key Tv value }
: | Tv { TStr String TNum i TTab ( Vec Ent ) }

@ get Tv v s key → ?Tv {
    ?? v {
        TTab entries → {
            : i n ( vec_len [Ent] entries )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [Ent] entries k ) {
                    T ev → { ? ( nurl_str_eq ( string_data . ev key ) key ) { ^ @ ?Tv { T . ev value } } {} }
                    F _ → {}
                }
                = k + k 1
            }
        }
        _ → {}
    }
    ^ @ ?Tv { F @ Tv { TNum 0 } }
}

@ get2 Tv v s key → ?Tv {
    ?? v {
        TTab entries → {
            : i n ( vec_len [Ent] entries )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [Ent] entries k ) {
                    T ev → { ? ( nurl_str_eq ( string_data . ev key ) key ) { ^ @ ?Tv { T . ev value } } {} }
                    F _ → {}
                }
                = k + k 1
            }
        }
        _ → {}
    }
    ^ @ ?Tv { F @ Tv { TNum 0 } }
}

@ get_bound Tv v s key → ?Tv {
    ?? v {
        TTab entries → {
            : i n ( vec_len [Ent] entries )
            : ~ i k 0
            ~ < k n {
                : ?Ent ek ( vec_get [Ent] entries k )
                ?? ek {
                    T ev → { ? ( nurl_str_eq ( string_data . ev key ) key ) { ^ @ ?Tv { T . ev value } } {} }
                    F _ → {}
                }
                = k + k 1
            }
        }
        _ → {}
    }
    ^ @ ?Tv { F # Tv TNum }
}

@ walk_bound Tv v → ?Tv {
    : ~ Tv cur v
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k 2 {
        : ?Tv nx ( get_bound cur `a` )
        ?? nx {
            T v2 → = cur v2
            F _ → = ok F
        }
        = k + k 1
    }
    ? ok { ^ @ ?Tv { T cur } } {}
    ^ @ ?Tv { F # Tv TNum }
}

@ walk Tv v → ?Tv {
    : ~ Tv cur v
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k 2 {
        : ?Tv nx ( get cur `a` )
        ?? nx {
            T v2 → = cur v2
            F _ → = ok F
        }
        = k + k 1
    }
    ^ ? ok @ ?Tv { T cur } @ ?Tv { F # Tv TNum }
}

@ mk → Tv {
    : ( Vec Ent ) es ( vec_new [Ent] )
    : ( Vec Ent ) inner ( vec_new [Ent] )
    ( vec_push [Ent] inner @ Ent { ( string_from `a` ) @ Tv { TStr ( string_from `one` ) } } )
    ( vec_push [Ent] es @ Ent { ( string_from `a` ) @ Tv { TTab inner } } )
    ^ @ Tv { TTab es }
}

@ main → i {
    : Tv d ( mk )
    : ~ i k 0
    ~ < k 3 { : ?Tv r ( get d `a` ) ?? r { T x → { ?? x { TStr t → { ( nurl_println ( string_data t ) ) } _ → {} } } F → {} } = k + k 1 }
    = k 0
    ~ < k 3 { : ?Tv r ( get2 d `a` ) ?? r { T x → { ?? x { TStr t → { ( nurl_println ( string_data t ) ) } _ → {} } } F → {} } = k + k 1 }
    = k 0
    ~ < k 3 { ?? ( walk d ) { T x → { ?? x { TStr t → { ( nurl_println ( string_data t ) ) } _ → { ( nurl_println `not str` ) } } } F → { ( nurl_println `none` ) } } = k + k 1 }
    = k 0
    ~ < k 3 { ?? ( walk_bound d ) { T x → { ?? x { TStr t → { ( nurl_println ( string_data t ) ) } _ → { ( nurl_println `not str` ) } } } F → { ( nurl_println `none` ) } } = k + k 1 }
    ^ 0
}
