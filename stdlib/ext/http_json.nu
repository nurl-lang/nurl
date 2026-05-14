// stdlib/ext/http_json.nu — JSON convenience layered on stdlib/ext/http.nu.
//
// Pulls in the JSON serializer so `http_post_json` can take a typed
// `Json` value instead of a pre-stringified body. Kept in a separate
// file from http.nu so HTTP-only callers don't pay the json.nu import
// cost (regex+NFA-style avoidance: opt-in modules).
//
// API:
//
//   ( http_post_json s url Json j )
//                                → ! Response HttpErr
//   ( http_put_json  s url Json j )
//                                → ! Response HttpErr
//
// Both serialize `j` with `json_stringify` (compact form), set
// `Content-Type: application/json`, and forward to the underlying
// http_post / http_put. The caller still owns `j` afterwards — these
// wrappers do NOT consume it.

$ `stdlib/ext/http.nu`
$ `stdlib/ext/json.nu`

@ http_post_json s url Json j → !Response HttpErr {
    : String body ( json_stringify j )
    : !Response HttpErr res
    ( http_post url ( string_data body ) `application/json` )
    ( string_free body )
    ^ res
}

@ http_put_json s url Json j → !Response HttpErr {
    : String body ( json_stringify j )
    : !Response HttpErr res
    ( http_put url ( string_data body ) `application/json` )
    ( string_free body )
    ^ res
}
