// oauth/pkce.nu — PKCE, state and nonce (RFC 7636, OIDC core §3.1.2.1).
//
// Three one-use random values, each closing a different hole in the
// authorization-code flow:
//
//   verifier/challenge  binds the code to THIS client instance. The
//       authorization request carries only SHA-256(verifier); the token
//       request carries the verifier itself. A code stolen in transit
//       (a redirect log, a malicious app claiming the same URI scheme)
//       is worthless without it. Mandatory for public clients, and
//       recommended for every client by OAuth 2.1.
//   state    binds the callback to the request the user started here,
//       which is what defeats login-CSRF.
//   nonce    binds the ID token to that same request — the check lives
//       in claims.nu (`oidc_policy_set_nonce`), the value is minted
//       here.
//
// All three come from the OS CSPRNG (std/random.nu → nurl_rand_fill) and
// are base64url with no padding, so they need no further escaping in a
// URL and are the RFC 7636 "unreserved" alphabet by construction.
//
//   : Pkce pk ( pkce_new )
//   … authorize with ( string_data . pk challenge ) …
//   … exchange with ( string_data . pk verifier ) …
//   ( pkce_free pk )

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_sha256.nu`

: Pkce {
    String verifier  // the secret, sent only to the token endpoint
    String challenge  // base64url(SHA-256(verifier)), sent in the URL
    String method  // always "S256"; "plain" is not offered
}

// `nbytes` of CSPRNG output, base64url-unpadded. 32 bytes → 43 chars,
// the RFC 7636 minimum verifier length and 256 bits of entropy.
@ oauth_random_token i nbytes → String {
    : ( Vec u ) raw ( rand_bytes ? > nbytes 0 nbytes 32 )
    : String out ( b64_url_encode_vec raw )
    ( vec_free [u] raw )
    ^ out
}

@ oauth_state_new → String { ^ ( oauth_random_token 32 ) }

@ oauth_nonce_new → String { ^ ( oauth_random_token 32 ) }

// base64url(SHA-256(ASCII(verifier))) — the S256 transform.
@ pkce_challenge_for s verifier → String {
    : ( Vec u ) msg ( bytes_from_str verifier )
    : ( Vec u ) h ( sha256_pure msg )
    ( vec_free [u] msg )
    : String out ( b64_url_encode_vec h )
    ( vec_free [u] h )
    ^ out
}

@ pkce_new → Pkce {
    : String verifier ( oauth_random_token 32 )
    : String challenge ( pkce_challenge_for ( string_data verifier ) )
    ^ @ Pkce { verifier challenge ( string_from `S256` ) }
}

@ pkce_free Pkce pk → v {
    ( string_free . pk verifier )
    ( string_free . pk challenge )
    ( string_free . pk method )
}
