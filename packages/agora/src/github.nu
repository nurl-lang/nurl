// agora/src/github.nu — the connection to GitHub: a GitHub App.
//
// One GitHub App (created once by the owner; the setup is in README.md)
// is the whole connection: GitHub sends its webhook events — the App's
// one webhook, never a hook per agent, watch or PR — to POST
// /github/webhook, and agora asks GitHub's REST API, as the App's
// installation, for what the events missed. Nothing here creates or
// removes anything on GitHub: watching and unwatching only change what
// agora tells whom (ghstore.nu).
//
// Configuration, [github] in agora.toml:
//
//   app       the App's JSON (id, webhook_secret, installation_id), as
//             written when the App was created
//   key       the App's private key (PEM)
//   org       signed in: the organisation (tenant) whose agoras the
//             repositories below are
//   repos     the GitHub repositories connected, "owner/name" each; the
//             events of one reach the agora of github.com/owner/name
//   workflows the Actions workflows whose results count (every one if
//             left out)
//   merge_channel  post one line per merged PR to this channel ('' = off)
//
// Leaving a repository out of `repos` disconnects it: its events are
// acknowledged and dropped, and no agent tool talks about it.
//
// Reception: the signature (X-Hub-Signature-256, HMAC-SHA256 of the raw
// body with the webhook secret) is checked before anything is read; the
// App's installation and the repository's stable id must be the ones
// configured; the payload is cut down to the few fields agora keeps and
// stored under GitHub's delivery id before 202 goes back — a retry of a
// delivery already kept changes nothing, and a full queue answers 503.
// A worker thread applies what was stored, in order (ghstore.nu).
//
// GitHub does not retry a delivery that failed, so the worker also asks
// GitHub directly: at once for a PR watched before agora knew it (its
// current state, taken silently — a watch's first look is not news),
// and every AG_GH_RECONCILE_EVERY seconds for every watched PR while
// watches exist. What it reads goes through the same path as an event:
// a change nobody was told of is told once, nothing old floods back.
// Rate limits and errors back off; the health (last event, last look,
// last error) is shown by `pr_watches`, and losing or regaining GitHub
// is told to the watchers once each way.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/regex.nu`
$ `deps/http-client/src/http_client.nu`
$ `api.nu`
$ `auth.nu`
$ `ghstore.nu`

: i AG_GH_RECONCILE_EVERY 600
: i AG_GH_TIDY_EVERY 60
: s AG_GH_API `https://api.github.com`

// ── Configuration ────────────────────────────────────────────────────

: AgGhConf {
    b on
    i app_id
    String secret  // the webhook secret
    i installation
    String key_path
    String org
    ( Vec String ) repos  // owner/name, lowercase
    String merge_channel
    ( Vec String ) workflows
    String api
}

@ __gh_conf_blank → ( Locked AgGhConf ) {
    ^ ( locked_new [AgGhConf] @ AgGhConf { F 0 ( string_new ) 0 ( string_new ) ( string_new ) ( vec_new [String] ) ( string_new ) ( vec_new [String] ) ( string_from AG_GH_API ) } )
}

: ( Locked AgGhConf ) g_gh_conf ( __gh_conf_blank )

// The App's slug (`github-app.json`): its issues are by `<slug>[bot]`.
@ __gh_slug_blank → ( Locked String ) { ^ ( locked_new [String] ( string_new ) ) }

: ( Locked String ) g_gh_slug ( __gh_slug_blank )

@ ag_gh_set_slug s slug → v {
    : String old ( locked_take [String] g_gh_slug )
    ( locked_restore [String] g_gh_slug ( string_from slug ) )
}

@ _gh_slug → String {
    : String c ( locked_take [String] g_gh_slug )
    : String out ( string_clone c )
    ( locked_restore [String] g_gh_slug c )
    ^ out
}

@ _gh_conf → AgGhConf {
    : AgGhConf c ( locked_take [AgGhConf] g_gh_conf )
    : AgGhConf out @ AgGhConf { . c on . c app_id ( string_clone . c secret ) . c installation ( string_clone . c key_path ) ( string_clone . c org )
        ( _gh_strs_clone . c repos ) ( string_clone . c merge_channel ) ( _gh_strs_clone . c workflows ) ( string_clone . c api ) }
    ( locked_restore [AgGhConf] g_gh_conf c )
    ^ out
}

@ _gh_strs_clone ( Vec String ) v → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] v k ) { T x → { ( vec_push [String] out ( string_clone x ) ) } F _ → {} }
        = k + k 1
    }
    ^ out
}

