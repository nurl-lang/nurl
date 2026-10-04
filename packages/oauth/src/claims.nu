// oauth/claims.nu — read the claims, and decide whether to believe them.
//
// A verified signature only says the token was issued by the holder of a
// key. Everything that makes it an ANSWER to "who is this, and is this
// token for me, right now" lives in the claims, and the checks are
// exactly the ones an attacker attacks when they are skipped:
//
//   iss    the token came from the issuer we trust, not another one
//   aud    it was minted for THIS client, not for a different relying
//          party that would happily hand it to us (the confused deputy)
//   azp    with several audiences, the authorized party is still us
//   exp    it has not expired · nbf it has begun · iat it is not future
//   nonce  it answers the authorization request WE started (replay)
//   sub    there is a subject at all — the user this token identifies
//
// `OidcPolicy` is the statement (a handle) of what this relying party
// will accept; `claims_check` applies it and names the first failure.
//
//   : OidcPolicy pol ( oidc_policy_new issuer client_id )
//   ( oidc_policy_set_leeway pol 60 )
//   ?? ( claims_check claims pol ( now_seconds ) ) {
//       T e → ( nurl_eprintln ( claim_err_desc e ) )
//       F _ → { /* believe it */ }
//   }
//
// `OidcIdentity` is the answer itself: the subject and the profile
// claims lifted out for direct use, with the full claim set still
// attached for anything else the provider sent (groups, roles, tenant).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/core/rcbox.nu`

// ── What can be wrong with a claim set ─────────────────────────────

: | ClaimErr {
    ClNotObject  // the payload was not a JSON object
    ClExpired  // now ≥ exp (+ leeway)
    ClNotYetValid  // now < nbf (− leeway)
    ClIssuedInFuture  // iat is ahead of our clock by more than the leeway
    ClNoExpiry  // policy demands exp; the token has none
    ClIssuer  // iss ≠ the issuer we trust
    ClAudience  // our client id is not in aud
    ClAuthorizedParty  // azp names a different client
    ClNonce  // nonce ≠ the one we sent
    ClNoSubject  // no sub — the token identifies nobody
    ClMaxAge  // the authentication is older than max_age
}

@ claim_err_desc ClaimErr e → s {
    ^ ?? e {
        ClNotObject → `claims are not a JSON object`
        ClExpired → `token expired`
        ClNotYetValid → `token not yet valid`
        ClIssuedInFuture → `token issued in the future`
        ClNoExpiry → `token has no exp claim`
        ClIssuer → `wrong issuer`
        ClAudience → `wrong audience`
        ClAuthorizedParty → `wrong authorized party (azp)`
        ClNonce → `nonce mismatch`
        ClNoSubject → `token has no sub claim`
        ClMaxAge → `authentication too old for max_age`
    }
}

// ── Accessors ──────────────────────────────────────────────────────

// A string claim as an owned String; empty when absent or not a string.
@ claims_str Json c s key → String {
    : ~ s raw ``
    ?? ( json_obj_get c key ) {
        T v → { ? ( json_is_str v ) { = raw ( json_str_data v ) } {} }
        F _ → {}
    }
    ^ ( string_from raw )
}

// A numeric claim (NumericDate and friends); `missing` when absent.
@ claims_int_or Json c s key i missing → i {
    : ~ i out missing
    ?? ( json_obj_get c key ) {
        T v → {
            ? ( json_is_num v ) {
                ?? ( json_num_as_i v ) { T n → { = out n } F _ → {} }
            } {}
        }
        F _ → {}
    }
    ^ out
}

@ claims_int Json c s key → i { ^ ( claims_int_or c key -1 ) }

@ claims_bool Json c s key → b {
    : ~ b out F
    ?? ( json_obj_get c key ) {
        T v → { ? ( json_is_bool v ) { = out ( json_bool_val v ) } {} }
        F _ → {}
    }
    ^ out
}

@ claims_has Json c s key → b { ^ ( json_obj_has c key ) }

