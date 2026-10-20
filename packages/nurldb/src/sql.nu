// packages/nurldb/src/sql.nu — SQL text to statements.
//
// The dialect (keywords in any case; identifiers fold to lower case):
//
//   CREATE TABLE t ( col type [NOT NULL] [PRIMARY KEY], …
//                    [, PRIMARY KEY ( col, … )] )
//       type: INT | INTEGER | BIGINT | REAL | FLOAT | DOUBLE | TEXT |
//             VARCHAR [( n )] | BOOL | BOOLEAN
//   CREATE [UNIQUE] INDEX name ON t ( col, … )
//   INSERT INTO t [( col, … )] VALUES ( expr, … ) [, ( … ) …]
//   SELECT [DISTINCT] expr [[AS] name], … | *
//       [FROM t [[AS] a] [[INNER] JOIN u [[AS] b] ON expr]]
//       [WHERE expr] [GROUP BY expr, …] [HAVING expr]
//       [ORDER BY expr [ASC | DESC], …] [LIMIT n [OFFSET n]]
//   UPDATE t SET col = expr, … [WHERE expr]
//   DELETE FROM t [WHERE expr]
//   BEGIN | COMMIT | ROLLBACK | CHECKPOINT | EXPLAIN select
//
// Expressions: literals (integers, reals, 'text' with '' for a quote,
// TRUE, FALSE, NULL), columns (col or t.col), + - * / % || unary -,
// = <> != < <= > >=, AND OR NOT, IS [NOT] NULL, [NOT] LIKE,
// [NOT] BETWEEN … AND …, [NOT] IN ( … ), COUNT(*) COUNT SUM AVG MIN MAX,
// and parentheses.
//
// A statement keeps its expressions in one arena (`ex`) and refers to them
// by index: a tree without boxes, walked by index by the evaluator.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/panic.nu`
$ `value.nu`

// ── tokens ─────────────────────────────────────────────────────────────

: i TK_EOF 0
: i TK_ID 1
: i TK_INT 2
: i TK_REAL 3
: i TK_STR 4
: i TK_OP 5

: Tok {
    i kind
    String text  // an identifier folded to lower case; an operator's spelling
    i ival
    f fval
}

@ __is_alpha i c → b { ^ | | & >= c 97 <= c 122 & >= c 65 <= c 90 == c 95 }

@ __is_digit i c → b { ^ & >= c 48 <= c 57 }

@ __lower i c → i { ^ ? & >= c 65 <= c 90 + c 32 c }

@ __w s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

@ __tok i kind String text → Tok { ^ @ Tok { kind text 0 0.0 } }