// "a, b" or a TOML array (ag_config_list joins it) → trimmed lowercase items.
@ __gh_split String raw b lower → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : String cur ( string_new )
    : s t ( string_data raw )
    : ( Slice u ) v ( slice_of_str t )
    : i n ( nurl_str_len t )
    : ~ i k 0
    ~ <= k n {
        : i c ? < k n ( slice_byte v k ) 44
        ? == c 44 {
            : String tr ( string_trim cur )
            ? > ( string_len tr ) 0 { ( vec_push [String] out ? lower ( string_to_lower tr ) tr ) } {}
            ( string_clear cur )
        } { ( string_push_char cur c ) }
        = k + k 1
    }
    ^ out
}

// A TOML array of strings, each whole (a redaction pattern may hold a
// comma); a lone string is a list of one.
@ __gh_cfg_strings AgConfig cfg s key → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ? . cfg loaded {} { ^ out }
    ?? ( toml_get_path . cfg root key ) {
        T v → {
            ?? ( toml_as_str v ) {
                T one → { ( vec_push [String] out one ) ^ out }
                F _ → {}
            }
            ?? v {
                TArr items → {
                    : i n ( vec_len [TomlValue] items )
                    : ~ i k 0
                    ~ < k n {
                        ?? ( vec_get [TomlValue] items k ) {
                            T e → { ?? ( toml_as_str e ) { T sv → { ( vec_push [String] out sv ) } F _ → {} } }
                            F _ → {}
                        }
                        = k + k 1
                    }
                }
                _ → {}
            }
        }
        F _ → {}
    }
    ^ out
}

@ _gh_repo_in ( Vec String ) repos s full → b {
    : i n ( vec_len [String] repos )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] repos k ) { T r → { ? != 0 ( nurl_str_eq ( string_data r ) full ) { ^ T } {} } F _ → {} }
        = k + k 1
    }
    ^ F
}

@ _gh_cfg_list AgConfig cfg s key → String {
    : String l ( ag_config_list cfg key )
    ? > ( string_len l ) 0 { ^ l } {}
    ^ ( ag_config_str cfg key `` )
}

// The agora a GitHub repository's events reach: github.com/owner/name.
@ gh_repo_key s full → String {
    : String k ( string_from `github.com/` )
    ( string_push_str k ( string_data ( string_to_lower ( string_from full ) ) ) )
    ^ k
}

