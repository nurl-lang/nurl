// authz_test.nu — the tenancy layer: organisations, roles, ownership, keys.
//
//   org key   — an organisation id becomes a filename, so a hostile one
//               must not be able to name a path.
//   users     — the first subject an org sees becomes its admin, the rest
//               viewers; the last admin cannot demote itself.
//   ownership — admins see the whole org including unclaimed legacy
//               models; viewers see exactly what they own.
//   keys      — issue, present, revoke; the stored form cannot be replayed.
//   off       — with authentication disabled every request is a local
//               admin, which is what keeps existing deployments working.
// Store root: $ANOMALY_TEST_DIR (default ./anomaly_authz_test).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/ext/sqlite.nu`
$ `src/authz.nu`

: ~ i g_pass 0
: ~ i g_fail 0
: i T0 1700000000

@ check b cond s label → v {
    ? cond {
        ( nurl_print `ok ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_pass + g_pass 1
    } {
        ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print `\n` )
        = g_fail + g_fail 1
    }
}

@ streq String a s b → b { ^ == ( nurl_str_eq ( string_data a ) b ) 1 }

// Does `hay` contain `needle`?
@ __has s hay s needle → b {
    : i hn ( nurl_str_len hay )
    : i nn ( nurl_str_len needle )
    ? == nn 0 { ^ T } {}
    ? > nn hn { ^ F } {}
    : ~ i k 0
    ~ <= k - hn nn {
        : ~ b same T
        : ~ i j 0
        ~ & same < j nn {
            ? == ( nurl_str_at hay hn + k j ) ( nurl_str_at needle nn j ) {} { = same F }
            = j + j 1
        }
        ? same { ^ T } {}
        = k + k 1
    }
    ^ F
}

// A syntactically valid, deliberately UNSIGNED JWT carrying one tenant.
// Enough to drive the issuer-derivation path; nothing can verify it.
@ __mk_unsigned_jwt s tid → String {
    : String claims ( string_from `{"iss":"https://id.example/` )
    ( string_push_str claims tid )
    ( string_push_str claims `/v2.0","sub":"u1","aud":"cid","tid":"` )
    ( string_push_str claims tid )
    ( string_push_str claims `","exp":4102444800}` )
    : String h64 ( b64_url_encode `{"alg":"RS256","typ":"JWT","kid":"k1"}` )
    : String c64 ( b64_url_encode ( string_data claims ) )
    : String out ( string_from ( string_data h64 ) )
    ( string_push_char out 46 )
    ( string_push_str out ( string_data c64 ) )
    ( string_push_str out `.AAAA` )
    ( string_free claims ) ( string_free h64 ) ( string_free c64 )
    ^ out
}

// A principal for `sub` with `role`, as the resolver would have built one.
@ mkp s org s sub s role → Principal {
    ^ @ Principal {
        T F ( string_from org ) ( string_from sub ) ( string_new )
        ( string_new ) ( string_from role ) ( string_new )
    }
}

@ test_orgkey → v {
    // A tenant GUID survives as itself, lowercased.
    : String a ( __az_org_key `A1B2C3D4-0000-4000-8000-ABCDEF123456` )
    ( check ( streq a `a1b2c3d4-0000-4000-8000-abcdef123456` ) `orgkey: a GUID passes through, lowercased` )
    ( string_free a )

    // Anything that could name a path is replaced by a digest of it. The
    // point is not that the digest is secret; it is that no input can
    // produce a separator, a dot-dot, or an empty name.
    : String b ( __az_org_key `../../etc/passwd` )
    ( check == ( string_len b ) 32 `orgkey: a path-shaped id becomes a 32-char digest` )
    ( check ! ( streq b `../../etc/passwd` ) `orgkey: it is not the input` )
    : ~ b clean T
    : ~ i k 0
    ~ < k ( string_len b ) {
        : i c ( string_get b k )
        : b hex | & >= c 48 <= c 57 & >= c 97 <= c 102
        ? hex {} { = clean F }
        = k + k 1
    }
    ( check clean `orgkey: the digest is hex only` )
    ( string_free b )

    : String c ( __az_org_key `https://login.microsoftonline.com/x/v2.0` )
    ( check == ( string_len c ) 32 `orgkey: an issuer URL digests too` )
    ( string_free c )
    : String d ( __az_org_key `` )
    ( check == ( string_len d ) 32 `orgkey: an empty id still yields a name` )
    ( string_free d )

    // Distinct inputs must not share a database.
    : String e1 ( __az_org_key `../a` )
    : String e2 ( __az_org_key `../b` )
    ( check ! ( streq e1 ( string_data e2 ) ) `orgkey: different inputs, different keys` )
    ( string_free e1 ) ( string_free e2 )
}

// Multi-tenant: which issuer a token has to carry, and which tenants are
// admitted at all.
@ test_tenancy → v {
    // Single-tenant is the default, and the issuer is simply the one
    // configured.
    ( check ! ( anomaly_authz_multi_tenant ) `tenancy: single-tenant by default` )

    ( anomaly_authz_configure_tenancy T `` )
    ( check ( anomaly_authz_multi_tenant ) `tenancy: it can be switched on` )

    // With no template learned from a provider yet, there is no issuer to
    // demand — and that is a refusal, not a wildcard.
    : String none ( __az_issuer_for `aaaa-bbbb` )
    ( check == ( string_len none ) 0 `tenancy: no template yields no issuer` )
    ( string_free none )

    // The provider's own template, with the token's tenant substituted.
    = g_az_iss_tmpl `https://login.example.com/{tenantid}/v2.0`
    : String iss ( __az_issuer_for `1111-2222` )
    ( check ( streq iss `https://login.example.com/1111-2222/v2.0` )
    `tenancy: the tenant is substituted into the template` )
    ( string_free iss )

    // A token that names no tenant cannot name an issuer either.
    : String empty ( __az_issuer_for `` )
    ( check == ( string_len empty ) 0 `tenancy: no tenant yields no issuer` )
    ( string_free empty )

    // A template with no placeholder is a fixed string somebody wrote by
    // mistake; substituting nothing into it would silently accept every
    // tenant under one issuer, so it is refused.
    = g_az_iss_tmpl `https://login.example.com/fixed/v2.0`
    : String noph ( __az_issuer_for `1111-2222` )
    ( check == ( string_len noph ) 0 `tenancy: a template without the placeholder is refused` )
    ( string_free noph )
    = g_az_iss_tmpl `https://login.example.com/{tenantid}/v2.0`

    // The allowlist. Empty admits everyone — that is what multi-tenant
    // asks for — and a list admits exactly what it names.
    ( check ( __az_tenant_allowed `anything-at-all` ) `tenancy: an empty allowlist admits any tenant` )
    ( anomaly_authz_configure_tenancy T `1111-2222,3333-4444` )
    ( check ( __az_tenant_allowed `1111-2222` ) `tenancy: a listed tenant is admitted` )
    ( check ( __az_tenant_allowed `3333-4444` ) `tenancy: the second entry too` )
    ( check ! ( __az_tenant_allowed `9999-0000` ) `tenancy: an unlisted tenant is refused` )
    ( check ! ( __az_tenant_allowed `` ) `tenancy: a token with no tenant is refused` )
    // Tenant ids are GUIDs and case is not meaningful in them, so a list
    // written in either case has to match either case.
    ( check ( __az_tenant_allowed `1111-2222` ) `tenancy: matching is case-insensitive` )

    // A near-miss must not pass: prefix and substring matches are how an
    // allowlist quietly stops being one.
    ( check ! ( __az_tenant_allowed `1111` ) `tenancy: a prefix of a listed tenant is refused` )
    ( check ! ( __az_tenant_allowed `1111-2222-5555` ) `tenancy: an extension of one is refused` )

    ( anomaly_authz_configure_tenancy F `` )
    ( check ! ( anomaly_authz_multi_tenant ) `tenancy: it can be switched back off` )
}

// The wiring between the two: that a multi-tenant deployment actually
// DEMANDS the issuer derived from the token's own tenant, rather than the
// authority it was configured with.
//
// This is the regression that matters. The helpers below can all be right
// and the service still refuse every token, because the authority a
// multi-tenant deployment configures (.../organizations/v2.0) is a URL no
// token ever carries — comparing against it rejects everything, with a 401
// that says nothing.
@ test_tenancy_wiring → v {
    // An unsigned JWT is enough: verification will fail either way, and
    // what is under test is WHICH failure comes back — a tenant refusal
    // means the substitution never ran.
    : String tok ( __mk_unsigned_jwt `aaaaaaaa-1111-2222-3333-444444444444` )

    ( anomaly_authz_configure T T `https://id.example/organizations/v2.0` `cid` `api://cid` )
    ( anomaly_authz_configure_tenancy T `` )
    = g_az_iss_tmpl `https://id.example/{tenantid}/v2.0`
    : Principal p1 ( __az_token_principal ( string_data tok ) 1700000000 )
    ( check ! . p1 authed `wiring: an unapproved organisation is refused` )
    ( check ( __has ( anomaly_authz_last_error ) `not approved` )
    `wiring: and the reason says it is not approved` )
    ( principal_free p1 )

    // With the tenant admitted, the refusal must move PAST the tenant check
    // — to the signature, which an unsigned token cannot pass. A reason
    // still mentioning the tenant would mean the issuer was never derived.
    //
    // The provider is seeded with a pinned, offline key set so this stays a
    // unit test: reaching for a real one would put a DNS lookup and a TLS
    // handshake in the middle of an assertion about string composition.
    // Approval now lives in the registry, not in a config list, so the
    // tenant is admitted the way the dashboard admits one.
    ( az_seed_allowed `aaaaaaaa-1111-2222-3333-444444444444` T0 )
    : *OidcProvider fake ( oidc_provider_new `https://id.example/organizations/v2.0` )
    : b _j ( oidc_provider_set_jwks fake `{"keys":[]}` )
    = g_az_prov_addr # i fake
    = g_az_iss_tmpl `https://id.example/{tenantid}/v2.0`
    : Principal p2 ( __az_token_principal ( string_data tok ) 1700000000 )
    ( check ! . p2 authed `wiring: an unsigned token is still refused` )
    ( check ! ( __has ( anomaly_authz_last_error ) `not approved` )
    `wiring: but no longer for its tenant — the issuer was derived` )
    ( principal_free p2 )

    // And every refusal says something. A 401 with an empty reason is the
    // sign-in screen that reappears forever with nothing to go on.
    ( check > ( nurl_str_len ( anomaly_authz_last_error ) ) 0
    `wiring: a refusal always carries a reason` )

    ( string_free tok )
    = g_az_prov_addr 0
    ( oidc_provider_free fake )
    ( anomaly_authz_configure_tenancy F `` )
    ( anomaly_authz_configure F T `` `` `` )
}

@ test_users → v {
    ?? ( az_db_open `orgA` ) {
        F _ → { ( check F `users: the org database opens` ) }
        T db → {
            ( check T `users: the org database opens` )
            ( check == ( az_user_count db ) 0 `users: a fresh org has none` )

            // Nobody could have granted the first user its role, and an org
            // whose every user is a viewer can never appoint an admin.
            : String r1 ( az_user_touch db `sub-1` `a@x` `Aa` T0 )
            ( check ( streq r1 `admin` ) `users: the first subject becomes admin` )
            ( string_free r1 )
            : String r2 ( az_user_touch db `sub-2` `b@x` `Bb` T0 )
            ( check ( streq r2 `viewer` ) `users: the second becomes a viewer` )
            ( string_free r2 )
            ( check == ( az_user_count db ) 2 `users: both were recorded` )
            ( check == ( az_admin_count db ) 1 `users: exactly one admin` )

            // A repeat visit refreshes the profile without changing the role.
            : String r1b ( az_user_touch db `sub-1` `a2@x` `Aa2` + T0 60 )
            ( check ( streq r1b `admin` ) `users: a return visit keeps the role` )
            ( string_free r1b )
            ( check == ( az_user_count db ) 2 `users: and adds no row` )

            ( check ( az_user_set_role db `sub-2` `admin` ) `users: a viewer can be promoted` )
            : String r2b ( az_user_role db `sub-2` )
            ( check ( streq r2b `admin` ) `users: the promotion stuck` )
            ( string_free r2b )
            ( check == ( az_admin_count db ) 2 `users: two admins now` )

            ( check ( az_user_set_role db `sub-2` `viewer` ) `users: and demoted again` )
            ( check == ( az_admin_count db ) 1 `users: back to one admin` )

            // The last admin may not demote itself: there would be nobody
            // left who could undo it.
            ( check ! ( az_user_set_role db `sub-1` `viewer` ) `users: the last admin cannot be demoted` )
            ( check == ( az_admin_count db ) 1 `users: so the org keeps its admin` )

            ( check ! ( az_user_set_role db `sub-1` `wizard` ) `users: an unknown role is refused` )
            ( check ! ( az_user_set_role db `nobody` `admin` ) `users: an unknown subject is refused` )

            : String none ( az_user_role db `nobody` )
            ( check == ( string_len none ) 0 `users: an unknown subject has no role` )
            ( string_free none )

            : Json us ( az_users_json db )
            ( check == ( json_arr_len us ) 2 `users: the listing has both` )
            ( json_free us )
        }
    }
}

@ test_ownership → v {
    ?? ( az_db_open `orgB` ) {
        F _ → { ( check F `own: the org database opens` ) }
        T db → {
            : String _r1 ( az_user_touch db `alice` `a@x` `Alice` T0 )
            ( string_free _r1 )
            : String _r2 ( az_user_touch db `bob` `b@x` `Bob` T0 )
            ( string_free _r2 )
            : Principal admin ( mkp `orgB` `alice` `admin` )
            : Principal viewer ( mkp `orgB` `bob` `viewer` )

            // A model nobody has claimed is not this organisation's just
            // because nobody else spoke for it. The store is one flat
            // directory shared by every tenant.
            ( check ! ( az_model_in_org db `legacy` ) `own: an unclaimed model is not in the org` )
            ( check ! ( az_may_see db admin `legacy` ) `own: an admin does NOT see an unclaimed model` )
            ( check ! ( az_may_see db viewer `legacy` ) `own: nor does a viewer` )

            // A model belongs to the ORGANISATION. Everyone in it sees the
            // same models — a colleague leaving must not take a production
            // model with them — and the ROLE decides what may be done.
            ( check ( az_model_claim db `shared` `bob` T0 F ) `own: a model can be claimed for the org` )
            ( check ( az_may_see db viewer `shared` ) `own: the viewer who created it sees it` )
            ( check ( az_may_see db admin `shared` ) `own: and so does the admin` )
            ( check ( az_model_claim db `alices` `alice` T0 F ) `own: the admin creates one too` )
            ( check ( az_may_see db viewer `alices` ) `own: which the viewer ALSO sees — it is the org's` )

            // Reading is what a viewer is for. Writing is not: a retrain
            // rewrites forests, a margin edit changes every verdict, and a
            // reset destroys history. None of that is viewing.
            ( check ( az_may_write db admin `shared` ) `own: an admin may write` )
            ( check ! ( az_may_write db viewer `shared` ) `own: a viewer may NOT write` )
            ( check ! ( az_may_write db viewer `alices` ) `own: not even one it created` )
            ( check ! ( az_may_write db admin `legacy` ) `own: nor an admin an unclaimed one` )

            // Deleting a model must not leave its row behind to be
            // inherited by the next model that reuses the name.
            ( az_model_forget db `alices` )
            ( check ! ( az_model_in_org db `alices` ) `own: forgetting removes it from the org` )
            ( check ! ( az_may_see db admin `alices` ) `own: and it stops being visible` )

            : Principal anon ( principal_anon )
            ( check ! ( az_may_see db anon `shared` ) `own: an unauthenticated caller sees nothing` )
            ( principal_free anon )
            ( principal_free admin )
            ( principal_free viewer )
        }
    }
}

// The regression that matters most: one organisation's admin must not see
// another's models. The store is a single flat directory, so this is not
// something the filesystem enforces — only the per-organisation claim
// tables do, and an admin who "sees everything" sees everything of
// everyone.
@ test_cross_org → v {
    ?? ( az_db_open `orgX` ) {
        F _ → { ( check F `cross: orgX opens` ) }
        T dbx → {
            : String _a ( az_user_touch dbx `xadmin` `x@x` `X` T0 )
            ( string_free _a )
            ( check ( az_model_claim dbx `shared-name` `xadmin` T0 F ) `cross: orgX claims a model` )
            ( check ( az_model_claim dbx `x-only` `xadmin` T0 F ) `cross: and another` )
        }
    }
    ?? ( az_db_open `orgY` ) {
        F _ → { ( check F `cross: orgY opens` ) }
        T dby → {
            : String ry ( az_user_touch dby `yadmin` `y@y` `Y` T0 )
            ( check ( streq ry `admin` ) `cross: orgY's first user is ITS admin` )
            ( string_free ry )
            : Principal yadmin ( mkp `orgY` `yadmin` `admin` )

            // Being an admin of orgY says nothing about orgX's models.
            ( check ! ( az_may_see dby yadmin `x-only` ) `cross: orgY's admin cannot see orgX's model` )
            ( check ! ( az_may_write dby yadmin `x-only` ) `cross: nor write it` )
            ( check ! ( az_may_see dby yadmin `shared-name` ) `cross: not even one it could name` )

            // Its own listing is empty, not the store's.
            : ( Vec String ) mine ( az_org_model_names dby )
            ( check == ( vec_len [String] mine ) 0 `cross: orgY's model list is empty` )
            ( vec_free_with [String] mine \ String x → v { ( string_free x ) } )

            // Once orgY claims a name of its own, it sees exactly that.
            ( check ( az_model_claim dby `y-only` `yadmin` T0 F ) `cross: orgY claims its own` )
            : ( Vec String ) mine2 ( az_org_model_names dby )
            ( check == ( vec_len [String] mine2 ) 1 `cross: and now lists exactly one` )
            ( vec_free_with [String] mine2 \ String x → v { ( string_free x ) } )
            ( check ( az_may_see dby yadmin `y-only` ) `cross: which it can see` )
            ( check ! ( az_may_see dby yadmin `x-only` ) `cross: while orgX's stays invisible` )
            ( principal_free yadmin )
        }
    }

    // The home organisation: the first this store created. Only it may
    // adopt a model no organisation has claimed, because nothing in such a
    // model says whose it is and any other admin adopting one would be
    // taking the operator's data.
    : String home ( az_home_org )
    ( check > ( string_len home ) 0 `home: a marker was written` )
    ( check ( az_is_home_org ( string_data home ) ) `home: it identifies itself` )
    ( check ! ( az_is_home_org `orgY` ) `home: a later organisation is not home` )
    // `public` must never hold the marker. It is the bucket ownerless data
    // lands in, and it is created by the first credential-less point — on a
    // fresh deployment, before anybody has signed in. If it took the marker
    // the operator could adopt nothing, ever, because the marker is written
    // once.
    ( check ! ( az_is_home_org AZ_PUBLIC_ORG ) `home: public is not home` )
    ( check ! ( streq home AZ_PUBLIC_ORG ) `home: and never became it` )
    ( string_free home )
}

// The public organisation: where a point that named no owner waits.
@ test_public_org → v {
    // Creating it must not claim the home marker, whatever the order.
    : String marker ( __az_home_marker )
    : !v IoErr rm ( file_delete ( string_data marker ) )
    ?? rm { T _ → {} F _ → {} }
    ( string_free marker )
    ?? ( az_db_open AZ_PUBLIC_ORG ) {
        F _ → { ( check F `public: its database opens` ) }
        T db → {
            ( check T `public: its database opens` )
            : b _c ( az_model_claim db `orphan` `` T0 F )
        }
    }
    : String h ( az_home_org )
    ( check == ( string_len h ) 0 `public: creating it wrote no home marker` )
    ( string_free h )

    // A real organisation created afterwards IS home — the operator who
    // signs in after the producers started must still be able to adopt.
    ?? ( az_db_open `orgReal` ) {
        F _ → { ( check F `public: a real org opens` ) }
        T db2 → { : String r ( az_user_touch db2 `op` `o@o` `Op` T0 ) ( string_free r ) }
    }
    ( check ( az_is_home_org `orgReal` ) `public: the first REAL organisation is home` )

    // And what waited in public can be released into it. Ownerless data is
    // not the public organisation's property.
    ( check ( az_model_in_public `orphan` ) `public: it holds the orphaned model` )
    ( check ( az_model_release_public `orphan` ) `public: which can be released` )
    ( check ! ( az_model_in_public `orphan` ) `public: and is no longer held` )
    ( check ! ( az_model_release_public `orphan` ) `public: releasing twice is a no-op` )
}

// The tenant registry: who may use this service at all.
@ test_registry → v {
    ( anomaly_authz_set_owner_tenant `1111owner-0000-0000-0000-000000000000` )
    ?? ( az_root_open ) {
        F _ → { ( check F `reg: the root database opens` ) }
        T db → {
            ( check T `reg: the root database opens` )
            : String none ( az_tenant_state db `never-seen` )
            ( check == ( string_len none ) 0 `reg: an unseen tenant has no state` )
            ( string_free none )

            // First knock: recorded as pending, and refused. Provisioning
            // an organisation for whoever turns up is how a multi-tenant
            // service fills a disk with strangers.
            : String st1 ( az_tenant_note db `stranger-tid` `Some Org` T0 )
            ( check ( streq st1 `pending` ) `reg: a first sighting is pending` )
            ( string_free st1 )
            ( check ! ( az_tenant_admitted `stranger-tid` T0 ) `reg: pending means refused` )

            // A repeat visit must not undo a decision.
            ( check ( az_tenant_set_state db `stranger-tid` `allowed` `admin-1` T0 ) `reg: it can be approved` )
            : String st2 ( az_tenant_note db `stranger-tid` `Some Org` T0 )
            ( check ( streq st2 `allowed` ) `reg: a return visit keeps the decision` )
            ( string_free st2 )
            ( check ( az_tenant_admitted `stranger-tid` T0 ) `reg: approved means admitted` )

            ( check ( az_tenant_set_state db `stranger-tid` `blocked` `admin-1` T0 ) `reg: it can be blocked` )
            ( check ! ( az_tenant_admitted `stranger-tid` T0 ) `reg: blocked means refused` )
            ( check ! ( az_tenant_set_state db `stranger-tid` `wizard` `admin-1` T0 ) `reg: an unknown state is refused` )

            // The owner tenant is the anchor the rest is decided from, so
            // it is admitted without a row. Locking it out would leave
            // nobody who could unlock anything.
            ( check ( az_tenant_admitted `1111owner-0000-0000-0000-000000000000` T0 )
            `reg: the owner tenant is always admitted` )
            ( check ! ( az_tenant_admitted `` T0 ) `reg: a token with no tenant is refused` )

            : Json ts ( az_tenants_json db )
            ( check > ( json_arr_len ts ) 0 `reg: the listing has the tenants seen` )
            ( json_free ts )
        }
    }
    ( anomaly_authz_set_owner_tenant `` )
}

// Being forgotten, and what it costs the organisation.
@ test_leaving → v {
    ?? ( az_db_open `orgZ` ) {
        F _ → { ( check F `leave: orgZ opens` ) }
        T db → {
            : String r1 ( az_user_touch db `zadmin` `z@z` `Z` T0 )
            ( string_free r1 )
            : String r2 ( az_user_touch db `zviewer` `v@z` `V` T0 )
            ( string_free r2 )
            ( check ( az_model_claim db `zmodel` `zviewer` T0 F ) `leave: the org holds a model` )
            : KeyIssue k ( az_key_create db `zviewer` `feed` AZ_ROLE_INGEST T0 )
            : KeyParts kp ( __az_key_split ( string_data . k secret ) )

            // The person goes. The organisation's credential does not: a
            // colleague leaving must not stop the data arriving.
            ( check ( az_user_delete db `zviewer` ) `leave: a user can be forgotten` )
            ( check == ( az_user_count db ) 1 `leave: and is gone from the roster` )
            : String gone ( az_user_role db `zviewer` )
            ( check == ( string_len gone ) 0 `leave: with no role left` )
            ( string_free gone )
            : Principal still ( az_key_principal db `orgZ` kp T0 )
            ( check . still authed `leave: the key they issued still works` )
            ( check ( streq . still sub `` ) `leave: but no longer names them` )
            ( principal_free still )
            ( check ( az_model_in_org db `zmodel` ) `leave: and the org keeps the model` )

            ( check ! ( az_user_delete db `nobody` ) `leave: an unknown user is not deletable` )
            ( key_parts_free kp )
            ( key_issue_free k )
        }
    }

    // The LAST member leaving takes the organisation with it: there is
    // nobody it could belong to any more.
    : ~ ( Vec String ) doomed ( vec_new [String] )
    ?? ( az_db_open `orgGone` ) {
        F _ → { ( check F `leave: orgGone opens` ) }
        T db → {
            : String r ( az_user_touch db `only` `o@o` `O` T0 )
            ( string_free r )
            : b _c ( az_model_claim db `gonemodel` `only` T0 F )
            ( check ( az_user_delete db `only` ) `leave: the last member leaves` )
            ( check == ( az_user_count db ) 0 `leave: the org has no members` )
            ( vec_free [String] doomed )
            = doomed ( az_org_models_before_delete db )
            ( check == ( vec_len [String] doomed ) 1 `leave: its models are named before it goes` )
        }
    }
    ( vec_free_with [String] doomed \ String x → v { ( string_free x ) } )
    ( check ( az_org_drop `orgGone` ) `leave: the organisation database is deleted` )
    // Reopening would CREATE a fresh one, so what is asserted is that
    // nothing survived: no members, no models, no keys.
    ?? ( az_db_open `orgGone` ) {
        F _ → { ( check F `leave: it can be reopened` ) }
        T db2 → {
            ( check == ( az_user_count db2 ) 0 `leave: nothing survived it` )
            : ( Vec String ) ms ( az_org_model_names db2 )
            ( check == ( vec_len [String] ms ) 0 `leave: not its models either` )
            ( vec_free_with [String] ms \ String x → v { ( string_free x ) } )
        }
    }
}

// What an ingest credential may do, and what it may not. The line is
// "putting data in" — including the model that data brings into being —
// against "changing or destroying one".
@ test_ingest_capability → v {
    : Principal admin ( mkp `orgI` `a` `admin` )
    : Principal viewer ( mkp `orgI` `v` `viewer` )
    : Principal key @ Principal {
        T T ( string_from `orgI` ) ( string_from `k` ) ( string_new )
        ( string_new ) ( string_from AZ_ROLE_INGEST ) ( string_from `kid` )
    }
    : Principal anon ( principal_anon )

    ( check ( principal_may_ingest admin ) `cap: an admin may put data in` )
    ( check ( principal_may_ingest key ) `cap: and so may an ingest key` )
    // A viewer reads what the models collected and decided. Sending a point
    // is not reading.
    ( check ! ( principal_may_ingest viewer ) `cap: a viewer may not` )
    ( check ! ( principal_may_ingest anon ) `cap: nor may nobody` )
    ( check ! ( principal_is_admin key ) `cap: an ingest key is not an admin` )

    // A key whose stored capability is a person's role is not an ingest
    // credential: the two vocabularies must not blur into each other.
    : Principal vkey @ Principal {
        T T ( string_from `orgI` ) ( string_from `k2` ) ( string_new )
        ( string_new ) ( string_from AZ_ROLE_VIEWER ) ( string_from `kid2` )
    }
    ( check ! ( principal_may_ingest vkey ) `cap: a viewer-roled key may not either` )
    ( principal_free vkey )

    ?? ( az_db_open `orgI` ) {
        F _ → { ( check F `cap: orgI opens` ) }
        T db → {
            : b _c ( az_model_claim db `owned` `a` T0 F )
            // Reading and writing are unchanged by the capability: an
            // ingest key may see its organisation's models and may not
            // rewrite them.
            ( check ( az_may_see db key `owned` ) `cap: an ingest key sees the org's model` )
            ( check ! ( az_may_write db key `owned` ) `cap: and may not change it` )
            ( check ( az_may_write db admin `owned` ) `cap: while an admin may` )
        }
    }
    ( principal_free admin ) ( principal_free viewer )
    ( principal_free key ) ( principal_free anon )
}

@ test_keys → v {
    ?? ( az_db_open `orgC` ) {
        F _ → { ( check F `keys: the org database opens` ) }
        T db → {
            // Seed an admin first, so carol arrives as an ordinary viewer
            // and her key can be shown to inherit a viewer's reach rather
            // than the first-user admin grant.
            : String _r0 ( az_user_touch db `founder` `f@x` `Founder` T0 )
            ( string_free _r0 )
            : String _r ( az_user_touch db `carol` `c@x` `Carol` T0 )
            ( check == ( nurl_str_eq ( string_data _r ) `viewer` ) 1 `keys: carol is a viewer` )
            ( string_free _r )

            : KeyIssue k1 ( az_key_create db `carol` `node-red` AZ_ROLE_INGEST T0 )
            ( check > ( string_len . k1 secret ) 40 `keys: the issued token is long` )
            : KeyParts p1 ( __az_key_split ( string_data . k1 secret ) )
            ( check . p1 ok `keys: the token parses` )
            ( check ( streq . p1 kp_id ( string_data . k1 key_id ) ) `keys: it carries its own id` )

            : Principal pr ( az_key_principal db `orgC` p1 T0 )
            ( check . pr authed `keys: presenting it authenticates` )
            ( check . pr via_key `keys: the principal is marked as a key` )
            ( check ( streq . pr sub `carol` ) `keys: it carries its creator's subject` )
            ( check ( streq . pr role `ingest` ) `keys: carrying the ingest capability` )
            : Principal ip ( mkp `orgC` `x` `ingest` )
            ( check ! ( principal_is_admin pr ) `keys: an ingest key is not an admin` )
            ( check ( principal_may_ingest pr ) `keys: but it may send points` )
            ( principal_free ip )
            ( check ( streq . pr org `orgC` ) `keys: and the organisation` )
            ( principal_free pr )

            // A key is only as good as its secret: the id alone is not it.
            : KeyParts forged @ KeyParts { T ( string_from ( string_data . p1 kp_id ) )
                ( string_from `00000000000000000000000000000000` ) }
            : Principal bad ( az_key_principal db `orgC` forged T0 )
            ( check ! . bad authed `keys: a wrong secret does not authenticate` )
            ( principal_free bad )
            ( key_parts_free forged )

            : KeyParts unknown @ KeyParts { T ( string_from `deadbeefdeadbeef` )
                ( string_from ( string_data . p1 kp_secret ) ) }
            : Principal bad2 ( az_key_principal db `orgC` unknown T0 )
            ( check ! . bad2 authed `keys: an unknown id does not authenticate` )
            ( principal_free bad2 )
            ( key_parts_free unknown )

            // Revocation is immediate and one-way. There is no owner check:
            // the key is the ORGANISATION's, and whoever pressed the button
            // that made it has no more claim on it than any other admin.
            ( check ( az_key_revoke db ( string_data . k1 key_id ) T0 ) `keys: it can be revoked` )
            : Principal after ( az_key_principal db `orgC` p1 T0 )
            ( check ! . after authed `keys: a revoked key stops working` )
            ( principal_free after )
            ( check ! ( az_key_revoke db ( string_data . k1 key_id ) T0 ) `keys: revoking twice is a no-op` )
            ( check ! ( az_key_revoke db `no-such-key` T0 ) `keys: an unknown id revokes nothing` )

            : String _r2 ( az_user_touch db `dave` `d@x` `Dave` T0 )
            ( string_free _r2 )
            : KeyIssue k2 ( az_key_create db `dave` `daves` AZ_ROLE_INGEST T0 )
            ( check ( az_key_revoke db ( string_data . k2 key_id ) T0 ) `keys: anyone's key is the org's to revoke` )

            // One listing, the organisation's. There is no per-person view,
            // because there is no per-person ownership.
            : Json all ( az_keys_json db )
            ( check == ( json_arr_len all ) 2 `keys: the listing is the organisation's` )
            ( json_free all )

            ( key_parts_free p1 )
            ( key_issue_free k1 )
            ( key_issue_free k2 )
        }
    }

    // Malformed tokens are rejected by shape, which is also how the
    // resolver tells an API key from a JWT.
    : KeyParts n1 ( __az_key_split `eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.x.y` )
    ( check ! . n1 ok `keys: a JWT is not mistaken for a key` )
    ( key_parts_free n1 )
    : KeyParts n2 ( __az_key_split `anok_noseparator` )
    ( check ! . n2 ok `keys: a token with no separator is refused` )
    ( key_parts_free n2 )
    : KeyParts n3 ( __az_key_split `anok__abc` )
    ( check ! . n3 ok `keys: an empty id is refused` )
    ( key_parts_free n3 )
    : KeyParts n4 ( __az_key_split `anok_abc_` )
    ( check ! . n4 ok `keys: an empty secret is refused` )
    ( key_parts_free n4 )
}

@ test_off → v {
    // The default: no configuration, no gate, and every caller is an admin
    // of a single reserved organisation. An upgrade must not lock anyone
    // out before the identity provider is configured.
    ( check ! ( anomaly_authz_enabled ) `off: authentication is off by default` )
    ( check ( anomaly_authz_simple ) `off: which is simple mode` )
    : Principal p ( principal_local_admin )
    ( check . p authed `off: the caller is authenticated` )
    ( check ( principal_is_admin p ) `off: and is an admin` )
    ( check ( streq . p org `public` ) `off: in the shared public organisation` )
    ( principal_free p )

    // Turning it on needs an issuer AND a client id; without them it would
    // refuse every request rather than protect anything, so it stays off.
    ( anomaly_authz_configure T T `` `` `` )
    : b half ( anomaly_authz_enabled )
    ( anomaly_authz_configure F T `` `` `` )
    ( check half `off: configure honours what it is told` )
}

@ main → i {
    : String root ( env_var_or `ANOMALY_TEST_DIR` `./anomaly_authz_test` )
    : !v IoErr junk ( dir_remove_all ( string_data root ) )
    ?? junk { T _ → {} F _ → {} }
    ( anomaly_authz_set_root ( string_data root ) )

    ( test_orgkey )
    ( test_tenancy )
    ( test_tenancy_wiring )
    ( test_users )
    ( test_ownership )
    ( test_cross_org )
    ( test_registry )
    ( test_leaving )
    ( test_ingest_capability )
    ( test_public_org )
    ( test_keys )
    ( test_off )

    : !v IoErr fin ( dir_remove_all ( string_data root ) )
    ?? fin { T _ → {} F _ → {} }
    ( string_free root )
    ( nurl_print `authz_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
