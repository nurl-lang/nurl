$ `stdlib/ext/semver.nu`

@ check b ok → v { ? ! ok { ( nurl_println `FAIL` ) ( nurl_exit 1 ) } {} }

@ bad_version s text → v {
    ?? ( semver_parse text ) {
        F e → ( check == # i e # i SvBadNumber )
        T version → { ( semver_free version ) ( check F ) }
    }
}

@ bad_range s text → v {
    ?? ( semver_req_parse text ) {
        F e → ( check == # i e # i SvBadReq )
        T range → { ( semver_req_free range ) ( check F ) }
    }
}

@ main → i {
    ( bad_version `9223372036854775808.0.0` )
    ( bad_version `0.9223372036854775808.0` )
    ( bad_version `0.0.9223372036854775808` )
    ( bad_version `18446744073709551616.0.0` )
    ( bad_range `>=18446744073709551616.0.0` )
    ( bad_range `^9223372036854775807.0.0` )
    ( bad_range `^0.9223372036854775807.0` )
    ( bad_range `^0.0.9223372036854775807` )
    ( bad_range `~1.9223372036854775807.0` )
    ( bad_range `9223372036854775807.x` )
    ( bad_range `>9223372036854775807` )
    ( bad_range `<=1.9223372036854775807` )
    ( bad_range `1 - 9223372036854775807` )
    : Semver last ?? ( semver_parse `9223372036854775807.9223372036854775807.9223372036854775807` ) {
        T value → value F _ → { ( check F ) @ Semver { 0 0 0 ( string_new ) ( string_new ) } }
    }
    ( check == . last major 9223372036854775807 )
    : VersionReq exact ?? ( semver_req_parse `>=9223372036854775807.9223372036854775807.9223372036854775807` ) {
        T value → value F _ → { ( check F ) @ VersionReq { ( vec_new [SvInterval] ) } }
    }
    ( check ( semver_req_matches exact last ) )
    ( semver_req_free exact ) ( semver_free last )
    : Semver huge ?? ( semver_parse `1.0.0-18446744073709551616` ) {
        T value → value F _ → { ( check F ) @ Semver { 0 0 0 ( string_new ) ( string_new ) } }
    }
    : Semver small ?? ( semver_parse `1.0.0-2` ) {
        T value → value F _ → { ( check F ) @ Semver { 0 0 0 ( string_new ) ( string_new ) } }
    }
    ( check > ( semver_compare huge small ) 0 )
    ( check < ( semver_compare small huge ) 0 )
    ( semver_free huge ) ( semver_free small )
    ( nurl_println `semver bounds passed` )
    ^ 0
}
