#!/usr/bin/env python3
"""nurlc's core IR (`nurlc --emit-core`) as a program of formal/A2's calculus,
for the verified checker of formal/C (`C.progOK2B`, `C.checkA2`,
`C.checked_program_safe2`) to decide (AGORA-975).

First subset: functions over integers (`i64`, `i1`, and the `void` of a
statement's join temporary): bindings, number computations, calls, `if`
and returns. A function's body is a block; `ret` stores the result slot
(variable `params`) and leaves it (`exit 0`). A number the IR does not
track (`c`) is read as a literal: the typing of an integer does not depend
on its value. Anything else is `Unsupported`, and the program is not
emitted.

    python3 tools/ncore/tolean.py prog.core > Prog.lean
"""
import sys

INT_TYS = {"i64", "i1", "i32", "i8", "void"}


class Unsupported(Exception):
    pass


def parse(text):
    fns, cur = [], None
    for raw in text.splitlines():
        if not raw.strip():
            continue
        f = raw.split("\t")
        if f[0] == "fn":
            cur = {"name": f[1], "ret": f[2], "np": int(f[3]), "vars": {}, "body": []}
        elif f[0] == "v" and cur is not None:
            cur["vars"][int(f[1])] = f[-1]
        elif f[0] == "endfn":
            fns.append(cur)
            cur = None
        elif cur is not None:
            cur["body"].append(raw.strip())
    return fns


def block_of(lines, i):
    """The statements from lines[i] to the matching `end` / `else` at
    depth 0: (statements, index of the closing line)."""
    out, depth = [], 0
    while i < len(lines):
        w = lines[i].split()[0]
        if depth == 0 and w in ("end", "else"):
            return out, i
        if w in ("scope", "if", "loop", "match", "foreach", "defer"):
            depth += 1
        elif w == "end":
            depth -= 1
        out.append(lines[i])
        i += 1
    return out, i


class Fn:
    def __init__(self, fn, index):
        self.fn, self.index = fn, index
        self.np = fn["np"]
        top = max(list(fn["vars"]) + [self.np - 1, -1])
        self.next = top + 2  # past every core variable and the result slot
        for v, ty in fn["vars"].items():
            if ty not in INT_TYS:
                raise Unsupported(f"{fn['name']}: variable {v} of type {ty}")
        if fn["ret"] not in INT_TYS:
            raise Unsupported(f"{fn['name']}: result of type {fn['ret']}")

    def var(self, k):
        return k if k < self.np else k + 1

    def fresh(self):
        self.next += 1
        return self.next - 1

    def operand(self, op):
        if op == "c":
            return "(.lit 0)"
        if op.startswith("v") and op[1:].isdigit():
            return f"(.var {self.var(int(op[1:]))})"
        raise Unsupported(f"{self.fn['name']}: operand {op}")

    def rhs(self, words):
        k = words[0]
        if k == "none":
            return ".expr (.lit 0)"
        if k == "use":
            return f".expr {self.operand(words[1])}"
        if k == "scalar":
            ops = [self.operand(o) for o in words[2:2 + int(words[1])]]
            e = "(.lit 0)"
            for o in ops:
                e = f"(.add {e} {o})"
            return f".expr {e}"
        raise Unsupported(f"{self.fn['name']}: rvalue {k}")

    def call(self, words, names, rest):
        """`call f n op…` into a fresh temporary, then `rest`."""
        f, n = words[1], int(words[2])
        if f not in names:
            raise Unsupported(f"{self.fn['name']}: call of {f}, not in the program")
        pre, args = [], []
        for op in words[3:3 + n]:
            if op == "c":
                t = self.fresh()
                pre.append(t)
                args.append(str(t))
            else:
                args.append(str(self.var(int(op[1:]))))
        x = self.fresh()
        s = f"(.letcall {x} {names[f]} [{', '.join(args)}] {rest})"
        for t in reversed(pre):
            s = f"(.letv {t} (.expr (.lit 0)) {s})"
        return s

    def stmts(self, lines, names):
        """A statement list as one A2 statement: each binding scoped over
        what follows it."""
        if not lines:
            return ".skip"
        head, i = lines[0].split(), 1
        w = head[0]
        if w in ("line", "drop"):
            return self.stmts(lines[1:], names)
        if w == "scope":
            body, j = block_of(lines, 1)
            return self.seq(self.stmts(body, names), self.stmts(lines[j + 1:], names))
        if w == "if":
            a, j = block_of(lines, 1)
            if lines[j].split()[0] == "else":
                b, k = block_of(lines, j + 1)
            else:
                b, k = [], j
            c = self.operand(head[1])
            ite = f"(.ite {c} {self.stmts(a, names)} {self.stmts(b, names)})"
            return self.seq(ite, self.stmts(lines[k + 1:], names))
        if w == "ret":
            v = "(.lit 0)" if head[1] == "-" else self.operand(head[1])
            ex = f"(.seq (.assign {self.np} (.expr {v})) (.exit 0))"
            return self.seq(ex, self.stmts(lines[1:], names))
        if w == "let":
            x = self.var(int(head[1]))
            rest = self.stmts(lines[1:], names)
            if head[2] == "call":
                t = self.fresh()
                return self.call(head[2:], names, f"(.letv {x} (.expr (.var {t})) {rest})".replace(
                    f"(.var {t})", "(.lit 0)"))
            return f"(.letv {x} ({self.rhs(head[2:])}) {rest})"
        if w == "eval":
            rest = self.stmts(lines[1:], names)
            if head[1] == "call":
                return self.call(head[1:], names, rest)
            t = self.fresh()
            return f"(.letv {t} ({self.rhs(head[1:])}) {rest})"
        if w == "assign":
            if not (head[1].startswith("v") and head[1][1:].isdigit()):
                raise Unsupported(f"{self.fn['name']}: store to {head[1]}")
            return self.seq(f"(.assign {self.var(int(head[1][1:]))} ({self.rhs(head[2:])}))",
                            self.stmts(lines[1:], names))
        raise Unsupported(f"{self.fn['name']}: statement {w}")

    @staticmethod
    def seq(a, b):
        return a if b == ".skip" else f"(.seq {a} {b})"

    def lean(self, names):
        body = f"(.block {self.stmts(self.fn['body'], names)})"
        params = ", ".join(["(.inp, .int)"] * self.np)
        return (f"{{ params := [{params}], resTy := .int, resOwn := false, lends := [], rholds := [],\n"
                f"    outHolds := [], body := {body}, nvars := {self.next + 1} }}")


def emit(text):
    fns = parse(text)
    names = {f["name"]: i for i, f in enumerate(fns)}
    if "main" not in names:
        raise Unsupported("no main")
    out = ["import C.A3Prog", "open A2 C", ""]
    defs = []
    for i, f in enumerate(fns):
        defs.append(f"def fn{i} : Fn :=\n  {Fn(f, i).lean(names)}")
    out += defs
    out.append("")
    out.append("def P : Prog := [" + ", ".join(f"fn{i}" for i in range(len(fns))) + "]")
    out.append(f"def entry : Stmt := .letcall 0 {names['main']} [] .skip")
    out.append("")
    out.append("#eval progOK2B P && (checkA2 P entry.vars (fun _ => none) [] entry).isSome && stmtCodesB P entry")
    return "\n".join(out) + "\n"


def main():
    text = open(sys.argv[1]).read()
    try:
        sys.stdout.write(emit(text))
    except Unsupported as e:
        print(f"unsupported: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