// Read [github]. F with `why` filled when it is there but unusable; F
// with `why` empty when there is none (GitHub is simply off).
@ ag_gh_apply_config AgConfig cfg String why → b {
    : String app_path ( ag_config_str cfg `github.app` `` )
    ? == ( string_len app_path ) 0 { ^ F } {}
    : String key_path ( ag_config_str cfg `github.key` `` )
    : ~ i app_id 0
    : ~ String secret ( string_new )
    : ~ i inst 0
    ?? ( read_file ( string_data app_path ) ) {
        F _ → { ( string_push_str why `[github] app: cannot read ` ) ( string_push_str why ( string_data app_path ) ) ^ F }
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                F _ → { ( string_push_str why `[github] app: not JSON` ) ^ F }
                T j → {
                    = app_id ( _gh_i j `id` )
                    = secret ( _gh_s j `webhook_secret` )
                    = inst ( _gh_i j `installation_id` )
                    ( ag_gh_set_slug ( string_data ( _gh_s j `slug` ) ) )
                }
            }
        }
    }
    ? | == app_id 0 == ( string_len secret ) 0 { ( string_push_str why `[github] app: needs id and webhook_secret` ) ^ F } {}
    ?? ( read_file ( string_data key_path ) ) {
        F _ → { ( string_push_str why `[github] key: cannot read the private key` ) ^ F }
        T pem → {
            ?? ( rsa_priv_from_pem ( string_data pem ) ) {
                F _ → { ( string_push_str why `[github] key: not an RSA private key` ) ^ F }
                T _ → {}
            }
        }
    }
    : ( Vec String ) repos ( __gh_split ( _gh_cfg_list cfg `github.repos` ) T )
    ? == ( vec_len [String] repos ) 0 { ( string_push_str why `[github] repos: name at least one owner/name` ) ^ F } {}
    : String org ( ag_config_str cfg `github.org` `` )
    ? & ( ag_auth_oidc ) == ( string_len org ) 0 { ( string_push_str why `[github] org: the organisation (tenant) the repositories belong to` ) ^ F } {}
    : ( Vec String ) wf ( __gh_split ( _gh_cfg_list cfg `github.workflows` ) F )
    : String mc ( ag_config_str cfg `github.merge_channel` `` )
    : String api ( ag_config_str cfg `github.api` AG_GH_API )
    // Credentials go only over TLS (a loopback stand-in excepted).
    ? | ( string_starts_with api `https://` ) ( _gh_loopback_url api ) {} {
        ( string_push_str why `[github] api: must be an https:// URL` )
        ^ F
    } {}
    // Locally every repository is the one file: its integration state
    // (repository binding, outbox) would be shared, so one repository.
    ? & ! ( ag_auth_oidc ) > ( vec_len [String] repos ) 1 { ( string_push_str why `[github] repos: a local agora is one file, so one repository (signed in, each has its own)` ) ^ F } {}
    ( ag_gh_configure app_id ( string_data secret ) inst ( string_data key_path ) ( string_data ( ag_org_key ( string_data org ) ) ) repos ( string_data mc ) wf ( string_data api ) )
    // The task board's mirror (ghmirror.nu): off unless named; dry run
    // unless told otherwise.
    : ( Vec String ) mirror ( __gh_split ( _gh_cfg_list cfg `github.mirror` ) T )
    : ( Vec String ) redact ( __gh_cfg_strings cfg `github.redact` )
    : i nre ( vec_len [String] redact )
    : ~ i k 0
    ~ < k nre {
        ?? ( vec_get [String] redact k ) {
            T pat → {
                ?? ( regex_compile ( string_data pat ) ) {
                    T _ → {}
                    F _ → {
                        ( string_push_str why `[github] redact: not a pattern: ` )
                        ( string_push_str why ( string_data pat ) )
                        ^ F
                    }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    : i nm ( vec_len [String] mirror )
    : ~ i j 0
    ~ < j nm {
        ?? ( vec_get [String] mirror j ) {
            T m → {
                ? ( _gh_repo_in repos ( string_data m ) ) {} {
                    ( string_push_str why `[github] mirror: ` )
                    ( string_push_str why ( string_data m ) )
                    ( string_push_str why ` is not in repos` )
                    ^ F
                }
            }
            F _ → {}
        }
        = j + j 1
    }
    ? & > nm 0 == ( string_len ( _gh_slug ) ) 0 { ( string_push_str why `[github] mirror: the app file needs the App's slug (from the manifest answer)` ) ^ F } {}
    : String alert ( ag_config_str cfg `github.mirror_alert` `` )
    ( ag_gh_mirror_configure mirror ( ag_config_bool cfg `github.dry_run` T ) redact ( string_data alert ) )
    ^ T
}

// The same from values (tests, and ag_gh_apply_config).
@ ag_gh_configure i app_id s secret i installation s key_path s org ( Vec String ) repos s merge_channel ( Vec String ) workflows s api → v {
    : ( Vec String ) keys ( vec_new [String] )
    : b oidc ( ag_auth_oidc )
    : i n ( vec_len [String] repos )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] repos k ) { T r → { ( vec_push [String] keys ? oidc ( gh_repo_key ( string_data r ) ) ( string_new ) ) } F _ → {} }
        = k + k 1
    }
    ( ag_gh_set_routes > n 0 keys )
    : AgGhConf old ( locked_take [AgGhConf] g_gh_conf )
    ( locked_restore [AgGhConf] g_gh_conf @ AgGhConf { > n 0 app_id ( string_from secret ) installation ( string_from key_path ) ( string_from org )
        ( _gh_strs_clone repos ) ( string_from merge_channel ) ( _gh_strs_clone workflows ) ( string_from api ) } )
}

@ ag_gh_off → v {
    ( ag_gh_set_routes F ( vec_new [String] ) )
    : AgGhConf old ( locked_take [AgGhConf] g_gh_conf )
    ( locked_restore [AgGhConf] g_gh_conf @ AgGhConf { F 0 ( string_new ) 0 ( string_new ) ( string_new ) ( vec_new [String] ) ( string_new ) ( vec_new [String] ) ( string_from AG_GH_API ) } )
}

@ _gh_route AgGhConf c → GhRoute { ^ @ GhRoute { ( string_clone . c merge_channel ) ( _gh_strs_clone . c workflows ) } }

// The agora file of GitHub repository `full` (signed in: the
// organisation's repository file; locally: the one file).
@ _gh_store AgGhConf c s full → AgStore {
    : String key ( gh_repo_key full )
    ? ( ag_auth_oidc ) { ^ ( ag_repo_store ( string_data . c org ) ( string_data key ) ) } {}
    ^ ( ag_store )
}

@ __gh_repo_ok AgGhConf c s full → b {
    : i n ( vec_len [String] . c repos )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . c repos k ) { T r → { ? != 0 ( nurl_str_eq ( string_data r ) full ) { ^ T } {} } F _ → {} }
        = k + k 1
    }
    ^ F
}

// ── Reception ────────────────────────────────────────────────────────

