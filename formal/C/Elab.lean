import C.A2Prog

/-!
# The core IR as words, read in the kernel (AGORA-1029, steps 1, 2 and 4)

docs/dev/TRANSLATION_TRUST.md route (b): a certificate holds nurlc's core IR
as plain Lean data, one entry per line and each line its words (header
lines `fn`, `v`, `ty` and `sum` split at tabs, statements at spaces), and
Lean builds the calculus term from it, so the translation is no longer a
trusted step. This file is the data and its reader (step 1), and the term
of a program of the subset built from it (`elabIR`: numbers, step 2;
buffers of numbers, step 4).

Everything here reduces in the kernel (`decide +kernel`): numbers are read
by structural recursion over a word's bytes, since Lean's own
`String.toNat?` and `String.splitOn` do not reduce there (measured,
`tools/ncore/trust/measure.sh`).
-/

namespace C.Elab

/-- The core IR: its lines, each its words. -/
abbrev IR := List (List String)

/-- A word's UTF-8 bytes, as numbers. In the kernel a string literal's
    `toList` decodes its bytes at ~4 ms a character; its bytes cost a third
    of that, and a list of numbers written out costs nothing, so a word is
    read as its bytes, and the texts it is compared with are written as
    bytes (each checked against its text where it is defined). -/
def bytesOf (w : String) : List Nat := w.toByteArray.data.toList.map UInt8.toNat

/-- A decimal number's digits (ASCII bytes), most significant first. -/
def digitsN : List Nat → Nat → Option Nat
  | [], acc => some acc
  | c :: r, acc => if 48 ≤ c && c ≤ 57 then digitsN r (acc * 10 + (c - 48)) else none

/-- A word that is a number: one digit at least, nothing else. -/
def natOf (w : String) : Option Nat :=
  match bytesOf w with
  | [] => none
  | cs => digitsN cs 0

/-- A variable operand `v<id>` (no field path). -/
def varOf (w : String) : Option Nat :=
  match bytesOf w with
  | 118 :: cs@(_ :: _) => digitsN cs 0   -- 'v'
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

/-! ## Steps 2 and 4: the term of a program of numbers and buffers (AGORA-1029)