// The tokens of `src`; a stray character is an error.
@ sql_lex String src → !( Vec Tok ) String {
    : ( Slice u ) b ( string_bytes src )
    : i n ( slice_len [u] b )
    : ( Vec Tok ) out ( vec_new [Tok] )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte b k )
        ? | | | == c 32 == c 10 == c 13 == c 9 { = k + k 1 continue } {}
        // -- a comment to the end of the line
        ? & == c 45 == ( slice_byte b + k 1 ) 45 {
            ~ & < k n != ( slice_byte b k ) 10 { = k + k 1 }
            continue
        } {}
        ? ( __is_alpha c ) {
            : String t ( string_new )
            ~ & < k n | ( __is_alpha ( slice_byte b k ) ) ( __is_digit ( slice_byte b k ) ) {
                ( string_push_char t ( __lower ( slice_byte b k ) ) )
                = k + k 1
            }
            ( vec_push [Tok] out ( __tok TK_ID t ) )
            continue
        } {}
        // "Quoted identifier": kept as written.
        ? == c 34 {
            : String t ( string_new )
            = k + k 1
            ~ & < k n != ( slice_byte b k ) 34 { ( string_push_char t ( slice_byte b k ) ) = k + k 1 }
            = k + k 1
            ( vec_push [Tok] out ( __tok TK_ID t ) )
            continue
        } {}
        ? ( __is_digit c ) {
            : ~ i iv 0
            ~ & < k n ( __is_digit ( slice_byte b k ) ) { = iv + * iv 10 - ( slice_byte b k ) 48 = k + k 1 }
            ? & == ( slice_byte b k ) 46 ( __is_digit ( slice_byte b + k 1 ) ) {
                : ~ f fv # f iv
                : ~ f scale 0.1
                = k + k 1
                ~ & < k n ( __is_digit ( slice_byte b k ) ) {
                    = fv + fv * scale # f - ( slice_byte b k ) 48
                    = scale / scale 10.0
                    = k + k 1
                }
                ( vec_push [Tok] out @ Tok { TK_REAL ( string_new ) 0 fv } )
            } {
                ( vec_push [Tok] out @ Tok { TK_INT ( string_new ) iv 0.0 } )
            }
            continue
        } {}
        // 'text', with '' for a quote inside
        ? == c 39 {
            : String t ( string_new )
            = k + k 1
            ~ < k n {
                : i d ( slice_byte b k )
                ? == d 39 {
                    ? == ( slice_byte b + k 1 ) 39 { ( string_push_char t 39 ) = k + k 2 continue } {}
                    break
                } {}
                ( string_push_char t d )
                = k + k 1
            }
            ? >= k n { ^ @ !( Vec Tok ) String { F ( string_from `nurldb: a text literal is not closed` ) } } {}
            = k + k 1
            ( vec_push [Tok] out ( __tok TK_STR t ) )
            continue
        } {}
        // Operators: the two-character ones first.
        : i c2 ( slice_byte b + k 1 )
        : b two | | | | & == c 60 == c2 61 & == c 62 == c2 61 & == c 60 == c2 62 & == c 33 == c2 61 & == c 124 == c2 124
        ? two {
            : String t ( string_new )
            ( string_push_char t c ) ( string_push_char t c2 )
            ( vec_push [Tok] out ( __tok TK_OP t ) )
            = k + k 2
            continue
        } {}
        ? >= ( nurl_str_find `(),;.*+-/%=<>` ( nurl_str_slice ( string_data src ) k 1 ) ) 0 {
            : String t ( string_new )
            ( string_push_char t c )
            ( vec_push [Tok] out ( __tok TK_OP t ) )
            = k + k 1
            continue
        } {}
        ^ @ !( Vec Tok ) String { F ( string_concat ( string_from `nurldb: unexpected character in SQL at offset ` ) ( string_from ( nurl_str_int k ) ) ) }
    }
    ( vec_push [Tok] out ( __tok TK_EOF ( string_new ) ) )
    ^ @ !( Vec Tok ) String { T out }
}

// ── the tree ───────────────────────────────────────────────────────────

: i EX_LIT 1
: i EX_COL 2
: i EX_UN 3
: i EX_BIN 4
: i EX_AGG 5
: i EX_ISNULL 6
: i EX_LIKE 7
: i EX_BETWEEN 8
: i EX_IN 9

: i OP_ADD 1
: i OP_SUB 2
: i OP_MUL 3
: i OP_DIV 4
: i OP_MOD 5
: i OP_EQ 6
: i OP_NE 7
: i OP_LT 8
: i OP_LE 9
: i OP_GT 10
: i OP_GE 11
: i OP_AND 12
: i OP_OR 13
: i OP_NOT 14
: i OP_NEG 15
: i OP_CONCAT 16

: i AG_COUNT 1
: i AG_SUM 2
: i AG_AVG 3
: i AG_MIN 4
: i AG_MAX 5

// One node. `a` / `b` / `c`: operands (indices into the arena, -1 none);
// `neg`: NOT for IS NULL / LIKE / BETWEEN / IN; `list`: IN's values;
// `col`: a column's position once bound (exec.nu), an aggregate's slot.
: Ex {
    i kind
    i op
    i a
    i b
    i c
    b neg
    Value lit
    String name
    String qual
    ( Vec i ) list
    i col
}