// The X-Hub-Signature-256 GitHub sends for `body` with `secret`.
@ gh_signature s secret ( Vec u ) body → String {
    : ( Vec u ) key ( vec_new [u] )
    ( bytes_extend_str key secret )
    : String out ( string_from `sha256=` )
    ( string_push_str out ( string_data ( bytes_to_hex ( hmac_sha256_pure key body ) ) ) )
    ^ out
}

// Equal, in time that does not depend on where they differ.
@ __gh_same String a String b → b {
    ? != ( string_len a ) ( string_len b ) { ^ F } {}
    : ( Slice u ) av ( slice_of_str ( string_data a ) )
    : ( Slice u ) bv ( slice_of_str ( string_data b ) )
    : i n ( string_len a )
    : ~ i diff 0
    : ~ i k 0
    ~ < k n {
        = diff | diff ^^ ( slice_byte av k ) ( slice_byte bv k )
        = k + k 1
    }
    ^ == diff 0
}

@ __gh_json_reply i status s key s value → HttpResponse {
    : Json o ( json_obj_new )
    ( json_obj_set o key ( json_str_lit value ) )
    : HttpResponse r ( response_json status o )
    ^ r
}

@ _gh_obj Json o s key → Json {
    ? ( json_is_obj o ) { ?? ( json_obj_get o key ) { T v → { ^ v } F → {} } } {}
    ^ ( json_null )
}

// GitHub's `2026-11-18T20:41:00Z` as unix seconds (0 when it is not one).
@ gh_time String iso → i {
    ?? ( time_parse_iso ( string_data iso ) ) { T t → { ^ t } F _ → { ^ 0 } }
}

// A pull_request object (from an event or the REST API) → what is kept.
@ gh_pr_from Json p → GhPr {
    : b merged | ( __gh_bool p `merged` ) > ( string_len ( _gh_s p `merged_at` ) ) 0
    : String st ( _gh_s p `state` )
    : String state ( string_from ? merged `merged` ? != 0 ( nurl_str_eq ( string_data st ) `closed` ) `closed` `open` )
    : Json head ( _gh_obj p `head` )
    // The tasks it names: in its title, or its description (read, not kept).
    : String both ( _gh_s p `title` )
    ( string_push_str both `\n` )
    ( string_push_str both ( string_data ( _gh_s p `body` ) ) )
    ^ @ GhPr { ( _gh_i p `number` ) ( _gh_s p `title` ) ( _gh_s p `html_url` ) state ( _gh_s head `sha` )
        ( string_from ? merged ( string_data ( _gh_s p `merge_commit_sha` ) ) `` ) ( gh_time ( _gh_s p `updated_at` ) ) ( gh_task_refs both ) }
}

@ __gh_bool Json o s key → b {
    ? ( json_is_obj o ) { ?? ( json_obj_get o key ) { T v → { ? ( json_is_bool v ) { ^ ( json_as_bool v ) } {} } F → {} } } {}
    ^ F
}

// A workflow_run object → what is kept.
@ gh_run_from Json w → GhRun {
    : ( Vec i ) prs ( vec_new [i] )
    : Json ps ( _gh_obj w `pull_requests` )
    ? ( json_is_arr ps ) {
        : i n ( json_arr_len ps )
        : ~ i k 0
        ~ < k n {
            ?? ( json_arr_get ps k ) { T x → { ( vec_push [i] prs ( _gh_i x `number` ) ) } F → {} }
            = k + k 1
        }
    } {}
    : i att ( _gh_i w `run_attempt` )
    ^ @ GhRun { ( _gh_i w `id` ) ? > att 0 att 1 ( _gh_s w `name` ) ( _gh_s w `head_sha` ) prs ( _gh_s w `status` )
        ( _gh_s w `conclusion` ) ( _gh_s w `html_url` ) ( gh_time ( _gh_s w `updated_at` ) ) }
}