`elabIR ir` (`elab` is a keyword of Lean) builds the A2 program and its
entry statement from the words of a core IR, for the **subset**: every
function of the program (the ones whose file is not the standard
library's, as the translator selects them) has only variables, parameters
and a result of a number type (step 2), or a buffer of numbers (step 4,
`bufTy`: raw text `i8*`, a `String`, a `Vec` of a number type; A2's
`.vec .int`), and its statements are among
`scope`/`if`/`else`/`loop`/`loopcond`/`end`, `line`, `drop`, `break`,
`continue`, `let k use|none|scalar …`, `let k call f …`,
`eval scalar|use|none …`, `eval call f …`, `assign vK use|none|scalar …`
and `ret c|-|vK`, where every call is of a function of the program or one
of the library calls `intrS` lowers (`vec_new`, `vec_push`, `vec_len`,
`vec_at`, `vec_free`, `string_from`, `string_len`, `string_free`,
`nurl_str_cat`, `nurl_str_len`). A buffer moves (`.var`), is borrowed by a
cursor (`.borrow`), is copied into an `inout` parameter, and its `drop` is
the end of its scope. No variable of the subset holds a view but a number
element read out of a Vec (`letCallOk`, `viewsOf`). Anything else is `none`
(fail closed).

It is `packages/nurl-cert/src/tolean.nu`'s translation of that subset,
rule for rule, meant to make exactly the term it prints:
`tools/ncore/elab_parity.sh` compares the two over every certify program
and hole probe. The order the translator takes things in is kept,
because it numbers its fresh temporaries in that order: a `let` or an
`eval` translates the rest of its list before its own right-hand side; a
loop its body before its condition.

Where the translator reads a core IR nurlc does not print as if it were
well formed, `elabIR` refuses it (stricter, never laxer): a count or an id
that is not plain digits, two functions of one name, a function of the
program named as a library call the translator makes a construct of, a
`Vec` of anything but numbers, a `let x` of a library call the translator
lowers by falling through to a call (`vec_push`, `vec_free`), a call whose
result may be a view. The checks the translator makes on what it
translates are made here too, the ones on code it then passes over
included (a buffer named after its `drop`, `__views_of`). It does not read
the IR's `ty`, `virt` and `sum` lines past what the subset needs (a `d`
drop flag: the program has a destructor; a `sum` line's keys).

Everything is total and reduces in the kernel: recursion is structural
(over a fuel bound by the body's length where a list is rebuilt), and
words are compared as strings and read as bytes (`bytesOf`). -/

open A2

/-! ### Words -/

/-- `p` is a prefix of `a`. -/
def prefixN : List Nat → List Nat → Bool
  | [], _ => true
  | _ :: _, [] => false
  | p :: ps, a :: as => p == a && prefixN ps as

def startsB (w : String) (p : List Nat) : Bool := prefixN p (bytesOf w)

def stdlibB : List Nat := [115, 116, 100, 108, 105, 98, 47]
def dropB : List Nat := [100, 114, 111, 112, 95, 95]
def closureB : List Nat := [95, 95, 99, 108, 111, 115, 117, 114, 101, 95]
example : stdlibB = bytesOf "stdlib/" ∧ dropB = bytesOf "drop__" ∧
    closureB = bytesOf "__closure_" := by decide +kernel

/-- The bound the core IR keeps its variable ids to (2^62, `core_id_max`). -/
def idMax : Nat := 4611686018427387904

/-- An id word (`let <k>`, `drop <k>`): digits, within the bound. -/
def idOf (w : String) : Option Nat :=
  match natOf w with
  | some k => if k ≤ idMax then some k else none
  | none => none

/-- A whole variable `v<k>` (no field path), within the bound. -/
def vref (w : String) : Option Nat :=
  match varOf w with
  | some k => if k ≤ idMax then some k else none
  | none => none

/-- The IR's number types (`__int_ty`): each is A2's `int`. -/
def intTy (t : String) : Bool :=
  t == "i64" || t == "i1" || t == "i32" || t == "i16" || t == "i8" || t == "void" ||
  t == "u64" || t == "u32" || t == "u16" || t == "u8" || t == "f64" || t == "f32" ||
  t == "double" || t == "float"

/-- The number types as bytes, for a type inside a name (`%Vec__i64`,
    `vec_push__i64`). -/
def intNamesB : List (List Nat) := [
  [105, 54, 52], [105, 49], [105, 51, 50], [105, 49, 54], [105, 56], [118, 111, 105, 100],
  [117, 54, 52], [117, 51, 50], [117, 49, 54], [117, 56], [102, 54, 52], [102, 51, 50],
  [100, 111, 117, 98, 108, 101], [102, 108, 111, 97, 116]]

def intTyB (cs : List Nat) : Bool := intNamesB.any (· == cs)

example : intNamesB = ["i64", "i1", "i32", "i16", "i8", "void", "u64", "u32", "u16", "u8",
    "f64", "f32", "double", "float"].map bytesOf := by decide +kernel

def vecTyB : List Nat := [37, 86, 101, 99, 95, 95]
example : vecTyB = bytesOf "%Vec__" := by decide +kernel

/-- A buffer of numbers (`__lean_ty`'s `(.vec .int)`): raw text bound from a
    literal or a fresh string (`i8*`; the subset holds no view of one, see
    `letCallOk`), a `String`, a `Vec` of a number type. -/
def bufTy (t : String) : Bool :=
  t == "i8*" || t == "%String" ||
  (let cs := bytesOf t
   prefixN vecTyB cs && intTyB (cs.drop 6))

/-- A type of the subset as A2's (`__lean_ty`): a number, or a buffer of
    numbers. -/
def tyOf (t : String) : Option Ty :=
  if intTy t then some .int else if bufTy t then some (.vec .int) else none

/-- Standard-library calls the translator makes A2 constructs of
    (`__intrinsic_`): a function of the program of such a name, or with
    such a prefix, is refused. -/
def intrinsicExact : List (List Nat) := [
  [110, 117, 114, 108, 95, 112, 114, 105, 110, 116, 108, 110],
  [110, 117, 114, 108, 95, 112, 114, 105, 110, 116, 108, 110, 95, 105, 110, 116],
  [110, 117, 114, 108, 95, 115, 116, 114, 95, 99, 97, 116],
  [110, 117, 114, 108, 95, 115, 116, 114, 95, 108, 101, 110],
  [115, 116, 114, 105, 110, 103, 95, 100, 97, 116, 97],
  [115, 116, 114, 105, 110, 103, 95, 102, 114, 101, 101],
  [115, 116, 114, 105, 110, 103, 95, 102, 114, 111, 109],
  [115, 116, 114, 105, 110, 103, 95, 108, 101, 110],
  [115, 116, 114, 105, 110, 103, 95, 112, 117, 115, 104, 95, 115, 116, 114],
  [116, 104, 114, 101, 97, 100, 95, 106, 111, 105, 110],
  [116, 104, 114, 101, 97, 100, 95, 115, 112, 97, 119, 110, 95, 111, 119, 110, 101, 100]]

def intrinsicPrefix : List (List Nat) := [
  [99, 104, 97, 110, 95, 99, 108, 111, 115, 101, 95, 95],
  [67, 104, 97, 110, 110, 101, 108, 95, 115, 104, 97, 114, 101, 95, 95],
  [99, 104, 97, 110, 95, 110, 101, 119, 95, 95],
  [99, 104, 97, 110, 95, 114, 101, 99, 118, 95, 95],
  [99, 104, 97, 110, 95, 115, 101, 110, 100, 95, 95],
  [99, 104, 97, 110, 95, 116, 114, 121, 95, 114, 101, 99, 118, 95, 95],
  [115, 108, 105, 99, 101, 95, 102, 114, 111, 109, 95, 118, 101, 99, 95, 95],
  [115, 108, 105, 99, 101, 95, 108, 101, 110, 95, 95],
  [118, 101, 99, 95, 97, 116, 95, 95],
  [118, 101, 99, 95, 99, 108, 101, 97, 114, 95, 95],
  [118, 101, 99, 95, 102, 114, 101, 101, 95, 95],
  [118, 101, 99, 95, 108, 101, 110, 95, 95],
  [118, 101, 99, 95, 110, 101, 119, 95, 95],
  [118, 101, 99, 95, 112, 117, 115, 104, 95, 95],
  [118, 101, 99, 95, 114, 101, 115, 101, 114, 118, 101, 95, 95],
  [118, 101, 99, 95, 115, 104, 114, 105, 110, 107, 95, 116, 111, 95, 102, 105, 116, 95, 95],
  [118, 101, 99, 95, 116, 114, 117, 110, 99, 97, 116, 101, 95, 95]]

/-- The two lists are the names `__intrinsic_` tests. -/
example : intrinsicExact = [
    "nurl_println", "nurl_println_int", "nurl_str_cat", "nurl_str_len", "string_data",
    "string_free", "string_from", "string_len", "string_push_str", "thread_join",
    "thread_spawn_owned"].map bytesOf := by decide +kernel
example : intrinsicPrefix = [
    "chan_close__", "Channel_share__", "chan_new__", "chan_recv__", "chan_send__",
    "chan_try_recv__", "slice_from_vec__", "slice_len__", "vec_at__", "vec_clear__",
    "vec_free__", "vec_len__", "vec_new__", "vec_push__", "vec_reserve__",
    "vec_shrink_to_fit__", "vec_truncate__"].map bytesOf := by decide +kernel

def intrinsicName (f : String) : Bool :=
  let cs := bytesOf f
  intrinsicExact.any (· == cs) || intrinsicPrefix.any (prefixN · cs)

/-- The library calls of the subset (`__intrinsic_`), by name or prefix. -/
def strCatB : List Nat := [110, 117, 114, 108, 95, 115, 116, 114, 95, 99, 97, 116]
def strLenB : List Nat := [110, 117, 114, 108, 95, 115, 116, 114, 95, 108, 101, 110]
def stringFromB : List Nat := [115, 116, 114, 105, 110, 103, 95, 102, 114, 111, 109]
def stringLenB : List Nat := [115, 116, 114, 105, 110, 103, 95, 108, 101, 110]
def stringFreeB : List Nat := [115, 116, 114, 105, 110, 103, 95, 102, 114, 101, 101]
def vecNewB : List Nat := [118, 101, 99, 95, 110, 101, 119, 95, 95]
def vecPushB : List Nat := [118, 101, 99, 95, 112, 117, 115, 104, 95, 95]
def vecLenB : List Nat := [118, 101, 99, 95, 108, 101, 110, 95, 95]
def vecFreeB : List Nat := [118, 101, 99, 95, 102, 114, 101, 101, 95, 95]
def vecAtB : List Nat := [118, 101, 99, 95, 97, 116, 95, 95]
example : [strCatB, strLenB, stringFromB, stringLenB, stringFreeB, vecNewB, vecPushB, vecLenB,
    vecFreeB, vecAtB] = ["nurl_str_cat", "nurl_str_len", "string_from", "string_len", "string_free",
    "vec_new__", "vec_push__", "vec_len__", "vec_free__", "vec_at__"].map bytesOf := by decide +kernel

/-- Each is a name `intrinsicName` takes, so no function of the program is
    named like one: a call is the library's or the program's, never both. -/
example : [strCatB, strLenB, stringFromB, stringLenB, stringFreeB].all (intrinsicExact.contains ·) ∧
    [vecNewB, vecPushB, vecLenB, vecFreeB, vecAtB].all (intrinsicPrefix.contains ·) := by decide +kernel

/-- The calls whose result the translator takes for a view of an argument
    (`__views_of`, `__view_vars`): `string_data…`, `slice_from_vec__…`,
    `vec_at__…`, `slice_at__…` (prefixes). -/
def viewCallB : List (List Nat) := [
  [115, 116, 114, 105, 110, 103, 95, 100, 97, 116, 97],
  [115, 108, 105, 99, 101, 95, 102, 114, 111, 109, 95, 118, 101, 99, 95, 95],
  [118, 101, 99, 95, 97, 116, 95, 95],
  [115, 108, 105, 99, 101, 95, 97, 116, 95, 95]]
example : viewCallB = ["string_data", "slice_from_vec__", "vec_at__", "slice_at__"].map bytesOf := by
  decide +kernel

/-- Of those, the ones outside the subset: all but `vec_at__…`, whose
    result is a number lent out of the Vec (`.at`). -/
def viewOutB : List (List Nat) := viewCallB.filter (· != [118, 101, 99, 95, 97, 116, 95, 95])
example : viewOutB = ["string_data", "slice_from_vec__", "slice_at__"].map bytesOf := by decide +kernel

def indexOf (xs : List String) (x : String) : Option Nat :=
  match xs with
  | [] => none
  | y :: ys => if y == x then some 0 else (indexOf ys x).map (· + 1)

def nth? {α : Type} : List α → Nat → Option α
  | [], _ => none
  | a :: _, 0 => some a
  | _ :: as, n + 1 => nth? as n

def nodupB : List String → Bool
  | [] => true
  | x :: xs => !xs.contains x && nodupB xs

/-! ### The `sum` lines -/

/-- `key=value`: the text before the first `=`, and after it. -/
def splitKV : List Nat → List Nat → Option (List Nat × List Nat)
  | [], _ => none
  | ch :: r, acc => if ch == 61 then some (acc.reverse, r) else splitKV r (ch :: acc)

/-- Each top-level line of the IR (outside every function), as the reader
    takes it: lines inside a function are its own. -/
def topLines : IR → Bool → List (List String)
  | [], _ => []
  | l :: ls, inFn =>
    match l with
    | "fn" :: _ => topLines ls true
    | "endfn" :: _ => topLines ls false
    | _ => if inFn then topLines ls inFn else l :: topLines ls inFn

/-- The pairs of function `f`'s summary: its last `sum` line's. -/
def sumKVs (tops : List (List String)) (f : String) : List String :=
  tops.foldl (fun acc l => match l with
    | "sum" :: name :: rest => if name == f then rest.drop 1 else acc
    | _ => acc) []

/-- A function's summary: the pairs of its last `sum` line, each key and
    value as bytes (a pair without `=` passed over, as the reader passes it
    over), read once per function and looked up by key. -/
abbrev Summary := List (List Nat × List Nat)

def sumOf (tops : List (List String)) (f : String) : Summary :=
  (sumKVs tops f).filterMap fun kv => splitKV (bytesOf kv) []

/-- The value of `key` in a summary (its last pair). -/
def Summary.val (sm : Summary) (key : String) : Option (List Nat) :=
  let kb := bytesOf key
  sm.foldl (fun acc p => if p.1 == kb then some p.2 else acc) none

/-- The value of `key` in function `f`'s summary. -/
def sumVal (tops : List (List String)) (f key : String) : Option (List Nat) := (sumOf tops f).val key

/-- ASCII whitespace, as the reader splits a summary's words. -/
def isWs (c : Nat) : Bool :=
  c == 32 || (9 ≤ c && c ≤ 13) || (28 ≤ c && c ≤ 31)

/-- The words of a text. -/
def wordsOf : List Nat → List Nat → List (List Nat)
  | [], cur => if cur.isEmpty then [] else [cur.reverse]
  | ch :: r, cur =>
    if isWs ch then (if cur.isEmpty then wordsOf r [] else cur.reverse :: wordsOf r [])
    else wordsOf r (ch :: cur)

/-- Is `j` one of the numbers among the words of a summary value? -/
def numIn (v : Option (List Nat)) (j : Nat) : Bool :=
  match v with
  | none => false
  | some cs => (wordsOf cs []).any fun w =>
      match w with
      | [] => false
      | _ => digitsN w 0 == some j

/-- The parameters the walk inferred consumed (`sink=`) or kept (`keeps=`):
    the callee owns them (`__flags`). -/
def sinkP (sm : Summary) (j : Nat) : Bool :=
  numIn (sm.val "sink") j || numIn (sm.val "keeps") j

/-- Does `f` hand back a value that views what it was handed
    (`__borrowed`)? -/
def borrowedB (sm : Summary) : Bool :=
  match sm.val "ret_owned" with
  | some _ => false
  | none =>
    if sm.val "ret_unowned" == some [49] then true      -- "1"
    else match sm.val "rviews" with
      | none => false
      | some v => !(v == [58] || v == [])                     -- ":"

/-- A word that is the decimal text of `j` (`__ns j`: no leading zero). -/
def decIs (w : List Nat) (j : Nat) : Bool :=
  match w with
  | [] => false
  | [48] => j == 0
  | 48 :: _ => false
  | _ => digitsN w 0 == some j

/-- Is the word `j` among the words of `key` in `f`'s summary
    (`__sum_has_word`: the words compared as text)? -/
def sumHasWord (sm : Summary) (key : String) (j : Nat) : Bool :=
  match sm.val key with
  | none => false
  | some cs => (wordsOf cs []).any (decIs · j)

/-- What `f` does to its parameter `j` through the handle, from the walk's
    summary (`__summary_change`): A2's bound of it, or nothing. -/
def changeOf (sm : Summary) (j : Nat) : Option Eff :=
  let d := sumHasWord sm "drops" j
  let r := sumHasWord sm "reallocs" j
  let ir := sumHasWord sm "ireallocs" j
  let mu := sumHasWord sm "mutates" j
  if d || mu || (r && ir) then some .drop
  else if r then some .realloc
  else if ir then some .dropIn
  else none

/-! ### A function's statements, as a tree -/

/-- A statement of a body with its blocks closed: a simple statement (its
    words), a `ret` that ends its list (`retnx`: the translator's), a
    `drop` with the number of the body's lines after it (`rem`: where it
    stands, for `mentions`), and the blocks of the subset. -/
inductive Item where
  | st (ws : List String)
  | retnx (ws : List String)
  | dropAt (ws : List String) (rem : Nat)
  | scope (b : List Item)
  | ite (c : String) (a b : List Item)
  | loop (cond : List Item) (c : String) (body : List Item)

/-- How a list of statements ended. -/
inductive Close where
  | eof
  | fin
  | els
  | lc (c : String)

/-- The statements up to the closer of their block, read into a tree, and
    the lines after it. A closer out of place, a block not closed, or an
    opener outside the subset (`match`, `foreach`, `defer`) is `none`. -/
def parseB : Nat → List (List String) → List Item → Option (List Item × Close × List (List String))
  | 0, _, _ => none
  | _ + 1, [], acc => some (acc.reverse, .eof, [])
  | f + 1, l :: ls, acc =>
    match l with
    | "end" :: _ => some (acc.reverse, .fin, ls)
    | "else" :: _ => some (acc.reverse, .els, ls)
    | "loopcond" :: c :: _ => some (acc.reverse, .lc c, ls)
    | "drop" :: _ => parseB f ls (.dropAt l ls.length :: acc)
    | "scope" :: _ =>
      match parseB f ls [] with
      | some (b, .fin, ls') => parseB f ls' (.scope b :: acc)
      | _ => none
    | "if" :: c :: _ =>
      match parseB f ls [] with
      | some (a, .fin, ls') => parseB f ls' (.ite c a [] :: acc)
      | some (a, .els, ls') =>
        match parseB f ls' [] with
        | some (b, .fin, ls'') => parseB f ls'' (.ite c a b :: acc)
        | _ => none
      | _ => none
    | "loop" :: _ =>
      match parseB f ls [] with
      | some (cnd, .lc c, ls') =>
        match parseB f ls' [] with
        | some (b, .fin, ls'') => parseB f ls'' (.loop cnd c b :: acc)
        | _ => none
      | _ => none
    | w :: _ =>
      if w == "match" || w == "foreach" || w == "defer" || w == "arm" ||
         w == "loopcond" || w == "if" then none
      else parseB f ls (.st l :: acc)
    | [] => none

/-- A `line` or a `drop`. -/
def isLD : Item → Bool
  | .st ("line" :: _) => true
  | .dropAt _ _ => true
  | _ => false

/-- A list whose last statement but `line`s and `drop`s is a `ret`: the
    statements before it, then the `ret` as the list's end (`retnx`; the
    `line`s and `drop`s after it are dropped, as the translator drops them). -/
def retSplit (items : List Item) : Option (List Item) :=
  match items.reverse.dropWhile isLD with
  | .st ("ret" :: ws) :: before => some (before.reverse ++ [.retnx ("ret" :: ws)])
  | _ => none

/-- `let x r` followed (past `line`s and `drop`s) by `ret vx`: the
    statements after the `ret`. -/
def retAt (h1 : String) : List Item → Option (List Item)
  | .st ["ret", w] :: r => if bytesOf w == 118 :: bytesOf h1 then some r else none  -- 'v'
  | _ => none

/-! ### The translation -/

/-- What the translation changes as it goes: the next fresh variable, the
    temporaries of untracked numbers not yet bound (newest first), and the
    blocks open around the statement (an `exit` leaves `depth + 1`). -/
structure St where
  next : Nat
  lits : List Nat
  depth : Nat

def M (α : Type) : Type := St → Option (α × St)

instance : Monad M where
  pure a := fun s => some (a, s)
  bind m k := fun s => match m s with
    | some (a, s') => k a s'
    | none => none

def M.fail {α : Type} : M α := fun _ => none

def M.lift {α : Type} (o : Option α) : M α := fun s => o.map (·, s)

def M.fresh : M Nat := fun s => some (s.next, { s with next := s.next + 1 })

/-- A temporary for an untracked number, bound around the statement that
    consumes it. -/
def M.litTemp : M Nat := fun s => some (s.next, { s with next := s.next + 1, lits := s.next :: s.lits })

def M.depth : M Nat := fun s => some (s.depth, s)

def M.addDepth (n : Nat) : M Unit := fun s => some ((), { s with depth := s.depth + n })

def M.subDepth (n : Nat) : M Unit := fun s => some ((), { s with depth := s.depth - n })

def M.nlits : M Nat := fun s => some (s.lits.length, s)

/-- The temporaries made since there were `n0` bound, each `(.letv q (.expr
    .any) …)` around `st` (the first made outermost), and forgotten. -/
def M.wrapLits (n0 : Nat) (st : Stmt) : M Stmt := fun s =>
  let k := s.lits.length - n0
  some ((s.lits.take k).foldl (fun acc q => .letv q (.expr .any) acc) st,
        { s with lits := s.lits.drop k })

/-- `(.seq a b)`, or `a` when `b` is `.skip` (`__seq`). -/
def seqS (a b : Stmt) : Stmt :=
  match b with
  | .skip => a
  | _ => .seq a b

/-! ### Where a variable is named -/

/-- The pieces of a word between its `/`s (a place `v3/a`: `v3`, `a`). -/
def slashPieces : List Nat → List Nat → List (List Nat)
  | [], cur => [cur.reverse]
  | ch :: r, cur => if ch == 47 then cur.reverse :: slashPieces r [] else slashPieces r (ch :: cur)

/-- A piece that is the text `v<k>` (`__is_v`: `k`'s decimal, no leading
    zero): `k`. -/
def vIdOf : List Nat → Option Nat
  | 118 :: ds => match ds with
    | [] => none
    | [48] => some 0
    | 48 :: _ => none
    | _ => digitsN ds 0
  | _ => none

/-- The variables a line names: every piece of every word (the
    translator's token scan after a `drop`). -/
def lineIds (l : List String) : List Nat :=
  l.foldr (fun w acc => (slashPieces (bytesOf w) []).filterMap vIdOf ++ acc) []

/-- Each variable a line of the body names, with the number of the body's
    lines after that line (`n` for the first). -/
def mentionsFrom : Nat → List (List String) → List (Nat × Nat)
  | _, [] => []
  | n, l :: ls => (lineIds l).map (·, n) ++ mentionsFrom (n - 1) ls

/-- The root of a place (`v3/a`: `v3`) as a variable. -/
def rootId (w : List Nat) : Option Nat := vIdOf (w.takeWhile (· != 47))

/-- One pass of `__views_of`: a `let j call f …` whose `f` hands back a
    view of what it is handed (`viewCallB`), one of whose words from `f` on
    names a variable of `out` by its root, adds `j`. (The translator adds
    a `let j use` copy of a raw-text view too; the subset has none,
    `letCallOk`.) -/
def viewsStep (body : List (List String)) (out : List Nat) : List Nat :=
  body.foldl (fun acc l => match l with
    | "let" :: j :: "call" :: f :: more =>
      match idOf j with
      | some jj =>
        if !acc.contains jj && viewCallB.any (prefixN · (bytesOf f)) &&
            (f :: more).any (fun w => match rootId (bytesOf w) with
              | some q => acc.contains q
              | none => false)
        then jj :: acc else acc
      | none => acc
    | _ => acc) out

/-- `out` and every variable that may view one of it (`__views_of`): passes
    until one adds nothing (each adds one at least, so `body.length + 1`
    passes suffice). -/
def viewsOf (body : List (List String)) : Nat → List Nat → List Nat
  | 0, out => out
  | n + 1, out =>
    let o' := viewsStep body out
    if o'.length == out.length then out else viewsOf body n o'

/-- What every statement of the function reads: its parameter count, its
    `v` lines (id, kind, flags, type), the program's functions, its
    summary, and where each
    variable is named in its body (`mentionsFrom`), and the body. -/
structure Ctx where
  np : Nat
  vars : List (Nat × Nat × Nat × String)
  prog : List CoreFn
  sum : Summary
  mentions : List (Nat × Nat)
  body : List (List String)

/-- Variable `k`'s last `v` line. -/
def lastVar (vs : List (Nat × Nat × Nat × String)) (k : Nat) : Option (Nat × Nat × Nat × String) :=
  vs.foldl (fun acc v => if v.1 == k then some v else acc) none

/-- Variable `k`'s type, or `d` where it has no `v` line (`__vtyd`). -/
def tyD (vs : List (Nat × Nat × Nat × String)) (k : Nat) (d : String) : String :=
  match lastVar vs k with
  | some (_, _, _, t) => t
  | none => d

/-- A2's numbering: the parameters, then the result slot (`np`), then the
    rest (`__var`). -/
def Ctx.var (c : Ctx) (k : Nat) : Nat := if k < c.np then k else k + 1

/-- Bit `k` of a flag word. -/
def bitB (n k : Nat) : Bool := n / 2 ^ k % 2 == 1

/-- Variable `k`'s kind (`__vkind`; none without a `v` line). -/
def Ctx.kind (c : Ctx) (k : Nat) : Option Nat := (lastVar c.vars k).map (·.2.1)

/-- Variable `k`'s flags (`__vflags`): its `v` line's, with `sink` (4) for
    a parameter the walk inferred taken over and not `inout` (2). -/
def Ctx.flags (c : Ctx) (k : Nat) : Nat :=
  let base := match lastVar c.vars k with
    | some (_, _, fl, _) => fl
    | none => 0
  if k < c.np && sinkP c.sum k && !bitB base 1 && !bitB base 2 then base + 4 else base

/-- Is variable `k` a buffer (declared, of a `bufTy` type)? -/
def Ctx.buf (c : Ctx) (k : Nat) : Bool :=
  match lastVar c.vars k with
  | some (_, _, _, t) => bufTy t
  | none => false

/-- Is variable `k` a number (`__int_ty` of its type, `i64` without a `v`
    line)? -/
def Ctx.int (c : Ctx) (k : Nat) : Bool := intTy (tyD c.vars k "i64")

/-- An operand (`__operand`): an untracked number (`c`) is any number. -/
def operandE (c : Ctx) (w : String) : Option Expr :=
  if w == "c" then some .any
  else (vref w).map fun k => .var (c.var k)

/-- `.letv` of each binding of `pre` around `st`, the first outermost
    (`__wrap`). -/
def wrapPre (pre : List (Nat × Rhs)) (st : Stmt) : Stmt :=
  pre.foldr (fun b acc => .letv b.1 b.2 acc) st

/-- An rvalue of the subset as A2's right-hand side (`__rhs`), bound to
    `dest` (`none`: no variable), with the bindings it needs made first
    (`pre`). `asg`: the store of an `assign`. A buffer moves (`.var`), or
    is borrowed by a cursor (`: ~` of a binding or a parameter, `.borrow`);
    raw text bound from a literal is a copy of its own (`.new .int`); a
    borrowed parameter assigned to an `inout` one is copied (its length
    read, then `.new`). Refused as the translator refuses them: an owner
    given a borrowed parameter's value, raw text assigned from another
    binding. -/
def rhsS (c : Ctx) (ws : List String) (dest : Option Nat) (asg : Bool) :
    M (List (Nat × Rhs) × Rhs) :=
  match ws with
  | "none" :: _ =>
    match dest with
    | some d => if intTy (tyD c.vars d "i64") then pure ([], .expr .any) else M.fail
    | none => pure ([], .expr .any)
  | "use" :: w :: _ =>
    if w == "c" then
      match dest with
      | some d =>
        -- a literal into raw text: its own copy of the text
        if (lastVar c.vars d).map (·.2.2.2) == some "i8*" then pure ([], .new .int)
        else pure ([], .expr .any)
      | none => pure ([], .expr .any)
    else match vref w with
      | none => M.fail
      | some y =>
        if c.int y then pure ([], .expr (.var (c.var y)))
        else if !c.buf y then M.fail
        else
          let ky := c.kind y
          let fy := c.flags y
          let kd := dest.bind c.kind
          let fd := match dest with
            | some d => c.flags d
            | none => 0
          let ys := tyD c.vars y "" == "i8*"
          let fy6 := !bitB fy 1 && !bitB fy 2
          if !asg && dest.isSome && kd == some 1 && bitB fd 0 && (ky == some 0 || ky == some 1) then
            pure ([], .borrow (c.var y))
          else if asg && ky == some 0 && fy6 && !ys && kd != some 0 then M.fail
          else if asg && ky == some 0 && fy6 && kd == some 0 && bitB fd 1 && !ys &&
              (match dest with
               | some d => (lastVar c.vars d).isSome && tyD c.vars y "" == tyD c.vars d ""
               | none => false) then do
            let x ← M.fresh
            pure ([(x, .expr (.len (c.var y)))], .new .int)
          else if asg && ys then M.fail
          else pure ([], .var (c.var y))
  | "scalar" :: n :: ops =>
    if natOf n != some ops.length then M.fail
    else match ops.mapM (operandE c) with
      | none => M.fail
      | some [] => pure ([], .expr .any)
      | some es => pure ([], .expr (.add .any (.lt (es.foldl .add (.lit 0)) (.lit 0))))
  | _ => M.fail

/-- A call's arguments (`__call`): an untracked number is a temporary of
    its own, bound around the call; one handed to a raw-string parameter
    is text, a buffer of the call's own (AGORA-994: `true`). -/
def argsS (c : Ctx) (callee : CoreFn) : Nat → List String → M (List (Nat × Bool))
  | _, [] => pure []
  | j, op :: ops => do
    let a ← (if op == "c" then
               (if tyD callee.vars j "" == "i8*" then do
                  let x ← M.fresh
                  pure (x, true)
                else do
                  let x ← M.litTemp
                  pure (x, false))
             else M.lift ((vref op).map fun k => (c.var k, false)))
    let as ← argsS c callee (j + 1) ops
    pure (a :: as)

/-- `call f n args…` of a function of the program: its index, and the
    arguments. -/
def callS (c : Ctx) : List String → M (Nat × List (Nat × Bool))
  | fname :: n :: args => do
    if natOf n != some args.length then M.fail
    if intrinsicName fname then M.fail
    let fi ← M.lift (indexOf (c.prog.map (·.name)) fname)
    let callee ← M.lift (nth? c.prog fi)
    let as ← argsS c callee 0 args
    pure (fi, as)
  | _ => M.fail

/-- The call `x := f(args)` then `body`, the text arguments' buffers bound
    around it, the first outermost. -/
def letcallS (x fi : Nat) (as : List (Nat × Bool)) (body : Stmt) : Stmt :=
  as.foldr (fun a acc => if a.2 then .letv a.1 (.new .int) acc else acc)
    (.letcall x fi (as.map (·.1)) body)

/-- The call's own variable (`__xf`): `x`, or a fresh one. -/
def xfS : Option Nat → M Nat
  | some x => pure x
  | none => M.fresh

/-- An argument the call takes (`__argvar`): an untracked number is a
    temporary of its own; else a whole variable. -/
def argvarS (c : Ctx) (op : String) : M Nat :=
  if op == "c" then M.litTemp else M.lift ((vref op).map c.var)

/-- An argument the call only reads (`__rd`): a whole variable. -/
def rdS (c : Ctx) (op : String) : M Nat := M.lift ((vref op).map c.var)

/-- A read of raw text (`__read`): a buffer's length. -/
def readE (c : Ctx) (op : String) : Option Expr :=
  match vref op with
  | some k => if c.buf k then some (.len (c.var k)) else none
  | none => none

/-- A read of an argument before `st`, into a fresh variable (the reads of
    `nurl_str_cat` and `string_from`); none for an untracked number. -/
def readWrap (c : Ctx) (op : String) (st : Stmt) : M Stmt :=
  if op == "c" then pure st
  else do
    let tt ← M.fresh
    let e ← M.lift (readE c op)
    pure (.letv tt (.expr e) st)

/-- A library call of the subset as A2's construct (`__intrinsic_`), into
    `x0` (`none`: no variable), then `rest`: `vec_new` (`.new`), `vec_push`
    (`.push`), `vec_len` and `string_len` (`.len`), `vec_free` and
    `string_free` (`.free`), and of raw text `nurl_str_cat` and
    `string_from` (a fresh buffer, each argument's read first),
    `nurl_str_len` (its read), `vec_at` (`.at`). The element of a `Vec` is
    a number. Any
    other library call is outside the subset; so are the forms the
    translator lowers by falling through to a call (`let x` of a
    `vec_push`). -/
def intrS (c : Ctx) (f : String) (ops : List String) (x0 : Option Nat) (rest : Stmt) : M Stmt :=
  let fb := bytesOf f
  if prefixN vecNewB fb then
    match ops with
    | [] => if intTyB (fb.drop 9) then do
        let x ← xfS x0
        pure (.letv x (.new .int) rest)
      else M.fail
    | _ => M.fail
  else if prefixN vecPushB fb then
    match ops, x0 with
    | [o0, o1], none => do
      let v ← argvarS c o0
      let y ← argvarS c o1
      if intTyB (fb.drop 10) then pure (seqS (.push v y) rest) else M.fail
    | _, _ => M.fail
  else if prefixN vecLenB fb || fb == stringLenB then
    match ops with
    | [o0] => if o0 == "c" then M.fail else do
        let x ← xfS x0
        let y ← rdS c o0
        pure (.letv x (.expr (.len y)) rest)
    | _ => M.fail
  else if prefixN vecFreeB fb || fb == stringFreeB then
    match ops, x0 with
    | [o0], none => if o0 == "c" then M.fail else do
        let y ← rdS c o0
        pure (seqS (.free y) rest)
    | _, _ => M.fail
  else if fb == strCatB then
    match ops with
    | [o0, o1] => do
      let x ← xfS x0
      let st ← readWrap c o0 (.letv x (.new .int) rest)
      readWrap c o1 st
    | _ => M.fail
  else if fb == stringFromB then
    match ops with
    | [o0] => do
      let x ← xfS x0
      readWrap c o0 (.letv x (.new .int) rest)
    | _ => M.fail
  else if fb == strLenB then
    match ops with
    | [o0] => if o0 == "c" then M.fail else do
        let x ← xfS x0
        let e ← M.lift (readE c o0)
        pure (.letv x (.expr e) rest)
    | _ => M.fail
  else if prefixN vecAtB fb then
    -- a bounds-checked read of a number element, lent (`.at`)
    match ops with
    | [o0, o1] => if o0 == "c" || !intTyB (fb.drop 8) then M.fail else do
        let i ← M.lift (operandE c o1)
        match x0 with
        | none => do
          let tt ← M.fresh
          let y ← rdS c o0
          pure (seqS (.letv tt (.at y i) .skip) rest)
        | some x => do
          let y ← rdS c o0
          pure (.letv x (.at y i) rest)
    | _ => M.fail
  else M.fail

/-- A call (`__call`, `__intrinsic`): the library's, as its construct, or
    a function of the program's, into `x0` (`none`: a fresh variable). -/
def callAny (c : Ctx) (ws : List String) (x0 : Option Nat) (rest : Stmt) : M Stmt :=
  match ws with
  | fname :: n :: args =>
    if natOf n != some args.length then M.fail
    else if intrinsicName fname then intrS c fname args x0 rest
    else do
      let (fi, as) ← callS c ws
      let x ← xfS x0
      pure (letcallS x fi as rest)
  | _ => M.fail

/-- `ret h` as the store of the result (`__stmts_`'s `ret`): a number is
    read, a buffer moves out. -/
def retR (c : Ctx) (h : String) : Option Rhs :=
  if h == "-" then some (.expr (.lit 0))
  else if h == "c" then some (.expr .any)
  else match vref h with
    | some k =>
      if c.int k then some (.expr (.var (c.var k)))
      else if c.buf k then some (.var (c.var k))
      else none
    | none => none

/-- The statements `items` as one A2 statement ending in `tail`
    (`__stmts`): each binding scoped over what follows it, and the
    temporaries of the untracked numbers a statement consumes bound around
    that statement. -/
def go (c : Ctx) : Nat → List Item → Stmt → M Stmt
  | 0, _, _ => M.fail
  | f + 1, items, tail => do
    let n0 ← M.nlits
    let st ← (match items with
      | [] => pure tail
      | it :: rest =>
        match retSplit items with
        | some body => do
          -- a list ending in `ret`: the exit after every binding before it
          let inner ← go c f body .skip
          let d ← M.depth
          pure (seqS inner (.exit d))
        | none =>
          match it with
          | .st ("line" :: _) => go c f rest tail
          | .dropAt ("drop" :: h :: _) rem => do
            -- a number's drop is nothing; a buffer's is its scope's end, the
            -- same only if no line after it names it, or a view of it
            -- (`__views_of`)
            let k ← M.lift (idOf h)
            if c.int k then go c f rest tail
            else if c.buf k then
              let dead := viewsOf c.body (c.body.length + 1) [k]
              if c.mentions.any fun m => decide (m.2 < rem) && dead.contains m.1 then M.fail
              else go c f rest tail
            else M.fail
          | .st ("break" :: _) => do
            let r ← go c f rest tail
            pure (seqS (.exit 1) r)
          | .st ("continue" :: _) => do
            let r ← go c f rest tail
            pure (seqS (.exit 0) r)
          | .st ("ret" :: h :: _) => do
            let e ← M.lift (retR c h)
            let d ← M.depth
            let r ← go c f rest tail
            pure (seqS (.seq (.assign c.np e) (.exit d)) r)
          | .retnx (_ :: h :: _) => do
            let e ← M.lift (retR c h)
            let r ← go c f rest tail
            pure (seqS (.assign c.np e) r)
          | .st ("let" :: h1 :: h2 :: more) => do
            let k ← M.lift (idOf h1)
            let atOnce := !(h2 == "call" || h2 == "closure" || h2 == "callind")
            match (if atOnce then retAt h1 (rest.dropWhile isLD) else none) with
            | some after => do
              -- `let x r` whose value is returned at once: the result takes `r`
              let (pre, rv) ← rhsS c (h2 :: more) (some k) false
              let d ← M.depth
              let r ← go c f after tail
              pure (seqS (wrapPre pre (.seq (.assign c.np rv) (.exit d))) r)
            | none => do
              let r ← go c f rest tail
              if h2 == "call" then callAny c more (some (c.var k)) r
              else do
                let (pre, rv) ← rhsS c (h2 :: more) (some k) false
                pure (wrapPre pre (.letv (c.var k) rv r))
          | .st ("eval" :: h1 :: more) => do
            let r ← go c f rest tail
            if h1 == "call" then callAny c more none r
            else if h1 == "callind" then M.fail
            else do
              let x ← M.fresh
              let (pre, rv) ← rhsS c (h1 :: more) none false
              pure (wrapPre pre (.letv x rv r))
          | .st ("assign" :: h1 :: more) => do
            let y ← M.lift (vref h1)
            if (lastVar c.vars y).map (·.2.2.2) == some "void" then go c f rest tail
            else do
              let (pre, rv) ← rhsS c more (some y) true
              let r ← go c f rest tail
              pure (seqS (wrapPre pre (.assign (c.var y) rv)) r)
          | .scope b => do
            let x ← go c f b .skip
            let y ← go c f rest tail
            pure (seqS x y)
          | .ite cw a b => do
            let o ← M.lift (operandE c cw)
            let sa ← go c f a .skip
            let sb ← go c f b .skip
            let r ← go c f rest tail
            pure (seqS (.ite o sa sb) r)
          | .loop cnd cw b => do
            -- the body a block of its own (`continue` leaves it), in the
            -- loop's block (`break` leaves both)
            M.addDepth 2
            let ib ← go c f b .skip
            M.subDepth 1
            let inner ← (if cw == "T" || cw == "1" then pure (.block ib)
              else do
                let o ← M.lift (operandE c cw)
                pure (.ite o (.block ib) (.exit 0)))
            let lb ← go c f cnd inner
            M.subDepth 1
            let r ← go c f rest tail
            pure (seqS (.block (.loop lb)) r)
          | _ => M.fail)
    M.wrapLits n0 st

/-- Parameter `j`'s mode (`__mode`, `__vflags`): `sink` if the flags say so
    or the walk inferred it taken over (and it is not `inout`), `inout`, a
    buffer the function changes through as its summary says (AGORA-994),
    else read only. -/
def modeOf (sm : Summary) (fn : CoreFn) (j : Nat) : PMode :=
  let base := match lastVar fn.vars j with
    | some (_, _, fl, _) => fl
    | none => 0
  if bitB base 2 || (sinkP sm j && !bitB base 1) then .sink
  else if bitB base 1 then .inout .replace
  else if bufTy (tyD fn.vars j "") then
    match changeOf sm j with
    | some e => .inout e
    | none => .inp
  else .inp

/-- The largest variable id, plus 2; 0 for none. -/
def topNext (vs : List (Nat × Nat × Nat × String)) : Nat :=
  vs.foldl (fun acc v => max acc (v.1 + 2)) 0

/-- A statement's operand count where its right-hand side counts its
    operands (`__wellformed`): a `let`/`assign` right-hand side (word 2) or
    an `eval`'s (word 1) that is a `call`/`closure` (count at +2), a
    `callind`/`scalar` (+1) or an `agg` (+2) has a count that is a number
    and exactly that many operand words after it (an `agg` at least that
    many: its type follows). Checked for every statement of the body, the
    ones the translation skips (a store to a `void`, code after a `ret`)
    included, as the translator does before it translates. -/
def opsOk (l : List String) : Bool :=
  let off : Option Nat := match l with
    | "let" :: _ => some 2
    | "assign" :: _ => some 2
    | "eval" :: _ => some 1
    | _ => none
  match off with
  | none => true
  | some off =>
    match nth? l off with
    | none => true
    | some h =>
      let cp : Option Nat :=
        if h == "call" || h == "closure" || h == "agg" then some (off + 2)
        else if h == "callind" || h == "scalar" then some (off + 1)
        else none
      match cp with
      | none => true
      | some cp =>
        match nth? l cp with
        | none => false
        | some w => match natOf w with
          | none => false
          | some n =>
            let nops := l.length - (cp + 1)
            if h == "agg" then decide (n ≤ nops) else n == nops

/-- A `let x call f …` the subset takes: `f`'s result no view of what it
    is handed (`__borrowed`, `__views_of`'s prefixes), but a number lent
    out of a Vec (`vec_at__…`). So raw text of the subset is owned
    (`__view_vars` finds nothing), and what a buffer's `drop` ends is the
    buffer and the elements read out of it (`viewsOf`). -/
def letCallOk (tops : List (List String)) (l : List String) : Bool :=
  match l with
  | "let" :: _ :: "call" :: f :: _ =>
    !borrowedB (sumOf tops f) && !(viewOutB.any (prefixN · (bytesOf f)))
  | _ => true

/-- A function of the subset as A2's `Fn` (`__fn_init`, `__lean`): its
    variables, parameters and result numbers or buffers (`tyOf`). -/
def fnElab (tops : List (List String)) (prog : List CoreFn) (fn : CoreFn) : Option Fn := do
  if startsB fn.name closureB then none
  if !(fn.vars.all fun v => (intTy v.2.2.2 || bufTy v.2.2.2) && v.1 ≤ idMax) then none
  let rt ← tyOf fn.ret
  let own := match rt with
    | .int => false
    | _ => true
  let sm := sumOf tops fn.name
  if sm.val "retdyn" == some [49] then none
  if borrowedB sm then none
  -- an owned result aliasing a parameter (`ret_alias`) is not translated
  if own && (sm.val "ret_alias").isSome then none
  if !(fn.body.all opsOk) then none
  if !(fn.body.all (letCallOk tops)) then none
  let params ← (List.range fn.np).mapM fun j =>
    (lastVar fn.vars j).bind fun (_, _, _, t) => (tyOf t).map (modeOf sm fn j, ·)
  let items ← match parseB (fn.body.length + 1) fn.body [] with
    | some (its, .eof, _) => some its
    | _ => none
  let c : Ctx := ⟨fn.np, fn.vars, prog, sm, mentionsFrom (fn.body.length - 1) fn.body, fn.body⟩
  let tail : Stmt := if fn.ret == "void" then .assign fn.np (.expr (.lit 0)) else .skip
  let s0 : St := ⟨max (fn.np + 1) (topNext fn.vars), [], 0⟩
  let (inner, s) ← go c (4 * fn.body.length + 4) items tail s0
  if !s.lits.isEmpty then none
  pure { params := params, resTy := rt, resOwn := own, lends := [], rholds := [],
         outHolds := [], body := .block inner, nvars := s.next + 1 }

/-- Drop exactly `n` elements, or fail if there are fewer. -/
def dropN {α : Type} : Nat → List α → Option (List α)
  | 0, l => some l
  | _ + 1, [] => none
  | n + 1, _ :: l => dropN n l

/-- `n` variants, each a name, a payload count and that many payloads,
    and nothing after them. -/
def variantsOk : Nat → List String → Bool
  | 0, l => l.isEmpty
  | n + 1, _ :: np :: rest => match natOf np with
    | some k => match dropN k rest with
      | some r => variantsOk n r
      | none => false
    | none => false
  | _ + 1, _ => false

/-- After the fields: nothing, or `V n` and `n` variants. -/
def afterFieldsOk : List String → Bool
  | [] => true
  | "V" :: nv :: rest => match natOf nv with
    | some k => variantsOk k rest
    | none => false
  | _ => false

/-- `F n`, `n` name–type pairs, then `afterFieldsOk`. -/
def fieldsOk : List String → Bool
  | "F" :: nf :: rest => match natOf nf with
    | some k => match dropN (2 * k) rest with
      | some r => afterFieldsOk r
      | none => false
    | none => false
  | _ => false

/-- A `ty` line the reader accepts (`__cr_ty`), and not a destructor type:
    name, class, drops (no `d`) and base, then either `A n` and exactly `n`
    type arguments or nothing, then the fields and the variants, and no
    column after them. The reader finds the fields at the first column `F`,
    so no column before them is `F`. -/
def tyOk : List String → Bool
  | "ty" :: name :: cls :: drops :: base :: rest =>
    !(bytesOf drops).contains 100 &&                  -- 'd'
    ![name, cls, drops, base].contains "F" &&
    match rest with
    | "A" :: na :: more => match natOf na with
      | some k => match dropN k more with
        | some r => !(more.take k).contains "F" && fieldsOk r
        | none => false
      | none => false
    | _ => fieldsOk rest
  | _ => false

/-- The top-level lines the reader would refuse (a `sum` line without its
    function, a `ty` line of another shape), and a destructor type, are
    outside the subset. -/
def topOk (tops : List (List String)) : Bool :=
  tops.all fun l => match l with
    | ["sum"] => false
    | "ty" :: _ => tyOk l
    | _ => true

/-- The program and its entry statement (`__emit`): the functions whose
    file is not the standard library's, in order, and a call of `main`.

    nurl-cert asks the kernel for this only on a translated term built from
    the constructors `elabIR` emits (`ELAB_CTORS`,
    packages/nurl-cert/src/claims.nu): a new constructor elabIR emits goes
    into nurl-cert's list too. -/
def elabIR (ir : IR) : Option (Prog × Stmt) := do
  let fns ← fnsOf ir
  let tops := topLines ir false
  if !(topOk tops) then none
  let prog := fns.filter fun f => !startsB f.file stdlibB
  let names := prog.map (·.name)
  if !(nodupB names) then none
  if names.any (fun n => startsB n dropB) then none
  -- a function of the program named like a library call the translator
  -- lowers to an A2 construct, called or not
  if names.any intrinsicName then none
  let mi ← indexOf names "main"
  let P ← prog.mapM (fnElab tops prog)
  pure (P, .letcall 0 mi [] .skip)

/-! ### Comparing terms

A2's `Stmt` has no decidable equality (its run-time forms hold a store),
so the terms of the subset are compared by `stmtBeq`, which answers
`false` for every form outside it, and is sound (`stmtBeq_sound`). -/

def stmtBeq : Stmt → Stmt → Bool
  | .skip, b => match b with
    | .skip => true
    | _ => false
  | .seq a1 a2, b => match b with
    | .seq b1 b2 => stmtBeq a1 b1 && stmtBeq a2 b2
    | _ => false
  | .letv x r s, b => match b with
    | .letv y q t => x == y && decide (r = q) && stmtBeq s t
    | _ => false
  | .letcall x f as s, b => match b with
    | .letcall y g bs t => x == y && f == g && decide (as = bs) && stmtBeq s t
    | _ => false
  | .assign x r, b => match b with
    | .assign y q => x == y && decide (r = q)
    | _ => false
  | .ite e a1 a2, b => match b with
    | .ite e' b1 b2 => decide (e = e') && stmtBeq a1 b1 && stmtBeq a2 b2
    | _ => false
  | .block a, b => match b with
    | .block b' => stmtBeq a b'
    | _ => false
  | .exit n, b => match b with
    | .exit m => n == m
    | _ => false
  | .loop a, b => match b with
    | .loop b' => stmtBeq a b'
    | _ => false
  | .push x y, b => match b with
    | .push x' y' => x == x' && y == y'
    | _ => false
  | .free x, b => match b with
    | .free x' => x == x'
    | _ => false
  | _, _ => false

theorem stmtBeq_sound : ∀ a b : Stmt, stmtBeq a b = true → a = b := by
  intro a
  induction a with
  | skip => intro b h; cases b <;> simp_all [stmtBeq]
  | seq a1 a2 ih1 ih2 =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.and_eq_true, Bool.false_eq_true] at h
    obtain ⟨h1, h2⟩ := h; rw [ih1 _ h1, ih2 _ h2]
  | letv x r s ih =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.and_eq_true, Bool.false_eq_true, beq_iff_eq,
      decide_eq_true_eq] at h
    obtain ⟨⟨h1, h2⟩, h3⟩ := h; subst h1; subst h2; rw [ih _ h3]
  | letcall x f as s ih =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.and_eq_true, Bool.false_eq_true, beq_iff_eq,
      decide_eq_true_eq] at h
    obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := h; subst h1; subst h2; subst h3; rw [ih _ h4]
  | assign x r =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.and_eq_true, Bool.false_eq_true, beq_iff_eq,
      decide_eq_true_eq] at h
    obtain ⟨h1, h2⟩ := h; subst h1; subst h2; rfl
  | ite e a1 a2 ih1 ih2 =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.and_eq_true, Bool.false_eq_true,
      decide_eq_true_eq] at h
    obtain ⟨⟨h1, h2⟩, h3⟩ := h; subst h1; rw [ih1 _ h2, ih2 _ h3]
  | block a ih =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.false_eq_true] at h
    rw [ih _ h]
  | exit n =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.false_eq_true, beq_iff_eq] at h
    rw [h]
  | loop a ih =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.false_eq_true] at h
    rw [ih _ h]
  | push x y =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.and_eq_true, Bool.false_eq_true, beq_iff_eq] at h
    obtain ⟨h1, h2⟩ := h; subst h1; subst h2; rfl
  | free x =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.false_eq_true, beq_iff_eq] at h
    rw [h]
  | _ => intro b h; simp [stmtBeq] at h

