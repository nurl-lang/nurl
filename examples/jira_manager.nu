// examples/jira_manager.nu — a direct port of jira_manager.py.
//
// Monipuolinen Jira-CLI: projektien listaus + kartoitus, issuen haku,
// statuksen vaihto, kommentointi, kuvauksen muokkaus, tiketin luonti,
// JQL-haku ja "omat issuet". Käyttää Jira REST API v3:a, Basic Auth
// (base64 email:token), ja ADF-muotoa kommenteille/kuvauksille — täsm
// kuten Python-versio.
//
// Konfiguraatio ympäristömuuttujista:
//   JIRA_URL       = https://your-domain.atlassian.net
//   JIRA_EMAIL     = your-email@example.com
//   JIRA_API_TOKEN = your-api-token
//
// Käyttö:
//   nurl jira_manager.nu list-projects
//   nurl jira_manager.nu map-projects
//   nurl jira_manager.nu my-issues [--status S] [--project P] [--max-results N]
//   nurl jira_manager.nu get HAL-123
//   nurl jira_manager.nu transitions HAL-123
//   nurl jira_manager.nu assign HAL-123
//   nurl jira_manager.nu status HAL-123 "In Progress"
//   nurl jira_manager.nu comment HAL-123 "kommentti"
//   nurl jira_manager.nu edit-desc HAL-123 "uusi kuvaus"
//   nurl jira_manager.nu create "Summary" --project HAL --type Task --description "Kuvaus"
//   nurl jira_manager.nu search "project = HAL AND status = 'In Progress'"

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/std/fs.nu`

// ── Errors ────────────────────────────────────────────────────────

: | JiraErr {
    JiraConfigMissing  // env-muuttujat puuttuvat
    JiraHttp  // verkkovirhe (curl)
    JiraJson  // vastauksen JSON ei jäsenny
    JiraAuth  // 401 — tarkista email/token
    JiraNotFound  // 404 — resurssia ei ole / ei oikeuksia
    JiraApi  // muu >=400 API-virhe
    JiraOther
}

@ jira_err_name JiraErr e → s {
    ^ ?? e {
        JiraConfigMissing → `JiraConfigMissing`
        JiraHttp → `JiraHttp`
        JiraJson → `JiraJson`
        JiraAuth → `JiraAuth`
        JiraNotFound → `JiraNotFound`
        JiraApi → `JiraApi`
        JiraOther → `JiraOther`
    }
}

// ── Konfiguraatio ─────────────────────────────────────────────────
//
// `url`     — base-URL ilman trailing slashia.
// `headers` — valmis headers-blob (Authorization/Accept/Content-Type).

: JiraConfig { String url String headers }

@ jira_config_free JiraConfig c → v {
    ( string_free . c url )
    ( string_free . c headers )
}

// Riisu trailing slash base-URL:sta.
@ __jira_trim_slash s raw → String {
    : i n ( nurl_str_len raw )
    ? & > n 0 == ( nurl_str_get raw - n 1 ) 47
    { ^ ( string_from_bytes # *u raw - n 1 ) }
    { ^ ( string_from raw ) }
}

// Build the config from env vars. All three must be set, else
// JiraConfigMissing. Uses `??` to unwrap each `?String` (the idiomatic
// option access — there is no generic `opt_unwrap`).
@ jira_config_from_env → !JiraConfig JiraErr {
    : ?String ou ( env_get `JIRA_URL` )
    ?? ou {
        F → { ^ @ !JiraConfig JiraErr { F # JiraErr JiraConfigMissing } }
        T url_raw → {
            : ?String oe ( env_get `JIRA_EMAIL` )
            ?? oe {
                F → {
                    ( string_free url_raw )
                    ^ @ !JiraConfig JiraErr { F # JiraErr JiraConfigMissing }
                }
                T email → {
                    : ?String ot ( env_get `JIRA_API_TOKEN` )
                    ?? ot {
                        F → {
                            ( string_free url_raw ) ( string_free email )
                            ^ @ !JiraConfig JiraErr { F # JiraErr JiraConfigMissing }
                        }
                        T token → {
                            : String url ( __jira_trim_slash ( string_data url_raw ) )
                            // Basic Auth: base64(email:token).
                            : String pair ( string_with_cap 128 )
                            ( string_push_str pair ( string_data email ) )
                            ( string_push_str pair `:` )
                            ( string_push_str pair ( string_data token ) )
                            : String b64 ( b64_encode ( string_data pair ) )
                            : String headers ( string_with_cap 256 )
                            ( string_push_str headers `Authorization: Basic ` )
                            ( string_push_str headers ( string_data b64 ) )
                            ( string_push_str headers `\r\n` )
                            ( string_push_str headers `Accept: application/json\r\n` )
                            ( string_push_str headers `Content-Type: application/json; charset=utf-8\r\n` )
                            ( string_free url_raw ) ( string_free email ) ( string_free token )
                            ( string_free pair ) ( string_free b64 )
                            : JiraConfig cfg @ JiraConfig { url headers }
                            ^ @ !JiraConfig JiraErr { T cfg }
                        }
                    }
                }
            }
        }
    }
    ^ @ !JiraConfig JiraErr { F # JiraErr JiraOther }
}

// ── HTTP-ydin (_make_request) ─────────────────────────────────────
//
// Tekee pyynnön, tarkistaa statuksen ja jäsentää vastauksen JSON:ksi.
// Tyhjä vastaus (204) → tyhjä JSON-objekti onnistumismerkkinä.

@ __jira_status_to_err i st → JiraErr {
    ? == st 401 { ^ # JiraErr JiraAuth } {}
    ? == st 404 { ^ # JiraErr JiraNotFound } {}
    ^ # JiraErr JiraApi
}

@ jira_request JiraConfig cfg s method s endpoint s body → !Json JiraErr {
    : String url ( string_with_cap 256 )
    ( string_push_str url ( string_data . cfg url ) )
    ( string_push_str url endpoint )

    : !Response HttpErr res
    ( http_request method ( string_data url ) body ( string_data . cfg headers ) )
    ( string_free url )

    ?? res {
        F _he → { ^ @ !Json JiraErr { F # JiraErr JiraHttp } }
        T r → {
            : i st ( http_status r )
            : String body_owned ( string_from ( http_body_str r ) )
            ( response_free r )

            // Tyhjä runko (esim. 204) onnistumisella → tyhjä objekti.
            ? & < st 300 == 0 ( string_len body_owned ) {
                ( string_free body_owned )
                ^ @ !Json JiraErr { T ( json_obj_new ) }
            } {}

            : !Json JsonError pj ( json_parse ( string_data body_owned ) )
            ( string_free body_owned )
            ?? pj {
                F _je → { ^ @ !Json JiraErr { F # JiraErr JiraJson } }
                T j → {
                    ? >= st 400 {
                        ( json_free j )
                        ^ @ !Json JiraErr { F ( __jira_status_to_err st ) }
                    } {}
                    ^ @ !Json JiraErr { T j }
                }
            }
        }
    }
    ^ @ !Json JiraErr { F # JiraErr JiraOther }
}

// ── ADF (Atlassian Document Format) ───────────────────────────────

@ __jira_adf_doc s text → Json {
    : Json textnode ( json_obj_new )
    : b _1 ( json_obj_set textnode `type` ( json_str_lit `text` ) )
    : b _2 ( json_obj_set textnode `text` ( json_str_lit text ) )
    : Json para_content ( json_arr_new )
    : b _3 ( json_arr_push para_content textnode )
    : Json para ( json_obj_new )
    : b _4 ( json_obj_set para `type` ( json_str_lit `paragraph` ) )
    : b _5 ( json_obj_set para `content` para_content )
    : Json content ( json_arr_new )
    : b _6 ( json_arr_push content para )
    : Json doc ( json_obj_new )
    : b _7 ( json_obj_set doc `type` ( json_str_lit `doc` ) )
    : b _8 ( json_obj_set doc `version` ( json_int 1 ) )
    : b _9 ( json_obj_set doc `content` content )
    ^ doc
}

// ── Operaatiot ────────────────────────────────────────────────────

@ jira_get_issue JiraConfig cfg s key → !Json JiraErr {
    : String ep ( string_with_cap 64 )
    ( string_push_str ep `/rest/api/3/issue/` )
    ( string_push_str ep key )
    : !Json JiraErr r ( jira_request cfg `GET` ( string_data ep ) `` )
    ( string_free ep )
    ^ r
}

@ jira_get_transitions JiraConfig cfg s key → !Json JiraErr {
    : String ep ( string_with_cap 64 )
    ( string_push_str ep `/rest/api/3/issue/` )
    ( string_push_str ep key )
    ( string_push_str ep `/transitions` )
    : !Json JiraErr r ( jira_request cfg `GET` ( string_data ep ) `` )
    ( string_free ep )
    ^ r
}

// Etsi transition-id annetulle status-nimelle (case-insensitive: vertaa
// transition.name TAI transition.to.name). Palauta OMISTETTU id-String,
// tai tyhjä String jos ei löydy.
@ __jira_find_transition Json transitions s status → String {
    : i n ( json_arr_len transitions )
    : ~ i i 0
    ~ < i n {
        : ?Json ot ( json_arr_get transitions i )
        ?? ot {
            F → {}
            T t → {
                : String tname ( __jira_json_field_str t `name` )
                : String toname ( __jira_json_path_str t `to` `name` )
                : b matched | ( __jira_ieq ( string_data tname ) status )
                ( __jira_ieq ( string_data toname ) status )
                ( string_free tname ) ( string_free toname )
                ? matched {
                    ^ ( __jira_json_field_str t `id` )
                } {}
            }
        }
        = i + i 1
    }
    ^ ( string_from `` )
}

@ jira_change_status JiraConfig cfg s key s status → !Json JiraErr {
    : !Json JiraErr tr ( jira_get_transitions cfg key )
    ?? tr {
        F e → { ^ @ !Json JiraErr { F e } }
        T tjson → {
            : ?Json otrans ( json_obj_get tjson `transitions` )
            : ~ String tid ( string_from `` )
            ?? otrans {
                F → {}
                T trans → {
                    : String found ( __jira_find_transition trans status )
                    ( string_free tid )
                    = tid found
                }
            }
            ( json_free tjson )
            ? == 0 ( string_len tid ) {
                ( string_free tid )
                ^ @ !Json JiraErr { F # JiraErr JiraNotFound }
            } {}
            // POST { transition: { id: <tid> } }
            : Json inner ( json_obj_new )
            : b _a ( json_obj_set inner `id` ( json_str_lit ( string_data tid ) ) )
            : Json body ( json_obj_new )
            : b _b ( json_obj_set body `transition` inner )
            : String bs ( json_stringify body )
            ( json_free body )
            ( string_free tid )
            : String ep ( string_with_cap 64 )
            ( string_push_str ep `/rest/api/3/issue/` )
            ( string_push_str ep key )
            ( string_push_str ep `/transitions` )
            : !Json JiraErr r ( jira_request cfg `POST` ( string_data ep ) ( string_data bs ) )
            ( string_free ep ) ( string_free bs )
            ^ r
        }
    }
}

@ jira_assign_to_me JiraConfig cfg s key → !Json JiraErr {
    : Json body ( json_obj_new )
    : b _a ( json_obj_set body `accountId` ( json_str_lit `-1` ) )
    : String bs ( json_stringify body )
    ( json_free body )
    : String ep ( string_with_cap 64 )
    ( string_push_str ep `/rest/api/3/issue/` )
    ( string_push_str ep key )
    ( string_push_str ep `/assignee` )
    : !Json JiraErr r ( jira_request cfg `PUT` ( string_data ep ) ( string_data bs ) )
    ( string_free ep ) ( string_free bs )
    ^ r
}

@ jira_add_comment JiraConfig cfg s key s text → !Json JiraErr {
    : Json body ( json_obj_new )
    : b _a ( json_obj_set body `body` ( __jira_adf_doc text ) )
    : String bs ( json_stringify body )
    ( json_free body )
    : String ep ( string_with_cap 64 )
    ( string_push_str ep `/rest/api/3/issue/` )
    ( string_push_str ep key )
    ( string_push_str ep `/comment` )
    : !Json JiraErr r ( jira_request cfg `POST` ( string_data ep ) ( string_data bs ) )
    ( string_free ep ) ( string_free bs )
    ^ r
}

@ jira_update_description JiraConfig cfg s key s text → !Json JiraErr {
    : Json fields ( json_obj_new )
    : b _a ( json_obj_set fields `description` ( __jira_adf_doc text ) )
    : Json body ( json_obj_new )
    : b _b ( json_obj_set body `fields` fields )
    : String bs ( json_stringify body )
    ( json_free body )
    : String ep ( string_with_cap 64 )
    ( string_push_str ep `/rest/api/3/issue/` )
    ( string_push_str ep key )
    : !Json JiraErr r ( jira_request cfg `PUT` ( string_data ep ) ( string_data bs ) )
    ( string_free ep ) ( string_free bs )
    ^ r
}

// Default parameters mirror the Python `issue_type='Task', description=''`
// — API callers can write `( jira_create_issue cfg key summary )` or use
// named arguments, e.g. `( jira_create_issue cfg key summary issue_type: `Bug` )`.
@ jira_create_issue JiraConfig cfg s project s summary s issue_type = `Task` s description = `` → !Json JiraErr {
    : Json proj ( json_obj_new )
    : b _p ( json_obj_set proj `key` ( json_str_lit project ) )
    : Json itype ( json_obj_new )
    : b _i ( json_obj_set itype `name` ( json_str_lit issue_type ) )
    : Json fields ( json_obj_new )
    : b _f1 ( json_obj_set fields `project` proj )
    : b _f2 ( json_obj_set fields `summary` ( json_str_lit summary ) )
    : b _f3 ( json_obj_set fields `issuetype` itype )
    ? != 0 ( nurl_str_len description ) {
        : b _f4 ( json_obj_set fields `description` ( __jira_adf_doc description ) )
    } {}
    : Json body ( json_obj_new )
    : b _b ( json_obj_set body `fields` fields )
    : String bs ( json_stringify body )
    ( json_free body )
    : !Json JiraErr r ( jira_request cfg `POST` `/rest/api/3/issue` ( string_data bs ) )
    ( string_free bs )
    ^ r
}

@ jira_search_issues JiraConfig cfg s jql i max_results s fields → !Json JiraErr {
    : String enc ( percent_encode jql )
    : String ep ( string_with_cap 128 )
    ( string_push_str ep `/rest/api/3/search/jql?jql=` )
    ( string_push_str ep ( string_data enc ) )
    ( string_push_str ep `&maxResults=` )
    ( string_push_str ep ( nurl_str_int max_results ) )
    ? != 0 ( nurl_str_len fields ) {
        ( string_push_str ep `&fields=` )
        ( string_push_str ep ( string_data ( percent_encode fields ) ) )
    } {}
    : !Json JiraErr r ( jira_request cfg `GET` ( string_data ep ) `` )
    ( string_free ep ) ( string_free enc )
    ^ r
}

// Rakenna JQL omille issueille ja hae.
@ jira_get_my_issues JiraConfig cfg s status s project i max_results → !Json JiraErr {
    : String jql ( string_with_cap 128 )
    ( string_push_str jql `assignee = currentUser()` )
    ? != 0 ( nurl_str_len status ) {
        ( string_push_str jql ` AND status = "` )
        ( string_push_str jql status )
        ( string_push_str jql `"` )
    } {}
    ? != 0 ( nurl_str_len project ) {
        ( string_push_str jql ` AND project = ` )
        ( string_push_str jql project )
    } {}
    : !Json JiraErr r ( jira_search_issues cfg ( string_data jql ) max_results `key,status,summary` )
    ( string_free jql )
    ^ r
}