// POST /github/webhook
@ ag_h_github_webhook HttpRequest req → HttpResponse {
    : i now ( now_seconds )
    : AgGhConf c ( _gh_conf )
    ? . c on {} { ^ ( __gh_json_reply 404 `error` `GitHub is not connected` ) }
    : ~ String event ( string_new )
    : ~ String delivery ( string_new )
    : ~ String sig ( string_new )
    ?? ( header_get . req headers `X-GitHub-Event` ) { T v → { = event v } F _ → {} }
    ?? ( header_get . req headers `X-GitHub-Delivery` ) { T v → { = delivery v } F _ → {} }
    ?? ( header_get . req headers `X-Hub-Signature-256` ) { T v → { = sig v } F _ → {} }
    // The signature first: nothing of an unsigned body is read.
    : String want ( gh_signature ( string_data . c secret ) . req body )
    ? ( __gh_same sig want ) {} { ^ ( __gh_json_reply 401 `error` `bad signature` ) }
    ? | == ( string_len event ) 0 | == ( string_len delivery ) 0 > ( string_len delivery ) 100 { ^ ( __gh_json_reply 400 `error` `X-GitHub-Event and X-GitHub-Delivery are required` ) } {}
    ? != 0 ( nurl_str_eq ( string_data event ) `ping` ) { ^ ( __gh_json_reply 200 `ok` `pong` ) } {}
    : b is_pr != 0 ( nurl_str_eq ( string_data event ) `pull_request` )
    : b is_run != 0 ( nurl_str_eq ( string_data event ) `workflow_run` )
    ? | is_pr is_run {} { ^ ( __gh_json_reply 202 `ignored` `not an event agora uses` ) }
    ?? ( json_parse_bytes . req body ) {
        F _ → { ^ ( __gh_json_reply 400 `error` `the body is not JSON` ) }
        T j → {
            // Bound to the App's installation and to the repository by
            // GitHub's own ids, not by anything a body could make up.
            : i inst ( _gh_i ( _gh_obj j `installation` ) `id` )
            ? & > . c installation 0 != inst . c installation { ^ ( __gh_json_reply 403 `error` `another installation` ) } {}
            : Json repo ( _gh_obj j `repository` )
            : String full ( string_to_lower ( _gh_s repo `full_name` ) )
            ? ( __gh_repo_ok c ( string_data full ) ) {} { ^ ( __gh_json_reply 202 `ignored` `repository not connected` ) }
            : i rid ( _gh_i repo `id` )
            : AgStore st ( ag_store_conn ( _gh_store c ( string_data full ) ) )
            ? . st ok {} { ^ ( __gh_json_reply 503 `error` `the repository's agora could not be opened` ) }
            : GhHealth bound ( ag_gh_health_get st `repo_id` )
            ? & > . bound ts 0 != . bound ts rid { ^ ( __gh_json_reply 403 `error` `repository id does not match the connected one` ) } {}
            ? == . bound ts 0 { ( ag_gh_health_set st `repo_id` rid ( string_data full ) ) } {}
            : Json norm ? is_pr ( gh_pr_json ( gh_pr_from ( _gh_obj j `pull_request` ) ) ) ( gh_run_json ( gh_run_from ( _gh_obj j `workflow_run` ) ) )
            : String data ( json_stringify norm )
            : i rc ( ag_gh_accept st ( string_data delivery ) ( string_data event ) ( string_data data ) now )
            ? == rc AG_GH_FULL { ^ ( __gh_json_reply 503 `error` `queue full; retry later` ) } {}
            ? < rc 0 { ^ ( __gh_json_reply 500 `error` `could not store the delivery` ) } {}
            ( ag_gh_health_set st `receipt` now ( string_data event ) )
            ^ ( __gh_json_reply 202 `accepted` ? == rc AG_GH_ACCEPTED `stored` `already stored` )
        }
    }
}

// ── The App's identity ───────────────────────────────────────────────

// The DigestInfo of a SHA-256 digest (RFC 8017 §9.2, note 1).
@ __gh_digest_info → ( Vec u ) {
    ?? ( bytes_from_hex `3031300d060960864801650304020105000420` ) { T v → { ^ v } F _ → { ^ ( vec_new [u] ) } }
}