: SelItem {
    i e  // -1: `*`
    String alias
}

: OrderItem {
    i e
    b desc
}

: i ST_SELECT 1
: i ST_INSERT 2
: i ST_UPDATE 3
: i ST_DELETE 4
: i ST_CREATE_TABLE 5
: i ST_CREATE_INDEX 6
: i ST_BEGIN 7
: i ST_COMMIT 8
: i ST_ROLLBACK 9
: i ST_CHECKPOINT 10

: Stmt {
    i kind
    b explain
    ( Vec Ex ) ex
    String table
    String alias
    String jtable
    String jalias
    i on
    ( Vec SelItem ) items
    b distinct
    i where_e
    ( Vec i ) group
    i having
    ( Vec OrderItem ) order
    i limit
    i offset
    ( Vec String ) cols
    ( Vec ( Vec i ) ) rows
    ( Vec i ) sets
    ( Vec ColDef0 ) defs
    String name
    b unique
}

// A column of CREATE TABLE as parsed (db.nu makes its ColDef).
: ColDef0 {
    String name
    i ty
    b notnull
    b pk
}

@ stmt_new i kind → Stmt {
    ^ @ Stmt {
        kind F ( vec_new [Ex] ) ( string_new ) ( string_new ) ( string_new ) ( string_new ) -1
        ( vec_new [SelItem] ) F -1 ( vec_new [i] ) -1 ( vec_new [OrderItem] ) -1 0
        ( vec_new [String] ) ( vec_new [( Vec i )] ) ( vec_new [i] ) ( vec_new [ColDef0] ) ( string_new ) F
    }
}

// ── the parser ─────────────────────────────────────────────────────────

: P {
    ( Vec Tok ) toks
    i pos
    ( Vec Ex ) ex
}

@ __err P p s what → v {
    : Tok t ( vec_at [Tok] . p toks . p pos )
    : String near ? == . t kind TK_EOF ( string_from `the end` ) ( string_concat ( string_from `'` ) ( string_concat ( string_clone . t text ) ( string_from `'` ) ) )
    ( panic_with ( string_concat ( string_from `nurldb: syntax error: expected ` ) ( string_concat ( string_from what ) ( string_concat ( string_from ` near ` ) near ) ) ) )
}

@ __peek P p → Tok { ^ ( vec_at [Tok] . p toks . p pos ) }

@ __is_kw P p s kw → b {
    : Tok t ( vec_at [Tok] . p toks . p pos )
    ^ & == . t kind TK_ID ( __w ( string_data . t text ) kw )
}

@ __is_op P p s op → b {
    : Tok t ( vec_at [Tok] . p toks . p pos )
    ^ & == . t kind TK_OP ( __w ( string_data . t text ) op )
}

@ __accept_kw inout P p s kw → b {
    ? ( __is_kw p kw ) { = . p pos + . p pos 1 ^ T } {}
    ^ F
}

@ __accept_op inout P p s op → b {
    ? ( __is_op p op ) { = . p pos + . p pos 1 ^ T } {}
    ^ F
}

@ __expect_kw inout P p s kw → v { ? ! ( __accept_kw p kw ) { ( __err p kw ) } {} }

@ __expect_op inout P p s op → v { ? ! ( __accept_op p op ) { ( __err p op ) } {} }

// A name (an identifier that is not a reserved word of the statement).
@ __ident inout P p → String {
    : Tok t ( vec_at [Tok] . p toks . p pos )
    ? != . t kind TK_ID { ( __err p `a name` ) } {}
    = . p pos + . p pos 1
    ^ ( string_clone . t text )
}

@ __int inout P p → i {
    : Tok t ( vec_at [Tok] . p toks . p pos )
    ? != . t kind TK_INT { ( __err p `a number` ) } {}
    = . p pos + . p pos 1
    ^ . t ival
}

