$ `stdlib/ext/json.nu`

@ show s label Json j → v {
    : String out ( json_stringify j )
    ( printf `%s: %s\n` label ( string_data out ) )
    ( string_free out )
    ( json_free j )
}

@ main → i {
    ( show `integral` ( json_float 85.0 ) )
    ( show `neg integral` ( json_float -3.0 ) )
    ( show `zero` ( json_float 0.0 ) )
    ( show `fractional` ( json_float 2.5 ) )
    ( show `exponent` ( json_float 1.0e300 ) )
    ( show `tiny` ( json_float 0.001 ) )
    ( show `neg fractional` ( json_float -0.25 ) )
    ^ 0
}
