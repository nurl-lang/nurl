// arima — the CLI: fit or select a model on a column of numbers, forecast.
//
//   arima fit  FILE --order p,d,q [--seasonal P,D,Q,s] [--mean] [--css] [--horizon h]
//   arima auto FILE [--season s] [--horizon h]
//
// FILE holds one number per line (a CSV's first column is taken; a
// header line that is not a number is skipped). The answer is JSON:
// the coefficients and fit statistics (arima_coef) and, with --horizon,
// the forecast means and standard errors.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `src/arima.nu`

@ usage → i {
    ( nurl_eprintln `usage: arima fit FILE --order p,d,q [--seasonal P,D,Q,s] [--mean] [--css] [--horizon h]` )
    ( nurl_eprintln `       arima auto FILE [--season s] [--horizon h]` )
    ^ 2
}

// Read the first numeric column of a text file.
@ read_series s path → ( Vec f ) {
    : ( Vec f ) out ( vec_new [f] )
    ?? ( read_file path ) {
        T txt → {
            : ( Vec String ) lines ( string_split txt `\n` )
            : i n ( vec_len [String] lines )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] lines k ) {
                    T line → {
                        : ( Vec String ) cells ( string_split line `,` )
                        ?? ( vec_get [String] cells 0 ) {
                            T c0 → {
                                : String t ( string_trim c0 )
                                ?? ( string_to_float t ) { T x → { ( vec_push [f] out x ) } F _ → {} }
                                ( string_free t )
                            }
                            F _ → {}
                        }
                        ( vec_free_with [String] cells \ String s → v { ( string_free s ) } )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] lines \ String s → v { ( string_free s ) } )
            ( string_free txt )
        }
        F _ → { ( nurl_eprint `arima: cannot read ` ) ( nurl_eprintln path ) }
    }
    ^ out
}

// "1,1,1" → up to 4 integers (missing ones 0).
@ ints_of String spec ( Vec i ) out → v {
    : ( Vec String ) parts ( string_split spec `,` )
    : i n ( vec_len [String] parts )
    : ~ i k 0
    ~ < k 4 {
        : ~ i v 0
        ? < k n { ?? ( vec_get [String] parts k ) { T p → { : String t ( string_trim p ) ?? ( string_to_int t ) { T x → { = v x } F _ → {} } ( string_free t ) } F _ → {} } } {}
        ( vec_push [i] out v )
        = k + k 1
    }
    ( vec_free_with [String] parts \ String s → v { ( string_free s ) } )
}

@ arg_after ( Vec String ) args s flag → String {
    : i n ( vec_len [String] args )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] args k ) {
            T a → {
                ? & == ( nurl_str_eq ( string_data a ) flag ) 1 < + k 1 n {
                    ?? ( vec_get [String] args + k 1 ) { T v → { ^ ( string_clone v ) } F _ → {} }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ ( string_new )
}

@ has_flag ( Vec String ) args s flag → b {
    : i n ( vec_len [String] args )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] args k ) { T a → { ? == ( nurl_str_eq ( string_data a ) flag ) 1 { ^ T } {} } F _ → {} }
        = k + k 1
    }
    ^ F
}

@ report * ArimaModel m i h → v {
    : Json o ( arima_coef m )
    ? > h 0 {
        : ArimaForecast fc ( arima_forecast m h )
        : Json fo ( json_obj_new )
        ( json_obj_set fo `mean` ( _ar_jarr . fc mean ) )
        ( json_obj_set fo `se` ( _ar_jarr . fc se ) )
        ( json_obj_set o `forecast` fo )
        ( arima_forecast_free fc )
    } {}
    : String s ( json_pretty o )
    ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
    ( string_free s )
    ( json_free o )
}

@ main → i {
    : ( Vec String ) args ( env_args_list )
    : i n ( vec_len [String] args )
    ? < n 3 { ^ ( usage ) } {}
    : String cmd ?? ( vec_get [String] args 1 ) { T a → ( string_clone a ) F _ → ( string_new ) }
    : String file ?? ( vec_get [String] args 2 ) { T a → ( string_clone a ) F _ → ( string_new ) }
    : ( Vec f ) y ( read_series ( string_data file ) )
    ? < ( vec_len [f] y ) 10 { ( nurl_eprintln `arima: need at least ten numbers` ) ^ 2 } {}
    : String hs ( arg_after args `--horizon` )
    : i h ?? ( string_to_int hs ) { T x → x F _ → 0 }
    ( string_free hs )
    ? == ( nurl_str_eq ( string_data cmd ) `fit` ) 1 {
        : String os ( arg_after args `--order` )
        ? == ( string_len os ) 0 { ( string_free os ) ^ ( usage ) } {}
        : ( Vec i ) o ( vec_new [i] )
        ( ints_of os o )
        ( string_free os )
        : String ss ( arg_after args `--seasonal` )
        : ( Vec i ) so ( vec_new [i] )
        ( ints_of ss so )
        ( string_free ss )
        : ArimaSpec sp ( arima_spec_with_mean ( arima_spec_seasonal ( vec_get_i o 0 ) ( vec_get_i o 1 ) ( vec_get_i o 2 ) ( vec_get_i so 0 ) ( vec_get_i so 1 ) ( vec_get_i so 2 ) ( vec_get_i so 3 ) ) ( has_flag args `--mean` ) )
        : *ArimaModel m ( arima_fit_method y sp ? ( has_flag args `--css` ) ARIMA_CSS ARIMA_ML )
        ( report m h )
        ( arima_free m )
        ( vec_free [i] o ) ( vec_free [i] so )
    } {
        ? == ( nurl_str_eq ( string_data cmd ) `auto` ) 1 {
            : String ss ( arg_after args `--season` )
            : i s ?? ( string_to_int ss ) { T x → x F _ → 0 }
            ( string_free ss )
            : *ArimaModel m ( arima_auto y s )
            ( report m h )
            ( arima_free m )
        } { ^ ( usage ) }
    }
    ( vec_free [f] y )
    ( string_free cmd ) ( string_free file )
    ( vec_free_with [String] args \ String s → v { ( string_free s ) } )
    ^ 0
}

@ vec_get_i ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F _ → { ^ 0 } }
}