@ __node inout P p i kind i op i a i b → i {
    ( vec_push [Ex] . p ex @ Ex { kind op a b -1 F @ Value { VNull } ( string_new ) ( string_new ) ( vec_new [i] ) -1 } )
    ^ - ( vec_len [Ex] . p ex ) 1
}

@ __lit inout P p Value v → i {
    ( vec_push [Ex] . p ex @ Ex { EX_LIT 0 -1 -1 -1 F v ( string_new ) ( string_new ) ( vec_new [i] ) -1 } )
    ^ - ( vec_len [Ex] . p ex ) 1
}

// A node with every part given (a list, a third operand, NOT).
@ __node_full inout P p i kind i op i a i b i c b neg sink ( Vec i ) list → i {
    ( vec_push [Ex] . p ex @ Ex { kind op a b c neg @ Value { VNull } ( string_new ) ( string_new ) list -1 } )
    ^ - ( vec_len [Ex] . p ex ) 1
}

@ __node_col inout P p sink String qual sink String name → i {
    ( vec_push [Ex] . p ex @ Ex { EX_COL 0 -1 -1 -1 F @ Value { VNull } name qual ( vec_new [i] ) -1 } )
    ^ - ( vec_len [Ex] . p ex ) 1
}

@ __is_reserved String t → b {
    : s w ( string_data t )
    ^ | | | | | | | | | | | | | | ( __w w `from` ) ( __w w `where` ) ( __w w `group` ) ( __w w `order` )
    ( __w w `limit` ) ( __w w `join` ) ( __w w `inner` ) ( __w w `on` ) ( __w w `having` )
    ( __w w `offset` ) ( __w w `and` ) ( __w w `or` ) ( __w w `as` ) ( __w w `set` ) ( __w w `values` )
}

@ parse_expr inout P p → i { ^ ( __or p ) }

@ __or inout P p → i {
    : ~ i l ( __and p )
    ~ ( __accept_kw p `or` ) { = l ( __node p EX_BIN OP_OR l ( __and p ) ) }
    ^ l
}

@ __and inout P p → i {
    : ~ i l ( __not p )
    ~ ( __accept_kw p `and` ) { = l ( __node p EX_BIN OP_AND l ( __not p ) ) }
    ^ l
}

@ __not inout P p → i {
    ? ( __accept_kw p `not` ) { ^ ( __node p EX_UN OP_NOT ( __not p ) -1 ) } {}
    ^ ( __cmp p )
}

@ __cmp inout P p → i {
    : i l ( __add p )
    : i op ? ( __accept_op p `=` ) OP_EQ ? ( __accept_op p `<>` ) OP_NE ? ( __accept_op p `!=` ) OP_NE ? ( __accept_op p `<=` ) OP_LE ? ( __accept_op p `>=` ) OP_GE ? ( __accept_op p `<` ) OP_LT ? ( __accept_op p `>` ) OP_GT 0
    ? > op 0 { ^ ( __node p EX_BIN op l ( __add p ) ) } {}
    ? ( __accept_kw p `is` ) {
        : b neg ( __accept_kw p `not` )
        ( __expect_kw p `null` )
        ^ ( __node_full p EX_ISNULL 0 l -1 -1 neg ( vec_new [i] ) )
    } {}
    : b neg ( __accept_kw p `not` )
    ? ( __accept_kw p `like` ) {
        : i pat ( __add p )
        ^ ( __node_full p EX_LIKE 0 l pat -1 neg ( vec_new [i] ) )
    } {}
    ? ( __accept_kw p `between` ) {
        : i lo ( __add p )
        ( __expect_kw p `and` )
        : i hi ( __add p )
        ^ ( __node_full p EX_BETWEEN 0 l lo hi neg ( vec_new [i] ) )
    } {}
    ? ( __accept_kw p `in` ) {
        ( __expect_op p `(` )
        : ( Vec i ) items ( vec_new [i] )
        ( vec_push [i] items ( parse_expr p ) )
        ~ ( __accept_op p `,` ) { ( vec_push [i] items ( parse_expr p ) ) }
        ( __expect_op p `)` )
        ^ ( __node_full p EX_IN 0 l -1 -1 neg items )
    } {}
    ? neg { ( __err p `LIKE, BETWEEN or IN after NOT` ) } {}
    ^ l
}

