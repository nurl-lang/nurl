// The raw and owned-string strict parsers share signed-i64 overflow checks.
$ `stdlib/std/int.nu`

@ valid_decimal s text i expected → b {
    : String owned ( string_from text )
    : b raw_ok ?? ( int_parse text ) { T value → == value expected F _ → F }
    : b owned_ok ?? ( string_to_int owned ) { T value → == value expected F _ → F }
    ( string_free owned )
    ^ & raw_ok owned_ok
}

@ invalid_decimal s text s expected → b {
    : String owned ( string_from text )
    : b raw_ok ?? ( int_parse text ) {
        T _ → F F error → != ( nurl_str_eq ( parse_err_msg error ) expected ) 0
    }
    : b owned_ok ?? ( string_to_int owned ) {
        T _ → F F error → != ( nurl_str_eq ( parse_err_msg error ) expected ) 0
    }
    ( string_free owned )
    ^ & raw_ok owned_ok
}

@ main → i {
    : ~ i failures 0
    ? ! ( valid_decimal `9223372036854775807` INT_MAX ) { = failures + failures 1 } {}
    ? ! ( valid_decimal `+9223372036854775807` INT_MAX ) { = failures + failures 1 } {}
    ? ! ( valid_decimal `-9223372036854775808` INT_MIN ) { = failures + failures 1 } {}
    ? ! ( valid_decimal `-9223372036854775807` -9223372036854775807 ) { = failures + failures 1 } {}
    ? ! ( valid_decimal `000000000000000000000009223372036854775807` INT_MAX ) { = failures + failures 1 } {}
    ? ! ( valid_decimal `-000000000000000000000009223372036854775808` INT_MIN ) { = failures + failures 1 } {}
    ? ! ( valid_decimal `00000000000000000000000000000000000000000` 0 ) { = failures + failures 1 } {}
    ? ! ( valid_decimal `+0` 0 ) { = failures + failures 1 } {}
    ? ! ( valid_decimal `-0` 0 ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `9223372036854775808` `overflow` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `+9223372036854775808` `overflow` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `-9223372036854775809` `overflow` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `18446744073709551615` `overflow` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `99999999999999999999999999999999999999999` `overflow` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `-99999999999999999999999999999999999999999` `overflow` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `99999999999999999999999999999999999999999x` `bad format` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `` `empty input` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `+` `empty input` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `-` `empty input` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `--1` `bad format` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `1 ` `bad format` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal ` 1` `bad format` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `1_000` `bad format` ) { = failures + failures 1 } {}
    ? ! ( invalid_decimal `1.0` `bad format` ) { = failures + failures 1 } {}
    : String nul ( string_from `123` )
    ( string_push_char nul 0 ) ( string_push_str nul `456` )
    : b nul_ok ?? ( string_to_int nul ) { T _ → F F error → ?? error { BadFormat → T _ → F } }
    ? ! nul_ok { = failures + failures 1 } {}
    ( string_free nul )
    : ~ i offset 0
    ~ < offset 256 {
        : String high ( string_new ) : String low ( string_new )
        ( string_push_int high - INT_MAX offset ) ( string_push_int low + INT_MIN offset )
        ? ! ( valid_decimal ( string_data high ) - INT_MAX offset ) { = failures + failures 1 } {}
        ? ! ( valid_decimal ( string_data low ) + INT_MIN offset ) { = failures + failures 1 } {}
        ( string_free high ) ( string_free low )
        = offset + offset 1
    }
    ( nurl_println ? == failures 0 `strict i64 boundaries: ok` `strict i64 boundaries: FAIL` )
    ^ ? == failures 0 0 1
}
