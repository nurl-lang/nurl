# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""
NURL IR Generator — typed AST → NUR-IR text (SSA form).

SSA construction strategy
──────────────────────────
Expressions produce fresh virtual registers (%0, %1, …).
Let/set bindings create named copies (%name, %name_N, …).

For loops the generator must insert phi nodes at the loop header
BEFORE knowing the back-edge values.  We use two mechanisms:

  1. _collect_mutations(block)  — pre-scan the AST for all SetStmt
     names directly inside a block (not recursing into nested loops).

  2. _reserve_line() / _patch_line() — output is stored in a list[str|None];
     a slot can be reserved (index returned) and patched later once the
     back-edge register is known.

  3. _cur_label tracking — every time we start a new basic block we update
     _cur_label so phi instructions know which predecessor label to cite.

Known limitation (v0.1)
───────────────────────
If a loop body contains a conditional (CondExpr) that itself mutates a
variable, the phi back-edge label may be wrong.  Full correctness requires
a dom-tree–based SSA construction (Braun et al. 2013) planned for v0.2.
"""

from __future__ import annotations
from typing import List, Optional, Dict, Set
from .ast_nodes import (
    Program, Decl, Stmt, Expr, Block, Param, NurlType,
    BaseType, PtrType, SliceType, OptType, FnType, NamedType,
    FnDecl, StructDecl, ConstDecl, ImportDecl,
    VariantDecl, EnumDecl, EnumConstructor,
    MatchPattern, MatchCase, MatchExpr,
    LetStmt, SetStmt, ExprStmt,
    IntLit, FloatLit, StrLit, BoolLit, IdentExpr,
    BinExpr, UnExpr, RetExpr, CallExpr, CondExpr,
    LoopExpr, MemberExpr, CastExpr, BlockExpr,
)

# ── Type mapping ───────────────────────────────────────────────────

def _ir_type(t: NurlType) -> str:
    if isinstance(t, BaseType):
        return {'i': 'i64', 'u': 'u64', 'f': 'f64',
                'b': 'b1', 's': 'sref', 'v': 'void'}[t.name]
    if isinstance(t, PtrType):   return 'ptr'
    if isinstance(t, SliceType): return 'slice'
    if isinstance(t, OptType):   return f'opt<{_ir_type(t.inner)}>'
    if isinstance(t, NamedType): return f'%{t.name}'
    if isinstance(t, FnType):
        ps = ' '.join(_ir_type(p) for p in t.params)
        return f'(@{_ir_type(t.ret)} {ps})'.rstrip()
    return 'unknown'


# ── Operator mapping ───────────────────────────────────────────────

_BIN_INSTR: Dict[str, str] = {
    '+': 'add', '-': 'sub', '*': 'mul', '/': 'div', '%': 'mod',
    '<': 'lt',  '>': 'gt',  '==': 'eq',
    '!=': 'ne', '<=': 'le', '>=': 'ge',
    '<<': 'shl', '>>': 'ashr',
    '&': 'band', '|': 'bor',
}

_UNARY_INSTR: Dict[str, str] = {
    '!': 'lnot',
    '~': 'bnot',
}


# ── Mutation analysis ──────────────────────────────────────────────

def _collect_mutations(block: Block) -> Set[str]:
    """
    Return the set of variable names directly assigned (SetStmt) in block.

    Does NOT recurse into nested LoopExpr bodies — those loops handle
    their own phi nodes.  Does recurse into inline BlockExprs.
    """
    return _scan_stmts(block.stmts, recurse_loops=False)


def _scan_stmts(stmts: list, recurse_loops: bool) -> Set[str]:
    names: Set[str] = set()
    for stmt in stmts:
        if isinstance(stmt, SetStmt):
            names.add(stmt.name)
        elif isinstance(stmt, ExprStmt):
            names |= _scan_expr(stmt.expr, recurse_loops)
        # LetStmt introduces a NEW name — doesn't count as mutation of an outer name
    return names


def _scan_expr(expr: Expr, recurse_loops: bool) -> Set[str]:
    names: Set[str] = set()
    if isinstance(expr, BlockExpr):
        names |= _scan_stmts(expr.stmts, recurse_loops)
    elif isinstance(expr, LoopExpr) and recurse_loops:
        names |= _scan_stmts(expr.body.stmts, recurse_loops)
    elif isinstance(expr, CondExpr):
        names |= _scan_expr(expr.then,  recurse_loops)
        names |= _scan_expr(expr.else_, recurse_loops)
    return names


# ── IR Generator ──────────────────────────────────────────────────

class IRGen:
    def __init__(self, program: Program):
        self.program = program

        # Output: list of lines; None = reserved placeholder
        self._lines: List[Optional[str]] = []

        # Per-function state (reset in _gen_fn)
        self._reg:       int             = 0
        self._lbl:       int             = 0
        self._vars:      Dict[str, str]  = {}   # name  → current SSA register
        self._var_types: Dict[str, str]  = {}   # name  → IR type string
        self._cur_label: str             = 'entry'
        self._did_ret:   bool            = False

    # ── output primitives ─────────────────────────────────────────

    def _emit(self, line: str) -> None:
        self._lines.append(line)

    def _indent(self, line: str) -> None:
        self._lines.append('  ' + line)

    def _reserve_line(self) -> int:
        """Reserve a slot; return its index for later patching."""
        idx = len(self._lines)
        self._lines.append(None)
        return idx

    def _patch_line(self, idx: int, line: str) -> None:
        self._lines[idx] = line

    def _set_label(self, lbl: str) -> None:
        """Emit a label and update the current-label tracker."""
        self._indent(f'lbl {lbl}:')
        self._cur_label = lbl

    # ── register / label allocation ───────────────────────────────

    def _fresh_reg(self) -> str:
        r = f'%{self._reg}'
        self._reg += 1
        return r

    def _fresh_lbl(self, hint: str = 'lbl') -> str:
        l = f'{hint}_{self._lbl}'
        self._lbl += 1
        return l

    # ── public entry ──────────────────────────────────────────────

    def generate(self) -> str:
        module = (self.program.file
                  .replace('.nu', '')
                  .replace('<', '')
                  .replace('>', ''))
        self._emit(f'module {module}')
        self._emit('')

        for decl in self.program.decls:
            if isinstance(decl, StructDecl):
                self._gen_struct_type(decl)
            elif isinstance(decl, EnumDecl):
                self._gen_enum_type(decl)

        if any(isinstance(d, (StructDecl, EnumDecl)) for d in self.program.decls):
            self._emit('')

        for decl in self.program.decls:
            if isinstance(decl, FnDecl):
                self._gen_fn(decl)
            elif isinstance(decl, ConstDecl):
                self._gen_const(decl)

        return '\n'.join(
            line for line in self._lines if line is not None
        ) + '\n'

    # ── struct types ──────────────────────────────────────────────

    def _gen_struct_type(self, decl: StructDecl) -> None:
        fields = '  '.join(_ir_type(f.type) for f in decl.fields)
        self._emit(f'type %{decl.name} {{ {fields} }}')

    def _gen_enum_type(self, decl: EnumDecl) -> None:
        """Generate enum type as struct with enough fields for largest variant payload + discriminant."""
        # Find maximum payload size across all variants
        max_payload_size = 0
        for variant in decl.variants:
            max_payload_size = max(max_payload_size, len(variant.payload))

        if max_payload_size == 0:
            # Pure enum with no payload data
            field_types = ['i64']  # Just discriminant
        else:
            # Analyze payload types across all variants to determine field types
            field_types = ['i64']  # Discriminant is always i64

            for field_idx in range(max_payload_size):
                # For each field position, determine the appropriate type
                field_type = self._determine_enum_field_type(decl, field_idx)
                field_types.append(field_type)

        fields_str = '  '.join(field_types)
        self._emit(f'type %{decl.name} {{ {fields_str} }}')

    def _determine_enum_field_type(self, decl: EnumDecl, field_idx: int) -> str:
        """Determine the appropriate IR type for a specific field position across all variants."""
        # Collect all types used at this field position across variants
        types_at_position = []
        for variant in decl.variants:
            if field_idx < len(variant.payload):
                payload_type = variant.payload[field_idx]
                ir_type = _ir_type(payload_type)
                types_at_position.append(ir_type)

        if not types_at_position:
            return 'i64'  # Default if no variants use this position

        # If all types are the same, use that type
        unique_types = set(types_at_position)
        if len(unique_types) == 1:
            return types_at_position[0]

        # If there are multiple different types, we need a common representation
        # For now, use i64 for primitives or ptr for mixed types with pointers
        if any(t in ['ptr', 'sref'] for t in unique_types):
            return 'ptr'  # Use ptr for mixed pointer types
        else:
            return 'i64'  # Use i64 for mixed primitive types

    # ── constants ─────────────────────────────────────────────────

    def _gen_const(self, decl: ConstDecl) -> None:
        self._emit(f'// const {decl.name} : {_ir_type(decl.type)}')

    # ── functions ─────────────────────────────────────────────────

    def _gen_fn(self, decl: FnDecl) -> None:
        self._reg       = 0
        self._lbl       = 0
        self._vars      = {}
        self._var_types = {}
        self._cur_label = 'entry'
        self._did_ret   = False

        params_str = '  '.join(
            f'({_ir_type(p.type)} %{p.name})' for p in decl.params
        )
        ret_ir = _ir_type(decl.ret_type)
        self._emit(f'fn @{decl.name} {params_str} → {ret_ir} {{')

        for p in decl.params:
            self._vars[p.name]      = f'%{p.name}'
            self._var_types[p.name] = _ir_type(p.type)

        self._set_label('entry')

        last_reg = self._gen_block(decl.body)

        if not self._did_ret:
            if isinstance(decl.ret_type, BaseType) and decl.ret_type.name == 'v':
                self._indent('ret void')
            elif last_reg is not None:
                self._indent(f'ret {ret_ir} {last_reg}')
            else:
                self._indent(f'// WARNING: missing return in {decl.name}')

        self._emit('}')
        self._emit('')

    # ── block ─────────────────────────────────────────────────────

    def _gen_block(self, block: Block) -> Optional[str]:
        last: Optional[str] = None
        for stmt in block.stmts:
            last = self._gen_stmt(stmt)
        return last

    # ── statements ────────────────────────────────────────────────

    def _gen_stmt(self, stmt: Stmt) -> Optional[str]:
        if isinstance(stmt, LetStmt):
            reg  = self._gen_expr(stmt.expr)
            t_ir = _ir_type(stmt.expr.nurl_type) if stmt.expr.nurl_type else 'unknown'
            named = f'%{stmt.name}'
            self._indent(f'{named} = copy {t_ir} {reg}')
            self._vars[stmt.name]      = named
            self._var_types[stmt.name] = t_ir
            return None

        if isinstance(stmt, SetStmt):
            reg  = self._gen_expr(stmt.expr)
            t_ir = _ir_type(stmt.expr.nurl_type) if stmt.expr.nurl_type else 'unknown'
            ver  = f'%{stmt.name}_{self._reg}'
            self._reg += 1
            self._indent(f'{ver} = copy {t_ir} {reg}')
            self._vars[stmt.name] = ver
            # _var_types already set by the original LetStmt
            return None

        if isinstance(stmt, ExprStmt):
            return self._gen_expr(stmt.expr)

        return None

    # ── expressions ───────────────────────────────────────────────

    def _gen_expr(self, expr: Expr) -> str:
        if isinstance(expr, IntLit):
            r = self._fresh_reg()
            self._indent(f'{r} = i64 {expr.value}')
            return r

        if isinstance(expr, FloatLit):
            r = self._fresh_reg()
            self._indent(f'{r} = f64 {expr.value}')
            return r

        if isinstance(expr, StrLit):
            r = self._fresh_reg()
            self._indent(f'{r} = sref "{expr.value}"')
            return r

        if isinstance(expr, BoolLit):
            r = self._fresh_reg()
            self._indent(f'{r} = b1 {"1" if expr.value else "0"}')
            return r

        if isinstance(expr, IdentExpr):
            return self._vars.get(expr.name, f'%{expr.name}')

        if isinstance(expr, BinExpr):
            return self._gen_binary(expr)

        if isinstance(expr, UnExpr):
            return self._gen_unary(expr)

        if isinstance(expr, RetExpr):
            val = self._gen_expr(expr.expr)
            t   = _ir_type(expr.expr.nurl_type) if expr.expr.nurl_type else 'unknown'
            self._indent(f'ret {t} {val}')
            self._did_ret = True
            return val

        if isinstance(expr, CallExpr):
            return self._gen_call(expr)

        if isinstance(expr, CondExpr):
            return self._gen_cond(expr)

        if isinstance(expr, LoopExpr):
            return self._gen_loop(expr)

        if isinstance(expr, MemberExpr):
            return self._gen_member(expr)

        if isinstance(expr, CastExpr):
            return self._gen_cast(expr)

        if isinstance(expr, BlockExpr):
            result = self._gen_block(Block(expr.stmts, expr.pos))
            return result or self._fresh_reg()

        if isinstance(expr, EnumConstructor):
            return self._gen_enum_constructor(expr)

        if isinstance(expr, MatchExpr):
            return self._gen_match(expr)

        raise RuntimeError(f"unhandled expr type {type(expr).__name__}")

    # ── binary ────────────────────────────────────────────────────

    def _gen_binary(self, expr: BinExpr) -> str:
        l     = self._gen_expr(expr.left)
        r     = self._gen_expr(expr.right)
        instr = _BIN_INSTR.get(expr.op, expr.op)
        t     = _ir_type(expr.left.nurl_type) if expr.left.nurl_type else 'unknown'
        res   = self._fresh_reg()
        self._indent(f'{res} = {instr} {t} {l} {r}')
        return res

    # ── unary ─────────────────────────────────────────────────────

    def _gen_unary(self, expr: UnExpr) -> str:
        v     = self._gen_expr(expr.expr)
        instr = _UNARY_INSTR.get(expr.op, expr.op)
        t     = _ir_type(expr.expr.nurl_type) if expr.expr.nurl_type else 'unknown'
        res   = self._fresh_reg()
        self._indent(f'{res} = {instr} {t} {v}')
        return res

    # ── call ──────────────────────────────────────────────────────

    def _gen_call(self, expr: CallExpr) -> str:
        fn_reg   = self._gen_expr(expr.fn)
        arg_regs = [self._gen_expr(a) for a in expr.args]
        ret_t    = _ir_type(expr.nurl_type) if expr.nurl_type else 'unknown'
        args_str = ' '.join(arg_regs)
        res      = self._fresh_reg()
        self._indent(f'{res} = call {ret_t} {fn_reg} {args_str}'.rstrip())
        return res

    # ── conditional ───────────────────────────────────────────────

    def _gen_cond(self, expr: CondExpr) -> str:
        cond_reg = self._gen_expr(expr.cond)

        lbl_then = self._fresh_lbl('then')
        lbl_else = self._fresh_lbl('else')
        lbl_end  = self._fresh_lbl('end')

        self._indent(f'brc {cond_reg} {lbl_then} {lbl_else}')

        self._set_label(lbl_then)
        then_reg  = self._gen_expr(expr.then)
        lbl_then_exit = self._cur_label   # may differ if then contained sub-blocks
        self._indent(f'br {lbl_end}')

        self._set_label(lbl_else)
        else_reg  = self._gen_expr(expr.else_)
        lbl_else_exit = self._cur_label
        self._indent(f'br {lbl_end}')

        self._set_label(lbl_end)
        t   = _ir_type(expr.nurl_type) if expr.nurl_type else 'unknown'
        res = self._fresh_reg()
        self._indent(
            f'{res} = phi {t} [{then_reg} {lbl_then_exit}] [{else_reg} {lbl_else_exit}]'
        )
        return res

    # ── loop — with proper phi nodes ──────────────────────────────

    def _gen_loop(self, expr: LoopExpr) -> str:
        """
        Generate:
          br loop_check
          lbl loop_check:
            %x = phi T [%x_pre, pre_lbl] [%x_post, loop_body]   ← inserted
            ...condition...
            brc cond loop_body loop_exit
          lbl loop_body:
            ...body (updates %x → %x_post)...
            br loop_check
          lbl loop_exit:
            (vars are the phi regs — valid here because loop_check dominates loop_exit)
        """
        # ── 1. Pre-scan: which vars are mutated directly in the body?
        mutated = _collect_mutations(expr.body)

        # ── 2. Snapshot pre-loop state
        pre_label = self._cur_label
        pre_vals: Dict[str, str] = {}
        for name in mutated:
            if name in self._vars:
                pre_vals[name] = self._vars[name]

        # ── 3. Allocate labels
        lbl_check = self._fresh_lbl('loop_check')
        lbl_body  = self._fresh_lbl('loop_body')
        lbl_exit  = self._fresh_lbl('loop_exit')

        self._indent(f'br {lbl_check}')

        # ── 4. Emit loop header; reserve phi slots
        self._set_label(lbl_check)

        # phi_info: name → (slot_index, phi_register)
        phi_info: Dict[str, tuple] = {}
        for name, pre_val in pre_vals.items():
            phi_reg  = self._fresh_reg()
            slot_idx = self._reserve_line()          # ← placeholder
            phi_info[name] = (slot_idx, phi_reg)
            self._vars[name] = phi_reg               # body sees the phi value

        # ── 5. Condition (uses phi regs)
        cond_reg = self._gen_expr(expr.cond)
        self._indent(f'brc {cond_reg} {lbl_body} {lbl_exit}')

        # ── 6. Body
        self._set_label(lbl_body)
        self._gen_block(expr.body)
        lbl_body_exit = self._cur_label   # in case body changed the label

        # ── 7. Patch phi slots now that we know post-body values
        for name, (slot_idx, phi_reg) in phi_info.items():
            post_val = self._vars[name]              # updated by body
            t_ir     = self._var_types.get(name, 'unknown')
            self._patch_line(
                slot_idx,
                f'  {phi_reg} = phi {t_ir} [{pre_vals[name]} {pre_label}] [{post_val} {lbl_body_exit}]'
            )

        self._indent(f'br {lbl_check}')

        # ── 8. Exit block; restore vars to phi regs
        #    (phi regs defined in loop_check, which dominates loop_exit)
        self._set_label(lbl_exit)
        for name, (_, phi_reg) in phi_info.items():
            self._vars[name] = phi_reg

        # Loops return void
        r = self._fresh_reg()
        self._indent(f'{r} = void')
        return r

    # ── member access ─────────────────────────────────────────────

    def _gen_member(self, expr: MemberExpr) -> str:
        obj = self._gen_expr(expr.obj)
        res = self._fresh_reg()
        self._indent(f'{res} = gfield {obj} {expr.field}')
        return res

    # ── cast ──────────────────────────────────────────────────────

    def _gen_cast(self, expr: CastExpr) -> str:
        val = self._gen_expr(expr.expr)
        src = _ir_type(expr.expr.nurl_type) if expr.expr.nurl_type else 'unknown'
        dst = _ir_type(expr.target)
        res = self._fresh_reg()
        self._indent(f'{res} = bitcast {src} {dst} {val}')
        return res

    # ── enum constructor ──────────────────────────────────────────────

    def _gen_enum_constructor(self, expr: EnumConstructor) -> str:
        """Generate enum constructor: @ EnumName { VariantName arg* }"""
        # Find the enum declaration to get variant information
        enum_decl = None
        for decl in self.program.decls:
            if isinstance(decl, EnumDecl) and decl.name == expr.enum_name:
                enum_decl = decl
                break

        if not enum_decl:
            raise RuntimeError(f"Unknown enum '{expr.enum_name}'")

        # Find the variant index (discriminant value)
        variant_idx = None
        variant_decl = None
        for i, variant in enumerate(enum_decl.variants):
            if variant.name == expr.variant_name:
                variant_idx = i
                variant_decl = variant
                break

        if variant_idx is None:
            raise RuntimeError(f"Unknown variant '{expr.variant_name}' in enum '{expr.enum_name}'")

        # Create enum value: start with all zeros, then set discriminant and payload
        enum_type = f'%{expr.enum_name}'

        # Start with zeroed struct
        result = self._fresh_reg()
        self._indent(f'{result} = zerostruct {enum_type}')

        # Set discriminant (field 0)
        disc_reg = self._fresh_reg()
        self._indent(f'{disc_reg} = i64 {variant_idx}')

        result_with_disc = self._fresh_reg()
        self._indent(f'{result_with_disc} = insertvalue {enum_type} {result} 0 {disc_reg}')

        # Set payload fields if any
        current_result = result_with_disc
        for i, arg_expr in enumerate(expr.args):
            arg_reg = self._gen_expr(arg_expr)
            field_idx = i + 1  # +1 because field 0 is discriminant

            # Get the actual field type from the enum definition
            enum_field_type = self._get_enum_field_type(enum_decl, field_idx)
            arg_type = _ir_type(arg_expr.nurl_type) if arg_expr.nurl_type else 'unknown'

            # Convert type if necessary
            if enum_field_type != arg_type:
                if enum_field_type == 'ptr' and arg_type in ['sref', 'ptr']:
                    # Convert string reference or pointer to generic pointer
                    converted_reg = self._fresh_reg()
                    self._indent(f'{converted_reg} = bitcast {arg_type} ptr {arg_reg}')
                    arg_reg = converted_reg
                elif enum_field_type == 'i64' and arg_type in ['i64', 'u64', 'b1']:
                    # These are compatible, no conversion needed
                    pass
                else:
                    # For other conversions, add explicit cast
                    converted_reg = self._fresh_reg()
                    self._indent(f'{converted_reg} = bitcast {arg_type} {enum_field_type} {arg_reg}')
                    arg_reg = converted_reg

            new_result = self._fresh_reg()
            self._indent(f'{new_result} = insertvalue {enum_type} {current_result} {field_idx} {arg_reg}')
            current_result = new_result

        return current_result

    def _get_enum_field_type(self, enum_decl: EnumDecl, field_idx: int) -> str:
        """Get the IR type for a specific field in an enum."""
        if field_idx == 0:
            return 'i64'  # Discriminant is always i64

        payload_field_idx = field_idx - 1
        return self._determine_enum_field_type(enum_decl, payload_field_idx)

    # ── pattern matching ──────────────────────────────────────────────

    def _gen_match(self, expr: MatchExpr) -> str:
        """Generate pattern matching: ?? expr { pattern → result ... }"""
        matched_reg = self._gen_expr(expr.expr)

        if not expr.cases:
            raise RuntimeError("Match expression must have at least one case")

        # Generate labels for each case + end label
        case_labels = [self._fresh_lbl(f'case_{i}') for i in range(len(expr.cases))]
        end_label = self._fresh_lbl('match_end')

        # Extract discriminant from matched value
        disc_reg = self._fresh_reg()
        matched_type = _ir_type(expr.expr.nurl_type)
        self._indent(f'{disc_reg} = extractvalue {matched_type} {matched_reg} 0')

        # Generate switch-like structure using conditional branches
        # For now, use sequential if-else chain (could be optimized to switch instruction)
        for i, (case, label) in enumerate(zip(expr.cases, case_labels)):
            # Check if discriminant matches this case
            case_disc_reg = self._fresh_reg()
            self._indent(f'{case_disc_reg} = i64 {i}')

            cmp_reg = self._fresh_reg()
            self._indent(f'{cmp_reg} = eq i64 {disc_reg} {case_disc_reg}')

            next_label = case_labels[i + 1] if i + 1 < len(case_labels) else end_label
            self._indent(f'br b1 {cmp_reg} {label} {next_label}')

        # Generate code for each case
        result_regs = []
        result_labels = []
        for i, (case, label) in enumerate(zip(expr.cases, case_labels)):
            self._emit(f'  lbl {label}:')
            self._cur_label = label

            # TODO: Bind pattern variables by extracting payload fields
            # For now, skip variable binding

            # Generate result expression
            case_result = self._gen_expr(case.result)
            result_regs.append(case_result)
            result_labels.append(label)

            # Branch to end
            self._indent(f'br {end_label}')

        # End label with phi node to merge results
        self._emit(f'  lbl {end_label}:')
        self._cur_label = end_label

        result_type = _ir_type(expr.nurl_type) if expr.nurl_type else 'i64'
        phi_reg = self._fresh_reg()

        # Build phi instruction: %result = phi type [%val1, lbl1] [%val2, lbl2] ...
        phi_pairs = ' '.join(f'[{reg}, {lbl}]' for reg, lbl in zip(result_regs, result_labels))
        self._indent(f'{phi_reg} = phi {result_type} {phi_pairs}')

        return phi_reg


def generate_ir(program: Program) -> str:
    """Generate NUR-IR text from a type-checked Program."""
    return IRGen(program).generate()
