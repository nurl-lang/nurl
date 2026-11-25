import C.A2Prog

/-!
# The core IR as words, read in the kernel (AGORA-1029, step 1)

docs/dev/TRANSLATION_TRUST.md route (b): a certificate holds nurlc's core IR
as plain Lean data, one entry per line and each line its words (header
lines `fn`, `v`, `ty` and `sum` split at tabs, statements at spaces), and
Lean builds the calculus term from it, so the translation is no longer a
trusted step. This file is the first part: the data and its reader.

Everything here reduces in the kernel (`decide +kernel`): numbers are read
by structural recursion over a word's characters, since Lean's own
`String.toNat?` and `String.splitOn` do not reduce there (measured,
`tools/ncore/trust/measure.sh`).
-/

namespace C.Elab

/-- The core IR: its lines, each its words. -/
abbrev IR := List (List String)

/-- A decimal number's digits, most significant first. -/
def digitsVal : List Char → Nat → Option Nat
  | [], acc => some acc
  | c :: r, acc => if c.isDigit then digitsVal r (acc * 10 + (c.toNat - 48)) else none

/-- A word that is a number: one digit at least, nothing else. -/
def natOf (w : String) : Option Nat :=
  match w.toList with
  | [] => none
  | cs => digitsVal cs 0

/-- A variable operand `v<id>` (no field path). -/
def varOf (w : String) : Option Nat :=
  match w.toList with
  | 'v' :: cs@(_ :: _) => digitsVal cs 0
  | _ => none

/-- A function of the core IR: its header, its variables (id, kind, flags,
    type) and its statements, each its words. -/
structure CoreFn where
  name : String
  ret : String
  np : Nat
  file : String
  vars : List (Nat × Nat × Nat × String)
  body : List (List String)
deriving DecidableEq, Repr

/-- A `v` line: `v id kind depth flags line value-block name type` (the
    name may be empty, so the type is the line's last word). -/
def readVar : List String → Option (Nat × Nat × Nat × String)
  | "v" :: id :: kind :: _depth :: flags :: rest =>
    match natOf id, natOf kind, natOf flags, rest.getLast? with
    -- a kind is one of 0–3 (parameter, binding, temporary, capture), as the
    -- translator's reader requires
    | some i, some k, some f, some ty => if k ≤ 3 then some (i, k, f, ty) else none
    | _, _, _, _ => none
  | _ => none

/-- The functions of the IR, in order: each `fn` header, its `v` lines and
    its statements up to its `endfn`. Fails (`none`) on a function left
    open, an `endfn` with none open, or a malformed header or `v` line, as
    the translator does (fail closed). Lines outside a function (`ty`,
    `sum`, `virt`) are passed over here. -/
def readFns : IR → Option CoreFn → List CoreFn → Option (List CoreFn)
  | [], none, acc => some acc.reverse
  | [], some _, _ => none
  | l :: ls, none, acc =>
    match l with
    | "fn" :: name :: ret :: np :: _line :: file :: _ =>
      match natOf np with
      | some n => readFns ls (some ⟨name, ret, n, file, [], []⟩) acc
      | none => none
    | "fn" :: _ => none        -- a header cut short
    | "endfn" :: _ => none
    | _ => readFns ls none acc
  | l :: ls, some f, acc =>
    match l with
    | "endfn" :: _ => readFns ls none ({ f with vars := f.vars.reverse, body := f.body.reverse } :: acc)
    | "fn" :: _ => none
    | "v" :: _ =>
      match readVar l with
      | some v => readFns ls (some { f with vars := v :: f.vars }) acc
      | none => none
    | _ => readFns ls (some { f with body := l :: f.body }) acc

/-- The IR's functions. -/
def fnsOf (ir : IR) : Option (List CoreFn) := readFns ir none []

/-! ### Witnesses -/

example : natOf "123" = some 123 := by decide +kernel
example : natOf "12a" = none := by decide +kernel
example : varOf "v42" = some 42 := by decide +kernel
example : varOf "v" = none := by decide +kernel

/-- A two-function IR read back: names, parameter counts, variables and the
    statements, in order. -/
example : (fnsOf [["fn", "f", "i64", "1", "1", "a.nu", "0"],
    ["v", "0", "0", "0", "0", "1", "-1", "n", "i64"],
    ["scope"], ["ret", "v0"], ["end"], ["endfn"],
    ["fn", "main", "i64", "0", "3", "a.nu", "0"], ["scope"], ["ret", "c"], ["end"], ["endfn"],
    ["sum", "f", "1", "safe=1"]]).map (·.map (fun f => (f.name, f.np, f.vars.length, f.body.length)))
    = some [("f", 1, 1, 3), ("main", 0, 0, 3)] := by decide +kernel

/-- A function left open, and an `endfn` with none open, are refused. -/
example : fnsOf [["fn", "f", "i64", "0", "1", "a.nu", "0"], ["scope"]] = none := by decide +kernel
example : fnsOf [["endfn"]] = none := by decide +kernel
/-- A header cut short, and a kind outside 0–3, are refused too. -/
example : fnsOf [["fn", "broken"]] = none := by decide +kernel
example : fnsOf [["fn", "f", "i64", "0", "1", "a.nu", "0"],
    ["v", "0", "4", "0", "0", "1", "-1", "", "i64"], ["endfn"]] = none := by decide +kernel

end C.Elab
