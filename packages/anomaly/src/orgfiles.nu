// src/orgfiles.nu — an organisation's storage folder
//
// Every organisation has a folder of files beside its database:
//
//   <root>/orgs/<org>/files/<name>
//
// Analyses drop their results there; the API lists and serves them to the
// organisation's members. A file can also be handed out as a link that
// carries its own permission — an HMAC over (org, name, expiry) under a
// secret the service generates once — so a result too large to return
// inline can be fetched by whoever holds the link, with no sign-in. The
// link names one file for a bounded time and nothing else; the secret
// never leaves the store.
//
// File names are the public identifier, so they are kept to one safe
// alphabet: letters, digits, `.`, `_`, `-`, not starting with a dot, at
// most 128 bytes. That rules out path tricks and URL escaping alike.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/ext/json.nu`

: i OF_NAME_MAX 128
: i OF_LINK_TTL_DEFAULT 604800  // a week
: i OF_LINK_TTL_MAX 2592000  // 30 days

// What the module keeps for the life of the process: the store root (the
// models' directory — the organisation folders live under <root>/orgs,
// beside the organisation databases) and the link-signing secret. Both
// are OWNED copies in one heap block a global points at, so a caller may
// free the root it passed, and the block stays reachable — a global that
// held only a data pointer would leave the String header unreachable,
// which is a leak in every accounting.
: OfState {
    String root
    String secret
}

: ~ i g_of_state 0

@ __of_state → *OfState {
    ? != g_of_state 0 { ^ # *OfState g_of_state } {}
    : *OfState st # *OfState ( nurl_malloc Z OfState )
    = . st root ( string_from `.` )
    = . st secret ( string_new )
    = g_of_state # i st
    ^ st
}

@ orgfiles_set_root s root → v {
    : *OfState st ( __of_state )
    ( string_clear . st root )
    ( string_push_str . st root root )
}

@ __of_orgs_dir → String {
    : String p ( string_from ( string_data . ( __of_state ) root ) )
    ( string_push_str p `/orgs` )
    ^ p
}

// <root>/orgs/<org>/<sub>, created on the way.
@ __of_org_sub s org s sub → String {
    : String p ( __of_orgs_dir )
    ( string_push_char p 47 )
    ( string_push_str p org )
    ( string_push_char p 47 )
    ( string_push_str p sub )
    : !v IoErr mk ( dir_create_all ( string_data p ) )
    ?? mk { T _ → {} F _ → {} }
    ^ p
}

@ orgfiles_dir s org → String { ^ ( __of_org_sub org `files` ) }

@ orgfiles_tasks_dir s org → String { ^ ( __of_org_sub org `tasks` ) }

// One safe alphabet for file names: [A-Za-z0-9._-], no leading dot, at
// most OF_NAME_MAX bytes.
@ orgfiles_name_ok s name → b {
    : i n ( nurl_str_len name )
    ? | == n 0 > n OF_NAME_MAX { ^ F } {}
    ? == ( nurl_str_at name n 0 ) 46 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_at name n k )
        : b digit & >= c 48 <= c 57
        : b lower & >= c 97 <= c 122
        : b upper & >= c 65 <= c 90
        : b punct | | == c 45 == c 46 == c 95
        ? | | | digit lower upper punct {} { ^ F }
        = k + k 1
    }
    ^ T
}

// A caller-chosen label, made into a safe name: every byte outside the
// alphabet becomes `_`, a leading dot too, and the result is cut to fit.
// Empty in, empty out — the caller picks a default.
@ orgfiles_safe_name s raw → String {
    : String out ( string_new )
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ & < k n < ( string_len out ) OF_NAME_MAX {
        : i c ( nurl_str_at raw n k )
        : b digit & >= c 48 <= c 57
        : b lower & >= c 97 <= c 122
        : b upper & >= c 65 <= c 90
        : b punct | | == c 45 == c 46 == c 95
        : ~ i keep ? | | | digit lower upper punct c 95
        ? & == k 0 == c 46 { = keep 95 } {}
        ( string_push_char out keep )
        = k + k 1
    }
    ^ out
}