@ __add inout P p → i {
    : ~ i l ( __mul p )
    ~ T {
        ? ( __accept_op p `+` ) { = l ( __node p EX_BIN OP_ADD l ( __mul p ) ) continue } {}
        ? ( __accept_op p `-` ) { = l ( __node p EX_BIN OP_SUB l ( __mul p ) ) continue } {}
        ? ( __accept_op p `||` ) { = l ( __node p EX_BIN OP_CONCAT l ( __mul p ) ) continue } {}
        break
    }
    ^ l
}

@ __mul inout P p → i {
    : ~ i l ( __unary p )
    ~ T {
        ? ( __accept_op p `*` ) { = l ( __node p EX_BIN OP_MUL l ( __unary p ) ) continue } {}
        ? ( __accept_op p `/` ) { = l ( __node p EX_BIN OP_DIV l ( __unary p ) ) continue } {}
        ? ( __accept_op p `%` ) { = l ( __node p EX_BIN OP_MOD l ( __unary p ) ) continue } {}
        break
    }
    ^ l
}

@ __unary inout P p → i {
    ? ( __accept_op p `-` ) { ^ ( __node p EX_UN OP_NEG ( __unary p ) -1 ) } {}
    ? ( __accept_op p `+` ) { ^ ( __unary p ) } {}
    ^ ( __primary p )
}

@ __agg_op String t → i {
    : s w ( string_data t )
    ? ( __w w `count` ) { ^ AG_COUNT } {}
    ? ( __w w `sum` ) { ^ AG_SUM } {}
    ? ( __w w `avg` ) { ^ AG_AVG } {}
    ? ( __w w `min` ) { ^ AG_MIN } {}
    ? ( __w w `max` ) { ^ AG_MAX } {}
    ^ 0
}

@ __primary inout P p → i {
    : Tok t ( vec_at [Tok] . p toks . p pos )
    ? == . t kind TK_INT { = . p pos + . p pos 1 ^ ( __lit p @ Value { VInt . t ival } ) } {}
    ? == . t kind TK_REAL { = . p pos + . p pos 1 ^ ( __lit p @ Value { VReal . t fval } ) } {}
    ? == . t kind TK_STR { = . p pos + . p pos 1 ^ ( __lit p @ Value { VText ( string_clone . t text ) } ) } {}
    ? ( __accept_op p `(` ) {
        : i e ( parse_expr p )
        ( __expect_op p `)` )
        ^ e
    } {}
    ? | != . t kind TK_ID ( __is_reserved . t text ) { ( __err p `an expression` ) } {}
    ? ( __accept_kw p `true` ) { ^ ( __lit p @ Value { VBool T } ) } {}
    ? ( __accept_kw p `false` ) { ^ ( __lit p @ Value { VBool F } ) } {}
    ? ( __accept_kw p `null` ) { ^ ( __lit p @ Value { VNull } ) } {}
    : String name ( __ident p )
    : i ag ( __agg_op name )
    ? & > ag 0 ( __is_op p `(` ) {
        ( __expect_op p `(` )
        : ~ i arg -1
        ? ( __accept_op p `*` ) {
            ? != ag AG_COUNT { ( __err p `a column (only COUNT takes *)` ) } {}
        } { = arg ( parse_expr p ) }
        ( __expect_op p `)` )
        ^ ( __node p EX_AGG ag arg -1 )
    } {}
    ? ( __accept_op p `.` ) {
        : String col ( __ident p )
        ^ ( __node_col p name col )
    } {}
    ^ ( __node_col p ( string_new ) name )
}

