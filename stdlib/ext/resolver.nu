// Registry dependency resolution with conflict-directed backtracking.
// One version per (registry, name); dependencies inherit their parent's origin.
// Try non-yanked versions in descending semver order, using the fewest remaining
// candidates to choose the next package (identity breaks ties deterministically).
// Choices and constraint changes live on explicit stacks: cycles do not recurse,
// long chains have no round limit, and abandoning a version removes its edges.
// Indexes, versions and distinct requirements are parsed once per resolution.
//
// resolve_registry roots default_registry fetch → ! (Vec LockPkg) ResolveErr
// fetch(registry, name) returns an owned index JSON String; empty means absent.
// Path roots are installed by the caller and are ignored here.

$ `stdlib/ext/manifest.nu`
$ `stdlib/ext/lockfile.nu`
$ `stdlib/ext/registry_index.nu`
$ `stdlib/ext/registry_id.nu`
$ `stdlib/ext/semver.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`

: | ResolveErr {
    ResolveNotFound
    ResolveBadIndex
    ResolveNoMatch
    ResolveConflict
    ResolveBadRegistry
    ResolveBadPackage
    ResolveBadRequirement
}

@ resolve_err_name ResolveErr error → s {
    ^ ?? error {
        ResolveNotFound → `ResolveNotFound`
        ResolveBadIndex → `ResolveBadIndex`
        ResolveNoMatch → `ResolveNoMatch`
        ResolveConflict → `ResolveConflict`
        ResolveBadRegistry → `ResolveBadRegistry`
        ResolveBadPackage → `ResolveBadPackage`
        ResolveBadRequirement → `ResolveBadRequirement`
    }
}

// Map keys borrow immutable strings owned by the node and requirement pools.
: __SolveKey { i registry s name }
: __SolveReq { String text VersionReq value }
: __SolveEdge { i target i requirement }
: __SolveConstraint { i requirement i reason }
: __SolveVersion { Semver value i index ( Vec __SolveEdge ) edges i ready }
: __SolveNode {
    String name i registry i loaded RegIndex index
    ( Vec __SolveVersion ) versions ( Vec __SolveConstraint ) requirements i chosen i level
    ( Vec i ) domain i position ( Vec i ) explanation
}
: __SolveFrame { i node ( Vec i ) candidates i next i mark ( Vec i ) conflicts }
: __Solver {
    ( Vec String ) registries ( HashMap s i ) registry_ids
    ( Vec __SolveReq ) requirements ( HashMap s i ) requirement_ids
    ( Vec __SolveNode ) nodes ( HashMap __SolveKey i ) node_ids
    ( Vec i ) trail ( Vec __SolveFrame ) frames ( Vec i ) pending ( Vec i ) conflict
}

@ __solve_key_hash __SolveKey key → i { ^ ^^ ( hash_string . key name ) ( hash_int . key registry ) }

@ __solve_key_eq __SolveKey a __SolveKey b → b { ^ & == . a registry . b registry ( eq_string . a name . b name ) }

@ __solver_new → __Solver {
    ^ @ __Solver {
        ( vec_new [String] ) ( map_new [s i] )
        ( vec_new [__SolveReq] ) ( map_new [s i] )
        ( vec_new [__SolveNode] ) ( map_new [__SolveKey i] )
        ( vec_new [i] ) ( vec_new [__SolveFrame] ) ( vec_new [i] ) ( vec_new [i] )
    }
}

@ __solver_free __Solver solver → v {
    ( map_free [s i] . solver registry_ids )
    ( map_free [s i] . solver requirement_ids )
    ( map_free [__SolveKey i] . solver node_ids )
    ( vec_free_with [String] . solver registries \ String text → v { ( string_free text ) } )
    ( vec_free_with [__SolveReq] . solver requirements \ __SolveReq req → v {
        ( string_free . req text ) ( semver_req_free . req value )
    } )
    ( vec_free_with [__SolveNode] . solver nodes \ __SolveNode node → v {
        ( string_free . node name ) ( regindex_free . node index )
        ( vec_free [__SolveConstraint] . node requirements ) ( vec_free [i] . node domain ) ( vec_free [i] . node explanation )
        ( vec_free_with [__SolveVersion] . node versions \ __SolveVersion version → v {
            ( semver_free . version value ) ( vec_free [__SolveEdge] . version edges )
        } )
    } )
    ( vec_free [i] . solver trail ) ( vec_free [i] . solver pending ) ( vec_free [i] . solver conflict )
    ( vec_free_with [__SolveFrame] . solver frames \ __SolveFrame frame → v { ( vec_free [i] . frame candidates ) ( vec_free [i] . frame conflicts ) } )
}

