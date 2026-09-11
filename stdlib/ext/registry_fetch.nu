// Typed registry index boundary, independent of any network backend.
// A successful fetch owns a validated RegIndex; only an explicit NotFound
// means absence. HTTP/transport failures and invalid metadata are errors.
$ `stdlib/ext/registry_index.nu`
$ `stdlib/ext/registry_id.nu`
$ `stdlib/ext/http_cli_types.nu`

: | RegistryFetchErr {
    RegistryNotFound
    RegistryHttp i
    RegistryTransport HttpcErr
    RegistryBadIdentity
    RegistryBadIndex
}

@ registry_fetch_err_text RegistryFetchErr error → String {
    : String text ( string_new )
    ?? error {
        RegistryNotFound → { ( string_push_str text `package not found (HTTP 404)` ) }
        RegistryHttp status → { ( string_push_str text `HTTP ` ) ( string_push_int text status ) }
        RegistryTransport cause → { ( string_push_str text `request failed: ` ) ( string_push_str text ( httpc_err_name cause ) ) }
        RegistryBadIdentity → { ( string_push_str text `invalid package identity` ) }
        RegistryBadIndex → { ( string_push_str text `invalid registry index` ) }
    }
    ^ text
}

// <registry>/index/<name>.json  (single '/' separator ensured)
@ registry_index_url s registry s name → String {
    : String out ( string_with_cap 80 )
    ( string_push_str out registry )
    : i rn ( nurl_str_len registry )
    ? > rn 0 { ? != ( nurl_str_get registry - rn 1 ) 47 { ( string_push_char out 47 ) } {} } {}
    ( string_push_str out `index/` )
    ( string_push_str out name )
    ( string_push_str out `.json` )
    ^ out
}

// Borrows text. The returned index owns its fields independently of the input.
@ registry_index_decode s name String text → !RegIndex RegistryFetchErr {
    ? ! ( registry_name_valid name ) { ^ @ !RegIndex RegistryFetchErr { F RegistryBadIdentity } } {}
    ? | == ( string_len text ) 0 != ( string_len text ) ( nurl_str_len ( string_data text ) ) {
        ^ @ !RegIndex RegistryFetchErr { F RegistryBadIndex }
    } {}
    ?? ( regindex_parse ( string_data text ) ) {
        F _ → { ^ @ !RegIndex RegistryFetchErr { F RegistryBadIndex } }
        T index → {
            ? != 0 ( nurl_str_eq name ( string_data . index name ) ) { ^ @ !RegIndex RegistryFetchErr { T index } } {}
            ( regindex_free index )
            ^ @ !RegIndex RegistryFetchErr { F RegistryBadIndex }
        }
    }
}
