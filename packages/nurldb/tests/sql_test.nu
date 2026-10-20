// sql_test.nu — SQL, end to end, one session.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/sql_test.nu /tmp/st && /tmp/st
//
// Tables with a primary key; INSERT, SELECT with WHERE / ORDER BY (by
// name, alias and position) / GROUP BY / HAVING / DISTINCT / LIMIT,
// aggregates, joins (hash and nested loop), UPDATE and DELETE, NULL in
// arithmetic, comparisons and logic, LIKE / IN / BETWEEN, an index scan
// in the plan, a duplicate key refused, BEGIN … ROLLBACK undone, and a
// statement error rolling its transaction back.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/fs.nu`
$ `src/exec.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
    ( flush )
}

// Run `sql`; the result, or an empty one tagged with the error.
@ q inout Session s s sql → Result {
    ^ ?? ( session_exec s ( string_from sql ) ) {
        T r → r
        F e → @ Result { ( vec_new [String] ) ( vec_new [( Vec Value )] ) -1 ( string_concat ( string_from `ERROR: ` ) e ) }
    }
}

// The rows of `sql` as text, `a,b;c,d`.
@ rows inout Session s s sql → String {
    : Result r ( q s sql )
    ? == . r affected -1 { ^ ( string_clone . r tag ) } {}
    : String out ( string_new )
    : ~ i k 0
    ~ row . r rows {
        ? > k 0 { ( string_push_char out 59 ) } {}
        : ~ i j 0
        ~ cell row {
            ? > j 0 { ( string_push_char out 44 ) } {}
            : String t ( val_text cell )
            ( string_push_str out ( string_data t ) )
            = j + j 1
        }
        = k + k 1
    }
    ^ out
}

@ is String got s want → b {
    : b ok != 0 ( nurl_str_eq ( string_data got ) want )
    ? ! ok { ( nurl_print `    got: ` ) ( nurl_println ( string_data got ) ) } {}
    ^ ok
}

@ tag inout Session s s sql → String { : Result r ( q s sql ) ^ ( string_clone . r tag ) }

@ main → i {
    : s dir `/tmp/nurldb_sql_test`
    ?? ( file_delete ( nurl_str_cat dir `/data` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/log` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/clog` ) ) { T _ → {} F _ → {} }
    : Db d ?? ( db_open dir ( db_default_opts ) ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    : ~ Session s ( session_new d )
    ( check `CREATE TABLE` ( is ( tag s `CREATE TABLE emp (id INT PRIMARY KEY, name TEXT NOT NULL, dept TEXT, salary REAL)` ) `CREATE TABLE` ) )
    ( check `INSERT four rows` ( is ( tag s `INSERT INTO emp VALUES (1, 'Ada', 'eng', 120.0), (2, 'Bob', 'eng', 95.5), (3, 'Cy', 'ops', 70), (4, 'Di', NULL, 88)` ) `INSERT 0 4` ) )
    ( check `SELECT * ORDER BY` ( is ( rows s `SELECT * FROM emp ORDER BY id` ) `1,Ada,eng,120;2,Bob,eng,95.5;3,Cy,ops,70;4,Di,NULL,88` ) )
    ( check `WHERE, an expression, ORDER BY its alias DESC` ( is ( rows s `SELECT name, salary * 2 AS d FROM emp WHERE salary > 80 ORDER BY d DESC` ) `Ada,240;Bob,191;Di,176` ) )
    ( check `GROUP BY with COUNT and AVG, NULL first` ( is ( rows s `SELECT dept, COUNT(*), AVG(salary) FROM emp GROUP BY dept ORDER BY dept` ) `NULL,1,88;eng,2,107.75;ops,1,70` ) )
    ( check `HAVING` ( is ( rows s `SELECT dept, COUNT(*) FROM emp GROUP BY dept HAVING COUNT(*) > 1` ) `eng,2` ) )
    ( check `aggregates over the table` ( is ( rows s `SELECT COUNT(*), MIN(salary), MAX(salary), SUM(id), COUNT(dept) FROM emp` ) `4,70,120,10,3` ) )
    ( check `aggregates over no rows` ( is ( rows s `SELECT COUNT(*), SUM(id), MAX(name) FROM emp WHERE id > 100` ) `0,NULL,NULL` ) )
    ( check `the primary key gives an index scan` ( is ( rows s `EXPLAIN SELECT * FROM emp WHERE id = 3` ) `Filter;  -> Index Scan using emp_pkey on emp` ) )
    ( check `and finds the row` ( is ( rows s `SELECT name FROM emp WHERE id = 3` ) `Cy` ) )
    ( check `a range on the key` ( is ( rows s `SELECT id FROM emp WHERE id >= 2 AND id < 4 ORDER BY id` ) `2;3` ) )
    ( check `DISTINCT` ( is ( rows s `SELECT DISTINCT dept FROM emp WHERE dept IS NOT NULL ORDER BY 1` ) `eng;ops` ) )
    ( check `LIMIT and OFFSET` ( is ( rows s `SELECT id FROM emp ORDER BY id LIMIT 2 OFFSET 1` ) `2;3` ) )
    ( check `LIKE, IN, ORDER BY position` ( is ( rows s `SELECT name FROM emp WHERE name LIKE '%a%' OR id IN (2, 3) ORDER BY 1` ) `Ada;Bob;Cy` ) )
    ( check `BETWEEN and NOT` ( is ( rows s `SELECT id FROM emp WHERE salary BETWEEN 80 AND 100 AND NOT id = 4` ) `2` ) )
    ( check `NULL: unknown is not true, IS NULL is` ( is ( rows s `SELECT COUNT(*) FROM emp WHERE dept = NULL OR dept <> 'eng'` ) `1` ) )
    ( check `expressions without a table` ( is ( rows s `SELECT 1 + 2 * 3, 'a' || 'b', 7 / 2, 7.0 / 2, NULL IS NULL, NULL + 1` ) `7,ab,3,3.5,true,NULL` ) )
    ( check `UPDATE` ( is ( tag s `UPDATE emp SET salary = salary + 10 WHERE dept = 'eng'` ) `UPDATE 2` ) )
    ( check `the new values` ( is ( rows s `SELECT name, salary FROM emp WHERE dept = 'eng' ORDER BY name` ) `Ada,130;Bob,105.5` ) )
    ( check `UPDATE of the key column keeps it unique` ( is ( tag s `UPDATE emp SET id = 2 WHERE id = 1` ) `ERROR: nurldb: duplicate key in the unique index emp_pkey` ) )
    ( check `and changed nothing` ( is ( rows s `SELECT id FROM emp ORDER BY id` ) `1;2;3;4` ) )
    ( check `DELETE` ( is ( tag s `DELETE FROM emp WHERE dept IS NULL` ) `DELETE 1` ) )
    ( check `a duplicate key is refused` ( is ( tag s `INSERT INTO emp VALUES (1, 'Dup', 'x', 1)` ) `ERROR: nurldb: duplicate key in the unique index emp_pkey` ) )
    ( check `NOT NULL is kept` ( is ( tag s `INSERT INTO emp (id, dept) VALUES (9, 'x')` ) `ERROR: nurldb: NULL in the NOT NULL column name` ) )
    ( check `a type mismatch is refused` ( is ( tag s `INSERT INTO emp VALUES ('x', 'y', 'z', 1)` ) `ERROR: nurldb: a TEXT value for the column id of type INT` ) )
    ( check `a second table` ( is ( tag s `CREATE TABLE dept (code TEXT PRIMARY KEY, title TEXT)` ) `CREATE TABLE` ) )
    ( check `rows in it` ( is ( tag s `INSERT INTO dept VALUES ('eng', 'Engineering'), ('ops', 'Operations'), ('hr', 'People')` ) `INSERT 0 3` ) )
    ( check `an equality join is a hash join` ( is ( rows s `EXPLAIN SELECT e.name, d.title FROM emp e JOIN dept d ON e.dept = d.code` ) `Hash Join;  -> Seq Scan on emp;  -> Seq Scan on dept` ) )
    ( check `the join` ( is ( rows s `SELECT e.name, d.title FROM emp e JOIN dept d ON e.dept = d.code ORDER BY e.name` ) `Ada,Engineering;Bob,Engineering;Cy,Operations` ) )
    ( check `a join on an inequality` ( is ( rows s `SELECT COUNT(*) FROM emp e JOIN dept d ON e.dept < d.code` ) `4` ) )
    ( check `an aggregate over a join` ( is ( rows s `SELECT d.title, COUNT(*) FROM emp e JOIN dept d ON e.dept = d.code GROUP BY d.title ORDER BY 2 DESC, 1` ) `Engineering,2;Operations,1` ) )
    ( check `CREATE INDEX` ( is ( tag s `CREATE INDEX by_name ON emp (name)` ) `CREATE INDEX` ) )
    ( check `used for a lookup` ( is ( rows s `EXPLAIN SELECT id FROM emp WHERE name = 'Bob'` ) `Filter;  -> Index Scan using by_name on emp` ) )
    ( check `and right` ( is ( rows s `SELECT id FROM emp WHERE name = 'Bob'` ) `2` ) )
    ( check `BEGIN` ( is ( tag s `BEGIN` ) `BEGIN` ) )
    ( check `INSERT in the transaction` ( is ( tag s `INSERT INTO emp VALUES (10, 'Temp', 'ops', 1)` ) `INSERT 0 1` ) )
    ( check `it sees its own row` ( is ( rows s `SELECT COUNT(*) FROM emp` ) `4` ) )
    ( check `ROLLBACK` ( is ( tag s `ROLLBACK` ) `ROLLBACK` ) )
    ( check `the row is gone` ( is ( rows s `SELECT COUNT(*) FROM emp` ) `3` ) )
    ( check `a failed statement ends its transaction` ( is ( tag s `BEGIN` ) `BEGIN` ) )
    ( check `(the statement)` ( is ( tag s `INSERT INTO emp VALUES (11, 'X', 'ops', 1), (1, 'Dup', 'ops', 1)` ) `ERROR: nurldb: duplicate key in the unique index emp_pkey` ) )
    ( check `(nothing of it stays)` ( is ( rows s `SELECT COUNT(*) FROM emp WHERE id = 11` ) `0` ) )
    ( check `a syntax error says where` ( is ( tag s `SELECT FROM WHERE` ) `ERROR: nurldb: syntax error: expected an expression near 'from'` ) )
    ( check `an unknown column is named` ( is ( tag s `SELECT nope FROM emp` ) `ERROR: nurldb: no such column: nope` ) )
    ( session_close s )
    ( db_close d )
    ( nurl_print `sql_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}