def fnBeq (f g : Fn) : Bool :=
  decide (f.params = g.params) && decide (f.resTy = g.resTy) && f.resOwn == g.resOwn &&
  decide (f.lends = g.lends) && decide (f.rholds = g.rholds) &&
  decide (f.outHolds = g.outHolds) && stmtBeq f.body g.body && f.nvars == g.nvars

theorem fnBeq_sound (f g : Fn) (h : fnBeq f g = true) : f = g := by
  cases f; cases g
  simp only [fnBeq, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  obtain ⟨⟨⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩, h7⟩, h8⟩ := h
  subst h1 h2 h3 h4 h5 h6 h8
  rw [stmtBeq_sound _ _ h7]

def progBeq : Prog → Prog → Bool
  | [], [] => true
  | f :: fs, g :: gs => fnBeq f g && progBeq fs gs
  | _, _ => false

theorem progBeq_sound : ∀ P Q : Prog, progBeq P Q = true → P = Q
  | [], [], _ => rfl
  | f :: fs, g :: gs, h => by
    simp only [progBeq, Bool.and_eq_true] at h
    rw [fnBeq_sound _ _ h.1, progBeq_sound _ _ h.2]
  | [], _ :: _, h => by simp [progBeq] at h
  | _ :: _, [], h => by simp [progBeq] at h

/-- Does `elab` make exactly the program `P` and the entry `e`?

    Irreducible for the elaborator, not for the kernel: `decide +kernel`
    has the kernel decide it, and when the kernel refuses (a term that is
    not `elabIR`'s), Lean explains the failure by reducing the instance
    again in the elaborator, which on a real core IR takes minutes and
    tens of GB. Irreducible, that stops at once and leaves the kernel's
    error. -/
@[irreducible] def elabIs (ir : IR) (P : Prog) (e : Stmt) : Bool :=
  match elabIR ir with
  | some (Q, e') => progBeq Q P && stmtBeq e' e
  | none => false

theorem elabIs_sound (ir : IR) (P : Prog) (e : Stmt) (h : elabIs ir P e = true) :
    elabIR ir = some (P, e) := by
  unfold elabIs at h
  split at h
  · rename_i Q e' heq
    simp only [Bool.and_eq_true] at h
    rw [heq, progBeq_sound _ _ h.1, stmtBeq_sound _ _ h.2]
  · simp at h

/-! ### Witnesses (step 2) -/

/-- `tools/ncore/certify/while_loop_summing.nu`'s core IR, as
    `nurl-cert words` prints it (its `ty` line left out). -/
def irWhile : IR := [
  ["fn", "main", "i64", "0", "1", "tools/ncore/certify/while_loop_summing.nu", "0", ""],
  ["v", "0", "1", "1", "1", "2", "-1", "n", "i64"],
  ["v", "1", "1", "1", "1", "3", "-1", "acc", "i64"],
  ["scope"], ["line", "2"], ["let", "0", "use", "c"], ["line", "3"], ["let", "1", "use", "c"],
  ["line", "4"], ["loop"], ["eval", "scalar", "2", "v0", "c"], ["loopcond", "c"],
  ["scope"], ["line", "5"], ["eval", "scalar", "2", "v1", "v0"], ["assign", "v1", "use", "c"],
  ["line", "6"], ["eval", "scalar", "2", "v0", "c"], ["assign", "v0", "use", "c"],
  ["end"], ["end"], ["line", "8"], ["ret", "v1"], ["end"], ["endfn"],
  ["sum", "main", "0", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"]]

/-- The term `nurl-cert translate` prints for it, written out: `n` is 1,
    `acc` 2 (after the result slot 0); the loop's body is translated before
    its condition, so the condition's temporary is the last made (5). -/
def pWhile : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := (.block (.seq (.letv 1 (.expr .any) (.letv 2 (.expr .any) (.seq (.block (.loop
      (.letv 5 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 1)) .any) (.lit 0))))
        (.ite .any (.block (.letv 4 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 2)) (.var 1)) (.lit 0))))
          (.seq (.assign 2 (.expr .any)) (.letv 3 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 1)) .any) (.lit 0))))
            (.assign 1 (.expr .any)))))) (.exit 0)))))
      (.assign 0 (.expr (.var 2)))))) (.exit 0))),
    nvars := 7 }]

