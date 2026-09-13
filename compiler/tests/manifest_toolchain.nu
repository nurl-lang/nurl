$ `stdlib/ext/manifest.nu`

@ check b ok → v { ? ! ok { ( nurl_println `FAIL` ) ( nurl_exit 1 ) } {} }

@ supports s requirement s actual b expected → v {
    : String source ( string_from `[package]\nname="test"\nversion="1.0.0"\n` )
    ( string_push_str source requirement )
    ?? ( manifest_parse ( string_data source ) `test.toml` ) {
        F _ → ( check F )
        T manifest → {
            ( check == ( manifest_supports_toolchain manifest actual ) expected )
            ( manifest_free manifest )
        }
    }
    ( string_free source )
}

@ invalid s requirement → v {
    : String source ( string_from `[package]\nname="test"\nversion="1.0.0"\n` )
    ( string_push_str source requirement )
    ?? ( manifest_parse ( string_data source ) `test.toml` ) {
        F error → ( check == # i error # i ManifestBadShape )
        T manifest → { ( manifest_free manifest ) ( check F ) }
    }
    ( string_free source )
}

@ main → i {
    ( supports `` `unknown` T )
    ( supports `nurl-version="0.65.0"` `v0.65.0` T )
    ( supports `nurl-version="0.65.0"` `0.66.0` T )
    ( supports `nurl-version="0.65.0"` `v0.64.0` F )
    ( supports `nurl-version="0.65.0"` `v0.65.0-rc.1` F )
    ( supports `nurl-version="0.65.0-rc.1"` `v0.65.0-rc.2` T )
    ( supports `nurl-version="0.65.0"` `v0.65.0+build.1` T )
    ( supports `nurl-version="0.65.0"` `` F )
    ( supports `nurl-version="0.65.0"` `unknown` F )
    ( invalid `nurl-version=65` )
    ( invalid `nurl-version=["0.65.0"]` )
    ( invalid `nurl-version="^0.65.0"` )
    ( invalid `nurl-version="unknown"` )
    ( invalid `nurl-version=""` )
    ( invalid `nurl-version="18446744073709551616.0.0"` )
    ( invalid `nurl-version="0.9223372036854775808.0"` )
    ( invalid `nurl-version="0.0.9223372036854775808"` )
    ( supports `nurl-version="0.65.0-rc.18446744073709551616"` `0.65.0-rc.2` F )
    ( nurl_println `minimum toolchain passed` )
    ^ 0
}