@ __solver_registry __Solver solver String normalized → i {
    : s key ( string_data normalized )
    ?? ( map_get [s i] . solver registry_ids key \ s text → i { ^ ( hash_string text ) } \ s a s b → b { ^ ( eq_string a b ) } ) {
        T id → { ^ id }
        F _ → {}
    }
    : i id ( vec_len [String] . solver registries )
    : String owned ( string_clone normalized )
    ( vec_push [String] . solver registries owned )
    ( map_set [s i] . solver registry_ids ( string_data owned ) id \ s text → i { ^ ( hash_string text ) } \ s a s b → b { ^ ( eq_string a b ) } )
    ^ id
}

@ __solver_node __Solver solver i registry s name → i {
    : __SolveKey key @ __SolveKey { registry name }
    ?? ( map_get [__SolveKey i] . solver node_ids key
    \ __SolveKey key → i { ^ ( __solve_key_hash key ) } \ __SolveKey a __SolveKey b → b { ^ ( __solve_key_eq a b ) } ) {
        T id → { ^ id }
        F _ → {}
    }
    : i id ( vec_len [__SolveNode] . solver nodes )
    : String owned ( string_from name )
    ( vec_push [__SolveNode] . solver nodes @ __SolveNode {
        owned registry 0 @ RegIndex { ( string_new ) ( vec_new [IdxVersion] ) }
        ( vec_new [__SolveVersion] ) ( vec_new [__SolveConstraint] ) -1 -1 ( vec_new [i] ) -1 ( vec_new [i] )
    } )
    ( map_set [__SolveKey i] . solver node_ids @ __SolveKey { registry ( string_data owned ) } id
    \ __SolveKey key → i { ^ ( __solve_key_hash key ) } \ __SolveKey a __SolveKey b → b { ^ ( __solve_key_eq a b ) } )
    ^ id
}

@ __solver_requirement __Solver solver s text → !i ResolveErr {
    ?? ( map_get [s i] . solver requirement_ids text \ s text → i { ^ ( hash_string text ) } \ s a s b → b { ^ ( eq_string a b ) } ) {
        T id → { ^ @ !i ResolveErr { T id } }
        F _ → {}
    }
    ?? ( semver_req_parse text ) {
        F _ → { ^ @ !i ResolveErr { F ResolveBadRequirement } }
        T value → {
            : i id ( vec_len [__SolveReq] . solver requirements )
            : String owned ( string_from text )
            ( vec_push [__SolveReq] . solver requirements @ __SolveReq { owned value } )
            ( map_set [s i] . solver requirement_ids ( string_data owned ) id \ s text → i { ^ ( hash_string text ) } \ s a s b → b { ^ ( eq_string a b ) } )
            ^ @ !i ResolveErr { T id }
        }
    }
}

// The candidate's parsed value is independent of the index's owned strings.
// Build metadata does not affect precedence; lexical build order breaks ties.
@ __solve_version_cmp __SolveVersion a __SolveVersion b → i {
    : i precedence ( semver_compare . b value . a value )
    ? != precedence 0 { ^ precedence } {}
    ^ ( cmp_string . . b value build . . a value build )
}