// An RS256 JWT (RFC 7519) naming the App, good for ~9 minutes: what
// GitHub wants to hand out an installation token. '' when the key will
// not load.
@ gh_app_jwt s key_path i app_id i now → String {
    ?? ( read_file key_path ) {
        F _ → { ^ ( string_new ) }
        T pem → {
            ?? ( rsa_priv_from_pem ( string_data pem ) ) {
                F _ → { ^ ( string_new ) }
                T pk → {
                    ?? ( rsa_priv_sign_key pk ) {
                        F → { ^ ( string_new ) }
                        T key → {
                            : String claims ( string_from `{"iat":` )
                            ( string_push_int claims - now 60 )
                            ( string_push_str claims `,"exp":` )
                            ( string_push_int claims + now 540 )
                            ( string_push_str claims `,"iss":"` )
                            ( string_push_int claims app_id )
                            ( string_push_str claims `"}` )
                            : String input ( b64_url_encode `{"alg":"RS256","typ":"JWT"}` )
                            ( string_push_str input `.` )
                            ( string_push_str input ( string_data ( b64_url_encode ( string_data claims ) ) ) )
                            : ( Vec u ) msg ( vec_new [u] )
                            ( bytes_extend_str msg ( string_data input ) )
                            : ( Vec u ) digest ( sha256_pure msg )
                            // EMSA-PKCS1-v1_5: 00 01 FF…FF 00 DigestInfo digest, k bytes.
                            : i k ( vec_len [u] ( rsa_key_n key ) )
                            : ( Vec u ) di ( __gh_digest_info )
                            : i pad - - - k 3 ( vec_len [u] di ) ( vec_len [u] digest )
                            ? < pad 8 { ^ ( string_new ) } {}
                            : ( Vec u ) em ( vec_new [u] )
                            ( vec_push [u] em # u 0 )
                            ( vec_push [u] em # u 1 )
                            : ~ i j 0
                            ~ < j pad { ( vec_push [u] em # u 255 ) = j + j 1 }
                            ( vec_push [u] em # u 0 )
                            ( vec_extend [u] em di )
                            ( vec_extend [u] em digest )
                            : ( Vec u ) sig ( _rsa_sign_raw key em )
                            ( string_push_str input `.` )
                            ( string_push_str input ( string_data ( b64_url_encode_vec sig ) ) )
                            ^ input
                        }
                    }
                }
            }
        }
    }
}

// The installation token, kept until five minutes before it expires.
: AgGhTok {
    String token
    i until
}

@ __gh_tok_blank → ( Locked AgGhTok ) { ^ ( locked_new [AgGhTok] @ AgGhTok { ( string_new ) 0 } ) }

: ( Locked AgGhTok ) g_gh_tok ( __gh_tok_blank )

: GhResp {
    i status
    String body
    i retry_at  // when GitHub says to come back (rate limit), 0 = no word
}

@ _gh_req HttpClient h s method s url s auth s body i now → GhResp {
    : ( Vec Header ) hs ( vec_new [Header] )
    ( vec_push [Header] hs ( header_new `Accept` `application/vnd.github+json` ) )
    ( vec_push [Header] hs ( header_new `X-GitHub-Api-Version` `2022-11-28` ) )
    ( vec_push [Header] hs ( header_new `User-Agent` `nurl-agora` ) )
    ? > ( nurl_str_len auth ) 0 { ( vec_push [Header] hs ( header_new `Authorization` auth ) ) } {}
    : ( Vec u ) b ( vec_new [u] )
    ? > ( nurl_str_len body ) 0 {
        ( bytes_extend_str b body )
        ( vec_push [Header] hs ( header_new `Content-Type` `application/json` ) )
    } {}
    ?? ( http_client_request h method url hs b ) {
        F e → { ^ @ GhResp { 0 ( string_from ( http_client_err_name e ) ) 0 } }
        T r → {
            : i st ( http_client_status r )
            : ~ i retry 0
            : String ra ( http_client_header r `Retry-After` )
            ? > ( string_len ra ) 0 { = retry + now ( nurl_str_to_int ( string_data ra ) ) } {}
            : String rem ( http_client_header r `X-RateLimit-Remaining` )
            : String reset ( http_client_header r `X-RateLimit-Reset` )
            ? & & == retry 0 != 0 ( nurl_str_eq ( string_data rem ) `0` ) > ( string_len reset ) 0 { = retry ( nurl_str_to_int ( string_data reset ) ) } {}
            ^ @ GhResp { st ( http_client_body_str r ) retry }
        }
    }
}

// A client for GitHub's API: bounded, and never following a redirect,
// which would carry the Authorization header to wherever it points.
@ _gh_client → HttpClient {
    : HttpClient h ( http_client_new )
    ( http_client_set_timeout h 15000 )
    ( http_client_set_follow h F )
    ^ h
}

// `token <installation token>`, fetched when the kept one is near its end.
@ _gh_auth HttpClient h AgGhConf c i now → GhResp {
    : AgGhTok t ( locked_take [AgGhTok] g_gh_tok )
    : b fresh & > ( string_len . t token ) 0 > . t until now
    : String kept ( string_clone . t token )
    ( locked_restore [AgGhTok] g_gh_tok t )
    ? fresh {
        : String a ( string_from `token ` )
        ( string_push_str a ( string_data kept ) )
        ^ @ GhResp { 200 a 0 }
    } {}
    : String jwt ( gh_app_jwt ( string_data . c key_path ) . c app_id now )
    ? == ( string_len jwt ) 0 { ^ @ GhResp { 0 ( string_from `the App's private key would not sign` ) 0 } } {}
    : String url ( string_clone . c api )
    ( string_push_str url `/app/installations/` )
    ( string_push_int url . c installation )
    ( string_push_str url `/access_tokens` )
    : String bearer ( string_from `Bearer ` )
    ( string_push_str bearer ( string_data jwt ) )
    : GhResp r ( _gh_req h `POST` ( string_data url ) ( string_data bearer ) `` now )
    ? != . r status 201 { ^ r } {}
    ?? ( json_parse ( string_data . r body ) ) {
        F _ → { ^ @ GhResp { 0 ( string_from `the token answer was not JSON` ) 0 } }
        T j → {
            : String tok ( _gh_s j `token` )
            : i exp ( gh_time ( _gh_s j `expires_at` ) )
            : AgGhTok o ( locked_take [AgGhTok] g_gh_tok )
            ( locked_restore [AgGhTok] g_gh_tok @ AgGhTok { ( string_clone tok ) - ? > exp 0 exp + now 3600 300 } )
            : String a ( string_from `token ` )
            ( string_push_str a ( string_data tok ) )
            ^ @ GhResp { 200 a 0 }
        }
    }
}

// `http://127.0.0.1`, `http://[::1]` or `http://localhost`, then nothing,
// `:` or `/` — a loopback stand-in, not `http://localhost.example.com`.
@ _gh_loopback_url String u → b {
    : ( Vec String ) hosts ( vec_new [String] )
    ( vec_push [String] hosts ( string_from `http://127.0.0.1` ) )
    ( vec_push [String] hosts ( string_from `http://[::1]` ) )
    ( vec_push [String] hosts ( string_from `http://localhost` ) )
    : i n ( vec_len [String] hosts )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] hosts k ) {
            T h → {
                ? ( string_starts_with u ( string_data h ) ) {
                    : i hl ( string_len h )
                    ? == ( string_len u ) hl { ^ T } {}
                    : String nx ( string_substr u hl 1 )
                    ? | ( string_eq nx ( string_from `:` ) ) ( string_eq nx ( string_from `/` ) ) { ^ T } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// ── Asking GitHub ────────────────────────────────────────────────────

// Not before this time (a rate limit or an error said so).
: AgGhBackoff {
    i until
    i fails
}

@ __gh_bo_blank → ( Locked AgGhBackoff ) { ^ ( locked_new [AgGhBackoff] @ AgGhBackoff { 0 0 } ) }

: ( Locked AgGhBackoff ) g_gh_bo ( __gh_bo_blank )

@ _gh_bo_ok i now → b {
    : AgGhBackoff b ( locked_take [AgGhBackoff] g_gh_bo )
    : b ok >= now . b until
    ( locked_restore [AgGhBackoff] g_gh_bo b )
    ^ ok
}

@ _gh_bo_note b failed i retry_at i now → v {
    : AgGhBackoff b ( locked_take [AgGhBackoff] g_gh_bo )
    ? failed {
        : i n + . b fails 1
        : ~ i wait 60
        : ~ i k 1
        ~ & < k n < wait 3600 { = wait * wait 2 = k + k 1 }
        : i until ? > retry_at now retry_at + now wait
        ( locked_restore [AgGhBackoff] g_gh_bo @ AgGhBackoff { until n } )
    } { ( locked_restore [AgGhBackoff] g_gh_bo @ AgGhBackoff { 0 0 } ) }
}

// A health change is told once to everyone watching something here.
@ __gh_health_note AgStore st b ok s why i now → v {
    : GhHealth h ( ag_gh_health_get st `status` )
    : b was_bad != 0 ( nurl_str_eq ( string_data . h text ) `error` )
    ? ok {
        ( ag_gh_health_set st `reconcile` now `` )
        ( ag_gh_health_set st `error` 0 `` )
        ? was_bad {
            ( ag_gh_health_set st `status` now `ok` )
            : String key ( string_from `health:ok:` )
            ( string_push_int key now )
            ( ag_gh_tell_all st ( string_data key ) `github: agora reaches GitHub again; PR and CI notices are current` now )
        } {}
    } {
        ( ag_gh_health_set st `error` now why )
        ? was_bad {} {
            ( ag_gh_health_set st `status` now `error` )
            : String key ( string_from `health:error:` )
            ( string_push_int key now )
            : String t ( string_from `github: agora cannot reach GitHub (` )
            ( string_push_str t ( string_data ( gh_line ( string_from why ) 120 ) ) )
            ( string_push_str t `); PR and CI notices may come late — pr_watches shows the state` )
            ( ag_gh_tell_all st ( string_data key ) ( string_data t ) now )
        }
    }
}

// Bring the watched PRs of repository `full` up to date from GitHub:
// `only_new` just those agora has never seen (a fresh watch). F when
// GitHub could not be asked.
@ ag_gh_reconcile AgGhConf c s full b only_new i now → b {
    ? ( _gh_bo_ok now ) {} { ^ F }
    : AgStore st ( _gh_store c full )
    ? . st ok {} { ^ F }
    : ( Vec i ) prs ( ag_gh_watched_prs st now )
    : ( Vec i ) todo ( vec_new [i] )
    : i n ( vec_len [i] prs )
    : ~ i k 0
    ~ < k n {
        : i p ?? ( vec_get [i] prs k ) { T x → x F _ → 0 }
        ? | ! only_new ! ( ag_gh_pr_asked st p ) { ( vec_push [i] todo p ) } {}
        = k + k 1
    }
    ? == ( vec_len [i] todo ) 0 {
        ? only_new {} { ( ag_gh_health_set st `reconcile` now `` ) }
        ^ T
    } {}
    : HttpClient h ( _gh_client )
    : GhResp a ( _gh_auth h c now )
    ? != . a status 200 {
        ( _gh_bo_note T . a retry_at now )
        : String why ( string_from `installation token: ` )
        ? > . a status 0 { ( string_push_str why `HTTP ` ) ( string_push_int why . a status ) } { ( string_push_str why ( string_data . a body ) ) }
        ( __gh_health_note st F ( string_data why ) now )
        ^ F
    } {}
    : GhRoute rt ( _gh_route c )
    : i m ( vec_len [i] todo )
    : ~ String miss ( string_new )
    : ~ i x 0
    ~ < x m {
        : i p ?? ( vec_get [i] todo x ) { T y → y F _ → 0 }
        : b silent ! ( ag_gh_pr_known st p )
        : String url ( string_clone . c api )
        ( string_push_str url `/repos/` )
        ( string_push_str url full )
        ( string_push_str url `/pulls/` )
        ( string_push_int url p )
        : GhResp r ( _gh_req h `GET` ( string_data url ) ( string_data . a body ) `` now )
        ? == . r status 404 {
            // No such PR — or the App lost access to it: GitHub answers the
            // same. Keep the watches (they expire by themselves) and say so.
            = miss ( string_from `GET pulls/` )
            ( string_push_int miss p )
            ( string_push_str miss `: HTTP 404 (no such PR, or the App cannot see it)` )
            // Known from now on (an open placeholder, no head): asked again
            // with every watched PR, every 10 minutes, not every second.
            ( ag_gh_pr_placeholder st p now )
        } {
            ? != . r status 200 {
                ( _gh_bo_note T . r retry_at now )
                : String why ( string_from `GET pulls/` )
                ( string_push_int why p )
                ( string_push_str why `: ` )
                ? > . r status 0 { ( string_push_str why `HTTP ` ) ( string_push_int why . r status ) } { ( string_push_str why ( string_data . r body ) ) }
                ( __gh_health_note st F ( string_data why ) now )
                ^ F
            } {}
            ?? ( json_parse ( string_data . r body ) ) {
                F _ → {}
                T j → {
                    : GhPr pr ( gh_pr_from j )
                    : String head ( string_clone . pr head )
                    ( ag_gh_apply st ( string_data ( json_stringify ( gh_pr_json pr ) ) ) rt silent now )
                    // The runs of its current head; older heads are not asked about.
                    : String ru ( string_clone . c api )
                    ( string_push_str ru `/repos/` )
                    ( string_push_str ru full )
                    ( string_push_str ru `/actions/runs?per_page=50&head_sha=` )
                    ( string_push_str ru ( string_data head ) )
                    : GhResp rr ( _gh_req h `GET` ( string_data ru ) ( string_data . a body ) `` now )
                    ? != . rr status 200 {
                        ( _gh_bo_note T . rr retry_at now )
                        : String why ( string_from `GET actions/runs for pulls/` )
                        ( string_push_int why p )
                        ( string_push_str why `: ` )
                        ? > . rr status 0 { ( string_push_str why `HTTP ` ) ( string_push_int why . rr status ) } { ( string_push_str why ( string_data . rr body ) ) }
                        ( __gh_health_note st F ( string_data why ) now )
                        ^ F
                    } {}
                    ? == . rr status 200 {
                        ?? ( json_parse ( string_data . rr body ) ) {
                            F _ → {}
                            T rj → {
                                : Json runs ( _gh_obj rj `workflow_runs` )
                                : i nr ? ( json_is_arr runs ) ( json_arr_len runs ) 0
                                // Oldest first, so the newest attempt is applied last.
                                : ~ i q - nr 1
                                ~ >= q 0 {
                                    ?? ( json_arr_get runs q ) {
                                        T w → { ( ag_gh_apply st ( string_data ( json_stringify ( gh_run_json ( gh_run_from w ) ) ) ) rt silent now ) }
                                        F → {}
                                    }
                                    = q - q 1
                                }
                            }
                        }
                    } {}
                }
            }
        }
        = x + x 1
    }
    ( _gh_bo_note F 0 now )
    // Healthy only when every watched PR could be read.
    ? > ( string_len miss ) 0 { ( ag_gh_health_set st `error` now ( string_data miss ) ) } { ( __gh_health_note st T `` now ) }
    ^ T
}