// [AS] alias, when one follows.
@ __alias inout P p → String {
    ? ( __accept_kw p `as` ) { ^ ( __ident p ) } {}
    : Tok t ( vec_at [Tok] . p toks . p pos )
    ? & == . t kind TK_ID ! ( __is_reserved . t text ) { ^ ( __ident p ) } {}
    ^ ( string_new )
}

@ __names inout P p → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ( __expect_op p `(` )
    ( vec_push [String] out ( __ident p ) )
    ~ ( __accept_op p `,` ) { ( vec_push [String] out ( __ident p ) ) }
    ( __expect_op p `)` )
    ^ out
}

@ __type inout P p → i {
    : String t ( __ident p )
    : s w ( string_data t )
    : i ty ? | | ( __w w `int` ) ( __w w `integer` ) ( __w w `bigint` ) TY_INT
    ? | | ( __w w `real` ) ( __w w `float` ) ( __w w `double` ) TY_REAL
    ? | ( __w w `text` ) ( __w w `varchar` ) TY_TEXT
    ? | ( __w w `bool` ) ( __w w `boolean` ) TY_BOOL 0
    ? == ty 0 { = . p pos - . p pos 1 ( __err p `a type (INT, REAL, TEXT, BOOL)` ) } {}
    // VARCHAR(n): the length is not kept.
    ? ( __accept_op p `(` ) { : i _n ( __int p ) ( __expect_op p `)` ) } {}
    ^ ty
}

@ __parse_select inout P p inout Stmt st → v {
    = . st distinct ( __accept_kw p `distinct` )
    ~ T {
        ? ( __accept_op p `*` ) {
            ( vec_push [SelItem] . st items @ SelItem { -1 ( string_new ) } )
        } {
            : i e ( parse_expr p )
            ( vec_push [SelItem] . st items @ SelItem { e ( __alias p ) } )
        }
        ? ! ( __accept_op p `,` ) { break } {}
    }
    ? ( __accept_kw p `from` ) {
        = . st table ( __ident p )
        = . st alias ( __alias p )
        : b inner ( __accept_kw p `inner` )
        ? ( __accept_kw p `join` ) {
            = . st jtable ( __ident p )
            = . st jalias ( __alias p )
            ( __expect_kw p `on` )
            = . st on ( parse_expr p )
        } { ? inner { ( __err p `JOIN` ) } {} }
    } {}
    ? ( __accept_kw p `where` ) { = . st where_e ( parse_expr p ) } {}
    ? ( __accept_kw p `group` ) {
        ( __expect_kw p `by` )
        ( vec_push [i] . st group ( parse_expr p ) )
        ~ ( __accept_op p `,` ) { ( vec_push [i] . st group ( parse_expr p ) ) }
    } {}
    ? ( __accept_kw p `having` ) { = . st having ( parse_expr p ) } {}
    ? ( __accept_kw p `order` ) {
        ( __expect_kw p `by` )
        ~ T {
            : i e ( parse_expr p )
            : b desc ( __accept_kw p `desc` )
            ? ! desc { : b _a ( __accept_kw p `asc` ) } {}
            ( vec_push [OrderItem] . st order @ OrderItem { e desc } )
            ? ! ( __accept_op p `,` ) { break } {}
        }
    } {}
    ? ( __accept_kw p `limit` ) {
        = . st limit ( __int p )
        ? ( __accept_kw p `offset` ) { = . st offset ( __int p ) } {}
    } {}
}

@ __parse_create_table inout P p inout Stmt st → v {
    = . st table ( __ident p )
    ( __expect_op p `(` )
    ~ T {
        ? ( __accept_kw p `primary` ) {
            ( __expect_kw p `key` )
            : ( Vec String ) pk ( __names p )
            ~ k pk { ( vec_push [String] . st cols k ) }
        } {
            : String name ( __ident p )
            : i ty ( __type p )
            : ~ b nn F
            : ~ b pk F
            ~ T {
                ? ( __accept_kw p `not` ) { ( __expect_kw p `null` ) = nn T continue } {}
                ? ( __accept_kw p `primary` ) { ( __expect_kw p `key` ) = pk T = nn T continue } {}
                break
            }
            ? pk { ( vec_push [String] . st cols ( string_clone name ) ) } {}
            ( vec_push [ColDef0] . st defs @ ColDef0 { name ty nn pk } )
        }
        ? ! ( __accept_op p `,` ) { break } {}
    }
    ( __expect_op p `)` )
}

