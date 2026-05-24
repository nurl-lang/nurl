$ `stdlib/ext/http.nu`
$ `stdlib/ext/json.nu`

// Helper to print a JSON‑parsing error
@ show_parse_err s label JsonError e → v {
    ( nurl_print label )
    ( nurl_print ( parse_err_msg # ParseErr . e kind ) )
    ( nurl_print `\n` )
}

// Helper to print an HTTP error
@ show_http_err s label HttpErr e → v {
    ( nurl_print label )
    ( nurl_print ( http_err_name # HttpErr e ) )
    ( nurl_print `\n` )
}

// Entry point – called as: json_request_parser "<url>"
@ main → i {
    // Ensure we have a URL argument
    : i argc ( nurl_argv_count )
    ? <= argc 1 {
        ( nurl_print `Usage: json_request_parser <url>\n` )
        ^ 1
    } {}

    // Get the URL string from the command line
    : s url ( nurl_argv_get 1 )

    // Perform a GET request (Result<Response, HttpErr>)
    : !Response HttpErr r ( http_get url )
    ?? r {
        T resp → {
            // Extract the response body as a string
            : s body ( http_body_str resp )

            // Parse the body as JSON (Result<Json, ParseErr>)
            : !Json JsonError j ( json_parse body )
            ?? j {
                T obj → {
                    // Pretty‑print the JSON object
                    : String pretty ( json_pretty obj )
                    ( nurl_print ( string_data pretty ) )
                    ( nurl_print `\n` )
                    ( string_free pretty )
                    ( json_free obj )
                }
                F e → ( show_parse_err `JSON parse error: ` # JsonError e )
            }

            ( response_free resp )
        }
        F e → ( show_http_err `HTTP error: ` # HttpErr e )
    }

    ^ 0
}
