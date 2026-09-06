// stdlib/ext/mcp_auth.nu — OAUTH RESOURCE-SERVER PLUMBING FOR AN MCP SERVER.
//
// The MCP Authorization spec makes an HTTP MCP server an OAuth 2.1
// RESOURCE SERVER: it does not issue tokens, it verifies them and tells
// a client that has none where to get one. Two pieces of that are pure
// protocol shape and identical in every server, so they live here:
//
//   1. RFC 9728 Protected Resource Metadata — a JSON document at
//      `/.well-known/oauth-protected-resource[/<path>]` naming the
//      resource, its authorization server(s) and the scopes it wants.
//   2. The 401 challenge that points at it:
//      `WWW-Authenticate: Bearer resource_metadata="<url>"`.
//
// A client (Claude Code, the MCP inspector, any spec-following agent)
// hits the endpoint without a token, reads the challenge, fetches the
// metadata, discovers the authorization server from it, runs the
// OAuth flow there with the resource URL as the RFC 8707 `resource`
// indicator, and retries with a bearer token. Nothing in that dance is
// server-specific except the three values the server fills in.
//
// What is NOT here, on purpose: token VERIFICATION. That is the
// server's own business (a JWT against an issuer's JWKS — see
// packages/oauth — an API key against a table, a shared secret via
// `mcp_server_with_bearer_auth`), and which one it is decides what
// "authenticated" means for its tools. The pattern for an HTTP host:
//
//   : String base ( mcp_auth_base_url req `http://localhost:8080` )
//   : String res  ( string_from ( string_data base ) )
//   ( string_push_str res `/mcp` )
//   // no / bad credential →
//   : String md ( mcp_auth_metadata_url ( string_data res ) )
//   ^ ( mcp_auth_challenge ( string_data md ) `invalid_token` `token missing or expired` )
//   // GET on ( mcp_auth_metadata_path `/mcp` ) →
//   ^ ( mcp_auth_metadata_response ( mcp_auth_resource_metadata
//         ( string_data res ) issuer `api://my-app/access_as_user` ) )
//
// …and once the credential checks out, thread the principal into the
// dispatch as the caller context (`mcp_server_dispatch_as`) so gated
// tools see who is calling.
//
// Sibling modules: mcp_server.nu (the server), mcp_http.nu (the
// transport), packages/oauth (OIDC discovery + JWT verification).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`

// The well-known path for the resource metadata of a resource served
// at `resource_path` (RFC 9728 §3.1): the path component is appended to
// `/.well-known/oauth-protected-resource`, and a resource at the root
// (`` or `/`) uses the bare well-known path. Returns an owned String.
@ mcp_auth_metadata_path s resource_path → String {
    : String out ( string_from `/.well-known/oauth-protected-resource` )
    : i n ( nurl_str_len resource_path )
    ? | == n 0 & == n 1 == ( nurl_str_get resource_path 0 ) 47 { ^ out } {}
    ? != 47 ( nurl_str_get resource_path 0 ) { ( string_push_str out `/` ) } {}
    // Drop one trailing slash so `/mcp/` and `/mcp` name one document.
    ? == 47 ( nurl_str_get resource_path - n 1 ) {
        : s head ( nurl_str_slice resource_path 0 - n 1 )
        ( string_push_str out head )
    } {
        ( string_push_str out resource_path )
    }
    ^ out
}

// Where `scheme://host[:port]` ends and the path begins in an absolute
// URL, or the string's length when there is no path. -1 when the input
// has no `://`.
@ __mcp_auth_origin_end s url → i {
    : i sep ( nurl_str_find url `://` )
    ? < sep 0 { ^ -1 } {}
    : i n ( nurl_str_len url )
    : ~ i k + sep 3
    ~ < k n {
        ? == 47 ( nurl_str_get url k ) { ^ k } {}
        = k + k 1
    }
    ^ n
}