@ __solver_load __Solver solver i id ( @ String s s ) fetch → v {
    : ~ __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) id
    ? != . node loaded 0 { ^ v } {}
    : String registry . ( vec_data [String] . solver registries ) . node registry
    : String text ( fetch ( string_data registry ) ( string_data . node name ) )
    = . node loaded ? == ( string_len text ) 0 -1 -2
    ? & > ( string_len text ) 0 == ( string_len text ) ( nurl_str_len ( string_data text ) ) {
        ?? ( regindex_parse ( string_data text ) ) {
            F _ → {}
            T index → {
                ? ( string_eq . index name . node name ) {
                    ( regindex_free . node index ) = . node index index
                    = . node loaded 1
                    : i n ( vec_len [IdxVersion] . index versions )
                    : ~ i k 0
                    ~ & == . node loaded 1 < k n {
                        : IdxVersion version . ( vec_data [IdxVersion] . index versions ) k
                        ?? ( semver_parse ( string_data . version version ) ) {
                            F _ → { = . node loaded -2 }
                            T value → { ( vec_push [__SolveVersion] . node versions @ __SolveVersion { value k ( vec_new [__SolveEdge] ) 0 } ) }
                        }
                        : ~ i d 0
                        ~ & == . node loaded 1 < d ( vec_len [IdxDep] . version deps ) {
                            : IdxDep dep . ( vec_data [IdxDep] . version deps ) d
                            ? ! ( registry_name_valid ( string_data . dep name ) ) { = . node loaded -2 } {
                                ?? ( __solver_requirement solver ( string_data . dep req ) ) {
                                    F _ → { = . node loaded -2 }
                                    T _ → {}
                                }
                            }
                            = d + d 1
                        }
                        = k + k 1
                    }
                    ( sort_by [__SolveVersion] . node versions \ __SolveVersion a __SolveVersion b → i { ^ ( __solve_version_cmp a b ) } )
                    : *__SolveVersion versions ( vec_data [__SolveVersion] . node versions )
                    : ~ i j 1
                    ~ < j ( vec_len [__SolveVersion] . node versions ) {
                        ? == ( __solve_version_cmp . versions - j 1 . versions j ) 0 { = . node loaded -2 } {}
                        = j + j 1
                    }
                } { ( regindex_free index ) }
            }
        }
    } {}
    ( string_free text )
    ( vec_set [__SolveNode] . solver nodes id node )
}

@ __solver_conflict __SolveNode node → ResolveErr {
    : *__SolveConstraint reqs ( vec_data [__SolveConstraint] . node requirements )
    : i n ( vec_len [__SolveConstraint] . node requirements )
    : ~ i k 1
    ~ < k n {
        ? != . . reqs 0 requirement . . reqs k requirement { ^ ResolveConflict } {}
        = k + k 1
    }
    ^ ResolveNoMatch
}

// Reasons are decision-stack levels. Root requirements have reason -1.
// A frame keeps the union of causes for all its failed candidates, plus the
// constraints that excluded candidates before the frame was created. Once its
// candidates are exhausted, only these earlier decisions can change the result.
@ __solver_reason ( Vec i ) reasons i reason → v {
    ? < reason 0 { ^ v } {}
    : *i data ( vec_data [i] reasons )
    : ~ i k 0
    ~ < k ( vec_len [i] reasons ) {
        ? == . data k reason { ^ v } {}
        = k + k 1
    }
    ( vec_push [i] reasons reason )
}

@ __solver_blame __Solver solver i id → v {
    ( vec_set_len [i] . solver conflict 0 )
    : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) id
    : *i reasons ( vec_data [i] . node explanation )
    : ~ i k 0
    ~ < k ( vec_len [i] . node explanation ) {
        ( __solver_reason . solver conflict . reasons k )
        = k + k 1
    }
}

// Indexed minimum heap of required, unassigned nodes. A constraint change
// refreshes only its target's domain; assigned/inactive nodes are never scanned.
// Unloaded nodes are considered before ordinary choices; known errors first.
@ __solver_rank __SolveNode node → i {
    ? == . node loaded 0 { ^ -1 } {}
    ? | < . node loaded 0 == ( vec_len [i] . node domain ) 0 { ^ -2 } {}
    ^ ( vec_len [i] . node domain )
}

