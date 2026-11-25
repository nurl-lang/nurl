// manifest.nu — manifest.json: the claims and their statuses, coverage,
// hashes, tool versions and the trust ledger (docs/dev/CERTIFICATE.md,
// docs/dev/certificate.schema.json).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`

: s CERT_SCHEMA `nurl-cert/1`

@ mj_str Json o s k s v → v { ( json_obj_set o k ( json_str_lit v ) ) }

@ mj_int Json o s k i v → v { ( json_obj_set o k ( json_int v ) ) }

@ mj_set Json o s k Json v → v { ( json_obj_set o k v ) }

@ mj_strs ( Vec String ) v → Json {
    : Json a ( json_arr_new )
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] v k ) {
            T x → ( json_arr_push a ( json_str_lit ( string_data x ) ) )
            F _ → {}
        }
        = k + k 1
    }
    ^ a
}

// One row of the trust ledger.
@ mj_row s id s what s why s where s vouches s claims → Json {
    : Json r ( json_obj_new )
    ( mj_str r `id` id )
    ( mj_str r `what` what )
    ( mj_str r `why` why )
    ( mj_str r `where` where )
    ( mj_str r `vouches` vouches )
    : String cs ( string_from claims )
    : ( Vec String ) parts ? == 0 ( nurl_str_len claims ) ( vec_new [String] ) ( string_split cs ` ` )
    ( mj_set r `claims` ( mj_strs parts ) )
    ^ r
}

// A string field of a parsed manifest, `` when missing.
@ mj_get_str Json m s path → String {
    ^ ?? ( json_get m path ) {
        T v → ( string_from ( json_as_str v ) )
        F → ( string_new )
    }
}