@ orgfiles_path s org s name → String {
    : String d ( orgfiles_dir org )
    ( string_push_char d 47 )
    ( string_push_str d name )
    ^ d
}

: OrgFile {
    String name
    i size
    i mtime
}

@ orgfiles_free ( Vec OrgFile ) xs → v {
    ( vec_free_with [OrgFile] xs \ OrgFile x → v { ( string_free . x name ) } )
}

// Every file in the folder that carries a valid name, by name. Anything
// else in the directory — a temp file mid-write, a stray dotfile — is
// not a file the API ever handed out and is not listed.
@ orgfiles_list s org → ( Vec OrgFile ) {
    : String d ( orgfiles_dir org )
    : ( Vec OrgFile ) out ( vec_new [OrgFile] )
    : !( Vec String ) IoErr lr ( dir_list ( string_data d ) )
    ?? lr {
        F _ → {}
        T names → {
            : i n ( vec_len [String] names )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? ( orgfiles_name_ok ( string_data nm ) ) {
                            : String p ( string_clone d )
                            ( string_push_char p 47 )
                            ( string_push_str p ( string_data nm ) )
                            ?? ( fs_stat ( string_data p ) ) {
                                T stt → {
                                    ? == & . stt mode 61440 32768 {
                                        ( vec_push [OrgFile] out @ OrgFile { ( string_clone nm ) . stt size . stt mtime } )
                                    } {}
                                }
                                F _ → {}
                            }
                            ( string_free p )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String x → v { ( string_free x ) } )
        }
    }
    ( string_free d )
    // Insertion sort by name: folders hold a handful of files, and a
    // stable listing is what a caller pages through.
    : i n ( vec_len [OrgFile] out )
    : ~ i i 1
    ~ < i n {
        : ~ i j i
        ~ > j 0 {
            : OrgFile a ?? ( vec_get [OrgFile] out - j 1 ) { T x → x F _ → @ OrgFile { ( string_new ) 0 0 } }
            : OrgFile b ?? ( vec_get [OrgFile] out j ) { T x → x F _ → @ OrgFile { ( string_new ) 0 0 } }
            ? > ( nurl_str_cmp ( string_data . a name ) ( string_data . b name ) ) 0 {
                ( vec_set [OrgFile] out - j 1 b )
                ( vec_set [OrgFile] out j a )
                = j - j 1
            } { = j 0 }
        }
        = i + i 1
    }
    ^ out
}

// The stat of one named file, or size -1 when there is no such file.
@ orgfiles_stat s org s name → OrgFile {
    : String p ( orgfiles_path org name )
    : ~ OrgFile out @ OrgFile { ( string_from name ) -1 0 }
    ?? ( fs_stat ( string_data p ) ) {
        T stt → {
            ? == & . stt mode 61440 32768 {
                = . out size . stt size
                = . out mtime . stt mtime
            } {}
        }
        F _ → {}
    }
    ( string_free p )
    ^ out
}

@ orgfiles_delete s org s name → b {
    : String p ( orgfiles_path org name )
    : ~ b ok F
    ?? ( file_delete ( string_data p ) ) { T _ → { = ok T } F _ → {} }
    ( string_free p )
    ^ ok
}

// Write a file into the folder atomically (tmp + rename), so a reader
// never sees a half-written result.
@ orgfiles_write s org s name ( Vec u ) data → b {
    : String p ( orgfiles_path org name )
    : String tmp ( string_clone p )
    ( string_push_str tmp `.tmp` )
    : ~ b ok F
    ?? ( write_file_bytes ( string_data tmp ) data ) {
        T _ → {
            ?? ( fs_rename ( string_data tmp ) ( string_data p ) ) { T _ → { = ok T } F _ → {} }
        }
        F _ → {}
    }
    ( string_free tmp )
    ( string_free p )
    ^ ok
}