@ __solver_less __Solver solver i a i b → b {
    : __SolveNode left . ( vec_data [__SolveNode] . solver nodes ) a
    : __SolveNode right . ( vec_data [__SolveNode] . solver nodes ) b
    : i lr ( __solver_rank left )
    : i rr ( __solver_rank right )
    ? != lr rr { ^ < lr rr } {}
    : i names ( cmp_string . left name . right name )
    ? != names 0 { ^ < names 0 } {}
    : String lreg . ( vec_data [String] . solver registries ) . left registry
    : String rreg . ( vec_data [String] . solver registries ) . right registry
    ^ < ( cmp_string lreg rreg ) 0
}

@ __solver_position __Solver solver i id i position → v {
    : ~ __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) id
    = . node position position
    ( vec_set [__SolveNode] . solver nodes id node )
}

@ __solver_swap __Solver solver i a i b → v {
    : *i heap ( vec_data [i] . solver pending )
    : i left . heap a
    : i right . heap b
    = . heap a right = . heap b left
    ( __solver_position solver left b ) ( __solver_position solver right a )
}

@ __solver_sift __Solver solver i start → v {
    : ~ i pos start
    : *i heap ( vec_data [i] . solver pending )
    ~ & > pos 0 ( __solver_less solver . heap pos . heap / - pos 1 2 ) {
        : i parent / - pos 1 2
        ( __solver_swap solver pos parent ) = pos parent
    }
    : i n ( vec_len [i] . solver pending )
    : ~ b done F
    ~ & ! done < + * pos 2 1 n {
        : ~ i child + * pos 2 1
        ? & < + child 1 n ( __solver_less solver . heap + child 1 . heap child ) { = child + child 1 } {}
        ? ( __solver_less solver . heap child . heap pos ) {
            ( __solver_swap solver pos child ) = pos child
        } { = done T }
    }
}

@ __solver_unqueue __Solver solver i id → v {
    : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) id
    : i pos . node position
    ? < pos 0 { ^ v } {}
    ?? ( vec_pop [i] . solver pending ) {
        T last → {
            ( __solver_position solver id -1 )
            ? < pos ( vec_len [i] . solver pending ) {
                ( vec_set [i] . solver pending pos last )
                ( __solver_position solver last pos )
                ( __solver_sift solver pos )
            } {}
        }
        F _ → {}
    }
}

@ __solver_refresh __Solver solver i id → v {
    ( __solver_unqueue solver id )
    : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) id
    ? | >= . node chosen 0 == ( vec_len [__SolveConstraint] . node requirements ) 0 { ^ v } {}
    ( vec_set_len [i] . node domain 0 )
    ( vec_set_len [i] . node explanation 0 )
    : *__SolveConstraint constraints ( vec_data [__SolveConstraint] . node requirements )
    : i total ( vec_len [__SolveConstraint] . node requirements )
    : ~ b root F
    : ~ i c 0
    ~ < c total { ? < . . constraints c reason 0 { = root T } {} = c + c 1 }
    ? > . node loaded 0 {
        : *__SolveVersion versions ( vec_data [__SolveVersion] . node versions )
        : *IdxVersion index ( vec_data [IdxVersion] . . node index versions )
        : ~ i k 0
        ~ < k ( vec_len [__SolveVersion] . node versions ) {
            : __SolveVersion candidate . versions k
            : IdxVersion raw . index . candidate index
            ? ! . raw yanked { ( vec_push [i] . node domain k ) } {}
            = k + k 1
        }
        // A condition becomes a cause only when it removes a still-possible
        // candidate. Redundant wildcard/duplicate edges must not turn an
        // independent contradiction into an exponential enumeration.
        : *__SolveReq pool ( vec_data [__SolveReq] . solver requirements )
        : ~ i r 0
        ~ < r total {
            : __SolveConstraint constraint . constraints r
            : __SolveReq req . pool . constraint requirement
            : i before ( vec_len [i] . node domain )
            : *i domain ( vec_data [i] . node domain )
            : ~ i keep 0
            : ~ i j 0
            ~ < j before {
                : i candidate . domain j
                : __SolveVersion version . versions candidate
                ? ( semver_req_matches . req value . version value ) {
                    = . domain keep candidate = keep + keep 1
                } {}
                = j + j 1
            }
            ( vec_set_len [i] . node domain keep )
            ? < keep before { ( __solver_reason . node explanation . constraint reason ) } {}
            = r + r 1
        }
    } {}
    // If no filtering condition establishes the package's necessity, retain
    // one presence cause. A root already makes that necessity unconditional.
    ? & ! root == ( vec_len [i] . node explanation ) 0 {
        ( __solver_reason . node explanation . . constraints 0 reason )
    } {}
    : i pos ( vec_len [i] . solver pending )
    ( vec_push [i] . solver pending id )
    ( __solver_position solver id pos )
    ( __solver_sift solver pos )
}