// Parse one statement (a trailing `;` is fine).
@ sql_parse String src → Stmt {
    : ( Vec Tok ) toks ?? ( sql_lex src ) { T v → v F e → { ( panic_with e ) ^ ( stmt_new 0 ) } }
    : ~ P p @ P { toks 0 ( vec_new [Ex] ) }
    : ~ Stmt st ( stmt_new 0 )
    = . st explain ( __accept_kw p `explain` )
    ? ( __accept_kw p `select` ) {
        = . st kind ST_SELECT
        ( __parse_select p st )
    } {
        ? . st explain { ( __err p `SELECT after EXPLAIN` ) } {}
        ? ( __accept_kw p `insert` ) {
            = . st kind ST_INSERT
            ( __expect_kw p `into` )
            = . st table ( __ident p )
            ? ( __is_op p `(` ) { = . st cols ( __names p ) } {}
            ( __expect_kw p `values` )
            ~ T {
                ( __expect_op p `(` )
                : ( Vec i ) row ( vec_new [i] )
                ( vec_push [i] row ( parse_expr p ) )
                ~ ( __accept_op p `,` ) { ( vec_push [i] row ( parse_expr p ) ) }
                ( __expect_op p `)` )
                ( vec_push [( Vec i )] . st rows row )
                ? ! ( __accept_op p `,` ) { break } {}
            }
        } {
            ? ( __accept_kw p `update` ) {
                = . st kind ST_UPDATE
                = . st table ( __ident p )
                ( __expect_kw p `set` )
                ~ T {
                    ( vec_push [String] . st cols ( __ident p ) )
                    ( __expect_op p `=` )
                    ( vec_push [i] . st sets ( parse_expr p ) )
                    ? ! ( __accept_op p `,` ) { break } {}
                }
                ? ( __accept_kw p `where` ) { = . st where_e ( parse_expr p ) } {}
            } {
                ? ( __accept_kw p `delete` ) {
                    = . st kind ST_DELETE
                    ( __expect_kw p `from` )
                    = . st table ( __ident p )
                    ? ( __accept_kw p `where` ) { = . st where_e ( parse_expr p ) } {}
                } {
                    ? ( __accept_kw p `create` ) {
                        ? ( __accept_kw p `table` ) {
                            = . st kind ST_CREATE_TABLE
                            ( __parse_create_table p st )
                        } {
                            = . st unique ( __accept_kw p `unique` )
                            ( __expect_kw p `index` )
                            = . st kind ST_CREATE_INDEX
                            = . st name ( __ident p )
                            ( __expect_kw p `on` )
                            = . st table ( __ident p )
                            = . st cols ( __names p )
                        }
                    } {
                        ? | ( __accept_kw p `begin` ) ( __accept_kw p `start` ) {
                            = . st kind ST_BEGIN
                            : b _t ( __accept_kw p `transaction` )
                        } {
                            ? ( __accept_kw p `commit` ) { = . st kind ST_COMMIT } {
                                ? ( __accept_kw p `rollback` ) { = . st kind ST_ROLLBACK } {
                                    ? ( __accept_kw p `checkpoint` ) { = . st kind ST_CHECKPOINT } {
                                        ( __err p `a statement` )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    : b _semi ( __accept_op p `;` )
    ? != . ( vec_at [Tok] . p toks . p pos ) kind TK_EOF { ( __err p `the end of the statement` ) } {}
    = . st ex ( mem_replace [( Vec Ex )] . p ex ( vec_new [Ex] ) )
    ^ st
}