@ jira_list_projects JiraConfig cfg → !Json JiraErr {
    ^ ( jira_request cfg `GET` `/rest/api/3/project` `` )
}

// ── map-projects: kartoita statuskentät + tallenna kotikansioon ───

// Lisää nimi string-taulukkoon ellei jo ole (case-insensitive).
@ __jira_arr_add_unique Json arr s name → v {
    : i n ( json_arr_len arr )
    : ~ i i 0
    ~ < i n {
        : ?Json oe ( json_arr_get arr i )
        ?? oe {
            F → {}
            T e → { ? ( json_is_str e ) { ? ( __jira_ieq ( json_str_data e ) name ) { ^ v } {} } {} }
        }
        = i + i 1
    }
    : b _ad ( json_arr_push arr ( json_str_lit name ) )
}

// status_transitions[sname] += toname (luo taulukko tarvittaessa).
@ __jira_trans_add Json transitions s sname s toname → v {
    ? == 0 ( nurl_str_len toname ) { ^ v } {}
    : ?Json oa ( json_obj_get transitions sname )
    ?? oa {
        T arr → { ( __jira_arr_add_unique arr toname ) }
        F → {
            : Json arr ( json_arr_new )
            ( __jira_arr_add_unique arr toname )
            : b _t ( json_obj_set transitions sname arr )
        }
    }
}