@ __solver_decision __Solver solver ( @ String s s ) fetch → !__SolveFrame ResolveErr {
    ~ > ( vec_len [i] . solver pending ) 0 {
        : i id . ( vec_data [i] . solver pending ) 0
        : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) id
        ? == . node loaded 0 {
            ( __solver_unqueue solver id )
            ( __solver_load solver id fetch )
            ( __solver_refresh solver id )
        } {
            ? < . node loaded 0 { ( __solver_blame solver id ) ^ @ !__SolveFrame ResolveErr { F ? == . node loaded -1 ResolveNotFound ResolveBadIndex } } {}
            ? == ( vec_len [i] . node domain ) 0 { ( __solver_blame solver id ) ^ @ !__SolveFrame ResolveErr { F ( __solver_conflict node ) } } {}
            : ( Vec i ) candidates ( vec_clone [i] . node domain )
            ( __solver_blame solver id )
            ^ @ !__SolveFrame ResolveErr { T @ __SolveFrame { id candidates 0 ( vec_len [i] . solver trail ) ( vec_clone [i] . solver conflict ) } }
        }
    }
    ^ @ !__SolveFrame ResolveErr { T @ __SolveFrame { -1 ( vec_new [i] ) 0 ( vec_len [i] . solver trail ) ( vec_new [i] ) } }
}

@ __solver_select __Solver solver i id i chosen → v {
    : ~ __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) id
    = . node chosen chosen
    = . node level ? >= chosen 0 - ( vec_len [__SolveFrame] . solver frames ) 1 -1
    ( vec_set [__SolveNode] . solver nodes id node )
    ? >= chosen 0 { ( __solver_unqueue solver id ) } { ( __solver_refresh solver id ) }
}

@ __solver_add_edge __Solver solver __SolveEdge edge i reason → b {
    : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) . edge target
    ( vec_push [__SolveConstraint] . node requirements @ __SolveConstraint { . edge requirement reason } )
    ( vec_push [i] . solver trail . edge target )
    ? >= . node chosen 0 {
        : __SolveVersion version . ( vec_data [__SolveVersion] . node versions ) . node chosen
        : __SolveReq req . ( vec_data [__SolveReq] . solver requirements ) . edge requirement
        ? ( semver_req_matches . req value . version value ) { ^ T } {}
        ( vec_set_len [i] . solver conflict 0 )
        ( __solver_reason . solver conflict reason )
        ( __solver_reason . solver conflict . node level )
        ^ F
    } {}
    ( __solver_refresh solver . edge target )
    ^ T
}

@ __solver_undo __Solver solver i mark → v {
    ~ > ( vec_len [i] . solver trail ) mark {
        ?? ( vec_pop [i] . solver trail ) {
            T target → {
                : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) target
                ( vec_pop [__SolveConstraint] . node requirements )
                ( __solver_refresh solver target )
            }
            F _ → {}
        }
    }
}

