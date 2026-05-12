"""
LLVM IR generator tests.

Verifies that generated LLVM IR has correct structure and syntax.
To actually compile: clang -O2 <file.ll> -o <output>
"""

import sys, os, re
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.parser      import parse
from src.typechecker import typecheck
from src.llvm_gen    import generate_llvm, _llvm_type, _encode_str
from src.ast_nodes   import BaseType, PtrType, SliceType, NamedType


def llvm(src: str) -> str:
    p = parse(src)
    typecheck(p)
    return generate_llvm(p)


def lines_of(ir: str, label: str) -> list[str]:
    """Lines inside a given basic block label."""
    result, in_block = [], False
    for line in ir.splitlines():
        s = line.strip()
        if s == f'{label}:':
            in_block = True; continue
        if in_block:
            if re.match(r'^\w[\w\d_]*:$', s) or s == '}':
                break
            if s:
                result.append(s)
    return result


# ── Type mapping ───────────────────────────────────────────────────

def test_type_base():
    assert _llvm_type(BaseType('i')) == 'i64'
    assert _llvm_type(BaseType('u')) == 'i64'
    assert _llvm_type(BaseType('f')) == 'double'
    assert _llvm_type(BaseType('b')) == 'i1'
    assert _llvm_type(BaseType('s')) == 'i8*'
    assert _llvm_type(BaseType('v')) == 'void'

def test_type_ptr():
    assert _llvm_type(PtrType(BaseType('i'))) == 'i64*'

def test_type_slice():
    assert _llvm_type(SliceType(BaseType('i'))) == '{ i64, i64* }'

def test_type_named():
    assert _llvm_type(NamedType('Point')) == '%Point'


# ── String encoding ────────────────────────────────────────────────

def test_encode_str_hello():
    enc, length = _encode_str('hello')
    assert '\\00' in enc
    assert length == 6  # 5 chars + null

def test_encode_str_empty():
    enc, length = _encode_str('')
    assert enc == '\\00'
    assert length == 1

def test_encode_str_special():
    enc, _ = _encode_str('"quoted"')
    assert '"' not in enc   # quotes must be escaped


# ── Module header ──────────────────────────────────────────────────

def test_module_has_header():
    ir = llvm('@ f → v {}')
    # No hardcoded target triple — clang auto-detects the host.
    assert 'NURL' in ir   # module comment must be present

def test_module_has_libc_decls():
    ir = llvm('@ f → v {}')
    assert 'declare i32 @puts(' in ir
    assert 'declare i8* @malloc(' in ir

def test_struct_type_emitted():
    ir = llvm(': Point { i x  i y }')
    assert '%Point = type { i64, i64 }' in ir


# ── Function signatures ────────────────────────────────────────────

def test_fn_simple():
    ir = llvm('@ add i x i y → i { ^ + x y }')
    assert 'define i64 @add(i64 %x, i64 %y)' in ir

def test_fn_void():
    ir = llvm('@ nothing → v {}')
    assert 'define void @nothing()' in ir

def test_fn_float():
    ir = llvm('@ square f x → f { ^ * x x }')
    assert 'define double @square(double %x)' in ir

def test_fn_bool():
    ir = llvm('@ pos i n → b { ^ > n 0 }')
    assert 'define i1 @pos(i64 %n)' in ir

def test_fn_struct_param():
    ir = llvm(': P { i x }\n@ getx P p → i { ^ . p x }')
    assert 'define i64 @getx(%P %p)' in ir


# ── Arithmetic instructions ────────────────────────────────────────

def test_arith_add():
    ir = llvm('@ f i x i y → i { ^ + x y }')
    assert 'add i64' in ir

def test_arith_sub():
    ir = llvm('@ f i x i y → i { ^ - x y }')
    assert 'sub i64' in ir

def test_arith_mul():
    ir = llvm('@ f i x i y → i { ^ * x y }')
    assert 'mul i64' in ir

def test_arith_div():
    ir = llvm('@ f i x i y → i { ^ / x y }')
    assert 'sdiv i64' in ir

