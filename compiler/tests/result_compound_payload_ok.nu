// result_compound_payload_ok.nu — a result whose payload or error is an
// option (agora #158): `! ?String i`, `! i ?String`, `! String ?i`, and
// one in a struct field. Each is registered through its twin, so the
// String it holds is dropped once, matched or not — LeakSanitizer-clean.

$ `stdlib/core/string.nu`

: S { ! String ? i r i pad }

@ ok_of_option → !?String i { ^ @ !?String i { T @ ?String { T ( string_from `ok of option` ) } } }

@ err_of_option → !i ? String { ^ @ !i ? String { F @ ?String { T ( string_from `error of option` ) } } }

@ ok_beside_option_error → !String ? i { ^ @ !String ? i { T ( string_from `ok beside an option error` ) } }

@ main → i {
    : !?String i a ( ok_of_option )
    ?? a {
        T o → { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} } }
        F e → {}
    }
    : !i ? String b ( err_of_option )
    ?? b {
        T n → {}
        F e → { ?? e { T s → { ( nurl_println ( string_data s ) ) } F → {} } }
    }
    : !String ? i c ( ok_beside_option_error )
    ?? c { T s → { ( nurl_println ( string_data s ) ) } F e → {} }
    : !?String i d ( ok_of_option )
    ?? d { T o → {} F e → {} }
    : S f @ S { ( ok_beside_option_error ) 0 }
    ?? . f r { T s → { ( nurl_println ( string_data s ) ) } F e → {} }
    ^ 0
}
