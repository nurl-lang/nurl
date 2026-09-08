// json_float_nonfinite.nu — JSON has no NaN and no infinity. `json_float`
// wrote `nan` for a NaN double, and a document holding one was rejected
// by every parser: a dashboard listing that carried one model's NaN
// standard error came back as nothing at all ("Cannot read properties
// of null"). A double that is not a number is `null` in JSON, as
// JavaScript's JSON.stringify writes it.

$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/ext/json.nu`

@ main → i {
    : Json o ( json_obj_new )
    ( json_obj_set o `nan` ( json_float ( float_nan ) ) )
    ( json_obj_set o `inf` ( json_float ( float_inf ) ) )
    ( json_obj_set o `neg` ( json_float - 0.0 ( float_inf ) ) )
    ( json_obj_set o `one` ( json_float 1.0 ) )
    : String s ( json_stringify o )
    ( puts ( string_data s ) )
    : b ok == ( nurl_str_eq ( string_data s ) `{"nan":null,"inf":null,"neg":null,"one":1.0}` ) 1
    ( string_free s )
    ( json_free o )
    ^ ? ok 0 1
}