// A claim that is either a string or an array of strings — `aud`, and
// the shape most providers use for groups and roles. Always an owned
// vector of owned Strings.
@ claims_string_list Json c s key → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( json_obj_get c key ) {
        T v → {
            ? ( json_is_str v ) {
                ( vec_push [String] out ( string_from ( json_str_data v ) ) )
            } {
                ? ( json_is_arr v ) {
                    : i n ( json_arr_len v )
                    : ~ i k 0
                    ~ < k n {
                        ?? ( json_arr_get v k ) {
                            T item → {
                                ? ( json_is_str item ) {
                                    ( vec_push [String] out ( string_from ( json_str_data item ) ) )
                                } {}
                            }
                            F _ → {}
                        }
                        = k + k 1
                    }
                } {}
            }
        }
        F _ → {}
    }
    ^ out
}

@ __cl_list_has ( Vec String ) list s want → b {
    : i n ( vec_len [String] list )
    : *String data ( vec_data [String] list )
    : ~ i k 0
    ~ < k n {
        : String item . data k
        ? == 1 ( nurl_str_eq ( string_data item ) want ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ claims_has_audience Json c s aud → b {
    : ( Vec String ) list ( claims_string_list c `aud` )
    : b found ( __cl_list_has list aud )
    ^ found
}

// The `scope` claim (RFC 8693 §4.2: one space-delimited string).
@ claims_scopes Json c → ( Vec String ) {
    : String sc ( claims_str c `scope` )
    : ( Vec String ) out ( string_split sc ` ` )
    ^ out
}

@ claims_has_scope Json c s scope → b {
    : ( Vec String ) list ( claims_scopes c )
    : b found ( __cl_list_has list scope )
    ^ found
}

// Replace a String field's text in place. A handle's state is reached
// through a pointer, and a store through a pointer does not release the
// String it overwrites; clearing and refilling the same buffer leaves
// nothing behind (and reuses the allocation). Setting a field to its own
// text is a no-op, not a clear.
@ _oauth_set_str String dst s v → v {
    ? == # i v # i ( string_data dst ) { ^ } {}
    ( string_clear dst )
    ( string_push_str dst v )
}

// ── Policy ─────────────────────────────────────────────────────────

: OidcPolicyImpl {
    String issuer  // expected `iss`; empty = do not check (never for OIDC)
    String audience  // our client id, expected in `aud`; empty = skip
    String nonce  // the nonce we sent with the authorization request
    String algs  // space-separated `alg` allowlist; empty = every supported
    i leeway  // clock-skew tolerance in seconds
    i max_age  // reject an authentication older than this; 0 = no limit
    b require_sub
    b require_exp
    b allow_symmetric  // permit HS* (only with a configured shared secret)
}

// An OidcPolicy is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: OidcPolicy { s ctl }

@ OidcPolicy_share OidcPolicy h → OidcPolicy { ^ @ OidcPolicy { # s ( rcbox_share # i . h ctl ) } }

@ OidcPolicy_drop sink OidcPolicy h → v {
    ( mem_forget h )
    ( rcbox_release [OidcPolicyImpl] # i . h ctl )
}

@ _OidcPolicy_ptr OidcPolicy h → *OidcPolicyImpl { ^ ( rcbox_ptr [OidcPolicyImpl] # i . h ctl ) }

@ oidc_policy_new s issuer s audience → OidcPolicy {
    : i p__box ( rcbox_zero [OidcPolicyImpl] )
    : *OidcPolicyImpl p ( rcbox_ptr [OidcPolicyImpl] p__box )
    = . p issuer ( string_from issuer )
    = . p audience ( string_from audience )
    = . p nonce ( string_new )
    = . p algs ( string_new )
    = . p leeway 60
    = . p max_age 0
    = . p require_sub T
    = . p require_exp T
    = . p allow_symmetric F
    ^ @ OidcPolicy { # s p__box }
}

// Let go of `p` now rather than at the end of its owner's scope.
@ oidc_policy_free sink OidcPolicy p → v {}

@ oidc_policy_set_issuer OidcPolicy p__h s issuer → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    ( _oauth_set_str . p issuer issuer )
}

@ oidc_policy_set_audience OidcPolicy p__h s audience → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    ( _oauth_set_str . p audience audience )
}

@ oidc_policy_set_nonce OidcPolicy p__h s nonce → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    ( _oauth_set_str . p nonce nonce )
}

@ oidc_policy_set_algs OidcPolicy p__h s algs → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    ( _oauth_set_str . p algs algs )
}

@ oidc_policy_set_leeway OidcPolicy p__h i secs → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    = . p leeway secs
}

@ oidc_policy_set_max_age OidcPolicy p__h i secs → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    = . p max_age secs
}

@ oidc_policy_require_sub OidcPolicy p__h b on → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    = . p require_sub on
}

@ oidc_policy_require_exp OidcPolicy p__h b on → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    = . p require_exp on
}

@ oidc_policy_allow_symmetric OidcPolicy p__h b on → v {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    = . p allow_symmetric on
}

// Is `alg` inside the policy's allowlist? An empty allowlist means "any
// algorithm the verifier supports", which still excludes HS* unless the
// caller deliberately allowed symmetric keys.
@ oidc_policy_alg_allowed OidcPolicy p__h s alg → b {
    : *OidcPolicyImpl p ( _OidcPolicy_ptr p__h )
    ? == 0 ( string_len . p algs ) { ^ T } {}
    : ( Vec String ) list ( string_split . p algs ` ` )
    : b found ( __cl_list_has list alg )
    ^ found
}

// ── The check ──────────────────────────────────────────────────────

// None = every check passed. `now` is epoch seconds — passed in, not
// read here, so a test (or a caller with its own time source) is
// deterministic. The claims of an ID token: see claims_check_access for
// an access token's.
@ claims_check Json c OidcPolicy pol__h i now → ?ClaimErr {
    ^ ( _claims_check c pol__h now F )
}

// The claims of an ACCESS token (RFC 9068) presented to a resource
// server. The one difference is `azp`: in an ID token it names the
// client the token was issued to, and must be us (OIDC Core §3.1.3.7);
// in an access token it names the client that ASKED for it — the MCP
// client, the CLI, the single-page app — which is any client the
// provider let request our scope, never the resource server itself.
// Requiring azp == our audience there refuses every token but the ones
// a server's own app registration fetched.
@ claims_check_access Json c OidcPolicy pol__h i now → ?ClaimErr {
    ^ ( _claims_check c pol__h now T )
}

@ _claims_check Json c OidcPolicy pol__h i now b access → ?ClaimErr {
    : *OidcPolicyImpl pol ( _OidcPolicy_ptr pol__h )
    ? ( json_is_obj c ) {} { ^ @ ?ClaimErr { T ClNotObject } }
    : i leeway . pol leeway

    // exp / nbf / iat
    : i exp ( claims_int c `exp` )
    ? >= exp 0 {
        ? >= now + exp leeway { ^ @ ?ClaimErr { T ClExpired } } {}
    } {
        ? . pol require_exp { ^ @ ?ClaimErr { T ClNoExpiry } } {}
    }
    : i nbf ( claims_int c `nbf` )
    ? >= nbf 0 {
        ? < + now leeway nbf { ^ @ ?ClaimErr { T ClNotYetValid } } {}
    } {}
    : i iat ( claims_int c `iat` )
    ? >= iat 0 {
        ? > iat + now leeway { ^ @ ?ClaimErr { T ClIssuedInFuture } } {}
    } {}

    // iss
    ? > ( string_len . pol issuer ) 0 {
        : String iss ( claims_str c `iss` )
        : b same ( string_eq iss . pol issuer )
        ? same {} { ^ @ ?ClaimErr { T ClIssuer } }
    } {}

    // aud + azp
    ? > ( string_len . pol audience ) 0 {
        : s want ( string_data . pol audience )
        ? ( claims_has_audience c want ) {} { ^ @ ?ClaimErr { T ClAudience } }
        // OIDC core §3.1.3.7: when azp is present it must be our client
        // (an ID token; an access token's azp is the requesting client).
        : String azp ( claims_str c `azp` )
        : b azp_bad & & ! access > ( string_len azp ) 0 == 0 ( nurl_str_eq ( string_data azp ) want )
        ? azp_bad { ^ @ ?ClaimErr { T ClAuthorizedParty } } {}
    } {}

    // nonce
    ? > ( string_len . pol nonce ) 0 {
        : String nonce ( claims_str c `nonce` )
        : b same ( string_eq nonce . pol nonce )
        ? same {} { ^ @ ?ClaimErr { T ClNonce } }
    } {}

    // sub
    ? . pol require_sub {
        : String sub ( claims_str c `sub` )
        : b empty == 0 ( string_len sub )
        ? empty { ^ @ ?ClaimErr { T ClNoSubject } } {}
    } {}

    // max_age — measured from auth_time when the provider sent one
    // (that is the actual authentication event), else from iat.
    ? > . pol max_age 0 {
        : i auth_time ( claims_int_or c `auth_time` iat )
        ? < auth_time 0 { ^ @ ?ClaimErr { T ClMaxAge } } {}
        ? > - now auth_time + . pol max_age leeway { ^ @ ?ClaimErr { T ClMaxAge } } {}
    } {}

    ^ @ ?ClaimErr { F }
}

@ claims_check_now Json c OidcPolicy pol__h → ?ClaimErr {
    ^ ( claims_check c pol__h ( now_seconds ) )
}

// ── The identity ───────────────────────────────────────────────────

: OidcIdentity {
    String subject  // `sub` — stable, unique WITHIN the issuer
    String issuer  // `iss` — the pair (issuer, subject) is the user
    String email
    String name
    String username  // `preferred_username`
    String picture
    b email_verified
    i issued_at
    i expires_at
    Json claims  // everything else the provider said, owned
}

// Takes OWNERSHIP of `claims`, which goes with the identity.
@ oidc_identity_from_claims Json claims → OidcIdentity {
    ^ @ OidcIdentity {
        ( claims_str claims `sub` )
        ( claims_str claims `iss` )
        ( claims_str claims `email` )
        ( claims_str claims `name` )
        ( claims_str claims `preferred_username` )
        ( claims_str claims `picture` )
        ( claims_bool claims `email_verified` )
        ( claims_int claims `iat` )
        ( claims_int claims `exp` )
        claims
    }
}

// Let go of `id` now rather than at the end of its owner's scope.
@ oidc_identity_free sink OidcIdentity id → v {}

// Any other claim, by name — the provider-specific half of the profile.
@ oidc_identity_claim OidcIdentity id s key → String {
    ^ ( claims_str . id claims key )
}

@ oidc_identity_claim_list OidcIdentity id s key → ( Vec String ) {
    ^ ( claims_string_list . id claims key )
}

@ oidc_identity_has_scope OidcIdentity id s scope → b {
    ^ ( claims_has_scope . id claims scope )
}

// "sub@issuer" — the globally unique name of the user, which is the
// pair, never the subject alone.
@ oidc_identity_key OidcIdentity id → String {
    : String out ( string_with_cap 64 )
    ( string_push_str out ( string_data . id subject ) )
    ( string_push_char out 64 )  // '@'
    ( string_push_str out ( string_data . id issuer ) )
    ^ out
}

// A one-line human rendering, for logs and CLI output.
@ oidc_identity_describe OidcIdentity id → String {
    : String out ( string_with_cap 128 )
    ( string_push_str out ( string_data . id subject ) )
    ? > ( string_len . id name ) 0 {
        ( string_push_str out ` (` )
        ( string_push_str out ( string_data . id name ) )
        ( string_push_char out 41 )  // ')'
    } {}
    ? > ( string_len . id email ) 0 {
        ( string_push_str out ` <` )
        ( string_push_str out ( string_data . id email ) )
        ( string_push_char out 62 )  // '>'
        ? . id email_verified {} { ( string_push_str out ` [unverified]` ) }
    } {}
    ( string_push_str out ` @ ` )
    ( string_push_str out ( string_data . id issuer ) )
    ^ out
}