// Käsittele yksi status: lisää statuses-objektiin (id→name) ja kerää sen
// untilStatuses-siirtymät transitions-objektiin.
@ __jira_collect_status Json st Json statuses Json transitions → v {
    : String sid ( __jira_json_field_str st `id` )
    : String sname ( __jira_json_field_str st `name` )
    ? & != 0 ( string_len sid ) ! ( json_obj_has statuses ( string_data sid ) ) {
        : b _s ( json_obj_set statuses ( string_data sid ) ( json_str_lit ( string_data sname ) ) )
    } {}
    : ?Json ou ( json_obj_get st `untilStatuses` )
    ?? ou {
        F → {}
        T untils → {
            ? ( json_is_arr untils ) {
                : i nu ( json_arr_len untils )
                : ~ i ui 0
                ~ < ui nu {
                    : ?Json oe ( json_arr_get untils ui )
                    ?? oe {
                        F → {}
                        T u → {
                            : String un ( __jira_json_field_str u `name` )
                            ( __jira_trans_add transitions ( string_data sname ) ( string_data un ) )
                            ( string_free un )
                        }
                    }
                    = ui + ui 1
                }
            } {}
        }
    }
    ( string_free sid ) ( string_free sname )
}

// Käsittele yhden issue-typen statukset.
@ __jira_collect_issue_type Json itd Json statuses Json issue_types Json transitions → v {
    : String itname ( __jira_json_field_str itd `name` )
    ? != 0 ( string_len itname ) { ( __jira_arr_add_unique issue_types ( string_data itname ) ) } {}
    ( string_free itname )
    : ?Json ost ( json_obj_get itd `statuses` )
    ?? ost {
        F → {}
        T sts → {
            ? ( json_is_arr sts ) {
                : i ns ( json_arr_len sts )
                : ~ i si 0
                ~ < si ns {
                    : ?Json os ( json_arr_get sts si )
                    ?? os { F → {} T st → { ( __jira_collect_status st statuses transitions ) } }
                    = si + si 1
                }
            } {}
        }
    }
}