// The absolute URL of the metadata document for `resource` — the value
// a 401 challenge carries in `resource_metadata`. Splits the resource
// URL at its origin and inserts the well-known path there. Owned.
@ mcp_auth_metadata_url s resource → String {
    : i oe ( __mcp_auth_origin_end resource )
    ? < oe 0 { ^ ( mcp_auth_metadata_path resource ) } {}
    : i n ( nurl_str_len resource )
    : s origin ( nurl_str_slice resource 0 oe )
    : s path ( nurl_str_slice resource oe - n oe )
    : String out ( string_from origin )
    : String wk ( mcp_auth_metadata_path path )
    ( string_push_str out ( string_data wk ) )
    ( string_free wk )
    ^ out
}

// RFC 9728 Protected Resource Metadata as Json (caller owns):
//   resource                  — the canonical URL clients present as
//                               the RFC 8707 resource indicator
//   authorization_servers     — [issuer]; push more for multi-issuer
//   bearer_methods_supported  — ["header"]: the token travels in the
//                               Authorization header, never in the query
//   scopes_supported          — `scopes`, split on spaces; omitted when ``
@ mcp_auth_resource_metadata s resource s authorization_server s scopes → Json {
    : Json md ( json_obj_new )
    ( json_obj_set md `resource` ( json_str_lit resource ) )
    : Json as ( json_arr_new )
    ( json_arr_push as ( json_str_lit authorization_server ) )
    ( json_obj_set md `authorization_servers` as )
    : Json bm ( json_arr_new )
    ( json_arr_push bm ( json_str_lit `header` ) )
    ( json_obj_set md `bearer_methods_supported` bm )
    : i n ( nurl_str_len scopes )
    ? > n 0 {
        : Json sc ( json_arr_new )
        : ~ i start 0
        : ~ i k 0
        ~ <= k n {
            ? | == k n == 32 ( nurl_str_get scopes k ) {
                ? > k start {
                    : s one ( nurl_str_slice scopes start - k start )
                    ( json_arr_push sc ( json_str_lit one ) )
                } {}
                = start + k 1
            } {}
            = k + k 1
        }
        ( json_obj_set md `scopes_supported` sc )
    } {}
    ^ md
}

// 200 with the metadata document. CORS-open, because the MCP inspector
// and browser-hosted agents fetch it cross-origin; a metadata document
// is public by definition. CONSUMES `md`.
@ mcp_auth_metadata_response Json md → HttpResponse {
    : HttpResponse r ( response_json 200 md )
    ( json_free md )
    ( response_set_header r `Access-Control-Allow-Origin` `*` )
    ( response_set_header r `Cache-Control` `public, max-age=3600` )
    ^ r
}

// Push `text` with `"` and `\` escaped, so a free-text error description
// cannot break out of the quoted-string parameter it lands in.
@ __mcp_auth_push_quoted String out s text → v {
    : i n ( nurl_str_len text )
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at text n k )
        ? | == c 34 == c 92 { ( string_push_char out 92 ) } {}
        ( string_push_char out c )
        = k + k 1
    }
}

// The 401 a client without a usable token receives. The challenge is
// what makes discovery automatic: `resource_metadata` names the RFC
// 9728 document, and the client takes it from there. `error` is one of
// the RFC 6750 codes (`invalid_token` for a missing/expired/wrong-
// audience token, `insufficient_scope` when the token is fine but lacks
// a scope); `` omits it. The JSON body repeats both for a caller that
// reads bodies rather than headers.
@ mcp_auth_challenge s metadata_url s error s description → HttpResponse {
    : String hv ( string_from `Bearer resource_metadata="` )
    ( __mcp_auth_push_quoted hv metadata_url )
    ( string_push_str hv `"` )
    : Json body ( json_obj_new )
    ? > ( nurl_str_len error ) 0 {
        ( string_push_str hv `, error="` )
        ( __mcp_auth_push_quoted hv error )
        ( string_push_str hv `"` )
        ( json_obj_set body `error` ( json_str_lit error ) )
    } {}
    ? > ( nurl_str_len description ) 0 {
        ( string_push_str hv `, error_description="` )
        ( __mcp_auth_push_quoted hv description )
        ( string_push_str hv `"` )
        ( json_obj_set body `error_description` ( json_str_lit description ) )
    } {}
    ( json_obj_set body `resource_metadata` ( json_str_lit metadata_url ) )
    : HttpResponse r ( response_json 401 body )
    ( json_free body )
    ( response_set_header r `WWW-Authenticate` ( string_data hv ) )
    ( response_set_header r `Access-Control-Allow-Origin` `*` )
    ( response_set_header r `Access-Control-Expose-Headers` `WWW-Authenticate` )
    ( string_free hv )
    ^ r
}