// Parse a version's dependency edges only on first use. Node/requirement pool
// growth may relocate their Vec data, so no pointers into those pools survive
// an interning call; the local node/version copies contain stable Vec handles.
@ __solver_prepare __Solver solver i id i chosen → b {
    : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) id
    : ~ __SolveVersion version . ( vec_data [__SolveVersion] . node versions ) chosen
    ? != . version ready 0 { ^ > . version ready 0 } {}
    : IdxVersion raw . ( vec_data [IdxVersion] . . node index versions ) . version index
    = . version ready 1
    : ~ i k 0
    ~ & > . version ready 0 < k ( vec_len [IdxDep] . raw deps ) {
        : IdxDep dep . ( vec_data [IdxDep] . raw deps ) k
        ? ! ( registry_name_valid ( string_data . dep name ) ) { = . version ready -1 } {
            ?? ( __solver_requirement solver ( string_data . dep req ) ) {
                F _ → { = . version ready -1 }
                T requirement → {
                    : i target ( __solver_node solver . node registry ( string_data . dep name ) )
                    ( vec_push [__SolveEdge] . version edges @ __SolveEdge { target requirement } )
                }
            }
        }
        = k + k 1
    }
    ( vec_set [__SolveVersion] . node versions chosen version )
    ^ > . version ready 0
}

@ __solver_roots __Solver solver ( Vec Dep ) roots s default_registry → !i ResolveErr {
    : ~ i k 0
    ~ < k ( vec_len [Dep] roots ) {
        : Dep dep . ( vec_data [Dep] roots ) k
        ? ( dep_is_registry dep ) {
            ? ! & == ( string_len . dep name ) ( nurl_str_len ( string_data . dep name ) ) ( registry_name_valid ( string_data . dep name ) ) {
                ^ @ !i ResolveErr { F ResolveBadPackage }
            } {}
            ? != ( string_len . dep registry ) ( nurl_str_len ( string_data . dep registry ) ) { ^ @ !i ResolveErr { F ResolveBadRegistry } } {}
            ? != ( string_len . dep version ) ( nurl_str_len ( string_data . dep version ) ) { ^ @ !i ResolveErr { F ResolveBadRequirement } } {}
            : s url ? > ( string_len . dep registry ) 0 ( string_data . dep registry ) default_registry
            : ~ i registry -1
            ?? ( registry_url url ) {
                F empty → { ( string_free empty ) ^ @ !i ResolveErr { F ResolveBadRegistry } }
                T normalized → { = registry ( __solver_registry solver normalized ) ( string_free normalized ) }
            }
            ?? ( __solver_requirement solver ( string_data . dep version ) ) {
                F error → { ^ @ !i ResolveErr { F error } }
                T requirement → {
                    : i target ( __solver_node solver registry ( string_data . dep name ) )
                    ( __solver_add_edge solver @ __SolveEdge { target requirement } -1 )
                }
            }
        } {}
        = k + k 1
    }
    ^ @ !i ResolveErr { T 0 }
}

@ __solver_lock __Solver solver → ( Vec LockPkg ) {
    : ( Vec LockPkg ) locked ( vec_new [LockPkg] )
    : ~ i k 0
    ~ < k ( vec_len [__SolveNode] . solver nodes ) {
        : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) k
        ? >= . node chosen 0 {
            : __SolveVersion version . ( vec_data [__SolveVersion] . node versions ) . node chosen
            : IdxVersion raw . ( vec_data [IdxVersion] . . node index versions ) . version index
            : String registry . ( vec_data [String] . solver registries ) . node registry
            ( vec_push [LockPkg] locked @ LockPkg {
                ( string_clone . node name ) ( string_clone . raw version )
                ( registry_source ( string_data registry ) ) ( string_clone . raw checksum )
            } )
        } {}
        = k + k 1
    }
    ^ locked
}

// Remove abandoned frames in reverse order. Their constraint trail entries
// are popped before the assignment is cleared, then their domains are freed.
@ __solver_pop __Solver solver → ?__SolveFrame {
    : ?__SolveFrame result ( vec_pop [__SolveFrame] . solver frames )
    ?? result {
        T frame → { ( __solver_undo solver . frame mark ) ( __solver_select solver . frame node -1 ) }
        F _ → {}
    }
    ^ result
}

@ __solver_frame_free __SolveFrame frame → v {
    ( vec_free [i] . frame candidates ) ( vec_free [i] . frame conflicts )
}