// ── Pre-authenticated links ───────────────────────────────────────────
//
// sig = HMAC-SHA256(secret, "<org>\n<name>\n<exp>"), hex. The secret is 32
// random bytes, generated on first use and kept at <root>/orgs/link.secret;
// deleting the file revokes every link at once.

@ __of_secret → s {
    : *OfState st ( __of_state )
    ? > ( string_len . st secret ) 0 { ^ ( string_data . st secret ) } {}
    : String p ( __of_orgs_dir )
    : !v IoErr mk ( dir_create_all ( string_data p ) )
    ?? mk { T _ → {} F _ → {} }
    ( string_push_str p `/link.secret` )
    : ~ String sec ( string_new )
    ?? ( read_file ( string_data p ) ) {
        T s0 → { ( string_free sec ) = sec ( string_trim s0 ) ( string_free s0 ) }
        F _ → {}
    }
    ? < ( string_len sec ) 32 {
        ( string_free sec )
        = sec ( rand_hex_str 32 )
        : !v IoErr wr ( write_file ( string_data p ) ( string_data sec ) )
        ?? wr { T _ → {} F _ → {} }
    } {}
    ( string_free p )
    // Kept for the life of the process, in the module's own block.
    ( string_free . st secret )
    = . st secret sec
    ^ ( string_data . st secret )
}

@ orgfiles_sign s org s name i exp → String {
    : String msg ( string_from org )
    ( string_push_char msg 10 )
    ( string_push_str msg name )
    ( string_push_char msg 10 )
    ( string_push_int msg exp )
    : ( Vec u ) k ( bytes_from_str ( __of_secret ) )
    : ( Vec u ) m ( bytes_from_str ( string_data msg ) )
    : ( Vec u ) dig ( hmac_sha256_pure k m )
    : String hex ( bytes_to_hex dig )
    ( vec_free [u] dig )
    ( vec_free [u] m )
    ( vec_free [u] k )
    ( string_free msg )
    ^ hex
}

// Constant-time equality: a link check must not leak how much of a
// guess was right.
@ __of_eq_ct s a s b → b {
    : i n ( nurl_str_len a )
    ? != n ( nurl_str_len b ) { ^ F } {}
    : ~ i acc 0
    : ~ i k 0
    ~ < k n {
        : i d - ( nurl_str_at a n k ) ( nurl_str_at b n k )
        = acc + acc * d d
        = k + k 1
    }
    ^ == acc 0
}

@ orgfiles_verify s org s name i exp s sig i now → b {
    ? | <= exp 0 > now exp { ^ F } {}
    ? ( orgfiles_name_ok name ) {} { ^ F }
    : String want ( orgfiles_sign org name exp )
    : b ok ( __of_eq_ct ( string_data want ) sig )
    ( string_free want )
    ^ ok
}

// The link's path + query, relative to the service root.
@ orgfiles_link s org s name i exp → String {
    : String sig ( orgfiles_sign org name exp )
    : String u ( string_from `/api/org/files/` )
    ( string_push_str u name )
    ( string_push_str u `?org=` )
    ( string_push_str u org )
    ( string_push_str u `&exp=` )
    ( string_push_int u exp )
    ( string_push_str u `&sig=` )
    ( string_push_str u ( string_data sig ) )
    ( string_free sig )
    ^ u
}

// Content type from the extension: the results are JSON, a caller may
// also have dropped CSV there; the rest is bytes.
@ orgfiles_content_type s name → s {
    : String n ( string_from name )
    : ~ s ct `application/octet-stream`
    ? ( string_ends_with n `.json` ) { = ct `application/json` } {}
    ? ( string_ends_with n `.csv` ) { = ct `text/csv; charset=utf-8` } {}
    ? ( string_ends_with n `.txt` ) { = ct `text/plain; charset=utf-8` } {}
    ( string_free n )
    ^ ct
}