// Kartoita yksi projekti ja lisää tulos project_map:iin avaimella pkey.
@ __jira_map_one_project JiraConfig cfg Json project_map Json proj s pkey → v {
    : String ep ( string_with_cap 64 )
    ( string_push_str ep `/rest/api/3/project/` )
    ( string_push_str ep pkey )
    ( string_push_str ep `/statuses` )
    : !Json JiraErr sr ( jira_request cfg `GET` ( string_data ep ) `` )
    ( string_free ep )
    ?? sr {
        F _e → {}  // ohita virheelliset projektit (Python kerää varoitukset)
        T sjson → {
            : Json statuses ( json_obj_new )
            : Json issue_types ( json_arr_new )
            : Json transitions ( json_obj_new )
            ? ( json_is_arr sjson ) {
                : i nt ( json_arr_len sjson )
                : ~ i ti 0
                ~ < ti nt {
                    : ?Json oit ( json_arr_get sjson ti )
                    ?? oit { F → {} T itd → { ( __jira_collect_issue_type itd statuses issue_types transitions ) } }
                    = ti + ti 1
                }
            } {}
            ( json_free sjson )
            : String pname ( __jira_json_field_str proj `name` )
            : String pid ( __jira_json_field_str proj `id` )
            : Json entry ( json_obj_new )
            : b _1 ( json_obj_set entry `id` ( json_str_lit ( string_data pid ) ) )
            : b _2 ( json_obj_set entry `name` ( json_str_lit ( string_data pname ) ) )
            : b _3 ( json_obj_set entry `statuses` statuses )
            : b _4 ( json_obj_set entry `status_transitions` transitions )
            : b _5 ( json_obj_set entry `issue_types` issue_types )
            : b _6 ( json_obj_set project_map pkey entry )
            ( string_free pname ) ( string_free pid )
        }
    }
}