def test_arith_float():
    ir = llvm('@ f f x f y → f { ^ + x y }')
    assert 'fadd double' in ir

def test_arith_float_mul():
    ir = llvm('@ f f x f y → f { ^ * x y }')
    assert 'fmul double' in ir


# ── Comparison instructions ────────────────────────────────────────

def test_cmp_lt():
    ir = llvm('@ f i x i y → b { ^ < x y }')
    assert 'icmp slt i64' in ir

def test_cmp_gt():
    ir = llvm('@ f i x i y → b { ^ > x y }')
    assert 'icmp sgt i64' in ir

def test_cmp_eq():
    ir = llvm('@ f i x i y → b { ^ == x y }')
    assert 'icmp eq i64' in ir

def test_cmp_float():
    ir = llvm('@ f f x f y → b { ^ < x y }')
    assert 'fcmp olt double' in ir


# ── Unary instructions ─────────────────────────────────────────────

def test_unary_not():
    ir = llvm('@ f b x → b { ^ ! x }')
    assert 'xor i1' in ir
    assert ', 1' in ir

def test_unary_complement_int():
    ir = llvm('@ f i x → i { ^ ~ x }')
    assert 'xor i64' in ir
    assert ', -1' in ir

def test_unary_negate_float():
    ir = llvm('@ f f x → f { ^ ~ x }')
    assert 'fneg double' in ir


# ── Control flow ───────────────────────────────────────────────────

def test_cond_has_branch():
    ir = llvm('@ f i n → i { ^ ? < n 0 0 n }')
    assert 'br i1' in ir
    assert 'phi i64' in ir

def test_cond_phi_has_two_preds():
    ir = llvm('@ f i n → i { ^ ? < n 0 0 n }')
    phi_lines = [l for l in ir.splitlines() if 'phi' in l]
    assert len(phi_lines) >= 1
    # Each phi must have exactly two predecessors [ v, %lbl ]
    for phi in phi_lines:
        assert phi.count('[') == 2, f"phi should have 2 predecessors: {phi}"


# ── Loop with phi nodes ────────────────────────────────────────────

def test_loop_phi_in_check_block():
    ir = llvm('''
@ count i n → i {
  : i k 0
  ~ < k n {
    = k + k 1
  }
  ^ k
}
''')
    check_lines = lines_of(ir, 'loop_check_0')
    phi_lines = [l for l in check_lines if 'phi' in l]
    assert len(phi_lines) == 1, f"Expected 1 phi in loop_check_0, got: {phi_lines}"

def test_loop_phi_entry_pred():
    ir = llvm('''
@ count i n → i {
  : i k 0
  ~ < k n { = k + k 1 }
  ^ k
}
''')
    phi_line = next(l for l in ir.splitlines() if 'phi' in l)
    assert '%entry' in phi_line, f"phi missing %entry: {phi_line}"

def test_loop_phi_body_pred():
    ir = llvm('''
@ count i n → i {
  : i k 0
  ~ < k n { = k + k 1 }
  ^ k
}
''')
    phi_line = next(l for l in ir.splitlines() if 'phi' in l)
    assert 'loop_body' in phi_line, f"phi missing loop_body: {phi_line}"

def test_loop_literal_in_phi():
    """Integer literals (not registers) must be valid phi predecessors."""
    ir = llvm('''
@ sumto i n → i {
  : i acc 0
  : i k   1
  ~ <= k n {
    = acc + acc k
    = k   + k   1
  }
  ^ acc
}
''')
    phi_lines = [l for l in ir.splitlines() if 'phi' in l]
    # At least one phi with literal 0 or 1 as predecessor
    assert any('[ 0,' in l or '[ 1,' in l for l in phi_lines), \
        f"Expected literal predecessor in phi: {phi_lines}"

def test_loop_two_phi_nodes():
    ir = llvm('''
@ sumto i n → i {
  : i acc 0
  : i k   1
  ~ <= k n {
    = acc + acc k
    = k   + k   1
  }
  ^ acc
}
''')
    phi_lines = [l for l in ir.splitlines() if 'phi' in l]
    assert len(phi_lines) == 2, f"Expected 2 phi nodes, got: {phi_lines}"