/-- The kernel builds the translator's term from the words itself. -/
theorem elab_while : elabIR irWhile = some (pWhile, .letcall 0 0 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- Outside the subset, `none`: a `Vec` of strings; a call of a library
    function outside it; a statement block left open. -/
example : (elabIR [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["v", "0", "1", "1", "1", "2", "-1", "v", "%Vec__String"],
    ["scope"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by decide +kernel
example : (elabIR [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["eval", "call", "nurl_println_int", "1", "c"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by
  decide +kernel
example : (elabIR [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["loop"], ["loopcond", "c"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by decide +kernel

/-- Refused as the translator refuses it, though the translation itself
    would skip it: a miscounted scalar stored to a `void` (the translator's
    `__wellformed` checks every statement's count first); a `ty` line
    without its fields (the reader refuses it); and a function of the
    program named like an intrinsic, even one no one calls. -/
def irRet (extra : IR) (pre : IR) : IR :=
  pre ++ [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["v", "0", "2", "1", "0", "2", "-1", "", "void"],
    ["scope"]] ++ extra ++ [["ret", "c"], ["end"], ["endfn"]]
example : (elabIR (irRet [["let", "0", "none"], ["assign", "v0", "scalar", "2", "c"]] [])).isNone := by
  decide +kernel
example : (elabIR (irRet [] [] ++ [["ty", "%X", "struct", "", ""]])).isNone := by decide +kernel
example : (elabIR ([["fn", "nurl_println_int", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["ret", "c"], ["end"], ["endfn"]] ++ irRet [] [])).isNone := by decide +kernel

/-- …while their well-formed neighbours are in the subset: the store to a
    `void` with its count right, and a struct `ty` line no one uses. -/
example : (elabIR (irRet [["let", "0", "none"], ["assign", "v0", "scalar", "1", "c"]] [])).isSome := by
  decide +kernel
example : (elabIR (irRet [] [] ++
    [["ty", "%X", "1", "0-----", "", "A", "0", "F", "2", "a", "i64", "b", "i64", "V", "0"]])).isSome := by
  decide +kernel

/-! ### Witnesses (step 4: buffers) -/

/-- A `main` of variables `vs` and statements `body`, then the lines
    `extra` (other functions, `sum` lines). -/
def irM (vs body extra : IR) : IR :=
  [["fn", "main", "i64", "0", "1", "a.nu", "0", ""]] ++ vs ++ [["scope"]] ++ body ++
    [["end"], ["endfn"]] ++ extra

/-- A Vec made, moved into its binding and its temporary dropped (`v0`, a
    temporary; `v1`, a `: ~` binding). -/
def vsVec : IR := [["v", "0", "2", "1", "0", "1", "-1", "", "%Vec__i64"],
  ["v", "1", "1", "1", "4097", "1", "-1", "v", "%Vec__i64"]]
def bodyVec : IR := [["let", "0", "call", "vec_new__i64", "0"], ["let", "1", "use", "v0"], ["drop", "0"]]

/-- The kernel's term for it: the push's untracked number a temporary of its
    own (bound around it), the length read into a fresh one. -/
def pPush : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 4 (.expr .any)
      (.seq (.push 2 4) (.letv 3 (.expr (.len 2)) (.assign 0 (.expr .any))))))) (.exit 0)),
    nvars := 6 }]
example : elabIR (irM vsVec (bodyVec ++ [["eval", "call", "vec_push__i64", "2", "v1", "c"],
    ["eval", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]]) []) = some (pPush, .letcall 0 0 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- A buffer's `drop` is the end of its scope only if no line after it names
    it (`__views_of`): the temporary read after its drop is refused, its
    binding read there is not. -/
example : (elabIR (irM vsVec (bodyVec ++ [["eval", "call", "vec_len__i64", "1", "v0"], ["ret", "c"]])
    [])).isNone := by decide +kernel
example : (elabIR (irM vsVec (bodyVec ++ [["eval", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]])
    [])).isSome := by decide +kernel
/-- …every word of every line after it counts, cut at its `/`s (here a
    `line` the translation passes over), and only the text `v<k>`. -/
example : (elabIR (irM vsVec (bodyVec ++ [["line", "x/v0/y"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabIR (irM vsVec (bodyVec ++ [["line", "x/v00/v01/w0"], ["ret", "c"]]) [])).isSome := by
  decide +kernel

/-- A call whose result may view an argument (its summary: `ret_unowned=1`)
    is refused (`letCallOk`), its owned neighbour (`ret_owned`) is not; so
    is a call of a function named like one the translator takes for a view
    (`slice_at__…`), even of the program's own. -/
def bodyLen : IR := bodyVec ++ [["let", "2", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]]
def vsLen : IR := vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "i64"]]
example : (elabIR (irM vsLen bodyLen [["sum", "vec_len__i64", "1", "ret_unowned=1"]])).isNone := by
  decide +kernel
example : (elabIR (irM vsLen bodyLen [["sum", "vec_len__i64", "1", "ret_unowned=1", "ret_owned=1"]])).isSome := by
  decide +kernel
def fnRead (name : String) : IR := [["fn", name, "i64", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", "0", "1", "-1", "v", "%Vec__i64"], ["scope"], ["ret", "c"], ["end"], ["endfn"]]
example : (elabIR (irM vsLen (bodyVec ++ [["let", "2", "call", "slice_at__x", "1", "v1"], ["ret", "c"]])
    (fnRead "slice_at__x"))).isNone := by decide +kernel
example : (elabIR (irM vsLen (bodyVec ++ [["let", "2", "call", "slice_atx", "1", "v1"], ["ret", "c"]])
    (fnRead "slice_atx"))).isSome := by decide +kernel

/-- A buffer's drop ends the elements read out of it too (`vec_at`,
    `__views_of`): the element of the temporary read after the temporary's
    drop is refused, the element of its binding is not. -/
example : (elabIR (irM vsLen [["let", "0", "call", "vec_new__i64", "0"],
    ["let", "2", "call", "vec_at__i64", "2", "v0", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
    ["eval", "scalar", "1", "v2"], ["ret", "c"]] [])).isNone := by decide +kernel
example : (elabIR (irM vsLen (bodyVec ++ [["let", "2", "call", "vec_at__i64", "2", "v1", "c"],
    ["drop", "0"], ["eval", "scalar", "1", "v2"], ["ret", "c"]]) [])).isSome := by decide +kernel

/-- An owned result aliasing a parameter (`ret_alias`) is refused; without
    the key the Vec handed back is the result, owned. -/
def fnMake (extra : IR) : IR := [["fn", "make", "%Vec__i64", "0", "1", "a.nu", "0", ""]] ++ vsVec ++
  [["scope"]] ++ bodyVec ++ [["ret", "v1"], ["end"], ["endfn"]] ++ extra
example : (elabIR (irM [] [["ret", "c"]] (fnMake [["sum", "make", "0", "ret_alias=0"]]))).isNone := by
  decide +kernel
example : (elabIR (irM [] [["ret", "c"]] (fnMake []))).isSome := by decide +kernel

/-- Stores the translator refuses: a borrowed parameter's value given to an
    owner (a `sink` one's is not); raw text assigned from another binding (a
    `String` is not). -/
def fnStore (pflags : String) : IR := [["fn", "f", "void", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", pflags, "1", "-1", "a", "%Vec__i64"],
  ["v", "1", "1", "1", "1", "1", "-1", "b", "%Vec__i64"],
  ["scope"], ["let", "1", "call", "vec_new__i64", "0"], ["assign", "v1", "use", "v0"], ["end"], ["endfn"]]
example : (elabIR (irM [] [["ret", "c"]] (fnStore "0"))).isNone := by decide +kernel
example : (elabIR (irM [] [["ret", "c"]] (fnStore "4"))).isSome := by decide +kernel
def vsText (t : String) : IR := [["v", "0", "1", "1", "1", "1", "-1", "a", t],
  ["v", "1", "1", "1", "1", "1", "-1", "b", t]]
def bodyText : IR := [["let", "0", "use", "c"], ["let", "1", "use", "c"], ["assign", "v1", "use", "v0"],
  ["ret", "c"]]
example : (elabIR (irM (vsText "i8*") bodyText [])).isNone := by decide +kernel
example : (elabIR (irM (vsText "%String") bodyText [])).isSome := by decide +kernel

/-- Outside the subset: a `Vec` of `Vec`s, and a `let` of a `vec_push` (the
    translator lowers it by falling through to a call). -/
example : (elabIR (irM [["v", "0", "1", "1", "1", "1", "-1", "v", "%Vec__Vec__i64"]] [["ret", "c"]]
    [])).isNone := by decide +kernel
example : (elabIR (irM (vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "void"]])
    (bodyVec ++ [["let", "2", "call", "vec_push__i64", "2", "v1", "c"], ["ret", "c"]]) [])).isNone := by
  decide +kernel

end C.Elab