// Polku ~/.jira_project_map.json (fallback nykyhakemistoon).
@ __jira_map_path → String {
    : ?String oh ( env_get `HOME` )
    ?? oh {
        F → { ^ ( string_from `.jira_project_map.json` ) }
        T home → {
            : String p ( string_with_cap 128 )
            ( string_push_str p ( string_data home ) )
            ( string_push_str p `/.jira_project_map.json` )
            ( string_free home )
            ^ p
        }
    }
}

@ jira_map_projects JiraConfig cfg → !Json JiraErr {
    : !Json JiraErr pr ( jira_list_projects cfg )
    ?? pr {
        F e → { ^ @ !Json JiraErr { F e } }
        T projects → {
            : Json project_map ( json_obj_new )
            ? ( json_is_arr projects ) {
                : i np ( json_arr_len projects )
                : ~ i i 0
                ~ < i np {
                    : ?Json op ( json_arr_get projects i )
                    ?? op {
                        F → {}
                        T proj → {
                            : String pkey ( __jira_json_field_str proj `key` )
                            ? != 0 ( string_len pkey ) {
                                ( __jira_map_one_project cfg project_map proj ( string_data pkey ) )
                            } {}
                            ( string_free pkey )
                        }
                    }
                    = i + i 1
                }
            } {}
            ( json_free projects )
            : String path ( __jira_map_path )
            : String js ( json_stringify project_map )
            : !v IoErr wr ( write_file ( string_data path ) ( string_data js ) )
            ( string_free js )
            ?? wr {
                F _io → {
                    ( string_free path )
                    ^ @ !Json JiraErr { F # JiraErr JiraOther }
                }
                T _ok → {}
            }
            ( nurl_print `  Tallennettu: ` ) ( nurl_print ( string_data path ) ) ( nurl_print `\n` )
            ( string_free path )
            ^ @ !Json JiraErr { T project_map }
        }
    }
}

// ── JSON-apurit ───────────────────────────────────────────────────

// Kentän string-arvo objektista; tyhjä jos puuttuu / ei merkkijono.
@ __jira_json_field_str Json j s key → String {
    : ?Json o ( json_obj_get j key )
    ?? o {
        F → { ^ ( string_from `` ) }
        T v → {
            ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) }
            { ^ ( string_from `` ) }
        }
    }
}

