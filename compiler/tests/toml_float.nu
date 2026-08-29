// toml_float.nu — TOML numbers: floats, signs and `_` digit separators.
//
// Locks the number scanner in stdlib/ext/toml.nu:
//
//   * a fraction or an exponent makes the value a TFloat, nothing else
//     does — `3` is an integer, `3.0` and `3e0` are floats;
//   * either sign is accepted on both (`+1_000`, `-0.25`, `1E-9`);
//   * `_` separates digits and must sit BETWEEN them (`1__0` and `1.` are
//     syntax errors, not silently truncated values);
//   * `toml_as_float` widens an integer, `toml_as_int` refuses a float;
//   * `toml_stringify` round-trips — an integral float keeps its `.0`, so
//     re-parsing the output yields a float again and not an integer.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/toml.nu`

@ probe s src → v {
    ( nurl_print src )
    ( nurl_print ` -> ` )
    ?? ( toml_parse src ) {
        T root → {
            ?? ( toml_get root `x` ) {
                T xv → {
                    ?? ( toml_as_int xv ) {
                        T n → {
                            ( nurl_print `int ` )
                            ( nurl_print ( nurl_str_int n ) )
                        }
                        F _ → {
                            ?? ( toml_as_float xv ) {
                                T f → {
                                    ( nurl_print `float ` )
                                    ( nurl_print ( nurl_str_float f ) )
                                }
                                F _ → ( nurl_print `other` )
                            }
                        }
                    }
                    ( nurl_print ` | as_float ` )
                    ?? ( toml_as_float xv ) {
                        T f2 → ( nurl_print ( nurl_str_float f2 ) )
                        F _ → ( nurl_print `none` )
                    }
                }
                F _ → ( nurl_print `<no x>` )
            }
            : String rt ( toml_stringify root )
            ( nurl_print ` | round-trip ` )
            ( nurl_print ( string_data rt ) )
            ( string_free rt )
            ( toml_value_free root )
        }
        F e → {
            ( nurl_print `ERR ` )
            ( nurl_print ( toml_err_name e ) )
            ( nurl_print `\n` )
        }
    }
}

@ main → i {
    ( probe `x = 7\n` )
    ( probe `x = -7\n` )
    ( probe `x = +1_000_000\n` )
    ( probe `x = 1.5\n` )
    ( probe `x = -0.25\n` )
    ( probe `x = 3.0\n` )
    ( probe `x = 6.02e23\n` )
    ( probe `x = 1E-9\n` )
    ( probe `x = 2.5e+3\n` )
    ( probe `x = 1_0.2_5\n` )
    ( probe `x = 1__0\n` )
    ( probe `x = 1.\n` )
    ( probe `x = _1\n` )

    // Floats inside arrays and inline tables.
    ( probe `x = [1.5, 2, -3.5]\n` )
    ( probe `x = { a = 1.25 }\n` )
    ^ 0
}