// The public origin (`scheme://host[:port]`, no trailing slash) this
// request was addressed to, as the client sees it — which behind a
// reverse proxy is NOT what the socket sees. `X-Forwarded-Proto` and
// `X-Forwarded-Host` (first value of each, as a proxy chain appends)
// win; then `Host` with scheme `http`; then `fallback` verbatim when a
// request carries neither, as an HTTP/1.0 client's may. Owned.
//
// The resource URL in the metadata and the `resource` indicator the
// client sends to the authorization server must be the same string,
// so derive both from this and nothing else — or let a deployment pin
// it in configuration and pass that as the answer instead.
@ mcp_auth_base_url HttpRequest req s fallback → String {
    : ~ String scheme ( string_from `http` )
    ?? ( header_get . req headers `X-Forwarded-Proto` ) {
        T v → {
            : String first ( __mcp_auth_first_value ( string_data v ) )
            ? > ( string_len first ) 0 {
                ( string_free scheme )
                = scheme first
            } { ( string_free first ) }
            ( string_free v )
        }
        F _ → {}
    }
    : ~ String host ( string_from `` )
    ?? ( header_get . req headers `X-Forwarded-Host` ) {
        T v → {
            ( string_free host )
            = host ( __mcp_auth_first_value ( string_data v ) )
            ( string_free v )
        }
        F _ → {}
    }
    ? == 0 ( string_len host ) {
        ?? ( header_get . req headers `Host` ) {
            T v → {
                ( string_free host )
                = host ( __mcp_auth_first_value ( string_data v ) )
                ( string_free v )
            }
            F _ → {}
        }
    } {}
    ? == 0 ( string_len host ) {
        ( string_free scheme )
        ( string_free host )
        ^ ( string_from fallback )
    } {}
    : String out ( string_from ( string_data scheme ) )
    ( string_push_str out `://` )
    ( string_push_str out ( string_data host ) )
    ( string_free scheme )
    ( string_free host )
    ^ out
}

// First comma-separated element of a header value, trimmed of spaces.
@ __mcp_auth_first_value s v → String {
    : i n ( nurl_str_len v )
    : ~ i end n
    : i comma ( nurl_str_find v `,` )
    ? >= comma 0 { = end comma } {}
    : ~ i start 0
    ~ & < start end == 32 ( nurl_str_at v n start ) { = start + start 1 }
    ~ & > end start == 32 ( nurl_str_at v n - end 1 ) { = end - end 1 }
    : s part ( nurl_str_slice v start - end start )
    ^ ( string_from part )
}

// The token of an `Authorization: Bearer <token>` header, or F when the
// header is absent or uses another scheme. Scheme match is case-
// insensitive per RFC 9110; the token is returned as sent. Owned.
@ mcp_auth_bearer_token HttpRequest req → ?String {
    ?? ( header_get . req headers `Authorization` ) {
        T v → {
            : s raw ( string_data v )
            : i n ( nurl_str_len raw )
            : ~ b is_bearer F
            ? >= n 7 {
                : s scheme ( nurl_str_slice raw 0 6 )
                : String low ( string_from `` )
                : ~ i k 0
                ~ < k 6 {
                    : ~ i c ( nurl_str_at scheme 6 k )
                    ? & >= c 65 <= c 90 { = c + c 32 } {}
                    ( string_push_char low c )
                    = k + k 1
                }
                = is_bearer & != 0 ( nurl_str_eq ( string_data low ) `bearer` )
                == 32 ( nurl_str_at raw n 6 )
                ( string_free low )
            } {}
            ? ! is_bearer {
                ( string_free v )
                ^ @ ?String { F }
            } {}
            : ~ i start 7
            ~ & < start n == 32 ( nurl_str_at raw n start ) { = start + start 1 }
            : s tok ( nurl_str_slice raw start - n start )
            : String out ( string_from tok )
            ( string_free v )
            ^ @ ?String { T out }
        }
        F _ → { ^ @ ?String { F } }
    }
}