// j[a][b] string-arvo (sisäkkäinen objekti).
@ __jira_json_path_str Json j s a s b → String {
    : ?Json o ( json_obj_get j a )
    ?? o {
        F → { ^ ( string_from `` ) }
        T inner → { ^ ( __jira_json_field_str inner b ) }
    }
}

// Case-insensitive ASCII-vertailu kahdelle C-merkkijonolle.
@ __jira_ieq s x s y → b {
    : i nx ( nurl_str_len x )
    : i ny ( nurl_str_len y )
    ? != nx ny { ^ F } {}
    : ~ i i 0
    ~ < i nx {
        : i cx ( __jira_lower ( nurl_str_get x i ) )
        : i cy ( __jira_lower ( nurl_str_get y i ) )
        ? != cx cy { ^ F } {}
        = i + i 1
    }
    ^ T
}

@ __jira_lower i c → i {
    ? & >= c 65 <= c 90 { ^ + c 32 } {}
    ^ c
}

// ── CLI-tulostus ──────────────────────────────────────────────────

@ __jira_print_ok s msg → v {
    ( nurl_print `✓ ` ) ( nurl_print msg ) ( nurl_print `\n` )
}

@ __jira_print_err JiraErr e → v {
    ( nurl_print `✗ Virhe: ` ) ( nurl_print ( jira_err_name e ) ) ( nurl_print `\n` )
}

// Tulosta transitions-listaus.
@ __jira_print_transitions Json j → v {
    : ?Json ot ( json_obj_get j `transitions` )
    ?? ot {
        F → {}
        T trans → {
            : i n ( json_arr_len trans )
            ( nurl_print `  Mahdolliset siirtymät:\n` )
            : ~ i i 0
            ~ < i n {
                : ?Json oe ( json_arr_get trans i )
                ?? oe {
                    F → {}
                    T t → {
                        : String tn ( __jira_json_field_str t `name` )
                        : String to ( __jira_json_path_str t `to` `name` )
                        ( nurl_print `    - ` ) ( nurl_print ( string_data tn ) )
                        ( nurl_print ` -> ` ) ( nurl_print ( string_data to ) ) ( nurl_print `\n` )
                        ( string_free tn ) ( string_free to )
                    }
                }
                = i + i 1
            }
        }
    }
}