def test_loop_ret_uses_phi():
    """Return must use one of the phi registers (not a stale loop-body reg)."""
    ir = llvm('''
@ sumto i n → i {
  : i acc 0
  : i k   1
  ~ <= k n {
    = acc + acc k
    = k   + k   1
  }
  ^ acc
}
''')
    phi_lines = [l for l in ir.splitlines() if 'phi' in l]
    phi_regs  = [l.split()[0] for l in phi_lines]
    ret_line  = next(l for l in ir.splitlines() if 'ret i64' in l)
    ret_reg   = ret_line.strip().split()[-1]
    assert ret_reg in phi_regs, \
        f"ret uses {ret_reg!r}, expected phi reg from {phi_regs}"


# ── Struct member access ───────────────────────────────────────────

def test_member_extractvalue():
    ir = llvm(': P { i x  i y }\n@ getx P p → i { ^ . p x }')
    assert 'extractvalue %P' in ir
    assert ', 0' in ir   # x is field index 0

def test_member_second_field():
    ir = llvm(': P { i x  i y }\n@ gety P p → i { ^ . p y }')
    assert 'extractvalue %P' in ir
    assert ', 1' in ir   # y is field index 1


# ── String literals ────────────────────────────────────────────────

def test_string_global_emitted():
    ir = llvm('@ f → s { ^ `hello` }')
    assert '@.str.0' in ir
    assert 'constant' in ir
    assert 'hello' in ir

def test_string_getelementptr():
    ir = llvm('@ f → s { ^ `hello` }')
    assert 'getelementptr' in ir

def test_string_multiple_unique():
    ir = llvm('@ f i n → s { ^ ? < n 0 `yes` `no` }')
    assert '@.str.0' in ir
    assert '@.str.1' in ir

def test_string_deduplication():
    ir = llvm('@ f i n → s { ^ ? < n 0 `same` `same` }')
    assert '@.str.0' in ir
    assert '@.str.1' not in ir  # deduplicated


# ── Cast ───────────────────────────────────────────────────────────

def test_cast_int_to_float():
    ir = llvm('@ f i n → f { ^ # f n }')
    assert 'sitofp' in ir

def test_cast_float_to_int():
    ir = llvm('@ f f x → i { ^ # i x }')
    assert 'fptosi' in ir


# ── Function call ──────────────────────────────────────────────────

def test_call_emitted():
    ir = llvm('@ double i n → i { ^ + n n }\n@ main → i { ^ ( double 5 ) }')
    assert 'call i64 @double' in ir

def test_call_with_args():
    ir = llvm('@ add i x i y → i { ^ + x y }\n@ main → i { ^ ( add 3 4 ) }')
    assert 'call i64 @add(i64' in ir


# ── Stdlib built-ins ───────────────────────────────────────────────

def test_stdlib_declares_present():
    ir = llvm('@ f → v {}')
    assert 'declare void @nurl_print_int(i64)' in ir
    assert 'declare void @nurl_print_str(i8*)' in ir
    assert 'declare void @nurl_print_bool(i1)' in ir
    assert 'declare i64  @nurl_read_int()' in ir

def test_stdlib_print_int_call():
    ir = llvm('@ main → v { ( print_int 42 ) }')
    assert 'call void @nurl_print_int(i64 42)' in ir

def test_stdlib_print_str_call():
    ir = llvm('@ main → v { ( print_str `hi` ) }')
    assert 'call void @nurl_print_str(i8*' in ir

def test_stdlib_print_bool_call():
    ir = llvm('@ main → v { ( print_bool T ) }')
    assert 'call void @nurl_print_bool(i1 1)' in ir

def test_stdlib_typechecks():
    """Stdlib functions must be callable without explicit declaration."""
    from src.typechecker import typecheck
    from src.parser import parse
    src = '@ main → v { ( print_int 7 ) ( print_str `ok` ) ( print_bool F ) }'
    p = parse(src)
    typecheck(p)   # must not raise


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
