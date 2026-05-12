"""
NURL compiler unit tests.
Run with: python -m pytest tests/test_compiler.py -v
or:        python tests/test_compiler.py
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.lexer       import Lexer, LexError, TT
from src.parser      import Parser, ParseError, parse
from src.typechecker import typecheck, TypeError as NurlTypeError
from src.ir_gen      import generate_ir


# ── helpers ───────────────────────────────────────────────────────

def lex(src): return Lexer(src).tokenize()
def tok_types(src): return [t.type for t in lex(src) if t.type != TT.EOF]
def do_parse(src): return parse(src)
def compile_(src):
    p = parse(src)
    typecheck(p)
    return generate_ir(p)


def assert_ok(src):
    p = parse(src)
    typecheck(p)
    return generate_ir(p)


def assert_type_error(src):
    try:
        p = parse(src)
        typecheck(p)
        raise AssertionError(f"expected TypeError, got none")
    except NurlTypeError:
        pass


# ── Lexer tests ───────────────────────────────────────────────────

def test_lex_integer():
    types = tok_types('42')
    assert types == [TT.INT]

def test_lex_float():
    types = tok_types('3.14')
    assert types == [TT.FLOAT]

def test_lex_string():
    types = tok_types('`hello world`')
    assert types == [TT.STR]
    tok = lex('`hello world`')[0]
    assert tok.value == 'hello world'

def test_lex_bool():
    types = tok_types('T F')
    assert types == [TT.BOOL, TT.BOOL]

def test_lex_type_keywords():
    types = tok_types('i u f b s v')
    assert all(t == TT.TYPE_KW for t in types)

def test_lex_arrow_unicode():
    types = tok_types('→')
    assert types == [TT.ARROW]

def test_lex_arrow_ascii():
    types = tok_types('->')
    assert types == [TT.ARROW]

def test_lex_two_char_ops():
    src = '== != <= >='
    types = tok_types(src)
    assert types == [TT.EQ, TT.NEQ, TT.LEQ, TT.GEQ]

def test_lex_comment_ignored():
    types = tok_types('42 // this is a comment\n 99')
    assert types == [TT.INT, TT.INT]

def test_lex_underscore_int():
    tok = lex('1_000_000')[0]
    assert tok.value == '1000000'

def test_lex_scientific_float():
    tok = lex('1.5e10')[0]
    assert tok.type == TT.FLOAT
    assert tok.value == '1.5e10'

def test_lex_multiline_string():
    tok = lex('`line1\nline2`')[0]
    assert tok.type == TT.STR
    assert 'line1' in tok.value and 'line2' in tok.value

def test_lex_unterminated_string():
    try:
        lex('`oops')
        raise AssertionError("expected LexError")
    except LexError:
        pass


# ── Parser tests ──────────────────────────────────────────────────

def test_parse_fn_decl():
    from src.ast_nodes import FnDecl, BaseType
    p = do_parse('@ double i n → i { ^ + n n }')
    assert len(p.decls) == 1
    fn = p.decls[0]
    assert isinstance(fn, FnDecl)
    assert fn.name == 'double'
    assert len(fn.params) == 1
    assert fn.params[0].name == 'n'
    assert isinstance(fn.ret_type, BaseType)
    assert fn.ret_type.name == 'i'

def test_parse_struct_decl():
    from src.ast_nodes import StructDecl
    p = do_parse(': Point { i x  i y }')
    assert len(p.decls) == 1
    s = p.decls[0]
    assert isinstance(s, StructDecl)
    assert s.name == 'Point'
    assert len(s.fields) == 2

def test_parse_let_stmt():
    from src.ast_nodes import LetStmt, IntLit
    p = do_parse('@ main → v { : i n 42 }')
    body = p.decls[0].body
    assert isinstance(body.stmts[0], LetStmt)
    assert body.stmts[0].name == 'n'

def test_parse_binary_expr():
    from src.ast_nodes import BinExpr, IntLit
    p = do_parse('@ f → i { ^ + 1 2 }')
    from src.ast_nodes import RetExpr
    ret = p.decls[0].body.stmts[0].expr
    assert isinstance(ret, RetExpr)
    assert isinstance(ret.expr, BinExpr)
    assert ret.expr.op == '+'

def test_parse_call_expr():
    from src.ast_nodes import CallExpr, IdentExpr
    p = do_parse('@ g → i { ^ ( add 1 2 ) }\n@ add i x i y → i { ^ + x y }')
    from src.ast_nodes import RetExpr
    ret = p.decls[0].body.stmts[0].expr
    assert isinstance(ret, RetExpr)
    assert isinstance(ret.expr, CallExpr)

def test_parse_cond_expr():
    from src.ast_nodes import CondExpr
    p = do_parse('@ f i n → i { ? < n 0 0 n }')
    from src.ast_nodes import ExprStmt
    stmt = p.decls[0].body.stmts[0]
    assert isinstance(stmt.expr, CondExpr)

def test_parse_member_expr():
    from src.ast_nodes import MemberExpr
    p = do_parse(': P { i x }\n@ f P p → i { ^ . p x }')
    from src.ast_nodes import RetExpr
    ret = p.decls[1].body.stmts[0].expr
    assert isinstance(ret, RetExpr)
    assert isinstance(ret.expr, MemberExpr)
    assert ret.expr.field == 'x'

def test_parse_optional_type():
    from src.ast_nodes import OptType, BaseType
    p = do_parse(': ?i n 0')
    from src.ast_nodes import ConstDecl
    # const decl: parse_colon_decl with type=?i, name=n
    # Actually this creates ConstDecl with type=?i — but the expr '0' doesn't
    # match ?i; that's a type error, not a parse error.
    assert len(p.decls) == 1


# ── Type-checker tests ────────────────────────────────────────────

def test_type_add_ints():
    assert_ok('@ add i x i y → i { ^ + x y }')

def test_type_bool_result():
    assert_ok('@ pos i n → b { ^ > n 0 }')

def test_type_cond_matching_branches():
    assert_ok('@ abs i n → i { ^ ? < n 0 ~ n n }')

def test_type_struct_member():
    assert_ok(': P { i x  i y }\n@ getx P p → i { ^ . p x }')

def test_type_fn_call():
    assert_ok('@ double i n → i { ^ + n n }\n@ main → i { ^ ( double 5 ) }')

def test_type_loop():
    assert_ok('''
@ count i n → v {
  : i k 0
  ~ < k n {
    = k + k 1
  }
}
''')

def test_type_error_mismatched_binop():
    assert_type_error('@ f → i { ^ + 1 3.0 }')

def test_type_error_wrong_arg():
    assert_type_error('''
@ double i n → i { ^ + n n }
@ main → i { ^ ( double 3.14 ) }
''')

def test_type_error_cond_branches_differ():
    assert_type_error('@ f i n → i { ^ ? < n 0 1 3.0 }')

def test_type_error_wrong_cond():
    assert_type_error('@ f i n → i { ^ ? n 1 0 }')


# ── IR generation tests ───────────────────────────────────────────

def test_ir_add():
    ir = compile_('@ add i x i y → i { ^ + x y }')
    assert 'fn @add' in ir
    assert 'add i64' in ir
    assert 'ret i64' in ir

def test_ir_struct():
    ir = compile_(': Point { i x  i y }')
    assert 'type %Point' in ir
    assert 'i64' in ir

def test_ir_cond():
    ir = compile_('@ abs i n → i { ^ ? < n 0 ~ n n }')
    assert 'brc' in ir
    assert 'phi i64' in ir
    assert 'ret i64' in ir

def test_ir_loop():
    ir = compile_('''
@ count i n → v {
  : i k 0
  ~ < k n {
    = k + k 1
  }
}
''')
    assert 'loop_check' in ir
    assert 'loop_body' in ir
    assert 'brc' in ir
    assert 'ret void' in ir

def test_ir_module_name():
    ir = compile_('@ f → v {}')
    assert ir.startswith('module')


# ── Runner ────────────────────────────────────────────────────────

if __name__ == '__main__':
    import traceback
    tests = [(k, v) for k, v in globals().items() if k.startswith('test_')]
    passed = failed = 0
    for name, fn in tests:
        try:
            fn()
            print(f'  ok  {name}')
            passed += 1
        except Exception as e:
            print(f'  FAIL {name}')
            traceback.print_exc()
            failed += 1
    print(f'\n{passed} passed, {failed} failed')
    sys.exit(0 if failed == 0 else 1)