// Tulosta haun issuet: [KEY] summary - status - assignee.
@ __jira_print_issues Json j → v {
    : ?Json oi ( json_obj_get j `issues` )
    ?? oi {
        F → {}
        T issues → {
            : i n ( json_arr_len issues )
            ( nurl_print `  Löytyi ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print ` issueta:\n` )
            : ~ i i 0
            ~ < i n {
                : ?Json oe ( json_arr_get issues i )
                ?? oe {
                    F → {}
                    T iss → {
                        : String key ( __jira_json_field_str iss `key` )
                        : String summary ( __jira_json_path_str iss `fields` `summary` )
                        : String status ( __jira_issue_status iss )
                        ( nurl_print `    [` ) ( nurl_print ( string_data key ) ) ( nurl_print `] ` )
                        ( nurl_print ( string_data summary ) ) ( nurl_print ` - ` )
                        ( nurl_print ( string_data status ) ) ( nurl_print `\n` )
                        ( string_free key ) ( string_free summary ) ( string_free status )
                    }
                }
                = i + i 1
            }
        }
    }
}

// issue.fields.status.name
@ __jira_issue_status Json iss → String {
    : ?Json of ( json_obj_get iss `fields` )
    ?? of {
        F → { ^ ( string_from `` ) }
        T fields → { ^ ( __jira_json_path_str fields `status` `name` ) }
    }
}

// Tulosta projektit: [KEY] name.
@ __jira_print_projects Json j → v {
    ? ( json_is_arr j ) {
        : i n ( json_arr_len j )
        ( nurl_print `  Löytyi ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print ` projektia:\n` )
        : ~ i i 0
        ~ < i n {
            : ?Json oe ( json_arr_get j i )
            ?? oe {
                F → {}
                T p → {
                    : String key ( __jira_json_field_str p `key` )
                    : String name ( __jira_json_field_str p `name` )
                    ( nurl_print `    [` ) ( nurl_print ( string_data key ) ) ( nurl_print `] ` )
                    ( nurl_print ( string_data name ) ) ( nurl_print `\n` )
                    ( string_free key ) ( string_free name )
                }
            }
            = i + i 1
        }
    } {}
}

// ── CLI-komennot ──────────────────────────────────────────────────
//
// Kukin komento ottaa configin, suorittaa operaation ja tulostaa.
// Palauttaa exit-koodin (0 ok, 1 virhe).

@ __jira_run_simple JiraConfig cfg s ok_msg ! Json JiraErr r → i {
    ?? r {
        F e → { ( __jira_print_err e ) ^ 1 }
        T j → { ( __jira_print_ok ok_msg ) ( json_free j ) ^ 0 }
    }
}

@ cmd_get JiraConfig cfg s key → i {
    : !Json JiraErr r ( jira_get_issue cfg key )
    ?? r {
        F e → { ( __jira_print_err e ) ^ 1 }
        T j → {
            ( __jira_print_ok key )
            : String pretty ( json_stringify j )
            ( nurl_print `  ` ) ( nurl_print ( string_data pretty ) ) ( nurl_print `\n` )
            ( string_free pretty )
            ( json_free j )
            ^ 0
        }
    }
}

@ cmd_transitions JiraConfig cfg s key → i {
    : !Json JiraErr r ( jira_get_transitions cfg key )
    ?? r {
        F e → { ( __jira_print_err e ) ^ 1 }
        T j → {
            ( __jira_print_ok key )
            ( __jira_print_transitions j )
            ( json_free j )
            ^ 0
        }
    }
}

@ cmd_search JiraConfig cfg s jql → i {
    : !Json JiraErr r ( jira_search_issues cfg jql 50 `key,status,summary` )
    ?? r {
        F e → { ( __jira_print_err e ) ^ 1 }
        T j → {
            ( __jira_print_ok `Haku valmis` )
            ( __jira_print_issues j )
            ( json_free j )
            ^ 0
        }
    }
}

@ cmd_my_issues JiraConfig cfg s status s project → i {
    : !Json JiraErr r ( jira_get_my_issues cfg status project 50 )
    ?? r {
        F e → { ( __jira_print_err e ) ^ 1 }
        T j → {
            ( __jira_print_ok `Omat issuet` )
            ( __jira_print_issues j )
            ( json_free j )
            ^ 0
        }
    }
}

@ cmd_list_projects JiraConfig cfg → i {
    : !Json JiraErr r ( jira_list_projects cfg )
    ?? r {
        F e → { ( __jira_print_err e ) ^ 1 }
        T j → {
            ( __jira_print_ok `Projektit` )
            ( __jira_print_projects j )
            ( json_free j )
            ^ 0
        }
    }
}

@ cmd_map_projects JiraConfig cfg → i {
    : !Json JiraErr r ( jira_map_projects cfg )
    ?? r {
        F e → { ( __jira_print_err e ) ^ 1 }
        T j → {
            ( __jira_print_ok `Projektikartta kartoitettu` )
            ( json_free j )
            ^ 0
        }
    }
}

// ── CLI-arviointi ─────────────────────────────────────────────────

// Etsi `--flag value` -optio argv:stä; palauta arvo tai tyhjä.
@ __jira_opt s flag → String {
    : i n ( env_args_count )
    : ~ i i 0
    ~ < i n {
        : String a ( env_arg i )
        ? & ( __jira_ieq ( string_data a ) flag ) < + i 1 n {
            : String v ( env_arg + i 1 )
            ( string_free a )
            ^ v
        } {}
        ( string_free a )
        = i + i 1
    }
    ^ ( string_from `` )
}

@ usage → v {
    ( nurl_print `Käyttö: nurl jira_manager.nu <toiminto> [argumentit]\n\n` )
    ( nurl_print `Toiminnot:\n` )
    ( nurl_print `  list-projects                       Listaa projektit\n` )
    ( nurl_print `  map-projects                        Kartoita statuskentät → ~/.jira_project_map.json\n` )
    ( nurl_print `  my-issues [--status S] [--project P] Omat issuet\n` )
    ( nurl_print `  get <key>                           Issuen tiedot\n` )
    ( nurl_print `  transitions <key>                   Mahdolliset siirtymät\n` )
    ( nurl_print `  assign <key>                        Ota issue itsellesi\n` )
    ( nurl_print `  status <key> <status>               Vaihda status\n` )
    ( nurl_print `  comment <key> "<teksti>"            Lisää kommentti\n` )
    ( nurl_print `  edit-desc <key> "<kuvaus>"          Muokkaa kuvausta\n` )
    ( nurl_print `  create "<summary>" --project P [--type T] [--description D]\n` )
    ( nurl_print `  search "<jql>"                      JQL-haku\n` )
}

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 {
        ( usage )
        ^ 1
    } {}
    : String action ( env_arg 1 )

    : !JiraConfig JiraErr cr ( jira_config_from_env )
    ?? cr {
        F _e → {
            ( nurl_print `✗ Virhe: Aseta JIRA_URL, JIRA_EMAIL ja JIRA_API_TOKEN\n` )
            ( string_free action )
            ^ 1
        }
        T cfg → {
            : ~ i rc 0
            : s act ( string_data action )

            ? ( __jira_ieq act `list-projects` ) {
                = rc ( cmd_list_projects cfg )
            } {
                ? ( __jira_ieq act `map-projects` ) {
                    = rc ( cmd_map_projects cfg )
                } {
                    ? ( __jira_ieq act `my-issues` ) {
                        : String st ( __jira_opt `--status` )
                        : String pr ( __jira_opt `--project` )
                        = rc ( cmd_my_issues cfg ( string_data st ) ( string_data pr ) )
                        ( string_free st ) ( string_free pr )
                    } {
                        ? & ( __jira_ieq act `get` ) >= argc 3 {
                            : String key ( env_arg 2 )
                            = rc ( cmd_get cfg ( string_data key ) )
                            ( string_free key )
                        } {
                            ? & ( __jira_ieq act `transitions` ) >= argc 3 {
                                : String key ( env_arg 2 )
                                = rc ( cmd_transitions cfg ( string_data key ) )
                                ( string_free key )
                            } {
                                ? & ( __jira_ieq act `assign` ) >= argc 3 {
                                    : String key ( env_arg 2 )
                                    = rc ( __jira_run_simple cfg `Issue otettu itsellesi` ( jira_assign_to_me cfg ( string_data key ) ) )
                                    ( string_free key )
                                } {
                                    ? & ( __jira_ieq act `status` ) >= argc 4 {
                                        : String key ( env_arg 2 )
                                        : String stv ( env_arg 3 )
                                        = rc ( __jira_run_simple cfg `Status vaihdettu` ( jira_change_status cfg ( string_data key ) ( string_data stv ) ) )
                                        ( string_free key ) ( string_free stv )
                                    } {
                                        ? & ( __jira_ieq act `comment` ) >= argc 4 {
                                            : String key ( env_arg 2 )
                                            : String txt ( env_arg 3 )
                                            = rc ( __jira_run_simple cfg `Kommentti lisätty` ( jira_add_comment cfg ( string_data key ) ( string_data txt ) ) )
                                            ( string_free key ) ( string_free txt )
                                        } {
                                            ? & ( __jira_ieq act `edit-desc` ) >= argc 4 {
                                                : String key ( env_arg 2 )
                                                : String txt ( env_arg 3 )
                                                = rc ( __jira_run_simple cfg `Kuvaus päivitetty` ( jira_update_description cfg ( string_data key ) ( string_data txt ) ) )
                                                ( string_free key ) ( string_free txt )
                                            } {
                                                ? & ( __jira_ieq act `create` ) >= argc 3 {
                                                    : String summary ( env_arg 2 )
                                                    : String pr ( __jira_opt `--project` )
                                                    : String ty ( __jira_opt `--type` )
                                                    : String de ( __jira_opt `--description` )
                                                    ? == 0 ( string_len pr ) {
                                                        ( nurl_print `✗ Virhe: Anna projekti (--project HAL)\n` )
                                                        = rc 1
                                                    } {
                                                        // Uses keyword arguments: omit issue_type / description
                                                        // when the flag was absent (their defaults `Task` / `` apply)
                                                        // and pass present ones BY NAME — `description:` can fill its
                                                        // slot while the earlier `issue_type` falls back to its default.
                                                        : b has_ty != 0 ( string_len ty )
                                                        : b has_de != 0 ( string_len de )
                                                        : s pd ( string_data pr )
                                                        : s sd ( string_data summary )
                                                        ? has_ty {
                                                            ? has_de
                                                            { = rc ( __jira_run_simple cfg `Issue luotu` ( jira_create_issue cfg pd sd issue_type: ( string_data ty ) description: ( string_data de ) ) ) }
                                                            { = rc ( __jira_run_simple cfg `Issue luotu` ( jira_create_issue cfg pd sd issue_type: ( string_data ty ) ) ) }
                                                        } {
                                                            ? has_de
                                                            { = rc ( __jira_run_simple cfg `Issue luotu` ( jira_create_issue cfg pd sd description: ( string_data de ) ) ) }
                                                            { = rc ( __jira_run_simple cfg `Issue luotu` ( jira_create_issue cfg pd sd ) ) }
                                                        }
                                                    }
                                                    ( string_free summary ) ( string_free pr ) ( string_free ty ) ( string_free de )
                                                } {
                                                    ? & ( __jira_ieq act `search` ) >= argc 3 {
                                                        : String jql ( env_arg 2 )
                                                        = rc ( cmd_search cfg ( string_data jql ) )
                                                        ( string_free jql )
                                                    } {
                                                        ( usage )
                                                        = rc 1
                                                    } } } } } } } } } } }

            ( jira_config_free cfg )
            ( string_free action )
            ^ rc
        }
    }
    ^ 1
}
