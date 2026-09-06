// mcp_auth.nu — the OAuth resource-server shapes in ext/mcp_auth.nu:
// RFC 9728 well-known path + metadata document, the 401 challenge that
// points at it (quoted-string escaping included), the public base URL
// behind a proxy, and bearer-token extraction.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/mcp_auth.nu`

@ label s tag s v → v {
    ( nurl_print tag ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ add_header HttpRequest rq s name s value → v {
    ( vec_push [Header] . rq headers @ Header { ( string_from name ) ( string_from value ) } )
}

@ show_path s p → v {
    : String out ( mcp_auth_metadata_path p )
    ( label `path` ( string_data out ) )
    ( string_free out )
}

@ main → i {
    ( show_path `/mcp` )
    ( show_path `/mcp/` )
    ( show_path `/` )
    ( show_path `` )
    ( show_path `api/v1/mcp` )

    : String u1 ( mcp_auth_metadata_url `https://h.example:8811/mcp/` )
    ( label `url` ( string_data u1 ) )
    ( string_free u1 )
    : String u2 ( mcp_auth_metadata_url `http://h` )
    ( label `url.root` ( string_data u2 ) )
    ( string_free u2 )

    : Json md ( mcp_auth_resource_metadata `https://h/mcp` `https://login/x/v2.0` `api://a/access_as_user  openid` )
    : String js ( json_stringify md )
    ( label `metadata` ( string_data js ) )
    ( string_free js )
    : Json md0 ( mcp_auth_resource_metadata `https://h/mcp` `https://login/x/v2.0` `` )
    : String js0 ( json_stringify md0 )
    ( label `metadata.noscopes` ( string_data js0 ) )
    ( string_free js0 )
    ( json_free md0 )

    : HttpResponse r ( mcp_auth_challenge `https://h/.well-known/oauth-protected-resource/mcp` `invalid_token` `say "hi"` )
    : ( Vec u ) out ( response_serialize r )
    ( vec_push [u] out 0 )
    ( nurl_print # s ( vec_data [u] out ) )
    ( vec_free [u] out )
    ( http_response_free r )

    : HttpResponse r2 ( mcp_auth_metadata_response md )
    ( label `metadata.status` ( nurl_str_int . r2 status ) )
    ( http_response_free r2 )

    : HttpRequest rq ( request_new )
    : String b0 ( mcp_auth_base_url rq `http://fallback` )
    ( label `base.none` ( string_data b0 ) )
    ( string_free b0 )
    ( add_header rq `Host` `x:1` )
    ( add_header rq `authorization` `BEARER  abc.def` )
    : String b ( mcp_auth_base_url rq `http://fallback` )
    ( label `base.host` ( string_data b ) )
    ( string_free b )
    ?? ( mcp_auth_bearer_token rq ) {
        T t → { ( label `bearer` ( string_data t ) ) ( string_free t ) }
        F _ → { ( label `bearer` `none` ) }
    }
    ( add_header rq `X-Forwarded-Host` `pub.example, inner` )
    ( add_header rq `X-Forwarded-Proto` `https` )
    : String b2 ( mcp_auth_base_url rq `http://fallback` )
    ( label `base.forwarded` ( string_data b2 ) )
    ( string_free b2 )
    ( request_free rq )

    : HttpRequest rq2 ( request_new )
    ( add_header rq2 `Authorization` `Basic abc` )
    ?? ( mcp_auth_bearer_token rq2 ) {
        T t → { ( label `bearer.basic` ( string_data t ) ) ( string_free t ) }
        F _ → { ( label `bearer.basic` `none` ) }
    }
    ( request_free rq2 )
    ^ 0
}
