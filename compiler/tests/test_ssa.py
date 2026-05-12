"""
SSA phi-node correctness tests.
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.parser      import parse
from src.typechecker import typecheck
from src.ir_gen      import generate_ir, _collect_mutations
from src.ast_nodes   import Block, SetStmt, ExprStmt, IntLit, Pos


def compile_(src):
    p = parse(src)
    typecheck(p)
    return generate_ir(p)


def phi_lines_in_block(ir: str, label: str) -> list:
    """Return phi-instruction lines inside the given label's block."""
    lines = ir.splitlines()
    in_block = False
    result = []
    for line in lines:
        stripped = line.strip()
        if stripped == f'lbl {label}:':
            in_block = True
            continue
        if in_block:
            if stripped.startswith('lbl ') and stripped.endswith(':'):
                break   # next block started
            if 'phi' in stripped:
                result.append(stripped)
    return result


# ── Mutation analysis ────────────────────────────────────────────────

def test_collect_mutations_simple():
    """SetStmt names are collected."""
    from src.ast_nodes import Block, SetStmt, ExprStmt, IntLit, Pos, IdentExpr
    p = Pos(0, 0)
    blk = Block([
        SetStmt('acc', IntLit(0, p), p),
        SetStmt('k',   IntLit(1, p), p),
    ], p)
    assert _collect_mutations(blk) == {'acc', 'k'}


def test_collect_mutations_ignores_let():
    """LetStmt (new binding) is NOT a mutation of an outer name."""
    from src.ast_nodes import LetStmt, BaseType
    p = Pos(0, 0)
    blk = Block([
        LetStmt(BaseType('i'), 'n', IntLit(0, p), p),
    ], p)
    assert _collect_mutations(blk) == set()


def test_collect_mutations_no_nested_loop():
    """Mutations inside a nested loop are NOT collected (they handle their own phi)."""
    from src.ast_nodes import LoopExpr, BoolLit, ExprStmt
    p = Pos(0, 0)
    inner_body = Block([SetStmt('x', IntLit(0, p), p)], p)
    loop = LoopExpr(BoolLit(False, p), inner_body, p)
    outer = Block([ExprStmt(loop, p)], p)
    assert _collect_mutations(outer) == set()


# ── Loop phi generation ───────────────────────────────────────────────

def test_loop_phi_nodes_exist():
    """loop_check block must contain phi nodes for mutated variables."""
    ir = compile_('''
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
    phis = phi_lines_in_block(ir, 'loop_check_0')
    assert len(phis) == 2, f"Expected 2 phi nodes, got {len(phis)}: {phis}"


def test_loop_phi_has_entry_predecessor():
    """Each phi must cite 'entry' as one predecessor (the pre-loop value)."""
    ir = compile_('''
@ countdown i n → i {
  : i k n
  ~ > k 0 {
    = k - k 1
  }
  ^ k
}
''')
    phis = phi_lines_in_block(ir, 'loop_check_0')
    assert len(phis) == 1
    assert 'entry' in phis[0], f"phi missing entry: {phis[0]}"


def test_loop_phi_has_body_predecessor():
    """Each phi must cite 'loop_body_*' as the back-edge predecessor."""
    ir = compile_('''
@ countdown i n → i {
  : i k n
  ~ > k 0 {
    = k - k 1
  }
  ^ k
}
''')
    phis = phi_lines_in_block(ir, 'loop_check_0')
    assert any('loop_body' in p for p in phis), f"phi missing loop_body: {phis}"


def test_ret_uses_phi_register():
    """The return value after a loop must be the phi register (valid SSA)."""
    ir = compile_('''
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
    phis   = phi_lines_in_block(ir, 'loop_check_0')
    phi_regs = [p.split()[0] for p in phis]   # e.g. ['%2', '%3']

    lines = ir.splitlines()
    ret_line = next((l for l in lines if 'ret i64' in l), None)
    assert ret_line is not None, "no ret instruction found"

    ret_reg = ret_line.strip().split()[-1]
    assert ret_reg in phi_regs, (
        f"ret uses {ret_reg!r}, expected one of {phi_regs}. "
        f"phi lines: {phis}"
    )


def test_no_phi_in_simple_fn():
    """Non-looping functions must not contain phi nodes."""
    ir = compile_('@ add i x i y → i { ^ + x y }')
    assert 'phi' not in ir


def test_no_phi_in_cond_fn():
    """Pure conditional without loops: no phi in non-cond blocks."""
    ir = compile_('@ abs i n → i { ^ ? < n 0 ~ n n }')
    # phi IS expected inside end_* (merge of if-else), but NOT in entry
    entry_lines = phi_lines_in_block(ir, 'entry')
    assert entry_lines == [], f"unexpected phi in entry: {entry_lines}"


def test_single_mutation_loop():
    """Loop that mutates only one variable: exactly 1 phi node."""
    ir = compile_('''
@ countdown i n → i {
  : i k n
  ~ > k 0 {
    = k - k 1
  }
  ^ k
}
''')
    phis = phi_lines_in_block(ir, 'loop_check_0')
    assert len(phis) == 1, f"Expected 1 phi, got {len(phis)}: {phis}"


def test_condition_uses_phi():
    """The loop condition must reference the phi register (not the pre-loop reg)."""
    ir = compile_('''
@ countdown i n → i {
  : i k n
  ~ > k 0 {
    = k - k 1
  }
  ^ k
}
''')
    phis = phi_lines_in_block(ir, 'loop_check_0')
    phi_reg = phis[0].split()[0]   # e.g. '%2'

    # The line after the phi should use phi_reg in the condition
    lines = ir.splitlines()
    check_start = next(i for i, l in enumerate(lines) if 'lbl loop_check_0:' in l)
    # Find the 'gt' or 'lt' condition line after loop_check_0
    cond_line = next(
        (l for l in lines[check_start:] if any(op in l for op in ('lt ', 'gt ', 'le ', 'ge '))),
        None
    )
    assert cond_line is not None, "no condition line found"
    assert phi_reg in cond_line, (
        f"condition {cond_line!r} does not reference phi reg {phi_reg!r}"
    )


# ── Runner ────────────────────────────────────────────────────────────

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