// Jump over decisions that cannot affect this contradiction. Each retained
// frame's cause set contains only earlier levels, so reused stack positions
// cannot leave stale reasons after an ancestor's assignment changes.
@ __solver_backjump __Solver solver → b {
    : *i causes ( vec_data [i] . solver conflict )
    : i n ( vec_len [i] . solver conflict )
    : ~ i target -1
    : ~ i k 0
    ~ < k n { ? > . causes k target { = target . causes k } {} = k + k 1 }
    ? < target 0 { ^ F } {}
    ~ > ( vec_len [__SolveFrame] . solver frames ) + target 1 {
        ?? ( __solver_pop solver ) { T frame → { ( __solver_frame_free frame ) } F _ → {} }
    }
    : __SolveFrame frame . ( vec_data [__SolveFrame] . solver frames ) target
    : ~ i j 0
    ~ < j n {
        ? < . causes j target { ( __solver_reason . frame conflicts . causes j ) } {}
        = j + j 1
    }
    ^ T
}

@ resolve_registry ( Vec Dep ) roots s default_registry ( @ String s s ) fetch → !( Vec LockPkg ) ResolveErr {
    : __Solver solver ( __solver_new )
    ?? ( __solver_roots solver roots default_registry ) {
        F error → { ( __solver_free solver ) ^ @ !( Vec LockPkg ) ResolveErr { F error } }
        T _ → {}
    }
    : ~ ResolveErr failure ResolveConflict
    : ~ b searching T
    ~ searching {
        : ~ b jumping F
        ?? ( __solver_decision solver fetch ) {
            F error → { = failure error = jumping T }
            T frame → {
                ? < . frame node 0 {
                    ( __solver_frame_free frame )
                    : ( Vec LockPkg ) locked ( __solver_lock solver )
                    ( __solver_free solver )
                    ^ @ !( Vec LockPkg ) ResolveErr { T locked }
                } {}
                ( vec_push [__SolveFrame] . solver frames frame )
            }
        }
        : ~ b advanced F
        ~ & searching ! advanced {
            ? jumping { = searching ( __solver_backjump solver ) = jumping F } {}
            ? searching {
                ?? ( __solver_pop solver ) {
                    F _ → { = searching F }
                    T old → {
                        : ~ __SolveFrame frame old
                        ? < . frame next ( vec_len [i] . frame candidates ) {
                            : i chosen . ( vec_data [i] . frame candidates ) . frame next
                            = . frame next + . frame next 1
                            ( vec_push [__SolveFrame] . solver frames frame )
                            ( __solver_select solver . frame node chosen )
                            : i level - ( vec_len [__SolveFrame] . solver frames ) 1
                            ? ( __solver_prepare solver . frame node chosen ) {
                                : __SolveNode node . ( vec_data [__SolveNode] . solver nodes ) . frame node
                                : __SolveVersion version . ( vec_data [__SolveVersion] . node versions ) chosen
                                = advanced T
                                : ~ i k 0
                                ~ & advanced < k ( vec_len [__SolveEdge] . version edges ) {
                                    : __SolveEdge edge . ( vec_data [__SolveEdge] . version edges ) k
                                    ? ! ( __solver_add_edge solver edge level ) { = advanced F = failure ResolveConflict } {}
                                    = k + k 1
                                }
                            } {
                                = failure ResolveBadIndex
                                ( vec_set_len [i] . solver conflict 0 )
                                ( __solver_reason . solver conflict level )
                            }
                            = jumping ! advanced
                        } {
                            ( vec_set_len [i] . solver conflict 0 )
                            : *i reasons ( vec_data [i] . frame conflicts )
                            : ~ i j 0
                            ~ < j ( vec_len [i] . frame conflicts ) {
                                ( __solver_reason . solver conflict . reasons j ) = j + j 1
                            }
                            ( __solver_frame_free frame )
                            = jumping T
                        }
                    }
                }
            } {}
        }
    }
    ( __solver_free solver )
    ^ @ !( Vec LockPkg ) ResolveErr { F failure }
}
