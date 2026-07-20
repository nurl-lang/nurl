// float_format — nurl_str_float must ROUND-TRIP, not truncate to 6 sig figs.
// Regression guard: "%g" (the old impl) rendered 41943040 as "4.1943e+07"
// (= 41943000, wrong) and pi as "3.14159". Integer-valued doubles now print as
// plain integers; everything else uses the shortest form that parses back to
// the same double.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

@ p f x → v { ( nurl_print ( nurl_str_float x ) ) ( nurl_print `\n` ) }

@ main → i {
    ( p 0.5 )
    ( p 3.14 )
    ( p 0.1 )
    ( p 2.5 )
    ( p 100.0 )
    ( p -7.25 )
    ( p 0.0 )
    ( p 41943040.0 )  // integer-valued, was truncated by %g
    ( p 1000000.0 )  // integer-valued, was "1e+06"
    ( p 123456789.0 )  // integer-valued, was "1.23457e+08"
    ( p 3.141592653589793 )  // pi, was "3.14159"
    ( p / 1.0 3.0 )  // 1/3, was "0.333333"
    ^ 0
}
