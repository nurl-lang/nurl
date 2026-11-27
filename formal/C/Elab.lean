import C.A2Prog

/-!
# The core IR as words, read in the kernel (AGORA-1029, steps 1, 2 and 4–7)

docs/dev/TRANSLATION_TRUST.md route (b): a certificate holds nurlc's core IR
as plain Lean data, one entry per line and each line its words (header
lines `fn`, `v`, `ty` and `sum` split at tabs, statements at spaces), and
Lean builds the calculus term from it, so the translation is no longer a
trusted step. This file is the data and its reader (step 1), and the term
of a program of the subset built from it (`elabIR`: numbers, step 2;
buffers of numbers, step 4; views, slices and changes through a borrow,
step 5; closures, step 6; structs and options, step 7).

Each word is a number (step 6, "the words as numbers"): `0x1` and then
the word's bytes from its last to its first, two hex digits each, so
256^k + Σ bᵢ·256^i for a word of k bytes b₀ … b_{k−1}. The kernel holds
such a number as one GMP integer and reads it back into its bytes
(`wordOf`) by `% 256` and `/ 256`, a step a byte. A string literal costs it
far more: Lean 4.35's `String` is a UTF-8 `ByteArray`, which the kernel
builds from a literal by one `push` a byte, quadratic in its length (40
distinct words: 0.15 s at 8 bytes, 1.24 s at 32, 17 s at 128).

Everything here reduces in the kernel (`decide +kernel`): numbers are read
by structural recursion over a word's bytes, since Lean's own
`String.toNat?` and `String.splitOn` do not reduce there (measured,
`tools/ncore/trust/measure.sh`).
-/

namespace C.Elab

/-- The core IR as `nurl-cert words` prints it: its lines, each its words,
    each word a number (`0x1` then its bytes, last to first). -/
abbrev IR := List (List Nat)

/-- A word, as its number: compared with a keyword's number at once (one
    GMP comparison), read into its bytes (`wordOf`) where its text is
    needed, which the kernel does once for each number (it keeps what it
    reduced). -/
abbrev W := Nat

/-- The core IR's lines, each its words. -/
abbrev Lines := List (List W)

/-- The bytes of a word number, first to last: the remainders by 256 until
    the leading 1 is left (fuel: the number itself, more than its bytes). -/
def wordGo : Nat → Nat → List Nat → List Nat
  | 0, _, acc => acc.reverse
  | f + 1, n, acc => if n < 256 then acc.reverse else wordGo f (n / 256) (n % 256 :: acc)

def wordOf (n : Nat) : List Nat := wordGo n n []

/-- A text's UTF-8 bytes, as numbers: for the texts written here (each
    keyword is written as its bytes and checked against its text), and the
    witnesses' IRs, which are written as text (`encIR`, `strs`). -/
def bytesOf (w : String) : List Nat := w.toByteArray.data.toList.map UInt8.toNat

/-- A word's number, as `nurl-cert words` prints it (`0x1`, then the bytes
    last to first). -/
def encB (bs : List Nat) : Nat := bs.foldr (fun b acc => acc * 256 + b) 1

/-- Witnesses' IRs, written as text, as numbers (`encIR`, `strs`). -/
def enc (w : String) : Nat := encB (bytesOf w)
def encIR (l : List (List String)) : IR := l.map (·.map enc)
def strs (l : List (List String)) : Lines := encIR l

/-- Reading a word back gives its bytes: `wordOf` inverts the printer's
    encoding for every list of bytes. -/
theorem wordGo_encB (bs acc : List Nat) (f : Nat) (hb : ∀ b ∈ bs, b < 256) (hf : bs.length < f) :
    wordGo f (encB bs) acc = acc.reverse ++ bs := by
  induction bs generalizing acc f with
  | nil =>
    cases f with
    | zero => simp at hf
    | succ f => simp [wordGo, encB]
  | cons b bs ih =>
    cases f with
    | zero => simp at hf
    | succ f =>
      have hb0 : b < 256 := hb b (by simp)
      have hr : ∀ c ∈ bs, c < 256 := fun c hc => hb c (by simp [hc])
      have hge : 1 ≤ encB bs := by
        clear ih hr hb hf
        induction bs with
        | nil => simp [encB]
        | cons c cs ihc => simp only [encB, List.foldr] at ihc ⊢; omega
      have he : encB (b :: bs) = encB bs * 256 + b := rfl
      have hn : ¬ encB (b :: bs) < 256 := by rw [he]; omega
      simp only [wordGo, hn, ite_false]
      rw [he, show (encB bs * 256 + b) / 256 = encB bs by omega,
        show (encB bs * 256 + b) % 256 = b by omega]
      rw [ih (b :: acc) f hr (by simp at hf; omega)]
      simp

theorem wordOf_encB (bs : List Nat) (hb : ∀ b ∈ bs, b < 256) : wordOf (encB bs) = bs := by
  have hlen : bs.length < encB bs := by
    clear hb
    induction bs with
    | nil => simp [encB]
    | cons c cs ih => simp only [encB, List.foldr, List.length_cons] at ih ⊢; omega
  simpa [wordOf] using wordGo_encB bs [] (encB bs) hb hlen

example : wordOf 0x16e66 = bytesOf "fn" ∧ wordOf 0x1 = [] ∧ encB (bytesOf "fn") = 0x16e66 ∧
    wordOf (encB (bytesOf "a\"\u00e9\n")) = bytesOf "a\"\u00e9\n" := by decide +kernel

@[match_pattern] def kFn : W := 0x16e66
@[match_pattern] def kEndfn : W := 0x16e66646e65
@[match_pattern] def kV : W := 0x176
@[match_pattern] def kSum : W := 0x16d7573
@[match_pattern] def kTy : W := 0x17974
@[match_pattern] def kScope : W := 0x165706f6373
@[match_pattern] def kIf : W := 0x16669
@[match_pattern] def kElse : W := 0x165736c65
@[match_pattern] def kEnd : W := 0x1646e65
@[match_pattern] def kLoop : W := 0x1706f6f6c
@[match_pattern] def kLoopcond : W := 0x1646e6f63706f6f6c
@[match_pattern] def kForeach : W := 0x168636165726f66
@[match_pattern] def kMatch : W := 0x1686374616d
@[match_pattern] def kDefer : W := 0x17265666564
@[match_pattern] def kArm : W := 0x16d7261
@[match_pattern] def kLine : W := 0x1656e696c
@[match_pattern] def kDrop : W := 0x1706f7264
@[match_pattern] def kBreak : W := 0x16b61657262
@[match_pattern] def kContinue : W := 0x165756e69746e6f63
@[match_pattern] def kRet : W := 0x1746572
@[match_pattern] def kLet : W := 0x174656c
@[match_pattern] def kEval : W := 0x16c617665
@[match_pattern] def kAssign : W := 0x16e6769737361
@[match_pattern] def kCall : W := 0x16c6c6163
@[match_pattern] def kClosure : W := 0x1657275736f6c63
@[match_pattern] def kCallind : W := 0x1646e696c6c6163
@[match_pattern] def kUse : W := 0x1657375
@[match_pattern] def kNone : W := 0x1656e6f6e
@[match_pattern] def kScalar : W := 0x172616c616373
@[match_pattern] def kAgg : W := 0x1676761
@[match_pattern] def kC : W := 0x163
@[match_pattern] def kT : W := 0x154
@[match_pattern] def kOne : W := 0x131
@[match_pattern] def kVoid : W := 0x164696f76
@[match_pattern] def kA : W := 0x141
@[match_pattern] def kF : W := 0x146
@[match_pattern] def kVV : W := 0x156
@[match_pattern] def kDash : W := 0x12d
@[match_pattern] def kPayload : W := 0x164616f6c796170
@[match_pattern] def kZero : W := 0x130
example : [kFn, kEndfn, kV, kSum, kTy, kScope, kIf, kElse, kEnd, kLoop, kLoopcond, kForeach, kMatch, kDefer,
    kArm, kLine, kDrop, kBreak, kContinue, kRet, kLet, kEval, kAssign, kCall, kClosure, kCallind, kUse, kNone,
    kScalar, kAgg, kC, kT, kOne, kVoid, kA, kF, kVV, kDash, kPayload, kZero] =
    ["fn", "endfn", "v", "sum", "ty", "scope", "if", "else", "end", "loop", "loopcond", "foreach", "match",
     "defer", "arm", "line", "drop", "break", "continue", "ret", "let", "eval", "assign", "call", "closure",
     "callind", "use", "none", "scalar", "agg", "c", "T", "1", "void", "A", "F", "V", "-", "payload", "0"].map enc := by
  decide +kernel

/-- Other texts the subset compares words with: a type, `main`, and the
    keys of a `sum` line it reads. -/
def kI64 : W := 0x1343669
/-- The empty word (a name a `v` line leaves out), and the raw-text and
    `String` types. -/
def kEmpty : W := 0x1
def kI8p : W := 0x12a3869
def kString : W := 0x1676e6972745325
def kMain : W := 0x16e69616d
def kSink : List Nat := [115, 105, 110, 107]
def kKeeps : List Nat := [107, 101, 101, 112, 115]
def kRetOwned : List Nat := [114, 101, 116, 95, 111, 119, 110, 101, 100]
def kRetUnowned : List Nat := [114, 101, 116, 95, 117, 110, 111, 119, 110, 101, 100]
def kRviews : List Nat := [114, 118, 105, 101, 119, 115]
def kDrops : List Nat := [100, 114, 111, 112, 115]
def kReallocs : List Nat := [114, 101, 97, 108, 108, 111, 99, 115]
def kIreallocs : List Nat := [105, 114, 101, 97, 108, 108, 111, 99, 115]
def kMutates : List Nat := [109, 117, 116, 97, 116, 101, 115]
def kRetdyn : List Nat := [114, 101, 116, 100, 121, 110]
def kRetAlias : List Nat := [114, 101, 116, 95, 97, 108, 105, 97, 115]
example : [kI64, kMain, kEmpty, kI8p, kString] = ["i64", "main", "", "i8*", "%String"].map enc ∧ [kSink, kKeeps, kRetOwned, kRetUnowned, kRviews, kDrops,
    kReallocs, kIreallocs, kMutates, kRetdyn, kRetAlias] = ["sink", "keeps", "ret_owned", "ret_unowned", "rviews",
    "drops", "reallocs", "ireallocs", "mutates", "retdyn", "ret_alias"].map bytesOf := by decide +kernel

/-- A decimal number's digits (ASCII bytes), most significant first. -/
def digitsN : List Nat → Nat → Option Nat
  | [], acc => some acc
  | c :: r, acc => if 48 ≤ c && c ≤ 57 then digitsN r (acc * 10 + (c - 48)) else none

/-- A word that is a number: one digit at least, nothing else. -/
def natOf (w : W) : Option Nat :=
  match wordOf w with
  | [] => none
  | cs => digitsN cs 0

/-- A variable operand `v<id>` (no field path). -/
def varOf (w : W) : Option Nat :=
  match wordOf w with
  | 118 :: cs@(_ :: _) => digitsN cs 0   -- 'v'
  | _ => none

/-- A function of the core IR: its header, its variables (id, kind, flags,
    type) and its statements, each its words. -/
structure CoreFn where
  name : W
  ret : W
  np : Nat
  file : W
  vars : List (Nat × Nat × Nat × W)
  body : List (List W)
deriving DecidableEq, Repr

/-- A `v` line: `v id kind depth flags line value-block name type` (the
    name may be empty, so the type is the line's last word). -/
def readVar : List W → Option (Nat × Nat × Nat × W)
  | kV :: id :: kind :: _depth :: flags :: rest =>
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
def readFns : Lines → Option CoreFn → List CoreFn → Option (List CoreFn)
  | [], none, acc => some acc.reverse
  | [], some _, _ => none
  | l :: ls, none, acc =>
    match l with
    | kFn :: name :: ret :: np :: _line :: file :: _ =>
      match natOf np with
      | some n => readFns ls (some ⟨name, ret, n, file, [], []⟩) acc
      | none => none
    | kFn :: _ => none        -- a header cut short
    | kEndfn :: _ => none
    | _ => readFns ls none acc
  | l :: ls, some f, acc =>
    match l with
    | kEndfn :: _ => readFns ls none ({ f with vars := f.vars.reverse, body := f.body.reverse } :: acc)
    | kFn :: _ => none
    | kV :: _ =>
      match readVar l with
      | some v => readFns ls (some { f with vars := v :: f.vars }) acc
      | none => none
    | _ => readFns ls (some { f with body := l :: f.body }) acc

/-- The IR's functions, its words read once. -/
def fnsOfL (ls : Lines) : Option (List CoreFn) := readFns ls none []

def fnsOf (ir : IR) : Option (List CoreFn) := fnsOfL ir

/-! ### Witnesses -/

example : natOf (enc "123") = some 123 := by decide +kernel
example : natOf (enc "12a") = none := by decide +kernel
example : varOf (enc "v42") = some 42 := by decide +kernel
example : varOf (enc "v") = none := by decide +kernel

/-- A two-function IR read back (its words as numbers): names, parameter
    counts, variables and the statements, in order. -/
example : (fnsOf (encIR [["fn", "f", "i64", "1", "1", "a.nu", "0"],
    ["v", "0", "0", "0", "0", "1", "-1", "n", "i64"],
    ["scope"], ["ret", "v0"], ["end"], ["endfn"],
    ["fn", "main", "i64", "0", "3", "a.nu", "0"], ["scope"], ["ret", "c"], ["end"], ["endfn"],
    ["sum", "f", "1", "safe=1"]])).map (·.map (fun f => (f.name, f.np, f.vars.length, f.body.length)))
    = some [(enc "f", 1, 1, 3), (enc "main", 0, 0, 3)] := by decide +kernel

/-- A function left open, and an `endfn` with none open, are refused. -/
example : fnsOfL (strs [["fn", "f", "i64", "0", "1", "a.nu", "0"], ["scope"]]) = none := by decide +kernel
example : fnsOfL (strs [["endfn"]]) = none := by decide +kernel
/-- A header cut short, and a kind outside 0–3, are refused too. -/
example : fnsOfL (strs [["fn", "broken"]]) = none := by decide +kernel
example : fnsOfL (strs [["fn", "f", "i64", "0", "1", "a.nu", "0"],
    ["v", "0", "4", "0", "0", "1", "-1", "", "i64"], ["endfn"]]) = none := by decide +kernel

/-! ## Steps 2 and 4–7: the term of a program of numbers, buffers, views, closures, structs and options (AGORA-1029)

`elabIR ir` (`elab` is a keyword of Lean) builds the A2 program and its
entry statement from the words of a core IR, for the **subset**: every
function of the program (the ones whose file is not the standard
library's, as the translator selects them) has only variables and
parameters of a type `tyOf` takes: a number (step 2); a buffer of numbers
(step 4: raw text `i8*`, a `String`, a `Vec` of a number type; A2's `.vec
.int`); a `Vec` of raw text (`%Vec__str`, `.vec (.slice .int)`) or a
`Slice` of a number type (`.slice .int`, step 5); a closure type of the
program's (`.fn [σ] .any`, step 6); an option of such a type (`.sum .int
T`) or a struct of such fields (`.prod`, nested to the right; step 7). Raw
text bound from a
view (`string_data`, an element of a `Vec` of raw text, a copy of such a
view) is a slice too (`viewVars`, the translator's `__view_vars`). A
result is a number, or a buffer or `Vec` handed over (owned), never a
slice. Its statements are among
`scope`/`if`/`else`/`loop`/`loopcond`/`foreach`/`end`, `line`, `drop`,
`break`, `continue`, `let k use|none|scalar …`, `let k call f …`,
`eval scalar|use|none …`, `eval call f …`, `assign vK use|none|scalar …`,
`ret c|-|vK`, (step 6) `let k closure f n caps…` and `let k|eval
callind n c args…`, and (step 7) `let k|assign vK agg -|T|F n ops…`
(a struct's or an option's literal), `payload vK T 0` (an option's
payload), `use vK/f` (a number field) and `match vK` with arms `T` and
`F`, where every call is of a function of the program or one
of the library calls `intrS` lowers (`vec_new`, `vec_push`, `vec_len`,
`vec_at`, `vec_free`, `string_from`, `string_len`, `string_free`,
`nurl_str_cat`, `nurl_str_len`; step 5: `string_data`, `slice_from_vec`,
`slice_len`, `nurl_println`, `vec_clear`, `vec_truncate`, `vec_reserve`,
`vec_shrink_to_fit`, `string_push_str`; step 6: `nurl_println_int`). A
closure's code (`__closure_…`) is a function of its environment, its
parameters and its captures by name; a literal packs the code with its
captures by value (`.pack`), a call through a closure value is `.callc` of
its type's interface, one function per closure type after the program's
own. A struct's literal is its fields' values nested in pairs (`.pair`),
a field read through the pairs into a temporary (`.fst`, `.snd`) where an
operand or a library call's argument names it; an option's literal is
`.inl`/`.inr`, its match a test of its tag (`.isl`) and its `T` arm's
payload lent (`.getr`). A buffer or a view moves
(`.var`), is borrowed by a cursor (`.borrow`), a Vec is copied into an
`inout` parameter, and a `drop` is the end of a scope. A view is a
`.view` of a buffer, a `foreach` a loop over a view of its Vec lending
each element (`.sat`), and a change of a Vec's elements in place an
`.edit` through a borrow of it. Anything else is `none` (fail closed).

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
`Vec` of anything but numbers and raw text, a slice of anything but
numbers, a slice handed back, a `let x` of a library call the translator
lowers by falling through to a call (`vec_push`, `vec_free`,
`vec_reserve`, `nurl_println`, …), a call whose result the summary says
is lent (but `string_data`'s), a change in place of a `foreach`'s element.
The checks the translator makes on what it translates are made here too,
the ones on code it then passes over included (a buffer, or a view of it,
named after its `drop`, `__views_of`; raw text that holds a view,
`__view_vars`, over the whole body). It does not read the IR's `ty`,
`virt` and `sum` lines past what the subset needs (a `d` drop flag: the
program has a destructor; a `sum` line's keys). Step 6 adds, stricter: a
literal of a function not named as a closure's code, a closure type's
arguments spelled other than nurlc prints them, a closure's code naming a
variable it does not declare, variables not in id order in a program with
closures, a closure copied from another binding where its value is handed
back at once, a `let x` of `nurl_println_int`. Step 7 adds, stricter: a
struct whose fields' names repeat, a type nested deeper than `tyFuel`, a
field of a type that is no struct of the subset (a `Vec`'s handle), a
field of a struct of one field named other than its field, a struct named
like a number type behind its `%`, a `match` of other than two arms.

Everything is total and reduces in the kernel: recursion is structural
(over a fuel bound by the body's length where a list is rebuilt), and
words are compared as numbers (with the keywords' numbers, `kLet` …) and
read as bytes (`wordOf`) where their text is needed: a variable, a count,
a type, a callee's name. -/

open A2

/-! ### Words -/

/-- `p` is a prefix of `a`. -/
def prefixN : List Nat → List Nat → Bool
  | [], _ => true
  | _ :: _, [] => false
  | p :: ps, a :: as => p == a && prefixN ps as

def startsB (w : W) (p : List Nat) : Bool := prefixN p (wordOf w)

def stdlibB : List Nat := [115, 116, 100, 108, 105, 98, 47]
def dropB : List Nat := [100, 114, 111, 112, 95, 95]
def closureB : List Nat := [95, 95, 99, 108, 111, 115, 117, 114, 101, 95]
example : stdlibB = bytesOf "stdlib/" ∧ dropB = bytesOf "drop__" ∧
    closureB = bytesOf "__closure_" := by decide +kernel

/-- The bound the core IR keeps its variable ids to (2^62, `core_id_max`). -/
def idMax : Nat := 4611686018427387904

/-- An id word (`let <k>`, `drop <k>`): digits, within the bound. -/
def idOf (w : W) : Option Nat :=
  match natOf w with
  | some k => if k ≤ idMax then some k else none
  | none => none

/-- A whole variable `v<k>` (no field path), within the bound. -/
def vref (w : W) : Option Nat :=
  match varOf w with
  | some k => if k ≤ idMax then some k else none
  | none => none

/-- The number types as bytes, for a type inside a name (`%Vec__i64`,
    `vec_push__i64`). -/
def intNamesB : List (List Nat) := [
  [105, 54, 52], [105, 49], [105, 51, 50], [105, 49, 54], [105, 56], [118, 111, 105, 100],
  [117, 54, 52], [117, 51, 50], [117, 49, 54], [117, 56], [102, 54, 52], [102, 51, 50],
  [100, 111, 117, 98, 108, 101], [102, 108, 111, 97, 116]]

def intTyB (cs : List Nat) : Bool := intNamesB.any (· == cs)

/-- The number types as words, compared at once. -/
def intCodes : List W := [0x1343669, 0x13169, 0x1323369, 0x1363169, 0x13869, 0x164696f76, 0x1343675, 0x1323375, 0x1363175, 0x13875, 0x1343666, 0x1323366, 0x1656c62756f64, 0x174616f6c66]
example : intCodes = intNamesB.map encB := by decide +kernel

/-- The IR's number types (`__int_ty`): each is A2's `int`. -/
def intTy (t : W) : Bool := intCodes.contains t

example : intNamesB = ["i64", "i1", "i32", "i16", "i8", "void", "u64", "u32", "u16", "u8",
    "f64", "f32", "double", "float"].map bytesOf := by decide +kernel

def vecTyB : List Nat := [37, 86, 101, 99, 95, 95]
example : vecTyB = bytesOf "%Vec__" := by decide +kernel

def sliceTyB : List Nat := [37, 83, 108, 105, 99, 101, 95, 95]
def strB : List Nat := [115, 116, 114]
example : sliceTyB = bytesOf "%Slice__" ∧ strB = bytesOf "str" := by decide +kernel

/-- An element type of a `Vec` of the subset, as A2's (`__lean_ty` of the
    name's last part): a number, or `str`, raw text held in a value, a view
    (`(.slice .int)`). -/
def elemTy (cs : List Nat) : Option Ty :=
  if intTyB cs then some .int else if cs == strB then some (.slice .int) else none

def i8pB : List Nat := [105, 56, 42]
def stringTyB : List Nat := [37, 83, 116, 114, 105, 110, 103]
example : i8pB = bytesOf "i8*" ∧ stringTyB = bytesOf "%String" := by decide +kernel

/-- `tyOf` below, of a type given as its bytes (an argument or the result
    of a closure type, step 6): the same answer on the same text. -/
def tyOfB (cs : List Nat) : Option Ty :=
  if intTyB cs then some .int
  else if cs == i8pB || cs == stringTyB then some (.vec .int)
  else if prefixN vecTyB cs then (elemTy (cs.drop 6)).map .vec
  else if prefixN sliceTyB cs && intTyB (cs.drop 8) then some (.slice .int)
  else none

/-! #### Closure types (step 6)

A closure type is `{ R (i8*, A1, A2…)*, i8* }`: code taking the
environment (`i8*`) and the arguments, and the environment (`__clo_sig`).
The translator makes it A2's `.fn [σ] .any`, where `σ` is the program's
interface for that type: one per closure type, after the program's own
functions, in the order the translator first meets the type
(`__clo_index`). -/

def cloHeadB : List Nat := [123, 32]
def cloTailRevB : List Nat := [125, 32, 42, 56, 105, 32, 44]
def cloRecvB : List Nat := [32, 40, 105, 56, 42]
example : cloHeadB = bytesOf "{ " ∧ cloTailRevB = (bytesOf ", i8* }").reverse ∧
    cloRecvB = bytesOf " (i8*" := by decide +kernel

/-- The first place `p` starts at in a text, counted from `i`. -/
def findB (p : List Nat) : List Nat → Nat → Option Nat
  | [], _ => none
  | c :: cs, i => if prefixN p (c :: cs) then some i else findB p cs (i + 1)

/-- The pieces of a text between its bytes `sep`. -/
def piecesAt (sep : Nat) : List Nat → List Nat → List (List Nat)
  | [], cur => [cur.reverse]
  | ch :: r, cur => if ch == sep then cur.reverse :: piecesAt sep r [] else piecesAt sep r (ch :: cur)

/-- ASCII whitespace, as the reader splits a summary's words. -/
def isWs (c : Nat) : Bool :=
  c == 32 || (9 ≤ c && c ≤ 13) || (28 ≤ c && c ≤ 31)

/-- An argument of a closure type, after its `,`: one space, then a word
    with no whitespace. -/
def cloArgB : List Nat → Option (List Nat)
  | 32 :: a@(_ :: _) => if a.any isWs then none else some a
  | _ => none

/-- A closure type's result and arguments, as text (`__clo_sig`): the type
    starts `{ ` and ends `, i8* }`; the result is what comes before the
    first ` (i8*`, the arguments the pieces between it and `)*`. The
    translator splits them at each `,`, drops the whitespace around a piece
    and skips an empty one; here each argument must be written `, A` (one
    space, a word with no whitespace), as nurlc prints it (stricter). -/
def cloSigB (cs : List Nat) : Option (List (List Nat)) :=
  if !(prefixN cloHeadB cs && prefixN cloTailRevB cs.reverse) then none
  else
    let head := (cs.drop 2).take (cs.length - 9)
    match findB cloRecvB head 0 with
    | none => none
    | some k =>
      let rest := head.drop (k + 5)
      if !prefixN [42, 41] rest.reverse then none        -- ends ")*"
      else match piecesAt 44 (rest.take (rest.length - 2)) [] with
        | [] :: ps => (ps.mapM cloArgB).map (head.take k :: ·)
        | _ => none

/-- The program's closure types, in the order the translator first meets
    them, each as its bytes: closure type `k` is A2's `.fn [base + k] .any`,
    its interface the program's function `base + k` (after the program's
    own functions, `base` of them). -/
structure CloTab where
  base : Nat
  tys : List (List Nat)
  /-- The IR's top-level lines (step 7: a struct's fields are read off its
      last `ty` line). -/
  tyls : List (List W)

def indexOfB (xs : List (List Nat)) (x : List Nat) : Option Nat :=
  match xs with
  | [] => none
  | y :: ys => if y == x then some 0 else (indexOfB ys x).map (· + 1)

/-! #### Options and structs (step 7)

An option is `{ i1, T }` (`__lean_ty`): A2's `.sum .int T`, `None` the
first variant. A struct is a type named `%S` with a `ty` line of fields:
its fields' types nested in pairs to the right (`_struct_ty`), one field
its field's type (A2 has no one-element tuple). -/

def optHeadB : List Nat := [123, 32, 105, 49, 44, 32]
def optTailRevB : List Nat := [125, 32]
def chanTyB : List Nat := [37, 67, 104, 97, 110, 110, 101, 108, 95, 95]
def strTyB : List Nat := [37, 115, 116, 114]
example : optHeadB = bytesOf "{ i1, " ∧ optTailRevB = (bytesOf " }").reverse ∧
    chanTyB = bytesOf "%Channel__" ∧ strTyB = bytesOf "%str" := by decide +kernel

/-- A type the translator reads as a closure type, well formed or not
    (`__clo_sig`: it starts `{ `, ends `, i8* }` and holds ` (i8*`). -/
def cloShaped (cs : List Nat) : Bool :=
  prefixN cloHeadB cs && prefixN cloTailRevB cs.reverse && (findB cloRecvB cs 0).isSome

/-- An option type: `{ i1, ` … ` }`, and not closure-shaped (the translator
    asks `__clo_sig` first). -/
def optB (cs : List Nat) : Bool :=
  prefixN optHeadB cs && prefixN optTailRevB cs.reverse && !cloShaped cs

/-- An option's payload type, the text between `{ i1, ` and ` }`. -/
def optInner (cs : List Nat) : List Nat := (cs.drop 6).take (cs.length - 8)

/-- A name `__lean_ty` reads as a struct's (its `ty` line's fields): it
    starts `%` and is none of the types the translator takes before it
    (`%Vec__…`, `%Channel__…`, `%str`, `%Slice__…`, `%String`), nor a
    number type behind its `%`s (the translator takes `%i64` for a number;
    `elabIR` refuses it, stricter). `%String` is no struct here either,
    though the IR has a `ty` line for it (`ctl i8*`): a place `v/ctl` of a
    String, which the translator would read as the whole String (one field,
    read without its name), is refused (stricter, as a `Vec`'s handle). -/
def structNameB (cs : List Nat) : Bool :=
  match cs with
  | 37 :: _ =>
    !prefixN vecTyB cs && !prefixN sliceTyB cs && !prefixN chanTyB cs && cs != strTyB &&
    cs != stringTyB && !intTyB (cs.dropWhile (· == 37))
  | _ => false

/-- `n` name–type pairs. -/
def pairsN : Nat → List W → List (W × W)
  | 0, _ => []
  | k + 1, a :: b :: r => (a, b) :: pairsN k r
  | _ + 1, _ => []

/-- A `ty` line's fields, as the reader reads them (`__cr_ty`): after the
    type arguments (`A n` and `n` words), `F n` and `n` pairs. (`topOk` has
    checked every `ty` line's shape.) -/
def tyFieldsW (rest : List W) : List (W × W) :=
  let fs := match rest with
    | kA :: na :: more => more.drop ((natOf na).getD 0)
    | _ => rest
  match fs with
  | kF :: nf :: r => pairsN ((natOf nf).getD 0) r
  | _ => []

/-- The fields of type `t` (name, type): its last `ty` line's (the reader's
    `ty_of`, `core_ty_index`), none without one. -/
def fieldsOf (tyls : List (List W)) (t : W) : Option (List (W × W)) :=
  tyls.foldl (fun acc l => match l with
    | kTy :: name :: _ :: _ :: _ :: rest => if name == t then some (tyFieldsW rest) else acc
    | _ => acc) none

/-- A closure's environment of captures of types `tys` (`__env_ty`), and a
    struct of two fields or more (`_struct_ty`): a number for none, the one,
    or pairs nested to the right. -/
def envTy : List Ty → Ty
  | [] => .int
  | [t] => t
  | t :: ts => .prod t (envTy ts)

/-- No word twice. -/
def nodupB : List W → Bool
  | [] => true
  | x :: xs => !xs.contains x && nodupB xs

/-- How deep `tyR` follows types inside types (an option's payload, a
    struct's field): deeper is refused (stricter than the translator, which
    follows any depth; fail closed). Every type `tyR` reads counts, the
    innermost one too: a number inside 31 options is read (32 types), inside
    32 it is refused (`nestOpt` below). -/
def tyFuel : Nat := 32

/-- A type of the subset as A2's (`__lean_ty`), types inside it included:
    a number; a buffer of numbers (`i8*`, `%String`, a `Vec` of numbers);
    a `Vec` of raw text; a `Slice` of numbers; an option of such a type
    (`.sum .int T`); a struct of such fields (`.prod`, nested to the right;
    one field: its type). As the translator: a struct holding raw text (a
    field `i8*`), a struct of no fields, a struct inside itself (`exp`, the
    structs being expanded) and a closure inside a value (`__no_clo`) are
    refused. Stricter: a struct whose fields' names are not distinct (the
    translator reads a field by its first name in one place and its last in
    another), and a nesting deeper than `tyFuel`. -/
def tyR (tyls : List (List W)) : Nat → List W → W → Option Ty
  | 0, _, _ => none
  | f + 1, exp, t =>
    if intTy t then some .int
    else if t == kI8p || t == kString then some (.vec .int)
    else
      let cs := wordOf t
      if prefixN vecTyB cs then (elemTy (cs.drop 6)).map .vec
      else if prefixN sliceTyB cs && intTyB (cs.drop 8) then some (.slice .int)
      else match cs with
        | 123 :: _ => if optB cs then (tyR tyls f exp (encB (optInner cs))).map (.sum .int) else none
        | 37 :: _ =>
          if !structNameB cs || exp.contains t then none
          else match fieldsOf tyls t with
            | some [(_, ft)] => if ft == kI8p then none else tyR tyls f (t :: exp) ft
            | some fs@(_ :: _ :: _) =>
              if fs.any (·.2 == kI8p) || !nodupB (fs.map (·.1)) then none
              else (fs.mapM fun p => tyR tyls f (t :: exp) p.2).map envTy
            | _ => none
        | _ => none

/-- A type of the subset as A2's (`__lean_ty`): `tyR`'s, and a closure type
    of the program's (`.fn [σ] .any`, step 6). (Raw text that holds a view
    is a slice too, `Ctx.vl`: that is the variable's, not its type's.) -/
def tyOf (cl : CloTab) (t : W) : Option Ty :=
  if intTy t || t == kI8p || t == kString then tyR cl.tyls tyFuel [] t
  else match wordOf t with
    | cs@(123 :: _) =>
      if optB cs then tyR cl.tyls tyFuel [] t
      else (indexOfB cl.tys cs).map fun k => .fn [cl.base + k] .any
    | _ => tyR cl.tyls tyFuel [] t

example : tyOf ⟨0, [], []⟩ (enc "%Vec__str") = some (.vec (.slice .int)) ∧
    tyOf ⟨0, [], []⟩ (enc "%Slice__u8") = some (.slice .int) ∧
    tyOf ⟨0, [], []⟩ (enc "%Slice__str") = none ∧ tyOf ⟨0, [], []⟩ (enc "%Vec__String") = none := by decide +kernel

/-- `i64` inside `n` options, as its bytes (`{ i1, ` … ` }` `n` times; built
    from the bytes, no string literal for the kernel to build). -/
def nestOpt : Nat → List Nat
  | 0 => [105, 54, 52]
  | n + 1 => optHeadB ++ nestOpt n ++ optTailRevB.reverse

/-- `tyFuel`'s bound: a number inside 31 options is read, inside 32 it is
    refused (fail closed; the translator follows any depth). -/
example : (tyOf ⟨0, [], []⟩ (encB (nestOpt 31))).isSome = true ∧
    tyOf ⟨0, [], []⟩ (encB (nestOpt 32)) = none ∧
    tyOf ⟨0, [], []⟩ (encB (nestOpt 2)) = some (.sum .int (.sum .int .int)) := by decide +kernel

/-- `%String` is no struct (a place `v/ctl` of a String is refused), though
    a struct may hold one. -/
example : structNameB stringTyB = false ∧ structNameB (bytesOf "%P") = true ∧
    tyOf ⟨0, [], strs [["ty", "%P", "1", "0-----", "P", "A", "0", "F", "2", "x", "i64", "s", "%String", "V", "0"]]⟩
      (enc "%P") = some (.prod .int (.vec .int)) := by decide +kernel

/-- A closure type's result or argument as A2's type: `tyOfB`'s, or a
    struct of the subset's (`tyR`, through the program's `ty` lines, as the
    translator's `__lean_ty` reads it). -/
def cloArgTy (tyls : List (List W)) (b : List Nat) : Option Ty :=
  match tyOfB b with
  | some t => some t
  | none => if structNameB b then tyR tyls tyFuel [] (encB b) else none

/-- A nested or pointer type in a closure type (`__clo_sig`): one that
    holds a `{` or a `(`, or a `*` and is not `i8*`. -/
def nestedOrPtrB (x : List Nat) : Bool :=
  x.contains 123 || x.contains 40 || (x.contains 42 && x != i8pB)

/-- A closure type's result and arguments as A2's types: no raw string
    among them (the translator refuses one: owned text or a view by its use,
    which a closure type does not say), no nested or pointer type (the
    translator refuses one, before it reads a type: so a `%P*` is no struct
    here even where the IR has a `ty %P*` line), each a type `cloArgTy`
    takes. -/
def cloTysB (tyls : List (List W)) (cs : List Nat) : Option (List Ty) := do
  let sig ← cloSigB cs
  if sig.any (· == i8pB) then none
  if sig.any nestedOrPtrB then none
  sig.mapM (cloArgTy tyls)

/-- The closure types `t` adds, met as a variable's or a result's type: a
    well-formed one not met before. (Any other type that starts `{` is
    none of `tyOf`'s.) -/
def cloAdd (tyls : List (List W)) (acc : List (List Nat)) (t : W) : List (List Nat) :=
  if intTy t then acc
  else
    let cs := wordOf t
    match cs with
    | 123 :: _ => if acc.contains cs || (cloTysB tyls cs).isNone then acc else acc ++ [cs]
    | _ => acc

/-- The program's closure types, in the order the translator meets them:
    it reads each function's variables' types, then its result's, in the
    program's order, before it translates the function's body, and it reads
    no other closure type on a program it translates (`__fn_init`). (In the
    order of the `v` lines, where the translator reads them by id, in the
    order an id first appears: `elabIR` requires the ids increasing.) -/
def cloScan (tyls : List (List W)) (prog : List CoreFn) : List (List Nat) :=
  prog.foldl (fun acc f => cloAdd tyls (f.vars.foldl (fun a v => cloAdd tyls a v.2.2.2) acc) f.ret) []

example : cloSigB (bytesOf "{ i64 (i8*, i64, %Vec__i64)*, i8* }") =
      some (["i64", "i64", "%Vec__i64"].map bytesOf) ∧
    cloSigB (bytesOf "{ void (i8*)*, i8* }") = some [bytesOf "void"] ∧
    cloTysB [] (bytesOf "{ i64 (i8*, i64, %Vec__i64)*, i8* }") = some [.int, .int, .vec .int] := by
  decide +kernel
/-- Refused: a raw string argument (the translator refuses it); an argument
    list spelled other than nurlc prints it (stricter: the translator splits
    it at its commas); no ` (i8*` in the head (the translator refuses it). -/
example : cloTysB [] (bytesOf "{ i64 (i8*, i8*)*, i8* }") = none ∧
    cloSigB (bytesOf "{ i64 (i8*,i64)*, i8* }") = none ∧
    cloSigB (bytesOf "{ i64 (i8*, , i64)*, i8* }") = none ∧
    cloSigB (bytesOf "{ (i8*)*, i8* }") = none := by decide +kernel

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

def intrinsicName (f : W) : Bool :=
  let cs := wordOf f
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

/-- The library calls of views and of changes through a borrow (step 5). -/
def stringDataB : List Nat := [115, 116, 114, 105, 110, 103, 95, 100, 97, 116, 97]
def stringPushStrB : List Nat := [115, 116, 114, 105, 110, 103, 95, 112, 117, 115, 104, 95, 115, 116, 114]
def printlnB : List Nat := [110, 117, 114, 108, 95, 112, 114, 105, 110, 116, 108, 110]
def sliceFromVecB : List Nat := [115, 108, 105, 99, 101, 95, 102, 114, 111, 109, 95, 118, 101, 99, 95, 95]
def sliceLenB : List Nat := [115, 108, 105, 99, 101, 95, 108, 101, 110, 95, 95]
def vecClearB : List Nat := [118, 101, 99, 95, 99, 108, 101, 97, 114, 95, 95]
def vecTruncB : List Nat := [118, 101, 99, 95, 116, 114, 117, 110, 99, 97, 116, 101, 95, 95]
def vecReserveB : List Nat := [118, 101, 99, 95, 114, 101, 115, 101, 114, 118, 101, 95, 95]
def vecShrinkB : List Nat :=
  [118, 101, 99, 95, 115, 104, 114, 105, 110, 107, 95, 116, 111, 95, 102, 105, 116, 95, 95]
/-- `vec_at__str` (exact): its result is raw text held in the Vec, a view
    (`__view_vars`). -/
def vecAtStrB : List Nat := vecAtB ++ strB
example : [stringDataB, stringPushStrB, printlnB, sliceFromVecB, sliceLenB, vecClearB, vecTruncB,
    vecReserveB, vecShrinkB, vecAtStrB] = ["string_data", "string_push_str", "nurl_println",
    "slice_from_vec__", "slice_len__", "vec_clear__", "vec_truncate__", "vec_reserve__",
    "vec_shrink_to_fit__", "vec_at__str"].map bytesOf := by decide +kernel

/-- `nurl_println_int` (step 6). -/
def printlnIntB : List Nat := [110, 117, 114, 108, 95, 112, 114, 105, 110, 116, 108, 110, 95, 105, 110, 116]
example : printlnIntB = bytesOf "nurl_println_int" ∧ intrinsicExact.contains printlnIntB := by decide +kernel

/-- Each is a name `intrinsicName` takes, so no function of the program is
    named like one: a call is the library's or the program's, never both. -/
example : [strCatB, strLenB, stringFromB, stringLenB, stringFreeB, stringDataB, stringPushStrB,
      printlnB].all (intrinsicExact.contains ·) ∧
    [vecNewB, vecPushB, vecLenB, vecFreeB, vecAtB, sliceFromVecB, sliceLenB, vecClearB, vecTruncB,
      vecReserveB, vecShrinkB].all (intrinsicPrefix.contains ·) := by decide +kernel

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

/-- Of those, the ones `letCallOk` refuses a `let` of: all but `vec_at__…`
    (an element lent out of the Vec, `.at`), and of these all but
    `slice_from_vec__…` and `string_data` itself (`.view`). -/
def viewOutB : List (List Nat) := viewCallB.filter (· != [118, 101, 99, 95, 97, 116, 95, 95])
example : viewOutB = ["string_data", "slice_from_vec__", "slice_at__"].map bytesOf := by decide +kernel

def indexOf (xs : List W) (x : W) : Option Nat :=
  match xs with
  | [] => none
  | y :: ys => if y == x then some 0 else (indexOf ys x).map (· + 1)

def nth? {α : Type} : List α → Nat → Option α
  | [], _ => none
  | a :: _, 0 => some a
  | _ :: as, n + 1 => nth? as n

/-! ### The `sum` lines -/

/-- `key=value`: the text before the first `=`, and after it. -/
def splitKV : List Nat → List Nat → Option (List Nat × List Nat)
  | [], _ => none
  | ch :: r, acc => if ch == 61 then some (acc.reverse, r) else splitKV r (ch :: acc)

/-- Each top-level line of the IR (outside every function), as the reader
    takes it: lines inside a function are its own. -/
def topLines : Lines → Bool → List (List W)
  | [], _ => []
  | l :: ls, inFn =>
    match l with
    | kFn :: _ => topLines ls true
    | kEndfn :: _ => topLines ls false
    | _ => if inFn then topLines ls inFn else l :: topLines ls inFn

/-- The pairs of function `f`'s summary: its last `sum` line's. -/
def sumKVs (tops : List (List W)) (f : W) : List W :=
  tops.foldl (fun acc l => match l with
    | kSum :: name :: rest => if name == f then rest.drop 1 else acc
    | _ => acc) []

/-- A function's summary: the pairs of its last `sum` line, each key and
    value as bytes (a pair without `=` passed over, as the reader passes it
    over), read once per function and looked up by key. -/
abbrev Summary := List (List Nat × List Nat)

def sumOf (tops : List (List W)) (f : W) : Summary :=
  (sumKVs tops f).filterMap fun kv => splitKV (wordOf kv) []

/-- The value of `key` in a summary (its last pair). -/
def Summary.val (sm : Summary) (key : List Nat) : Option (List Nat) :=
  let kb := key
  sm.foldl (fun acc p => if p.1 == kb then some p.2 else acc) none

/-- The value of `key` in function `f`'s summary. -/
def sumVal (tops : List (List W)) (f : W) (key : List Nat) : Option (List Nat) := (sumOf tops f).val key

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
  numIn (sm.val kSink) j || numIn (sm.val kKeeps) j

/-- Does `f` hand back a value that views what it was handed
    (`__borrowed`)? -/
def borrowedB (sm : Summary) : Bool :=
  match sm.val kRetOwned with
  | some _ => false
  | none =>
    if sm.val kRetUnowned == some [49] then true      -- "1"
    else match sm.val kRviews with
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
def sumHasWord (sm : Summary) (key : List Nat) (j : Nat) : Bool :=
  match sm.val key with
  | none => false
  | some cs => (wordsOf cs []).any (decIs · j)

/-- What `f` does to its parameter `j` through the handle, from the walk's
    summary (`__summary_change`): A2's bound of it, or nothing. -/
def changeOf (sm : Summary) (j : Nat) : Option Eff :=
  let d := sumHasWord sm kDrops j
  let r := sumHasWord sm kReallocs j
  let ir := sumHasWord sm kIreallocs j
  let mu := sumHasWord sm kMutates j
  if d || mu || (r && ir) then some .drop
  else if r then some .realloc
  else if ir then some .dropIn
  else none

/-! ### A function's statements, as a tree -/

/-- A statement of a body with its blocks closed: a simple statement (its
    words), a `ret` that ends its list (`retnx`: the translator's), a
    `drop` with the body's lines after it (`after`: what its check reads),
    and the blocks of the subset. -/
inductive Item where
  | st (ws : List W)
  | retnx (ws : List W)
  | dropAt (ws : List W) (after : List (List W))
  | scope (b : List Item)
  | ite (c : W) (a b : List Item)
  | loop (cond : List Item) (c : W) (body : List Item)
  | each (x xs : W) (body : List Item)
  | mat (c a1 : W) (b1 : List Item) (a2 : W) (b2 : List Item)

/-- How a list of statements ended. -/
inductive Close where
  | eof
  | fin
  | els
  | lc (c : W)
  | arm (a : W)

/-- The statements up to the closer of their block, read into a tree, and
    the lines after it. A closer out of place, a block not closed, or an
    opener outside the subset (`defer`) is `none`. A `foreach x v` (step 5)
    is a block up to its `end`. A `match v` (step 7) is its arms, each `arm
    a` and the statements up to the next `arm` or the match's `end`: two of
    them (stricter: the translator takes more arms where their names repeat,
    the last block of a name; it refuses any other count of names). -/
def parseB : Nat → List (List W) → List Item → Option (List Item × Close × List (List W))
  | 0, _, _ => none
  | _ + 1, [], acc => some (acc.reverse, .eof, [])
  | f + 1, l :: ls, acc =>
    match l with
    | kEnd :: _ => some (acc.reverse, .fin, ls)
    | kElse :: _ => some (acc.reverse, .els, ls)
    | kLoopcond :: c :: _ => some (acc.reverse, .lc c, ls)
    | kArm :: a :: _ => some (acc.reverse, .arm a, ls)
    | kDrop :: _ => parseB f ls (.dropAt l ls :: acc)
    | kScope :: _ =>
      match parseB f ls [] with
      | some (b, .fin, ls') => parseB f ls' (.scope b :: acc)
      | _ => none
    | kIf :: c :: _ =>
      match parseB f ls [] with
      | some (a, .fin, ls') => parseB f ls' (.ite c a [] :: acc)
      | some (a, .els, ls') =>
        match parseB f ls' [] with
        | some (b, .fin, ls'') => parseB f ls'' (.ite c a b :: acc)
        | _ => none
      | _ => none
    | kLoop :: _ =>
      match parseB f ls [] with
      | some (cnd, .lc c, ls') =>
        match parseB f ls' [] with
        | some (b, .fin, ls'') => parseB f ls'' (.loop cnd c b :: acc)
        | _ => none
      | _ => none
    | kForeach :: x :: xs :: _ =>
      match parseB f ls [] with
      | some (b, .fin, ls') => parseB f ls' (.each x xs b :: acc)
      | _ => none
    | kMatch :: c :: _ =>
      match ls with
      | (kArm :: a1 :: _) :: ls1 =>
        match parseB f ls1 [] with
        | some (b1, .arm a2, ls2) =>
          match parseB f ls2 [] with
          | some (b2, .fin, ls3) => parseB f ls3 (.mat c a1 b1 a2 b2 :: acc)
          | _ => none
        | _ => none
      | _ => none
    | w :: _ =>
      if w == kMatch || w == kForeach || w == kDefer || w == kArm ||
         w == kLoopcond || w == kIf then none
      else parseB f ls (.st l :: acc)
    | [] => none

/-- A `line` or a `drop`. -/
def isLD : Item → Bool
  | .st (kLine :: _) => true
  | .dropAt _ _ => true
  | _ => false

/-- A list whose last statement but `line`s and `drop`s is a `ret`: the
    statements before it, then the `ret` as the list's end (`retnx`; the
    `line`s and `drop`s after it are dropped, as the translator drops them). -/
def retSplit (items : List Item) : Option (List Item) :=
  match items.reverse.dropWhile isLD with
  | .st (kRet :: ws) :: before => some (before.reverse ++ [.retnx (kRet :: ws)])
  | _ => none

/-- `let x r` followed (past `line`s and `drop`s) by `ret vx`: the
    statements after the `ret`. -/
def retAt (h1 : W) : List Item → Option (List Item)
  | .st [kRet, w] :: r => if wordOf w == 118 :: wordOf h1 then some r else none  -- 'v'
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

/-- The temporaries not yet bound, set aside while a statement runs: it
    starts with none (`M.wrapLits` gives them back). -/
def M.saveLits : M (List Nat) := fun s => some (s.lits, { s with lits := [] })

/-- The temporaries the statement made (all there are, since `M.saveLits`),
    each `(.letv q (.expr .any) …)` around `st` (the first made outermost),
    and the ones set aside back. (Not a count and a `take`/`drop` of one
    list: the kernel keeps a state's fields as terms, so each `drop` was
    one more step every later read of the list took again, quadratic in a
    function's statements; 65 000 steps of `List.drop` for
    `joins_each_freeing_a_different_vec`.) -/
def M.wrapLits (saved : List Nat) (st : Stmt) : M Stmt := fun s =>
  some (s.lits.foldl (fun acc q => .letv q (.expr .any) acc) st, { s with lits := saved })

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
def lineIds (l : List W) : List Nat :=
  l.foldr (fun w acc => (slashPieces (wordOf w) []).filterMap vIdOf ++ acc) []

/-- A drop's check (`go`) reads the variables up to `maskB` as bits of one
    number: bit `i` of `maskAfter ls` is 1 exactly when a line of `ls` names
    `i` (`lineIds`), so the lines after a drop name a variable of its set
    exactly when the two numbers share a bit, when every variable of the set
    is up to `maskB` (a line's larger ones are none of them); otherwise the
    check reads the lines. The kernel computes `|||`, `&&&` and `2 ^ i` as
    numbers, at once, and keeps `maskAfter` of each suffix of a body: one
    pass for every drop of a function, not one a drop (on
    `joins_each_freeing_a_different_vec`, 44 drops in 470 lines: 2.26 →
    1.83 s of kernel for the whole Elab.lean part). -/
def maskB : Nat := 4096

def idBit (i : Nat) : Nat := if i ≤ maskB then 2 ^ i else 0

/-- A line's variables up to `maskB`, as bits. -/
def lineMask (l : List W) : Nat := (lineIds l).foldl (fun m i => m ||| idBit i) 0

/-- The variables up to `maskB` the lines name, as bits. -/
def maskAfter : List (List W) → Nat
  | [] => 0
  | l :: ls => lineMask l ||| maskAfter ls

example : maskAfter (strs [["eval", "scalar", "2", "v3/a", "v5"], ["line", "x/v4000/v5000"]]) =
    2 ^ 3 ||| 2 ^ 5 ||| 2 ^ 4000 := by decide +kernel

/-- The root of a place (`v3/a`: `v3`) as a variable. -/
def rootId (w : List Nat) : Option Nat := vIdOf (w.takeWhile (· != 47))

/-- One pass of `__view_vars`: raw text that holds a view, not its own text.
    A `let j call string_data …` or `let j call vec_at__str …` adds `j`; so
    does a `let j use vK` of such a `k`. (The translator adds `j` too for a
    call whose summary says its result is lent, `__borrowed`; the subset
    has no other such call, `letCallOk`: `string_data` is one.) -/
def viewVarStep (body : List (List W)) (out : List Nat) : List Nat :=
  body.foldl (fun acc l => match l with
    | kLet :: j :: kCall :: f :: _ =>
      match idOf j with
      | some jj =>
        let fb := wordOf f
        if !acc.contains jj && (fb == stringDataB || fb == vecAtStrB) then jj :: acc else acc
      | none => acc
    | kLet :: j :: kUse :: op :: _ =>
      match idOf j, varOf op with
      | some jj, some q => if !acc.contains jj && acc.contains q then jj :: acc else acc
      | _, _ => acc
    | _ => acc) out

/-- `__view_vars`: passes until one adds nothing. -/
def viewVars (body : List (List W)) : Nat → List Nat → List Nat
  | 0, out => out
  | n + 1, out =>
    let o' := viewVarStep body out
    if o'.length == out.length then out else viewVars body n o'

/-- Variable `k`'s last `v` line: the first from the end (the reversed list
    is one term for every lookup in a function, read once). -/
def lastVar (vs : List (Nat × Nat × Nat × W)) (k : Nat) : Option (Nat × Nat × Nat × W) :=
  vs.reverse.find? (·.1 == k)

/-- The lines of the body that may add a variable to `__views_of`'s set,
    in order, each as the variable it adds and the variables its words name
    by their roots (from the fourth word on): a `let j call f …` whose `f`
    hands back a view of what it is handed (`viewCallB`), or a `let j use …`
    of a temporary `j` that is raw text holding a view (`views`,
    `__view_vars`). (The translator adds a call whose summary says it lends
    its result too, `__borrowed`; the subset has no other, `letCallOk`.)
    Read once per function: every `drop` of it runs the passes below over
    these lines only. -/
def viewEdges (body : List (List W)) (vs : List (Nat × Nat × Nat × W)) (views : List Nat) :
    List (Nat × List Nat) :=
  let roots (ws : List W) : List Nat := ws.filterMap fun w => rootId (wordOf w)
  body.filterMap fun l => match l with
    | kLet :: j :: kCall :: f :: more =>
      match idOf j with
      | some jj => if viewCallB.any (prefixN · (wordOf f)) then some (jj, roots (f :: more)) else none
      | none => none
    | kLet :: j :: kUse :: more =>
      match idOf j with
      | some jj =>
        -- (`views` first: it is short, mostly empty)
        if views.contains jj && (lastVar vs jj).map (·.2.1) == some 2 then some (jj, roots more) else none
      | none => none
    | _ => none

/-- One pass of `__views_of` over the lines: one not yet in the set that
    names a variable of it adds its own. -/
def viewsStep (es : List (Nat × List Nat)) (out : List Nat) : List Nat :=
  es.foldl (fun acc e => if !acc.contains e.1 && e.2.any acc.contains then e.1 :: acc else acc) out

/-- `out` and every variable that may view one of it (`__views_of`): passes
    until one adds nothing (each adds one at least, of the lines' variables,
    so `es.length + 1` passes suffice). -/
def viewsOf (es : List (Nat × List Nat)) : Nat → List Nat → List Nat
  | 0, out => out
  | n + 1, out =>
    let o' := viewsStep es out
    if o'.length == out.length then out else viewsOf es n o'

/-- The elements a `foreach` lends (`foreach x v`: `x`), in the whole body.
    The translator changes such an element in place without a borrow of it
    (`__edit_through`); the subset refuses that change instead (`intrS`). -/
def eachIds (body : List (List W)) : List Nat :=
  body.filterMap fun l => match l with
    | kForeach :: x :: _ => idOf x
    | _ => none

/-- What every statement of the function reads: its parameter count, its
    `v` lines (id, kind, flags, type), the program's functions, its
    summary, the body, its raw text that holds a view (`viewVars`), the elements
    its `foreach`es lend (`eachIds`) and the lines that may add a view
    (`viewEdges`); the program's closure types (`cl`), the result slot
    (`rslot`), a closure's code's numbering of its variables (`vmap`,
    step 6), and the IR's top-level lines (the callees' summaries). -/
structure Ctx where
  np : Nat
  vars : List (Nat × Nat × Nat × W)
  prog : List CoreFn
  sum : Summary
  body : List (List W)
  views : List Nat
  elems : List Nat
  edges : List (Nat × List Nat)
  cl : CloTab
  rslot : Nat
  vmap : Option (List (Nat × Nat))
  tops : List (List W)

/-- Variable `k`'s type, or `d` where it has no `v` line (`__vtyd`). -/
def tyD (vs : List (Nat × Nat × Nat × W)) (k : Nat) (d : W) : W :=
  match lastVar vs k with
  | some (_, _, _, t) => t
  | none => d

/-- The value of `k` in a list of pairs (its first). -/
def lookupN (m : List (Nat × Nat)) (k : Nat) : Option Nat :=
  match m with
  | [] => none
  | p :: ps => if p.1 == k then some p.2 else lookupN ps k

/-- A2's numbering (`__var`): the parameters, then the result slot (`np`),
    then the rest; in a closure's code, its own (`vmap`). (`fnElab` checks
    that a closure's code names no variable it does not declare, where the
    translator stops: so the 0 is never taken.) -/
def Ctx.var (c : Ctx) (k : Nat) : Nat :=
  match c.vmap with
  | none => if k < c.np then k else k + 1
  | some m => (lookupN m k).getD 0

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

/-- Variable `k`'s type as A2's (`__lean_ty` of its `v` line's; none
    without one). -/
def Ctx.ty (c : Ctx) (k : Nat) : Option Ty :=
  match lastVar c.vars k with
  | some (_, _, _, t) => tyOf c.cl t
  | none => none

/-- Variable `k`'s A2 type where it is read (`__vlean`): raw text that
    holds a view (`views`) is a slice. -/
def vlOf (cl : CloTab) (vs : List (Nat × Nat × Nat × W)) (views : List Nat) (k : Nat) : Option Ty :=
  match lastVar vs k with
  | some (_, _, _, t) => if t == kI8p && views.contains k then some (.slice .int) else tyOf cl t
  | none => none

def Ctx.vl (c : Ctx) (k : Nat) : Option Ty := vlOf c.cl c.vars c.views k

/-- Is variable `k` a number (`__int_ty` of its type, `i64` without a `v`
    line)? -/
def Ctx.int (c : Ctx) (k : Nat) : Bool := intTy (tyD c.vars k kI64)

/-- Is variable `k` declared, of a type of the subset, and no number by its
    IR type (a buffer, a `Vec` of views, a slice, a closure; step 7: a
    struct or an option)? The translator moves it where it is used
    (`__is_int` reads the IR type: a struct of one number field, A2's
    `.int`, moves too). -/
def Ctx.obj (c : Ctx) (k : Nat) : Bool := (c.ty k).isSome && !c.int k

/-- An operand (`__operand`): an untracked number (`c`) is any number. -/
def operandE (c : Ctx) (w : W) : Option Expr :=
  if w == kC then some .any
  else (vref w).map fun k => .var (c.var k)

/-! #### Fields (step 7) -/

/-- A place `v<k>/<f>` (`__field_temp`): the variable and the field's name,
    as bytes, cut at the first `/`. A nested path (a second `/`) is none, as
    the translator refuses it; so is a root that is not `v` and digits
    (stricter: the translator reads `int()` of what follows its first
    character). -/
def fieldRef (w : W) : Option (Nat × List Nat) :=
  let cs := wordOf w
  let b := cs.takeWhile (· != 47)
  let fb := cs.drop (b.length + 1)
  if b.length == cs.length || fb.contains 47 then none
  else match b with
    | 118 :: ds@(_ :: _) => match digitsN ds 0 with
      | some k => if k ≤ idMax then some (k, fb) else none
      | none => none
    | _ => none

/-- A place's root, the field's index, the number of its struct's fields,
    the struct's A2 type and the field's IR type. The
    root's type a struct's of the subset (`structNameB`; stricter: the
    translator reads the fields of any type with a `ty` line, a `Vec`'s
    handle included), the field one of its names (stricter for a struct of
    one field, which the translator reads without its name). -/
def fieldAt (c : CloTab) (vs : List (Nat × Nat × Nat × W)) (w : W) :
    Option (Nat × Nat × Nat × Ty × W) := do
  let (b, fb) ← fieldRef w
  let bt ← (lastVar vs b).map (·.2.2.2)
  if !structNameB (wordOf bt) then none
  let fs ← fieldsOf c.tyls bt
  let i ← indexOf (fs.map (·.1)) (encB fb)
  let t ← tyOf c bt
  let ft ← nth? fs i
  pure (b, i, fs.length, t, ft.2)

/-- A place of a String (`v0/ctl`, its handle: the IR's `ty %String` line
    has one field) is refused; the same place of a struct of one number
    field is read. -/
example : fieldAt ⟨0, [], strs [["ty", "%String", "1", "0-----", "String", "A", "0", "F", "1", "ctl", "i8*", "V", "0"]]⟩
      [(0, 0, 0, enc "%String")] (enc "v0/ctl") = none ∧
    (fieldAt ⟨0, [], strs [["ty", "%S", "1", "0-----", "S", "A", "0", "F", "1", "ctl", "i64", "V", "0"]]⟩
      [(0, 0, 0, enc "%S")] (enc "v0/ctl")).isSome = true := by decide +kernel

/-- Field `i` of a struct of `n` fields, of A2 type `t` (its fields nested
    in pairs to the right): its own A2 type (`__flean`: `__lean_ty` of the
    field's type, the same type `_struct_ty` put in the pairs). -/
def fieldTy : Ty → Nat → Nat → Option Ty
  | t, 0, 1 => some t
  | .prod a _, 0, _ + 2 => some a
  | .prod _ b, i + 1, n + 1 => fieldTy b i n
  | _, _, _ => none

/-- `__field_temp`'s `.snd` steps: `q` of them from `cur`, each a fresh
    variable. -/
def sndChain : Nat → Nat → M (List (Nat × Rhs) × Nat)
  | 0, cur => pure ([], cur)
  | q + 1, cur => do
    let x ← M.fresh
    let (pre, y) ← sndChain q x
    pure ((x, .snd cur) :: pre, y)

/-- A field read into a temporary through the pairs (`__field_temp`): the
    bindings it needs (each fresh), and the variable holding the field (a
    struct of one field is its field: its variable). -/
def fieldTemp (c : Ctx) (w : W) : M (List (Nat × Rhs) × Nat) := do
  let (b, i, n, _, _) ← M.lift (fieldAt c.cl c.vars w)
  if n == 1 then pure ([], c.var b)
  else do
    let (pre, cur) ← sndChain i (c.var b)
    if i + 1 < n then do
      let x ← M.fresh
      pure (pre ++ [(x, .fst cur)], x)
    else pure (pre, cur)

/-- Does a word hold a `/` (a place with a field, `__has op "/"`)? -/
def hasSlash (w : W) : Bool := (wordOf w).contains 47

/-- An operand where a field may be read (`__operand` with `has_pre`): a
    field's value is read into a temporary first (`pre`). -/
def operandP (c : Ctx) (w : W) : M (List (Nat × Rhs) × Expr) :=
  if w == kC then pure ([], .any)
  else if hasSlash w then do
    let (pre, x) ← fieldTemp c w
    pure (pre, .var x)
  else M.lift ((vref w).map fun k => ([], .var (c.var k)))

/-- The operands of a `scalar`, each where a field may be read, in order. -/
def operandsP (c : Ctx) : List W → M (List (Nat × Rhs) × List Expr)
  | [] => pure ([], [])
  | w :: ws => do
    let (p, e) ← operandP c w
    let (ps, es) ← operandsP c ws
    pure (p ++ ps, e :: es)

/-- `.letv` of each binding of `pre` around `st`, the first outermost
    (`__wrap`). -/
def wrapPre (pre : List (Nat × Rhs)) (st : Stmt) : Stmt :=
  pre.foldr (fun b acc => .letv b.1 b.2 acc) st

/-- An argument the call takes (`__argvar`): an untracked number is a
    temporary of its own; else a whole variable. -/
def argvarS (c : Ctx) (op : W) : M Nat :=
  if op == kC then M.litTemp else M.lift ((vref op).map c.var)

/-- The pairs around the values `vs` (all but the last, newest first) and
    `acc` (the last): each a fresh variable (`__closure_lit`; a struct
    literal's, `__rhs`, all but its outermost pair). -/
def pairUp : List Nat → Nat → M (List (Nat × Rhs) × Nat)
  | [], acc => pure ([], acc)
  | v :: vs, acc => do
    let tt ← M.fresh
    let (pre, y) ← pairUp vs tt
    pure ((tt, .pair v acc) :: pre, y)

/-- An rvalue of the subset as A2's right-hand side (`__rhs`), bound to
    `dest` (`none`: no variable), with the bindings it needs made first
    (`pre`). `asg`: the store of an `assign`. A buffer or a view moves
    (`.var`), or is borrowed by a cursor (`: ~` of a binding or a
    parameter, `.borrow`); raw text bound from a literal is a copy of its
    own (`.new .int`); a borrowed `Vec` parameter assigned to an `inout`
    one is copied (its length read, then `.new` of its element type).
    Step 7: a number field's value is read through the pairs (`fieldTemp`);
    a struct's literal is its operands nested in pairs (the inner ones bound
    first), one of one field its operand's value; an option's literal is
    `.inl` of a temporary (`F`) or `.inr` of its payload (`T`), into a
    variable of an option type; `payload v T 0` is `.getr`. Refused as the
    translator refuses them: an owner given a borrowed parameter's value,
    raw text assigned from another binding, a field that is no number moved
    or copied, a literal given no variable, a struct's literal of no
    operand. -/
def rhsS (c : Ctx) (ws : List W) (dest : Option Nat) (asg : Bool) :
    M (List (Nat × Rhs) × Rhs) :=
  match ws with
  | kNone :: _ =>
    match dest with
    | some d =>
      -- (only a number's slot, `__lean_ty`: a struct of one number field too)
      if intTy (tyD c.vars d kI64) || c.ty d == some .int then pure ([], .expr .any) else M.fail
    | none => pure ([], .expr .any)
  | kUse :: w :: _ =>
    if w == kC then
      match dest with
      | some d =>
        -- a literal into raw text: its own copy of the text
        if (lastVar c.vars d).map (·.2.2.2) == some kI8p then pure ([], .new .int)
        else pure ([], .expr .any)
      | none => pure ([], .expr .any)
    else if hasSlash w then
      -- (step 7) a field's value: a number, read through the pairs; a
      -- field that owns would move out of its struct, which A2 does only
      -- by `unpair` (the translator refuses it)
      match fieldAt c.cl c.vars w with
      | some (_, _, _, _, ft) => if intTy ft then do
          let (pre, x) ← fieldTemp c w
          pure (pre, .expr (.var x))
        else M.fail
      | none => M.fail
    else match vref w with
      | none => M.fail
      | some y =>
        if c.int y then pure ([], .expr (.var (c.var y)))
        else if !c.obj y then M.fail
        else
          let ky := c.kind y
          let fy := c.flags y
          let kd := dest.bind c.kind
          let fd := match dest with
            | some d => c.flags d
            | none => 0
          let ys := tyD c.vars y kEmpty == kI8p
          let fy6 := !bitB fy 1 && !bitB fy 2
          if !asg && dest.isSome && kd == some 1 && bitB fd 0 && (ky == some 0 || ky == some 1) then
            pure ([], .borrow (c.var y))
          else if asg && ky == some 0 && fy6 && !ys && kd != some 0 then M.fail
          else if asg && ky == some 0 && fy6 && kd == some 0 && bitB fd 1 && !ys &&
              (match dest with
               | some d => (lastVar c.vars d).isSome && tyD c.vars y kEmpty == tyD c.vars d kEmpty
               | none => false) then
            -- (the parameter's type a Vec's: `.new` of its element type; a
            -- slice is not copied, `a copy of a … parameter`)
            match c.ty y with
            | some (.vec el) => do
              let x ← M.fresh
              pure ([(x, .expr (.len (c.var y)))], .new el)
            | _ => M.fail
          else if asg && ys then M.fail
          else pure ([], .var (c.var y))
  | kScalar :: n :: ops =>
    if natOf n != some ops.length then M.fail
    else do
      -- (step 7: an operand may be a field, read into a temporary first)
      let (pre, es) ← operandsP c ops
      match es with
      | [] => pure (pre, .expr .any)
      | _ => pure (pre, .expr (.add .any (.lt (es.foldl .add (.lit 0)) (.lit 0))))
  | kAgg :: w1 :: rest =>
    -- (step 7) a literal, given a variable: an option's (`T`/`F`, of a
    -- variable of an option type) or a struct's (`-`)
    match dest with
    | none => M.fail
    | some d =>
      if w1 == kT || w1 == kF then
        match c.ty d with
        | some (.sum .int pay) =>
          if w1 == kF then do
            let lt ← M.litTemp
            pure ([], .inl lt pay)
          else match rest with
            | _ :: op :: _ =>
              if op == kC then do
                let lt ← M.litTemp
                pure ([], .inr .int lt)
              else match vref op with
                | some y => pure ([], .inr .int (c.var y))
                | none => M.fail
            | _ => M.fail
        | _ => M.fail
      else if w1 == kDash then
        match rest with
        | n :: ops =>
          match natOf n with
          | some 1 =>
            -- a struct of one field is its field's value (the translator
            -- reads the variable's type first, `__vty`: it has a `v` line)
            match ops with
            | op :: _ => if (lastVar c.vars d).isNone then M.fail else
              if op == kC then pure ([], .expr .any)
              else match vref op with
                | some y => if c.int y then pure ([], .expr (.var (c.var y))) else pure ([], .var (c.var y))
                | none => M.fail
            | [] => M.fail
          | some k => if k < 2 then M.fail else do
            -- its fields nested in pairs to the right (`opsOk`: at least
            -- `k` operand words; the type's words follow them)
            let vs ← (ops.take k).mapM (argvarS c)
            match vs, vs.reverse with
            | v0 :: _, last :: init => do
              let (pre, acc) ← pairUp init.dropLast last
              pure (pre, .pair v0 acc)
            | _, _ => M.fail
          | none => M.fail
        | [] => M.fail
      else M.fail
  | kPayload :: w :: kT :: z :: _ =>
    -- (step 7) an option's payload where its `T` arm matched, lent
    if z == kZero then M.lift ((vref w).map fun y => ([], .getr (c.var y))) else M.fail
  | _ => M.fail

/-- A call's arguments (`__call`): an untracked number is a temporary of
    its own, bound around the call; one handed to a raw-string parameter
    is text, a buffer of the call's own (AGORA-994: `true`). -/
def argsS (c : Ctx) (callee : CoreFn) : Nat → List W → M (List (Nat × Bool))
  | _, [] => pure []
  | j, op :: ops => do
    let a ← (if op == kC then
               (if tyD callee.vars j kEmpty == kI8p then do
                  let x ← M.fresh
                  pure (x, true)
                else do
                  let x ← M.litTemp
                  pure (x, false))
             else M.lift ((vref op).map fun k => (c.var k, false)))
    let as ← argsS c callee (j + 1) ops
    pure (a :: as)

/-- Each element with its index, from `n`. -/
def idxFrom {α : Type} : Nat → List α → List (Nat × α)
  | _, [] => []
  | n, a :: as => (n, a) :: idxFrom (n + 1) as

/-- Variable `k`'s flags as its `v` line has them (0 without one). -/
def baseFlags (vs : List (Nat × Nat × Nat × W)) (k : Nat) : Nat :=
  match lastVar vs k with
  | some (_, _, fl, _) => fl
  | none => 0

/-- Does the closure value `op` go to a `sink` or `inout` parameter `j` of
    `callee` (`__call`; the callee's flags as `__vflags` reads them)? nurlc
    copies a closure it hands to one (`nurl_closure_clone`), which the core
    IR does not show: the translator refuses it (step 6). -/
def cloToSink (c : Ctx) (callee : CoreFn) (j : Nat) (op : W) : Bool :=
  match vref op with
  | some k =>
    (match c.ty k with | some (.fn _ _) => true | _ => false) &&
    (let fl := baseFlags callee.vars j
     bitB fl 1 || bitB fl 2 || (decide (j < callee.np) && sinkP (sumOf c.tops callee.name) j))
  | none => false

/-- `call f n args…` of a function of the program: its index, and the
    arguments. -/
def callS (c : Ctx) : List W → M (Nat × List (Nat × Bool))
  | fname :: n :: args => do
    if natOf n != some args.length then M.fail
    if intrinsicName fname then M.fail
    let fi ← M.lift (indexOf (c.prog.map (·.name)) fname)
    let callee ← M.lift (nth? c.prog fi)
    if (idxFrom 0 args).any fun e => cloToSink c callee e.1 e.2 then M.fail
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

/-- A whole variable (`__pvar`; an argument the call reads may also be a
    field, `rdF`). -/
def rdS (c : Ctx) (op : W) : M Nat := M.lift ((vref op).map c.var)

/-- An argument the call reads (`__rd`): a field (`v3/name`) read through
    the pairs into a temporary (its bindings, `fpre`, bound around the
    call's construct: `__intrinsic`), or a whole variable. -/
def rdF (c : Ctx) (op : W) : M (List (Nat × Rhs) × Nat) :=
  if hasSlash op then fieldTemp c op else do
    let y ← rdS c op
    pure ([], y)

/-- An argument's A2 type where it is read (`__rd_ty`): a field's (`__flean`)
    or the variable's (`__vlean`). -/
def rdTy (c : Ctx) (op : W) : Option Ty :=
  if hasSlash op then (fieldAt c.cl c.vars op).bind fun r => fieldTy r.2.2.2.1 r.2.1 r.2.2.1
  else (vref op).bind c.vl

/-- A read of raw text (`__read`): the argument read (`rdF`), then a view's
    length (`.slen`) or an owner's (`.len`). -/
def readP (c : Ctx) (op : W) : M (List (Nat × Rhs) × Expr) := do
  let (fp, y) ← rdF c op
  match rdTy c op with
  | some (.slice _) => pure (fp, .slen y)
  | some (.vec _) => pure (fp, .len y)
  | _ => M.fail

/-- A read of an argument before `st`, into a fresh variable (the reads of
    `nurl_str_cat` and `string_from`); none for an untracked number. -/
def readWrap (c : Ctx) (op : W) (st : Stmt) : M (List (Nat × Rhs) × Stmt) :=
  if op == kC then pure ([], st)
  else do
    let tt ← M.fresh
    let (fp, e) ← readP c op
    pure (fp, .letv tt (.expr e) st)

/-- A change of the elements of the buffer `y` (the A2 variable the
    argument `op` is read into, `rdF`) through a borrow of it
    (`__edit_through`): `(.letv b (.borrow y) (.edit true b e))`. The
    translator changes a `foreach`'s element through itself (`elems`); the
    subset refuses a change of one instead (a field is none: its temporary
    is fresh). -/
def editS (c : Ctx) (op : W) (y : Nat) (e : Edit) : M Stmt :=
  if (match vref op with | some k => c.elems.contains k | none => false) then M.fail
  else do
    let b ← M.fresh
    pure (.letv b (.borrow y) (.edit true b e))

/-- A library call of the subset as A2's construct (`__intrinsic_`), into
    `x0` (`none`: no variable), then `rest`: `vec_new` (`.new`), `vec_push`
    (`.push`), `vec_len` and `string_len` (`.len`), `vec_free` and
    `string_free` (`.free`), and of raw text `nurl_str_cat` and
    `string_from` (a fresh buffer, each argument's read first),
    `nurl_str_len` (its read), `vec_at` (`.at`). Step 5: `string_data` and
    `slice_from_vec` (a view, `.view`), `slice_len` (`.slen`),
    `nurl_println` (its read), and the changes through a borrow:
    `vec_clear` and `vec_truncate` (`.edit … (.trunc i)`), `vec_reserve` and
    `vec_shrink_to_fit` (a push that may move the buffer and a cut back to
    its length), `string_push_str` (a push, then the read of the text). The
    element of a `Vec` is a number, or raw text held in it (`str`, a view:
    a raw string pushed into it is viewed, `.view`). Any other library call
    is outside the subset; so are the forms the translator lowers by
    falling through to a call (`let x` of a `vec_push`). An argument it
    reads may be a field (step 7, `rdF`): the field's bindings (`fpre`) are
    bound around the whole construct (`__intrinsic`), outside the ones of an
    index or a length operand (`pre`, `operandP`). -/
def intrP (c : Ctx) (f : W) (ops : List W) (x0 : Option Nat) (rest : Stmt) :
    M (List (Nat × Rhs) × Stmt) :=
  let fb := wordOf f
  if prefixN vecNewB fb then
    match ops, elemTy (fb.drop 9) with
    | [], some el => do
        let x ← xfS x0
        pure ([], .letv x (.new el) rest)
    | _, _ => M.fail
  else if prefixN vecPushB fb then
    match ops, x0 with
    | [o0, o1], none => do
      let v ← argvarS c o0
      let y ← argvarS c o1
      match elemTy (fb.drop 10) with
      | some .int => pure ([], seqS (.push v y) rest)
      | some _ =>
        -- raw text pushed where it is held in a value: the Vec keeps a
        -- view of it (owned text is viewed first); no literal
        if o1 == kC then M.fail
        else match (vref o1).bind c.vl with
          | some (.vec .int) => do
            let tt ← M.fresh
            pure ([], .letv tt (.view y) (seqS (.push v tt) rest))
          | some _ => pure ([], seqS (.push v y) rest)
          | none => M.fail
      | none => M.fail
    | _, _ => M.fail
  else if prefixN vecLenB fb || fb == stringLenB then
    match ops with
    | [o0] => if o0 == kC then M.fail else do
        let x ← xfS x0
        let (fp, y) ← rdF c o0
        pure (fp, .letv x (.expr (.len y)) rest)
    | _ => M.fail
  else if prefixN vecFreeB fb || fb == stringFreeB then
    match ops, x0 with
    | [o0], none => if o0 == kC then M.fail else do
        let y ← rdS c o0
        pure ([], seqS (.free y) rest)
    | _, _ => M.fail
  else if fb == strCatB then
    match ops with
    | [o0, o1] => do
      let x ← xfS x0
      let (p0, st) ← readWrap c o0 (.letv x (.new .int) rest)
      let (p1, st') ← readWrap c o1 st
      pure (p0 ++ p1, st')
    | _ => M.fail
  else if fb == stringFromB then
    match ops with
    | [o0] => do
      let x ← xfS x0
      readWrap c o0 (.letv x (.new .int) rest)
    | _ => M.fail
  else if fb == strLenB then
    match ops with
    | [o0] => if o0 == kC then M.fail else do
        let x ← xfS x0
        let (fp, e) ← readP c o0
        pure (fp, .letv x (.expr e) rest)
    | _ => M.fail
  else if prefixN vecAtB fb then
    -- a bounds-checked read of an element, lent (`.at`)
    match ops with
    | [o0, o1] => if o0 == kC || (elemTy (fb.drop 8)).isNone then M.fail else do
        let (pre, i) ← operandP c o1
        match x0 with
        | none => do
          let tt ← M.fresh
          let (fp, y) ← rdF c o0
          pure (fp, wrapPre pre (seqS (.letv tt (.at y i) .skip) rest))
        | some x => do
          let (fp, y) ← rdF c o0
          pure (fp, wrapPre pre (.letv x (.at y i) rest))
    | _ => M.fail
  else if fb == stringDataB || prefixN sliceFromVecB fb then
    -- a view of the text or of the Vec's elements (`.view`); a slice of a
    -- Vec of numbers only (the translator also slices a Vec of buffers)
    match ops with
    | [o0] =>
      if o0 == kC || (fb != stringDataB && !intTyB (fb.drop 16)) then M.fail else do
        let x ← xfS x0
        let (fp, y) ← rdF c o0
        pure (fp, .letv x (.view y) rest)
    | _ => M.fail
  else if prefixN sliceLenB fb then
    match ops with
    | [o0] => if o0 == kC then M.fail else do
        let x ← xfS x0
        let (fp, y) ← rdF c o0
        pure (fp, .letv x (.expr (.slen y)) rest)
    | _ => M.fail
  else if fb == printlnB then
    -- it reads its argument (a literal: nothing): a view's length, an
    -- owner's, anything else's value
    match ops, x0 with
    | [o0], none => if o0 == kC then pure ([], rest) else do
        let (fp, y) ← rdF c o0
        let e ← (match rdTy c o0 with
          | some (.slice _) => pure (Expr.slen y)
          | some (.vec _) => pure (.len y)
          | some _ => pure (.var y)
          | none => M.fail)
        let tt ← M.fresh
        pure (fp, .letv tt (.expr e) rest)
    | _, _ => M.fail
  else if prefixN vecClearB fb || prefixN vecTruncB fb then
    -- the Vec changed through a borrow: its elements past the new length
    -- dropped; a `let x` of it is any number
    let clear := prefixN vecClearB fb
    match (if clear then (match ops with | [o0] => some (o0, none) | _ => none)
           else (match ops with | [o0, o1] => some (o0, some o1) | _ => none)) with
    | some (o0, o1) => if o0 == kC then M.fail else do
        let (pre, i) ← (match o1 with
          | none => pure ([], .lit 0)
          | some w => operandP c w)
        let (fp, y) ← rdF c o0
        let st ← editS c o0 y (.trunc i)
        let rs := match x0 with
          | none => rest
          | some x => .letv x (.expr .any) rest
        pure (fp, wrapPre pre (seqS st rs))
    | none => M.fail
  else if prefixN vecReserveB fb || prefixN vecShrinkB fb then
    -- the buffer may move, its length unchanged: a push and a cut back to
    -- the length it had, through a borrow; of a Vec of numbers
    let res := prefixN vecReserveB fb
    match x0, (if res then (match ops with | [o0, o1] => some (o0, some o1) | _ => none)
               else (match ops with | [o0] => some (o0, none) | _ => none)) with
    | none, some (o0, o1) =>
      if o0 == kC || !intTyB (if res then fb.drop 13 else fb.drop 19) then M.fail else do
        let pre ← (match o1 with
          | some w => do
            let (p, _) ← operandP c w
            pure p
          | none => pure [])
        let b ← M.fresh
        let cc ← M.litTemp
        let k ← M.fresh
        let (fp, y) ← rdF c o0
        pure (fp, wrapPre pre (seqS (.letv b (.borrow y) (.letv k (.expr (.len b))
          (.seq (.edit true b (.push cc)) (.edit true b (.trunc (.var k)))))) rest))
    | _, _ => M.fail
  else if fb == stringPushStrB then
    -- the String grows through a borrow, then the text's bytes are read
    match ops, x0 with
    | [o0, o1], none => if o0 == kC then M.fail else do
        let cc ← M.litTemp
        let (fp0, y0) ← rdF c o0
        let st ← editS c o0 y0 (.push cc)
        if o1 == kC then pure (fp0, seqS st rest)
        else do
          let (fp1, e) ← readP c o1
          let tt ← M.fresh
          pure (fp0 ++ fp1, seqS (.seq st (.letv tt (.expr e) .skip)) rest)
    | _, _ => M.fail
  else if fb == printlnIntB then
    -- (step 6) it reads a number: nothing of memory past the read (a
    -- literal: nothing); a `let x` of it is refused (stricter: the
    -- translator falls through to a call, which drops `x`)
    match ops, x0 with
    | [o0], none => if o0 == kC then pure ([], rest) else do
        let y ← M.fresh
        let e ← M.lift (operandE c o0)
        pure ([], .letv y (.expr e) rest)
    | _, _ => M.fail
  else M.fail

def intrS (c : Ctx) (f : W) (ops : List W) (x0 : Option Nat) (rest : Stmt) : M Stmt := do
  let (fp, st) ← intrP c f ops x0 rest
  pure (wrapPre fp st)

/-- A call (`__call`, `__intrinsic`): the library's, as its construct, or
    a function of the program's, into `x0` (`none`: a fresh variable). -/
def callAny (c : Ctx) (ws : List W) (x0 : Option Nat) (rest : Stmt) : M Stmt :=
  match ws with
  | fname :: n :: args =>
    if natOf n != some args.length then M.fail
    else if intrinsicName fname then intrS c fname args x0 rest
    else do
      let (fi, as) ← callS c ws
      let x ← xfS x0
      pure (letcallS x fi as rest)
  | _ => M.fail

/-! ### Closures (step 6) -/

/-- Variable `k`'s type as A2's (`__vty`, then `__lean_ty`). -/
def varTy (cl : CloTab) (vs : List (Nat × Nat × Nat × W)) (k : Nat) : Option Ty :=
  (lastVar vs k).bind fun v => tyOf cl v.2.2.2

/-- A capture's A2 type where the translator follows it (`__cap_ty`): a
    number, or a buffer of numbers; anything else stops the translation. -/
def capTy : Option Ty → Option Ty
  | some .int => some .int
  | some (.vec .int) => some (.vec .int)
  | _ => none

/-- The calls that change the buffer they are handed first (`__changes`):
    `vec_push__…`, `vec_clear__…`, `vec_truncate__…`, `vec_reserve__…`,
    `vec_shrink_to_fit__…`, `string_push_str…` (prefixes). -/
def changerB : List (List Nat) := [vecPushB, vecClearB, vecTruncB, vecReserveB, vecShrinkB, stringPushStrB]

/-- Does closure code `q`'s body change its capture `k` in place
    (`__changes`): a line whose first word `call` is followed by a changer
    and, past its count, the text `v<k>`? -/
def changesB (body : List (List W)) (k : Nat) : Bool :=
  body.any fun l => match l.dropWhile (· != kCall) with
    | kCall :: f :: _ :: a0 :: _ => changerB.any (prefixN · (wordOf f)) && vIdOf (wordOf a0) == some k
    | _ => false

/-- A capture by name's A2 mode in closure code `q` (`__cap_mode`): read
    only, or, taken by pointer (flag 8) or changed in place, `inout` at
    `drop`, of a buffer only. -/
def capModeOf (cl : CloTab) (q : CoreFn) (k : Nat) : Option PMode :=
  if !bitB (baseFlags q.vars k) 3 && !changesB q.body k then some .inp
  else match capTy (varTy cl q.vars k) with
    | some (.vec _) => some (.inout .drop)
    | _ => none

/-- Is capture `k` of closure code `q` one by name, unless every literal
    moves it in (`__named_cap`)? A buffer is, unless its environment owns it
    (`CORE_VF_ENVOWN`, flag 2048). -/
def namedCapOf (cl : CloTab) (q : CoreFn) (k : Nat) : Option Bool := do
  let t ← capTy (varTy cl q.vars k)
  pure ((match t with | .int => false | _ => true) && !bitB (baseFlags q.vars k) 11)

/-- The literals of closure code `code` among a body's lines, each with the
    lines after it. -/
def litsOf (code : W) : List (List W) → List (List W × List (List W))
  | [] => []
  | l :: ls => match l with
    | kLet :: _ :: kClosure :: f :: _ :: _ => if f == code then (l, ls) :: litsOf code ls else litsOf code ls
    | _ => litsOf code ls

/-- Does the literal `l` of function `p` (the lines after it `after`) move
    its capture `j` into the environment (`__moved_caps`)? It is a binding
    of `p`'s own (a local or a temporary) that `p` drops nowhere and names
    no more after the literal (a word's piece between its `/`s that is its
    text). -/
def movedAt (p : CoreFn) (l : List W) (after : List (List W)) (j : Nat) : Bool :=
  match l with
  | _ :: _ :: _ :: _ :: n :: ops =>
    match natOf n, nth? ops j with
    | some cnt, some op =>
      decide (j < cnt) &&
      match vref op with
      | some id =>
        let ob := wordOf op
        ((lastVar p.vars id).map (·.2.1) == some 1 || (lastVar p.vars id).map (·.2.1) == some 2) &&
        !(p.body.any fun d => match d with
          | kDrop :: w :: _ => wordOf w == ob.drop 1
          | _ => false) &&
        !(after.any fun d => d.any fun w => (slashPieces (wordOf w) []).contains ob)
      | none => false
    | _, _ => false
  | _ => false

/-- Does every literal of closure code `code`, in every function of the
    program, move its capture `j` into the environment (and is there one)? -/
def isMovedQ (prog : List CoreFn) (code : W) (j : Nat) : Bool :=
  let ls := prog.foldr (fun p acc => (litsOf code p.body).map (p, ·) ++ acc) []
  !ls.isEmpty && ls.all fun e => movedAt e.1 e.2.1 e.2.2 j

/-- A capture split by the literal (`__closure_lit`): its variable, by
    value (its A2 type), or by name (its mode and type where it is read). -/
def capSplit (c : Ctx) (q : CoreFn) : Nat → List (Nat × Nat) →
    Option (List (Nat × Ty) × List (Nat × PMode × Ty))
  | _, [] => some ([], [])
  | j, (y, k) :: r => do
    let nm ← namedCapOf c.cl q k
    let (vals, cs) ← capSplit c q (j + 1) r
    if nm && !isMovedQ c.prog q.name j then
      let md ← capModeOf c.cl q k
      let vl ← c.vl y
      pure (vals, (c.var y, md, vl) :: cs)
    else
      let ct ← capTy (c.ty y)
      pure ((c.var y, ct) :: vals, cs)

/-- The interface a closure value is of (`__fn_sigma`). -/
def sigmaOf : Option Ty → Option Nat
  | some (.fn [σ] .any) => some σ
  | _ => none

/-- `closure f n caps…` bound to `dest` (`__closure_lit`): the captures by
    value copied into the environment (none: a number; more: pairs), packed
    with the code `f` and the interface of `dest`'s type, the others by
    name; the bindings it needs first (`pre`). The code is a closure's
    (`__closure_…`; stricter: the translator takes any function of the
    program), and its captures (its variables of kind 3) are the
    literal's, one each, each a variable. -/
def cloLitS (c : Ctx) (ws : List W) (dest : Nat) : M (List (Nat × Rhs) × Rhs) :=
  match ws with
  | fname :: n :: caps0 =>
    if natOf n != some caps0.length || !startsB fname closureB then M.fail
    else do
      let qi ← M.lift (indexOf (c.prog.map (·.name)) fname)
      let q ← M.lift (nth? c.prog qi)
      let ys ← M.lift (caps0.mapM vref)
      let ck := (q.vars.filter (·.2.1 == 3)).map (·.1)
      if ck.length != ys.length then M.fail
      let (vals, cs) ← M.lift (capSplit c q 0 (ys.zip ck))
      let σ ← M.lift (sigmaOf (c.vl dest))
      let (pre, y) ← (match vals.reverse with
        | [] => do
          let y ← M.fresh
          pure ([(y, .expr (.lit 0))], y)
        | last :: init => pairUp (init.map (·.1)) last.1)
      pure (pre, .pack [qi] (envTy (vals.map (·.2))) [σ] y cs)
  | _ => M.fail

/-- `callind n c args…` (`__callind`): method 0 of the closure value `c`,
    of its type's interface (A2's `callc`), into `x0` (`none`: a fresh
    variable). -/
def callindS (c : Ctx) (ws : List W) (x0 : Option Nat) (rest : Stmt) : M Stmt :=
  match ws with
  | n :: c0 :: args =>
    if natOf n != some (args.length + 1) || c0 == kC then M.fail
    else do
      let k ← M.lift (vref c0)
      let σ ← M.lift (sigmaOf (c.vl k))
      let zs ← args.mapM (argvarS c)
      let x ← xfS x0
      pure (.callc x (c.var k) 0 σ zs rest)
  | _ => M.fail

/-- A `let`/`assign … use vY` of a closure the translator refuses: a closure
    moves only from the temporary its literal made into its binding; given
    another binding, nurlc copies it, which the core IR does not show. -/
def cloCopied (c : Ctx) (more : List W) (asg : Bool) : Bool :=
  match more with
  | op :: _ => match vref op with
    | some y => (match c.ty y with | some (.fn _ _) => true | _ => false) && (asg || c.kind y != some 2)
    | none => false
  | [] => false

/-- `ret h` as the store of the result (`__stmts_`'s `ret`): a number is
    read, a buffer moves out. -/
def retR (c : Ctx) (h : W) : Option Rhs :=
  if h == kDash then some (.expr (.lit 0))
  else if h == kC then some (.expr .any)
  else match vref h with
    | some k =>
      if c.int k then some (.expr (.var (c.var k)))
      else if c.obj k then some (.var (c.var k))
      else none
    | none => none

/-- The statements `items` as one A2 statement ending in `tail`
    (`__stmts`): each binding scoped over what follows it, and the
    temporaries of the untracked numbers a statement consumes bound around
    that statement. `fr`: a list of its own (a block's, a function's), whose
    end may be a `ret` (`retSplit`); a list `go` goes on with (the rest
    after a statement, or the split list, which ends in `retnx`) has none,
    since the last statement but `line`s and `drop`s of a list that is no
    `ret` is the same one, or none, in every suffix of it: so `retSplit`
    runs once a list, not once a statement (which made it quadratic in the
    list's length). -/
def go (c : Ctx) : Nat → Bool → List Item → Stmt → M Stmt
  | 0, _, _, _ => M.fail
  | f + 1, fr, items, tail => do
    let n0 ← M.saveLits
    let st ← (match items with
      | [] => pure tail
      | it :: rest =>
        match (if fr then retSplit items else none) with
        | some body => do
          -- a list ending in `ret`: the exit after every binding before it
          let inner ← go c f false body .skip
          let d ← M.depth
          pure (seqS inner (.exit d))
        | none =>
          match it with
          | .st (kLine :: _) => go c f false rest tail
          | .dropAt (kDrop :: h :: _) after => do
            -- a number's drop is nothing; a buffer's or a view's is its
            -- scope's end, the same only if no line after it names it, or a
            -- view of it (`__views_of`): every word of every line after it
            -- (as bits, `maskAfter`, for variables up to `maskB`)
            let k ← M.lift (idOf h)
            if c.int k || c.ty k == some .int then go c f false rest tail
            else if c.obj k then
              let dead := viewsOf c.edges (c.edges.length + 1) [k]
              if (if dead.all (· ≤ maskB) then maskAfter after &&& dead.foldl (fun m d => m ||| 2 ^ d) 0 != 0
                  else after.any fun l => (lineIds l).any dead.contains) then M.fail
              else go c f false rest tail
            else M.fail
          | .st (kBreak :: _) => do
            let r ← go c f false rest tail
            pure (seqS (.exit 1) r)
          | .st (kContinue :: _) => do
            let r ← go c f false rest tail
            pure (seqS (.exit 0) r)
          | .st (kRet :: h :: _) => do
            let e ← M.lift (retR c h)
            let d ← M.depth
            let r ← go c f false rest tail
            pure (seqS (.seq (.assign c.rslot e) (.exit d)) r)
          | .retnx (_ :: h :: _) => do
            let e ← M.lift (retR c h)
            let r ← go c f false rest tail
            pure (seqS (.assign c.rslot e) r)
          | .st (kLet :: h1 :: h2 :: more) => do
            let k ← M.lift (idOf h1)
            -- a closure bound from another binding (the translator's check,
            -- made here before the value returned at once too: stricter)
            if h2 == kUse && cloCopied c more false then M.fail
            let atOnce := !(h2 == kCall || h2 == kClosure || h2 == kCallind)
            match (if atOnce then retAt h1 (rest.dropWhile isLD) else none) with
            | some after => do
              -- `let x r` whose value is returned at once: the result takes `r`
              let (pre, rv) ← rhsS c (h2 :: more) (some k) false
              let d ← M.depth
              let r ← go c f false after tail
              pure (seqS (wrapPre pre (.seq (.assign c.rslot rv) (.exit d))) r)
            | none => do
              let r ← go c f false rest tail
              if h2 == kCall then callAny c more (some (c.var k)) r
              else if h2 == kClosure then do
                let (pre, rv) ← cloLitS c more k
                pure (wrapPre pre (.letv (c.var k) rv r))
              else if h2 == kCallind then callindS c more (some (c.var k)) r
              else do
                let (pre, rv) ← rhsS c (h2 :: more) (some k) false
                pure (wrapPre pre (.letv (c.var k) rv r))
          | .st (kEval :: h1 :: more) => do
            let r ← go c f false rest tail
            if h1 == kCall then callAny c more none r
            else if h1 == kCallind then callindS c more none r
            else do
              let x ← M.fresh
              let (pre, rv) ← rhsS c (h1 :: more) none false
              pure (wrapPre pre (.letv x rv r))
          | .st (kAssign :: h1 :: more) => do
            -- (a closure is given no other value: the translator's check,
            -- before a store to a `void` is passed over)
            if (match more with | kUse :: m => cloCopied c m true | _ => false) then M.fail
            let y ← M.lift (vref h1)
            if (lastVar c.vars y).map (·.2.2.2) == some kVoid then go c f false rest tail
            else do
              let (pre, rv) ← rhsS c more (some y) true
              let r ← go c f false rest tail
              pure (seqS (wrapPre pre (.assign (c.var y) rv)) r)
          | .scope b => do
            let x ← go c f true b .skip
            let y ← go c f false rest tail
            pure (seqS x y)
          | .ite cw a b => do
            let o ← M.lift (operandE c cw)
            let sa ← go c f true a .skip
            let sb ← go c f true b .skip
            let r ← go c f false rest tail
            pure (seqS (.ite o sa sb) r)
          | .loop cnd cw b => do
            -- the body a block of its own (`continue` leaves it), in the
            -- loop's block (`break` leaves both)
            M.addDepth 2
            let ib ← go c f true b .skip
            M.subDepth 1
            let inner ← (if cw == kT || cw == kOne then pure (.block ib)
              else do
                let o ← M.lift (operandE c cw)
                pure (.ite o (.block ib) (.exit 0)))
            let lb ← go c f true cnd inner
            M.subDepth 1
            let r ← go c f false rest tail
            pure (seqS (.block (.loop lb)) r)
          | .mat cw a1 b1 a2 b2 => do
            -- (step 7) an option's match: `isl` is 1 for its first variant,
            -- `None` (`F`), whose arm is translated first; the arms are `T`
            -- and `F`, in either order
            let (bt, bf) ← M.lift (if a1 == kT && a2 == kF then some (b1, b2)
              else if a1 == kF && a2 == kT then some (b2, b1) else none)
            let mv ← M.lift ((vref cw).map c.var)
            let sf ← go c f true bf .skip
            let st ← go c f true bt .skip
            let r ← go c f false rest tail
            pure (seqS (.ite (.isl mv) sf st) r)
          | .each xw vw b => do
            -- `foreach x v` over a Vec of numbers: the loop holds a view of
            -- the Vec for its whole run and lends each element through it
            -- (`.sat`); the index is stepped before the body, so `continue`
            -- keeps it; the blocks as a loop's
            let xv ← M.lift (vref vw)
            if !(let cs := wordOf (tyD c.vars xv kEmpty)
                 prefixN vecTyB cs && intTyB (cs.drop 6)) then M.fail
            let v := c.var xv
            let x ← M.lift ((idOf xw).map c.var)
            let i ← M.fresh
            let wv ← M.fresh
            M.addDepth 2
            let inner ← go c f true b .skip
            M.subDepth 2
            let step : Stmt := .assign i (.expr (.add (.var i) (.lit 1)))
            let each : Stmt := .letv x (.sat wv (.var i)) (.seq step inner)
            let lp : Stmt := .loop (.ite (.lt (.var i) (.slen wv)) (.block each) (.exit 0))
            let r ← go c f false rest tail
            pure (seqS (.block (.letv i (.expr (.lit 0)) (.letv wv (.view v) lp))) r)
          | _ => M.fail)
    M.wrapLits n0 st

/-- Parameter `j`'s mode (`__mode`, `__vflags`): `sink` if the flags say so
    or the walk inferred it taken over (and it is not `inout`), `inout`, a
    buffer the function changes through as its summary says (AGORA-994),
    else read only. -/
def modeOf (cl : CloTab) (sm : Summary) (fn : CoreFn) (views : List Nat) (j : Nat) : PMode :=
  let base := match lastVar fn.vars j with
    | some (_, _, fl, _) => fl
    | none => 0
  if bitB base 2 || (sinkP sm j && !bitB base 1) then .sink
  else if bitB base 1 then .inout .replace
  else match vlOf cl fn.vars views j with
    | some (.vec _) =>
      match changeOf sm j with
      | some e => .inout e
      | none => .inp
    | _ => .inp

/-- The largest variable id, plus 2; 0 for none. -/
def topNext (vs : List (Nat × Nat × Nat × W)) : Nat :=
  vs.foldl (fun acc v => max acc (v.1 + 2)) 0

/-- A statement's operand count where its right-hand side counts its
    operands (`__wellformed`): a `let`/`assign` right-hand side (word 2) or
    an `eval`'s (word 1) that is a `call`/`closure` (count at +2), a
    `callind`/`scalar` (+1) or an `agg` (+2) has a count that is a number
    and exactly that many operand words after it (an `agg` at least that
    many: its type follows). Checked for every statement of the body, the
    ones the translation skips (a store to a `void`, code after a `ret`)
    included, as the translator does before it translates. -/
def opsOk (l : List W) : Bool :=
  let off : Option Nat := match l with
    | kLet :: _ => some 2
    | kAssign :: _ => some 2
    | kEval :: _ => some 1
    | _ => none
  match off with
  | none => true
  | some off =>
    match nth? l off with
    | none => true
    | some h =>
      let cp : Option Nat :=
        if h == kCall || h == kClosure || h == kAgg then some (off + 2)
        else if h == kCallind || h == kScalar then some (off + 1)
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
            if h == kAgg then decide (n ≤ nops) else n == nops

/-- A `let x call f …` the subset takes: `string_data`, whose result is a
    view of the text (its summary says so, `ret_unowned=1`); else a call
    whose summary does not say it lends its result (`__borrowed`), and none
    named like a view the translator takes it for (`__views_of`'s prefixes)
    but `slice_from_vec__…` and `vec_at__…`. So the only calls whose result
    `__view_vars` and `__views_of` take for a view because the summary says
    so are `string_data`'s, which both take for one by name too. -/
def letCallOk (tops : List (List W)) (l : List W) : Bool :=
  match l with
  | kLet :: _ :: kCall :: f :: _ =>
    let fb := wordOf f
    fb == stringDataB ||
      (!(viewOutB.any (prefixN · fb) && !prefixN sliceFromVecB fb) && !borrowedB (sumOf tops f))
  | _ => true

/-- Does every variable a closure's code names (a word `v<k>`, a `let`'s or
    a `foreach`'s id) have a `v` line? Where one does not, the translator
    stops when it numbers it (`__var`); `elabIR` refuses the code whether
    or not the translation reaches the word (stricter). -/
def namesDeclared (ids : List Nat) (body : List (List W)) : Bool :=
  body.all fun l =>
    l.all (fun w => match varOf w with
      | some k => ids.contains k
      | none => true) &&
    match l with
    | kLet :: x :: _ | kForeach :: x :: _ => match idOf x with
      | some k => ids.contains k
      | none => true
    | _ => true

/-- The captures of closure code `q` by name (`__fn_init`): a buffer it
    does not own, unless every literal moves it in (`j`: its place among the
    captures). -/
def namedOf (cl : CloTab) (prog : List CoreFn) (q : CoreFn) : Nat → List Nat → Option (List Nat)
  | _, [] => some []
  | j, k :: ks => do
    let nm ← namedCapOf cl q k
    let r ← namedOf cl prog q (j + 1) ks
    pure (if nm && !isMovedQ prog q.name j then k :: r else r)

/-- A capture read out of the environment (`__take`): a number is copied,
    a buffer lent. -/
def takeR (c : Ctx) (k src : Nat) : Rhs :=
  match capTy (c.ty k) with
  | some .int => .expr (.var src)
  | _ => .var src

/-- The bindings that read a closure's captures by value out of its
    environment `cur` (`__read_caps`): one is the environment; more are its
    pairs' fields, each pair's second a fresh variable. -/
def capBinds (c : Ctx) : Nat → List Nat → M (List (Nat × Rhs))
  | _, [] => pure []
  | cur, [k] => pure [(c.var k, takeR c k cur)]
  | cur, k :: ks => do
    let x ← M.fresh
    let r ← capBinds c x ks
    pure ((c.var k, .fst cur) :: (x, .snd cur) :: r)

/-- A closure's code as A2's `Fn` (`__fn_init`, `__lean`, step 6): its
    environment first (lent; its captures by value, read out of it at the
    top of the body), then its parameters, then its captures by name (a
    buffer it does not own, unless every literal moves it in), then the
    result slot; its other variables after that, in id order, one number
    left out (the translator's numbering). -/
def cloFnElab (c0 : Ctx) (fn : CoreFn) (items : List Item) (rt : Ty) (own : Bool) : Option Fn := do
  let caps := (fn.vars.filter (·.2.1 == 3)).map (·.1)
  let prms := (fn.vars.filter (·.2.1 == 0)).map (·.1)
  if prms.length != fn.np then none
  -- every capture's type and mode as the translator reads them, the
  -- parameters neither `sink` nor `inout`
  if !(caps.all fun k => (capTy (c0.ty k)).isSome && (capModeOf c0.cl fn k).isSome) then none
  if prms.any fun k => bitB (c0.flags k) 1 || bitB (c0.flags k) 2 then none
  let ids := fn.vars.map (·.1)
  if !(namesDeclared ids fn.body) then none
  let named ← namedOf c0.cl c0.prog fn 0 caps
  let caps2 := caps.filter (!named.contains ·)
  let rslot := fn.np + 1 + named.length
  let others := ids.filter fun k => !prms.contains k && !named.contains k
  let vm := (idxFrom 1 prms).map (fun e => (e.2, e.1)) ++
    (idxFrom (fn.np + 1) named).map (fun e => (e.2, e.1)) ++
    (idxFrom (rslot + 1) others).map (fun e => (e.2, e.1))
  let c : Ctx := { c0 with rslot := rslot, vmap := some vm }
  let envT := envTy (← caps2.mapM fun k => capTy (c.ty k))
  let ps ← prms.mapM fun k => (c.vl k).map (PMode.inp, ·)
  let ns ← named.mapM fun k => do
    let md ← capModeOf c.cl fn k
    let vl ← c.vl k
    pure (md, vl)
  let tail : Stmt := if fn.ret == kVoid then .assign rslot (.expr (.lit 0)) else .skip
  let s0 : St := ⟨rslot + 1 + others.length + 1, [], 0⟩
  let (inner, s) ← go c (4 * fn.body.length + 4) true items tail s0
  if !s.lits.isEmpty then none
  let (binds, s') ← capBinds c 0 caps2 s
  pure { params := (.inp, envT) :: ps ++ ns, resTy := rt, resOwn := own, lends := [], rholds := [],
         outHolds := [], body := .block (wrapPre binds inner), nvars := s'.next + 1 }

/-- A function of the subset as A2's `Fn` (`__fn_init`, `__lean`): its
    variables, parameters and result numbers, buffers, views or closures
    (`tyOf`); a closure's code by `cloFnElab`. -/
def fnElab (tops : List (List W)) (prog : List CoreFn) (cl : CloTab) (fn : CoreFn) : Option Fn := do
  if !(fn.vars.all fun v => (tyOf cl v.2.2.2).isSome && v.1 ≤ idMax) then none
  let rt ← tyOf cl fn.ret
  -- (a slice handed back is not in the subset: it views what it is handed)
  let own ← match rt with
    | .int => some false
    | .slice _ => none
    | _ => some true
  let sm := sumOf tops fn.name
  if sm.val kRetdyn == some [49] then none
  if borrowedB sm then none
  -- an owned result aliasing a parameter (`ret_alias`) is not translated
  if own && (sm.val kRetAlias).isSome then none
  if !(fn.body.all opsOk) then none
  if !(fn.body.all (letCallOk tops)) then none
  let views := viewVars fn.body (fn.body.length + 1) []
  let items ← match parseB (fn.body.length + 1) fn.body [] with
    | some (its, .eof, _) => some its
    | _ => none
  let c : Ctx := ⟨fn.np, fn.vars, prog, sm, fn.body, views, eachIds fn.body, viewEdges fn.body fn.vars views, cl,
    fn.np, none, tops⟩
  if startsB fn.name closureB then cloFnElab c fn items rt own
  else
    let params ← (List.range fn.np).mapM fun j =>
      (vlOf cl fn.vars views j).map (modeOf cl sm fn views j, ·)
    let tail : Stmt := if fn.ret == kVoid then .assign fn.np (.expr (.lit 0)) else .skip
    let s0 : St := ⟨max (fn.np + 1) (topNext fn.vars), [], 0⟩
    let (inner, s) ← go c (4 * fn.body.length + 4) true items tail s0
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
def variantsOk : Nat → List W → Bool
  | 0, l => l.isEmpty
  | n + 1, _ :: np :: rest => match natOf np with
    | some k => match dropN k rest with
      | some r => variantsOk n r
      | none => false
    | none => false
  | _ + 1, _ => false

/-- After the fields: nothing, or `V n` and `n` variants. -/
def afterFieldsOk : List W → Bool
  | [] => true
  | kVV :: nv :: rest => match natOf nv with
    | some k => variantsOk k rest
    | none => false
  | _ => false

/-- `F n`, `n` name–type pairs, then `afterFieldsOk`. -/
def fieldsOk : List W → Bool
  | kF :: nf :: rest => match natOf nf with
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
def tyOk : List W → Bool
  | kTy :: name :: cls :: drops :: base :: rest =>
    !(wordOf drops).contains 100 &&                  -- 'd'
    ![name, cls, drops, base].contains kF &&
    match rest with
    | kA :: na :: more => match natOf na with
      | some k => match dropN k more with
        | some r => !(more.take k).contains kF && fieldsOk r
        | none => false
      | none => false
    | _ => fieldsOk rest
  | _ => false

/-- The top-level lines the reader would refuse (a `sum` line without its
    function, a `ty` line of another shape), and a destructor type, are
    outside the subset. -/
def topOk (tops : List (List W)) : Bool :=
  tops.all fun l => match l with
    | [kSum] => false
    | kTy :: _ => tyOk l
    | _ => true

/-- Each id below the next one's: every variable has one `v` line, in id
    order. -/
def idsAbove (prev : Nat) : List (Nat × Nat × Nat × W) → Bool
  | [] => true
  | a :: r => decide (prev < a.1) && idsAbove a.1 r

def idsInc : List (Nat × Nat × Nat × W) → Bool
  | [] => true
  | a :: r => idsAbove a.1 r

/-- A closure type's argument may be a struct of the subset (its `ty` line
    read as a variable's type is), not a struct holding raw text, nor a
    struct with no `ty` line. -/
example : cloTysB (strs [["ty", "%P", "1", "0-----", "P", "A", "0", "F", "2", "x", "i64", "y", "i64", "V", "0"]])
      (bytesOf "{ i64 (i8*, %P)*, i8* }") = some [.int, .prod .int .int] ∧
    cloTysB (strs [["ty", "%Q", "1", "0-----", "Q", "A", "0", "F", "2", "x", "i64", "s", "i8*", "V", "0"]])
      (bytesOf "{ i64 (i8*, %Q)*, i8* }") = none ∧
    cloTysB (strs [["ty", "%P", "1", "0-----", "P", "A", "0", "F", "2", "x", "i64", "y", "i64", "V", "0"]])
      (bytesOf "{ i64 (i8*, %R)*, i8* }") = none := by decide +kernel

/-- A pointer to a struct is no argument of a closure type, though the IR
    has a `ty` line for it (`%P*`, one field `*` of type `%P`), nor is a
    nested type; the struct itself is. -/
example : cloTysB (strs [["ty", "%P*", "2", "0-----", "", "A", "0", "F", "1", "*", "%P", "V", "0"],
        ["ty", "%P", "1", "0-----", "P", "A", "0", "F", "1", "x", "i64", "V", "0"]])
      (bytesOf "{ i64 (i8*, %P*)*, i8* }") = none ∧
    cloTysB (strs [["ty", "%P*", "2", "0-----", "", "A", "0", "F", "1", "*", "%P", "V", "0"],
        ["ty", "%P", "1", "0-----", "P", "A", "0", "F", "1", "x", "i64", "V", "0"]])
      (bytesOf "{ i64 (i8*, %P)*, i8* }") = some [.int, .int] ∧
    cloTysB [] (bytesOf "{ i64 (i8*, { i1, i64 })*, i8* }") = none ∧
    cloTysB [] (bytesOf "{ { i1, i64 } (i8*, i64)*, i8* }") = none := by decide +kernel

/-- The interface of closure type `cs`, the program's function `σ`
    (`__emit`): the closure (lent), then the type's arguments; its body is
    never run (a call runs the package's code), so it is one that
    type-checks, a result of the type made fresh: a number, or an empty
    buffer of numbers (any other result stops the translator). -/
def ifaceFn (tyls : List (List W)) (σ : Nat) (cs : List Nat) : Option Fn := do
  let tys ← cloTysB tyls cs
  match tys with
  | [] => none
  | rt :: args =>
    let made ← match rt with
      | .int => some (Rhs.expr (.lit 0))
      | .vec .int => some (.new .int)
      | _ => none
    let ns := tys.length
    pure { params := (.inp, .fn [σ] .any) :: args.map (.inp, ·), resTy := rt,
           resOwn := (match rt with | .int => false | _ => true), lends := [], rholds := [],
           outHolds := [], body := .block (.seq (.assign ns made) (.exit 0)), nvars := ns + 1 }

/-- The program and its entry statement (`__emit`): the functions whose
    file is not the standard library's, in order, and a call of `main`.

    The program's functions are followed by one interface per closure
    type (step 6). A term `elabIR` builds that holds `.callc` or `.pack`
    holds `.fn` too: those come only from a call through, or a literal of,
    a variable of a closure type (`callindS`, `cloLitS`: `sigmaOf` of its
    type), and every closure type has an interface whose first parameter is
    a `.fn` (`ifaceFn`). (`.pair .fst .snd .prod` are a struct's too, step
    7: no longer read by the skip.)

    nurl-cert asks the kernel for this only on a translated term built from
    the constructors `elabIR` emits (`ELAB_CTORS`,
    packages/nurl-cert/src/claims.nu): a new constructor elabIR emits goes
    into nurl-cert's list too. -/
def elabL (ls : Lines) : Option (Prog × Stmt) := do
  let fns ← fnsOfL ls
  let tops := topLines ls false
  if !(topOk tops) then none
  let prog := fns.filter fun f => !startsB f.file stdlibB
  let names := prog.map (·.name)
  if !(nodupB names) then none
  if names.any (fun n => startsB n dropB) then none
  -- a function of the program named like a library call the translator
  -- lowers to an A2 construct, called or not
  if names.any intrinsicName then none
  let mi ← indexOf names kMain
  let cl : CloTab := ⟨prog.length, cloScan tops prog, tops⟩
  -- (step 6: where the program has closures, the translator reads each
  -- function's variables in id order; `elabIR` reads them in the order of
  -- their `v` lines, and requires the two the same)
  if (!cl.tys.isEmpty || names.any (startsB · closureB)) && !(prog.all fun f => idsInc f.vars) then none
  -- a closure's code where the program has no closure type, which no
  -- literal can pack (stricter: the translator translates it)
  if cl.tys.isEmpty && names.any (startsB · closureB) then none
  let P ← prog.mapM (fnElab tops prog cl)
  let I ← (idxFrom cl.base cl.tys).mapM fun e => ifaceFn cl.tyls e.1 e.2
  pure (P ++ I, .letcall 0 mi [] .skip)

/-- The program and its entry statement, from the IR's words. -/
def elabIR (ir : IR) : Option (Prog × Stmt) := elabL ir

/-! ### Comparing terms

A2's `Stmt` has no decidable equality (its run-time forms hold a store),
so the terms of the subset are compared by `stmtBeq`, which answers
`false` for every form outside it, and is sound (`stmtBeq_sound`). -/

/-- A2's `Edit` has no decidable equality; the changes of the subset are
    compared by `editBeq` (sound: `editBeq_sound`). -/
def editBeq : Edit → Edit → Bool
  | .push y, .push y' => y == y'
  | .trunc i, .trunc i' => decide (i = i')
  | .set i y, .set i' y' => decide (i = i') && y == y'
  | _, _ => false

theorem editBeq_sound : ∀ a b : Edit, editBeq a b = true → a = b := by
  intro a b h
  cases a <;> cases b <;> simp_all [editBeq]

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
  | .edit t x o, b => match b with
    | .edit t' x' o' => t == t' && x == x' && editBeq o o'
    | _ => false
  | .callc x c j σ zs s, b => match b with
    | .callc x' c' j' σ' zs' t => x == x' && c == c' && j == j' && σ == σ' && decide (zs = zs') && stmtBeq s t
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
  | edit t x o =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.and_eq_true, Bool.false_eq_true, beq_iff_eq] at h
    obtain ⟨⟨h1, h2⟩, h3⟩ := h; subst h1; subst h2; rw [editBeq_sound _ _ h3]
  | callc x c j σ zs s ih =>
    intro b h; cases b <;> simp only [stmtBeq, Bool.and_eq_true, Bool.false_eq_true, beq_iff_eq,
      decide_eq_true_eq] at h
    obtain ⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩ := h; subst h1; subst h2; subst h3; subst h4; subst h5
    rw [ih _ h6]
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

/-- `elabIs` on words already read (the witnesses'). -/
@[irreducible] def elabLIs (ls : Lines) (P : Prog) (e : Stmt) : Bool :=
  match elabL ls with
  | some (Q, e') => progBeq Q P && stmtBeq e' e
  | none => false

theorem elabLIs_sound (ls : Lines) (P : Prog) (e : Stmt) (h : elabLIs ls P e = true) :
    elabL ls = some (P, e) := by
  unfold elabLIs at h
  split at h
  · rename_i Q e' heq
    simp only [Bool.and_eq_true] at h
    rw [heq, progBeq_sound _ _ h.1, stmtBeq_sound _ _ h.2]
  · simp at h

theorem elabIs_sound (ir : IR) (P : Prog) (e : Stmt) (h : elabIs ir P e = true) :
    elabIR ir = some (P, e) := by
  unfold elabIs at h
  split at h
  · rename_i Q e' heq
    simp only [Bool.and_eq_true] at h
    rw [heq, progBeq_sound _ _ h.1, stmtBeq_sound _ _ h.2]
  · simp at h

/-! ### Witnesses (step 2) -/

/-- The witnesses write their IRs as text, read as the reader reads the
    words (`strs`), or, for the named theorems, as numbers (`encIR`), the
    printer's form, so that reading them back is checked too. -/
abbrev SIR := List (List String)

def elabS (l : SIR) : Option (Prog × Stmt) := elabL (strs l)


/-- `tools/ncore/certify/while_loop_summing.nu`'s core IR, as
    `nurl-cert words` prints it (its `ty` line left out). -/
def irWhile : SIR := [
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
theorem elab_while : elabIR (encIR irWhile) = some (pWhile, .letcall 0 0 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- Outside the subset, `none`: a `Vec` of strings; a call of a library
    function outside it; a statement block left open. -/
example : (elabS [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["v", "0", "1", "1", "1", "2", "-1", "v", "%Vec__String"],
    ["scope"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by decide +kernel
example : (elabS [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["eval", "call", "vec_pop__i64", "1", "c"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by
  decide +kernel
example : (elabS [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["loop"], ["loopcond", "c"], ["ret", "c"], ["end"], ["endfn"]]).isNone := by decide +kernel

/-- Refused as the translator refuses it, though the translation itself
    would skip it: a miscounted scalar stored to a `void` (the translator's
    `__wellformed` checks every statement's count first); a `ty` line
    without its fields (the reader refuses it); and a function of the
    program named like an intrinsic, even one no one calls. -/
def irRet (extra : SIR) (pre : SIR) : SIR :=
  pre ++ [["fn", "main", "i64", "0", "1", "a.nu", "0", ""],
    ["v", "0", "2", "1", "0", "2", "-1", "", "void"],
    ["scope"]] ++ extra ++ [["ret", "c"], ["end"], ["endfn"]]
example : (elabS (irRet [["let", "0", "none"], ["assign", "v0", "scalar", "2", "c"]] [])).isNone := by
  decide +kernel
example : (elabS (irRet [] [] ++ [["ty", "%X", "struct", "", ""]])).isNone := by decide +kernel
example : (elabS ([["fn", "nurl_println_int", "i64", "0", "1", "a.nu", "0", ""],
    ["scope"], ["ret", "c"], ["end"], ["endfn"]] ++ irRet [] [])).isNone := by decide +kernel

/-- …while their well-formed neighbours are in the subset: the store to a
    `void` with its count right, and a struct `ty` line no one uses. -/
example : (elabS (irRet [["let", "0", "none"], ["assign", "v0", "scalar", "1", "c"]] [])).isSome := by
  decide +kernel
example : (elabS (irRet [] [] ++
    [["ty", "%X", "1", "0-----", "", "A", "0", "F", "2", "a", "i64", "b", "i64", "V", "0"]])).isSome := by
  decide +kernel

/-! ### Witnesses (step 4: buffers) -/

/-- A `main` of variables `vs` and statements `body`, then the lines
    `extra` (other functions, `sum` lines). -/
def irM (vs body extra : SIR) : SIR :=
  [["fn", "main", "i64", "0", "1", "a.nu", "0", ""]] ++ vs ++ [["scope"]] ++ body ++
    [["end"], ["endfn"]] ++ extra

/-- A Vec made, moved into its binding and its temporary dropped (`v0`, a
    temporary; `v1`, a `: ~` binding). -/
def vsVec : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%Vec__i64"],
  ["v", "1", "1", "1", "4097", "1", "-1", "v", "%Vec__i64"]]
def bodyVec : SIR := [["let", "0", "call", "vec_new__i64", "0"], ["let", "1", "use", "v0"], ["drop", "0"]]

/-- The kernel's term for it: the push's untracked number a temporary of its
    own (bound around it), the length read into a fresh one. -/
def pPush : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 4 (.expr .any)
      (.seq (.push 2 4) (.letv 3 (.expr (.len 2)) (.assign 0 (.expr .any))))))) (.exit 0)),
    nvars := 6 }]
example : elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_push__i64", "2", "v1", "c"],
    ["eval", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]]) []) = some (pPush, .letcall 0 0 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)

/-- A buffer's `drop` is the end of its scope only if no line after it names
    it (`__views_of`): the temporary read after its drop is refused, its
    binding read there is not. -/
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_len__i64", "1", "v0"], ["ret", "c"]])
    [])).isNone := by decide +kernel
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]])
    [])).isSome := by decide +kernel
/-- …every word of every line after it counts, cut at its `/`s (here a
    `line` the translation passes over), and only the text `v<k>`. -/
example : (elabS (irM vsVec (bodyVec ++ [["line", "x/v0/y"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM vsVec (bodyVec ++ [["line", "x/v00/v01/w0"], ["ret", "c"]]) [])).isSome := by
  decide +kernel

/-- …and so for variables past `maskB`, which the check reads line by line. -/
def vsBig : SIR := [["v", "5000", "2", "1", "0", "1", "-1", "", "%Vec__i64"],
  ["v", "5001", "1", "1", "4097", "1", "-1", "v", "%Vec__i64"]]
def bodyBig : SIR := [["let", "5000", "call", "vec_new__i64", "0"], ["let", "5001", "use", "v5000"], ["drop", "5000"]]
example : (elabS (irM vsBig (bodyBig ++ [["eval", "call", "vec_len__i64", "1", "v5000"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM vsBig (bodyBig ++ [["eval", "call", "vec_len__i64", "1", "v5001"], ["ret", "c"]]) [])).isSome := by
  decide +kernel

/-- A call whose result may view an argument (its summary: `ret_unowned=1`)
    is refused (`letCallOk`), its owned neighbour (`ret_owned`) is not; so
    is a call of a function named like one the translator takes for a view
    (`slice_at__…`), even of the program's own. -/
def bodyLen : SIR := bodyVec ++ [["let", "2", "call", "vec_len__i64", "1", "v1"], ["ret", "c"]]
def vsLen : SIR := vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "i64"]]
example : (elabS (irM vsLen bodyLen [["sum", "vec_len__i64", "1", "ret_unowned=1"]])).isNone := by
  decide +kernel
example : (elabS (irM vsLen bodyLen [["sum", "vec_len__i64", "1", "ret_unowned=1", "ret_owned=1"]])).isSome := by
  decide +kernel
def fnRead (name : String) : SIR := [["fn", name, "i64", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", "0", "1", "-1", "v", "%Vec__i64"], ["scope"], ["ret", "c"], ["end"], ["endfn"]]
example : (elabS (irM vsLen (bodyVec ++ [["let", "2", "call", "slice_at__x", "1", "v1"], ["ret", "c"]])
    (fnRead "slice_at__x"))).isNone := by decide +kernel
example : (elabS (irM vsLen (bodyVec ++ [["let", "2", "call", "slice_atx", "1", "v1"], ["ret", "c"]])
    (fnRead "slice_atx"))).isSome := by decide +kernel

/-- A buffer's drop ends the elements read out of it too (`vec_at`,
    `__views_of`): the element of the temporary read after the temporary's
    drop is refused, the element of its binding is not. -/
example : (elabS (irM vsLen [["let", "0", "call", "vec_new__i64", "0"],
    ["let", "2", "call", "vec_at__i64", "2", "v0", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
    ["eval", "scalar", "1", "v2"], ["ret", "c"]] [])).isNone := by decide +kernel
example : (elabS (irM vsLen (bodyVec ++ [["let", "2", "call", "vec_at__i64", "2", "v1", "c"],
    ["drop", "0"], ["eval", "scalar", "1", "v2"], ["ret", "c"]]) [])).isSome := by decide +kernel

/-- An owned result aliasing a parameter (`ret_alias`) is refused; without
    the key the Vec handed back is the result, owned. -/
def fnMake (extra : SIR) : SIR := [["fn", "make", "%Vec__i64", "0", "1", "a.nu", "0", ""]] ++ vsVec ++
  [["scope"]] ++ bodyVec ++ [["ret", "v1"], ["end"], ["endfn"]] ++ extra
example : (elabS (irM [] [["ret", "c"]] (fnMake [["sum", "make", "0", "ret_alias=0"]]))).isNone := by
  decide +kernel
example : (elabS (irM [] [["ret", "c"]] (fnMake []))).isSome := by decide +kernel

/-- Stores the translator refuses: a borrowed parameter's value given to an
    owner (a `sink` one's is not); raw text assigned from another binding (a
    `String` is not). -/
def fnStore (pflags : String) : SIR := [["fn", "f", "void", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", pflags, "1", "-1", "a", "%Vec__i64"],
  ["v", "1", "1", "1", "1", "1", "-1", "b", "%Vec__i64"],
  ["scope"], ["let", "1", "call", "vec_new__i64", "0"], ["assign", "v1", "use", "v0"], ["end"], ["endfn"]]
example : (elabS (irM [] [["ret", "c"]] (fnStore "0"))).isNone := by decide +kernel
example : (elabS (irM [] [["ret", "c"]] (fnStore "4"))).isSome := by decide +kernel
def vsText (t : String) : SIR := [["v", "0", "1", "1", "1", "1", "-1", "a", t],
  ["v", "1", "1", "1", "1", "1", "-1", "b", t]]
def bodyText : SIR := [["let", "0", "use", "c"], ["let", "1", "use", "c"], ["assign", "v1", "use", "v0"],
  ["ret", "c"]]
example : (elabS (irM (vsText "i8*") bodyText [])).isNone := by decide +kernel
example : (elabS (irM (vsText "%String") bodyText [])).isSome := by decide +kernel

/-- Outside the subset: a `Vec` of `Vec`s, and a `let` of a `vec_push` (the
    translator lowers it by falling through to a call). -/
example : (elabS (irM [["v", "0", "1", "1", "1", "1", "-1", "v", "%Vec__Vec__i64"]] [["ret", "c"]]
    [])).isNone := by decide +kernel
example : (elabS (irM (vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "void"]])
    (bodyVec ++ [["let", "2", "call", "vec_push__i64", "2", "v1", "c"], ["ret", "c"]]) [])).isNone := by
  decide +kernel


/-! ### Witnesses (step 5: views, slices and changes through a borrow) -/

/-- A `String` made, viewed (`string_data`, a temporary `v2`), the view
    bound (`v3`) and read: raw text that holds a view is a slice, read by
    its length (`.slen`). -/
def vsStr : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%String"],
  ["v", "1", "1", "1", "4096", "1", "-1", "t", "%String"],
  ["v", "2", "2", "1", "0", "1", "-1", "", "i8*"], ["v", "3", "1", "1", "0", "1", "-1", "v", "i8*"]]
def bodyStr : SIR := [["let", "0", "call", "string_from", "1", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["let", "2", "call", "string_data", "1", "v1"], ["let", "3", "use", "v2"], ["drop", "2"]]

/-- The translator's term for it (`nurl-cert translate`), written out. -/
def pView : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 3 (.view 2) (.letv 4 (.var 3)
      (.letv 5 (.expr (.slen 4)) (.assign 0 (.expr .any))))))) (.exit 0)),
    nvars := 7 }]
example : elabS (irM vsStr (bodyStr ++ [["eval", "call", "nurl_str_len", "1", "v3"], ["ret", "c"]]) []) =
    some (pView, .letcall 0 0 [] .skip) := elabLIs_sound _ _ _ (by decide +kernel)
/-- …and so is `nurl_println` of the view; `string_data` is taken though its
    summary says it lends its result (`ret_unowned=1`, as nurlc prints it). -/
example : elabS (irM vsStr (bodyStr ++ [["eval", "call", "nurl_println", "1", "v3"], ["ret", "c"]])
    [["sum", "string_data", "1", "ret_unowned=1"]]) = some (pView, .letcall 0 0 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)
/-- A `let x` of `nurl_println` is refused: the translator lowers it by
    falling through to a call, which drops `x` (stricter). -/
example : (elabS (irM (vsStr ++ [["v", "4", "2", "1", "0", "1", "-1", "", "void"]])
    (bodyStr ++ [["let", "4", "call", "nurl_println", "1", "v3"], ["ret", "c"]]) [])).isNone := by
  decide +kernel

/-- A drop ends the views copied out of a view into a temporary
    (`__views_of`'s `use` case): the String's temporary `v0` is viewed (`v2`),
    the view copied into the temporary `v3`, and `v3` read after `v0`'s drop
    is refused; copied into a binding instead, it is not followed (the
    translator's rule), and the program is in the subset. -/
def vsChain (k3 : String) : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%String"],
  ["v", "1", "1", "1", "4096", "1", "-1", "t", "%String"], ["v", "2", "2", "1", "0", "1", "-1", "", "i8*"],
  ["v", "3", k3, "1", "0", "1", "-1", "", "i8*"]]
def bodyChain : SIR := [["let", "0", "call", "string_from", "1", "c"], ["let", "2", "call", "string_data", "1", "v0"],
  ["let", "3", "use", "v2"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["eval", "call", "nurl_str_len", "1", "v3"], ["ret", "c"]]
example : (elabS (irM (vsChain "2") bodyChain [])).isNone := by decide +kernel
example : (elabS (irM (vsChain "1") bodyChain [])).isSome := by decide +kernel

/-- A slice of a Vec of numbers (`.view`) and its length (`.slen`); a
    `slice_from_vec` whose summary says it lends its result is refused
    (stricter: the translator takes it), and so is a slice of a Vec of
    views (the translator refuses it). -/
def vsSl : SIR := vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "%Slice__i64"]]
def bodySl : SIR := bodyVec ++ [["let", "2", "call", "slice_from_vec__i64", "1", "v1"],
  ["eval", "call", "slice_len__i64", "1", "v2"], ["ret", "c"]]
def pSlice : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 3 (.view 2)
      (.letv 4 (.expr (.slen 3)) (.assign 0 (.expr .any)))))) (.exit 0)),
    nvars := 6 }]
example : elabS (irM vsSl bodySl []) = some (pSlice, .letcall 0 0 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)
example : (elabS (irM vsSl bodySl [["sum", "slice_from_vec__i64", "1", "rviews=0"]])).isNone := by
  decide +kernel
def vsVecS : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%Vec__str"],
  ["v", "1", "1", "1", "4097", "1", "-1", "v", "%Vec__str"]]
def bodyVecS : SIR := [["let", "0", "call", "vec_new__str", "0"], ["let", "1", "use", "v0"], ["drop", "0"]]
example : (elabS (irM (vsVecS ++ [["v", "2", "2", "1", "0", "1", "-1", "", "%Slice__str"]])
    (bodyVecS ++ [["let", "2", "call", "slice_from_vec__str", "1", "v1"], ["ret", "c"]]) [])).isNone := by
  decide +kernel

/-- Raw text pushed into a `Vec` of raw strings is viewed first (the Vec
    holds a view of it); a literal is refused, as the translator refuses it. -/
def vsNames : SIR := vsVecS ++ [["v", "2", "1", "1", "0", "1", "-1", "a", "i8*"]]
def pNames : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new (.slice .int)) (.letv 2 (.var 1) (.letv 3 (.new .int)
      (.letv 4 (.view 3) (.seq (.push 2 4) (.assign 0 (.expr .any))))))) (.exit 0)),
    nvars := 6 }]
example : elabS (irM vsNames (bodyVecS ++ [["let", "2", "use", "c"],
    ["eval", "call", "vec_push__str", "2", "v1", "v2"], ["ret", "c"]]) []) = some (pNames, .letcall 0 0 [] .skip) :=
  elabLIs_sound _ _ _ (by decide +kernel)
example : (elabS (irM vsNames (bodyVecS ++ [["let", "2", "use", "c"],
    ["eval", "call", "vec_push__str", "2", "v1", "c"], ["ret", "c"]]) [])).isNone := by decide +kernel

/-- `foreach x v` over a Vec of numbers: a view of the Vec held for the
    loop, each element lent through it (`.sat`), the index stepped first. -/
def vsEach : SIR := vsVec ++ [["v", "2", "1", "1", "0", "1", "-1", "x", "i64"]]
def bodyEach (over : String) (inner : SIR) : SIR :=
  bodyVec ++ [["foreach", "2", over], ["scope"]] ++ inner ++ [["end"], ["end"], ["ret", "c"]]
def pEach : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.seq (.block (.letv 4 (.expr (.lit 0))
      (.letv 5 (.view 2) (.loop (.ite (.lt (.var 4) (.slen 5)) (.block (.letv 3 (.sat 5 (.var 4))
        (.seq (.assign 4 (.expr (.add (.var 4) (.lit 1)))) (.letv 6 (.expr (.add .any (.lt (.add (.lit 0)
          (.var 3)) (.lit 0)))) .skip)))) (.exit 0))))))
      (.assign 0 (.expr .any))))) (.exit 0)),
    nvars := 8 }]
example : elabS (irM vsEach (bodyEach "v1" [["eval", "scalar", "1", "v2"]]) []) =
    some (pEach, .letcall 0 0 [] .skip) := elabLIs_sound _ _ _ (by decide +kernel)
/-- Refused as the translator refuses them: a `foreach` over a Vec of views,
    and over a `String`. -/
example : (elabS (irM (vsVecS ++ [["v", "2", "1", "1", "0", "1", "-1", "x", "i8*"]])
    (bodyVecS ++ [["foreach", "2", "v1"], ["scope"], ["end"], ["end"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM [["v", "0", "2", "1", "0", "1", "-1", "", "%String"],
    ["v", "1", "1", "1", "4097", "1", "-1", "s", "%String"], ["v", "2", "1", "1", "0", "1", "-1", "x", "i64"]]
    [["let", "0", "call", "string_from", "1", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
     ["foreach", "2", "v1"], ["scope"], ["end"], ["end"], ["ret", "c"]] [])).isNone := by decide +kernel
/-- A change of the loop's element in place is refused (stricter: the
    translator changes it through itself, `__edit_through`); a change of
    the Vec is a change through a borrow of it. -/
example : (elabS (irM vsEach (bodyEach "v1" [["eval", "call", "vec_clear__i64", "1", "v2"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM vsEach (bodyEach "v1" [["eval", "call", "vec_clear__i64", "1", "v1"]]) [])).isSome := by
  decide +kernel

/-- `vec_reserve`: a push through a borrow (its untracked number a temporary
    of its own) and a cut back to the length read before it. -/
def pReserve : Prog := [
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [], outHolds := [],
    body := .block (.seq (.letv 1 (.new .int) (.letv 2 (.var 1) (.letv 4 (.expr .any)
      (.seq (.letv 3 (.borrow 2) (.letv 5 (.expr (.len 3))
        (.seq (.edit true 3 (.push 4)) (.edit true 3 (.trunc (.var 5))))))
        (.assign 0 (.expr .any)))))) (.exit 0)),
    nvars := 7 }]
example : elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_reserve__i64", "2", "v1", "c"], ["ret", "c"]])
    []) = some (pReserve, .letcall 0 0 [] .skip) := elabLIs_sound _ _ _ (by decide +kernel)
/-- …a `let x` of it is refused (stricter: the translator falls through to a
    call that drops `x`), and so is one of a Vec of views (the translator
    refuses it). -/
example : (elabS (irM (vsVec ++ [["v", "2", "2", "1", "0", "1", "-1", "", "void"]])
    (bodyVec ++ [["let", "2", "call", "vec_reserve__i64", "2", "v1", "c"], ["ret", "c"]]) [])).isNone := by
  decide +kernel
example : (elabS (irM vsVecS (bodyVecS ++ [["eval", "call", "vec_reserve__str", "2", "v1", "c"], ["ret", "c"]])
    [])).isNone := by decide +kernel

/-- `vec_clear` and `vec_truncate` of the counts the translator lowers; a
    `vec_clear` of two operands falls through to a call of a function the
    program does not have, and is refused. -/
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_clear__i64", "1", "v1"], ["ret", "c"]])
    [])).isSome := by decide +kernel
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_truncate__i64", "2", "v1", "c"], ["ret", "c"]])
    [])).isSome := by decide +kernel
example : (elabS (irM vsVec (bodyVec ++ [["eval", "call", "vec_clear__i64", "2", "v1", "c"], ["ret", "c"]])
    [])).isNone := by decide +kernel

/-- `string_push_str` of text (here the String itself) reads its length
    after the push; of a number it is refused, as the translator refuses it. -/
def vsPs : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%String"],
  ["v", "1", "1", "1", "4097", "1", "-1", "s", "%String"], ["v", "2", "1", "1", "1", "1", "-1", "n", "i64"]]
def bodyPs : SIR := [["let", "0", "call", "string_from", "1", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["let", "2", "use", "c"]]
example : (elabS (irM vsPs (bodyPs ++ [["eval", "call", "string_push_str", "2", "v1", "v1"], ["ret", "c"]])
    [])).isSome := by decide +kernel
example : (elabS (irM vsPs (bodyPs ++ [["eval", "call", "string_push_str", "2", "v1", "v2"], ["ret", "c"]])
    [])).isNone := by decide +kernel

/-- A slice parameter is in the subset; a slice handed back is not
    (stricter: the translator takes it as an owned result). -/
def fnSl (ret : String) (body : SIR) : SIR := [["fn", "f", ret, "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", "0", "1", "-1", "s", "%Slice__i64"], ["scope"]] ++ body ++ [["end"], ["endfn"]]
example : (elabS (irM [] [["ret", "c"]] (fnSl "i64" [["eval", "call", "slice_len__i64", "1", "v0"],
    ["ret", "c"]]))).isSome := by decide +kernel
example : (elabS (irM [] [["ret", "c"]] (fnSl "%Slice__i64" [["ret", "v0"]]))).isNone := by decide +kernel

/-- A borrowed parameter assigned to an `inout` one is copied when it is a
    Vec (here of raw strings: `.new (.slice .int)`); a slice is not, as the
    translator refuses it. -/
def fnCopy (t : String) : SIR := [["fn", "f", "void", "2", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", "0", "1", "-1", "a", t], ["v", "1", "0", "0", "2", "1", "-1", "b", t],
  ["scope"], ["assign", "v1", "use", "v0"], ["end"], ["endfn"]]
example : (elabS (irM [] [["ret", "c"]] (fnCopy "%Vec__str"))).isSome := by decide +kernel
example : (elabS (irM [] [["ret", "c"]] (fnCopy "%Slice__i64"))).isNone := by decide +kernel

/-! ### Witnesses (step 6: closures) -/

def cloTyW : String := "{ i64 (i8*, i64)*, i8* }"

/-- A closure's code `cn` of a capture `c` (type `ct`, flags `cf`) and a
    parameter `x` (flags `pf`), body `cb`; then `main`: `v0` the capture's
    binding (type `ct`, made by `mk`), the literal `lit` into the temporary
    `v1` (type `cty`), moved into `f` (`v2`), its other variables `mvs`,
    then `body`; then the lines `extra`. -/
def irCloW (cn ct cf pf cty : String) (cb mk lit body mvs extra : SIR) : SIR :=
  [["fn", cn, "i64", "1", "1", "a.nu", "0", ""], ["v", "0", "3", "0", cf, "1", "-1", "c", ct],
   ["v", "1", "0", "1", pf, "0", "-1", "x", "i64"], ["scope"]] ++ cb ++ [["ret", "c"], ["end"], ["endfn"],
   ["fn", "main", "i64", "0", "1", "a.nu", "0", ""], ["v", "0", "1", "1", "0", "1", "-1", "c", ct],
   ["v", "1", "2", "1", "0", "1", "-1", "", cty], ["v", "2", "1", "1", "0", "1", "-1", "f", cty]] ++ mvs ++
  [["scope"]] ++ mk ++ lit ++ [["let", "2", "use", "v1"], ["drop", "1"]] ++ body ++ [["ret", "c"], ["end"], ["endfn"]] ++
  extra

def litW : SIR := [["let", "1", "closure", "__closure_1", "1", "v0"]]
def callW : SIR := [["eval", "callind", "2", "v2", "c"]]
/-- A number captured by value and the closure called. -/
def irNumW (cb lit body mvs extra : SIR) : SIR :=
  irCloW "__closure_1" "i64" "0" "0" cloTyW cb [["let", "0", "use", "c"]] lit body mvs extra
def cbW : SIR := [["eval", "scalar", "2", "v1", "v0"]]

/-- The translator's term for it (`nurl-cert translate`), written out: the
    code reads its capture out of the environment (`v0`) at the top; the
    literal packs the code (function 0) with the environment, the number,
    at the interface of its type (function 2, after the program's two);
    the call is `callc` of that interface's method 0. -/
def pCloW : Prog := [
  { params := [(.inp, .int), (.inp, .int)], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.letv 3 (.expr (.var 0)) (.seq (.letv 5 (.expr (.add .any (.lt (.add (.add
      (.lit 0) (.var 1)) (.var 3)) (.lit 0)))) (.assign 2 (.expr .any))) (.exit 0))), nvars := 7 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 1 (.expr .any) (.letv 2 (.pack [0] .int [2] 1 []) (.letv 3 (.var 2)
      (.letv 4 (.expr .any) (.callc 5 3 0 2 [4] (.assign 0 (.expr .any))))))) (.exit 0)), nvars := 7 },
  { params := [(.inp, .fn [2] .any), (.inp, .int)], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.assign 2 (.expr (.lit 0))) (.exit 0)), nvars := 3 }]
theorem elab_clo : elabIR (encIR (irNumW cbW litW callW [] [])) = some (pCloW, .letcall 0 1 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- Refused as the translator refuses them: a capture that is not a
    variable; a literal of fewer captures than its code has; a call through
    a number; a closure bound from another binding (`v3`), or given another
    value. -/
example : (elabS (irNumW cbW [["let", "1", "closure", "__closure_1", "1", "c"]] callW [] [])).isNone := by
  decide +kernel
example : (elabS (irNumW cbW [["let", "1", "closure", "__closure_1", "0"]] callW [] [])).isNone := by
  decide +kernel
example : (elabS (irNumW cbW litW [["eval", "callind", "1", "v0"]] [] [])).isNone := by decide +kernel
def v3W : SIR := [["v", "3", "1", "1", "0", "1", "-1", "g", cloTyW]]
example : (elabS (irNumW cbW litW [["let", "3", "use", "v2"], ["eval", "callind", "2", "v3", "c"]] v3W [])).isNone := by
  decide +kernel
example : (elabS (irNumW cbW litW [["assign", "v2", "use", "v2"]] [] [])).isNone := by decide +kernel
/-- …and where the copy's value is handed back at once (stricter: the
    translator checks the copy only past that case). -/
example : (elabS (irNumW cbW litW [["let", "3", "use", "v2"], ["ret", "v3"]] v3W [])).isNone := by decide +kernel

/-- A closure handed to a `sink` parameter is refused (nurlc copies it there,
    unseen in the core IR), to a read-only one it is not. -/
def fnTakesW (fl : String) : SIR := [["fn", "g", "i64", "1", "1", "a.nu", "0", ""],
  ["v", "0", "0", "0", fl, "1", "-1", "h", cloTyW], ["scope"], ["ret", "c"], ["end"], ["endfn"]]
example : (elabS (irNumW cbW litW [["eval", "call", "g", "1", "v2"]] [] (fnTakesW "4"))).isNone := by decide +kernel
example : (elabS (irNumW cbW litW [["eval", "call", "g", "1", "v2"]] [] (fnTakesW "0"))).isSome := by decide +kernel

/-- A capture the code takes by pointer (flag 8) is refused for a number,
    and is `inout` for a Vec; a capture of a Vec of raw strings is refused
    (the translator follows numbers and buffers of numbers only); a closure
    parameter taken `inout` is refused. -/
def irVecW (ct cf : String) (body : SIR) : SIR :=
  irCloW "__closure_1" ct cf "0" cloTyW [] [["let", "0", "call", "vec_new__" ++ (if ct == "%Vec__str" then "str" else "i64"), "0"]]
    litW body [] []
example : (elabS (irCloW "__closure_1" "i64" "8" "0" cloTyW cbW [["let", "0", "use", "c"]] litW callW [] [])).isNone := by
  decide +kernel
example : (elabS (irVecW "%Vec__i64" "8" callW)).isSome := by decide +kernel
example : (elabS (irVecW "%Vec__str" "0" callW)).isNone := by decide +kernel
example : (elabS (irCloW "__closure_1" "i64" "0" "2" cloTyW cbW [["let", "0", "use", "c"]] litW callW [] [])).isNone := by
  decide +kernel

/-- A Vec captured by a literal that moves it in (the binding named no more
    after it) is the environment's (the code: the environment, `x`); named
    after the literal, it is a capture by name (the code: the environment,
    `x`, the Vec). -/
example : ((elabS (irVecW "%Vec__i64" "0" callW)).map fun r => r.1.head?.map (·.params.length)) =
    some (some 2) := by decide +kernel
example : ((elabS (irVecW "%Vec__i64" "0" (callW ++ [["eval", "call", "vec_len__i64", "1", "v0"]]))).map fun r =>
    r.1.head?.map (·.params.length)) = some (some 3) := by decide +kernel

/-- An interface whose result is a slice is refused (the translator makes
    no such result); one whose result is a Vec is not (an empty one). -/
example : (elabS (irCloW "__closure_1" "i64" "0" "0" "{ %Slice__i64 (i8*, i64)*, i8* }" cbW [["let", "0", "use", "c"]]
    litW callW [] [])).isNone := by decide +kernel
example : (elabS (irCloW "__closure_1" "i64" "0" "0" "{ %Vec__i64 (i8*, i64)*, i8* }" cbW [["let", "0", "use", "c"]]
    litW callW [] [])).isSome := by decide +kernel

/-- Stricter than the translator: a literal of a function not named as a
    closure's code; a closure's code naming a variable it does not declare,
    where the translation passes over it (a `line`; where it is read the
    translator stops too); variables not in id order; a `let x` of
    `nurl_println_int` (whose `eval` is in the subset). -/
example : (elabS (irCloW "clo1" "i64" "0" "0" cloTyW cbW [["let", "0", "use", "c"]]
    [["let", "1", "closure", "clo1", "1", "v0"]] callW [] [])).isNone := by decide +kernel
example : (elabS (irNumW [["line", "v7"]] litW callW [] [])).isNone := by decide +kernel
example : (elabS (irNumW [["eval", "scalar", "1", "v7"]] litW callW [] [])).isNone := by decide +kernel
example : (elabS (irNumW [["line", "7"]] litW callW [] [])).isSome := by decide +kernel
example : (elabS ([["fn", "main", "i64", "0", "1", "a.nu", "0", ""], ["v", "1", "1", "1", "0", "1", "-1", "a", "i64"],
    ["v", "0", "1", "1", "0", "1", "-1", "f", cloTyW], ["scope"], ["ret", "c"], ["end"], ["endfn"]])).isNone := by
  decide +kernel
example : (elabS ([["fn", "main", "i64", "0", "1", "a.nu", "0", ""], ["v", "0", "1", "1", "0", "1", "-1", "f", cloTyW],
    ["v", "1", "1", "1", "0", "1", "-1", "a", "i64"], ["scope"], ["ret", "c"], ["end"], ["endfn"]])).isSome := by
  decide +kernel
example : (elabS (irNumW cbW litW [["let", "3", "call", "nurl_println_int", "1", "c"]]
    [["v", "3", "1", "1", "0", "1", "-1", "r", "i64"]] [])).isNone := by decide +kernel
example : (elabS (irNumW cbW litW [["eval", "call", "nurl_println_int", "1", "v0"]] [] [])).isSome := by
  decide +kernel
/-- …and a closure's code in a program with no closure type, which no literal
    can pack. -/
example : (elabS ([["fn", "__closure_1", "i64", "0", "1", "a.nu", "0", ""], ["scope"], ["ret", "c"], ["end"], ["endfn"]] ++
    irM [] [["ret", "c"]] [])).isNone := by decide +kernel
example : (elabS ([["fn", "f1", "i64", "0", "1", "a.nu", "0", ""], ["scope"], ["ret", "c"], ["end"], ["endfn"]] ++
    irM [] [["ret", "c"]] [])).isSome := by decide +kernel

/-- A closure's code reading `changes` (`__changes`): its first `call` of a
    changer whose first argument is the capture's text. -/
example : changesB (strs [["eval", "call", "vec_push__i64", "2", "v0", "v1"]]) 0 = true ∧
    changesB (strs [["eval", "call", "vec_len__i64", "1", "v0"]]) 0 = false ∧
    changesB (strs [["eval", "call", "vec_push__i64", "2", "v00", "v1"]]) 0 = false := by decide +kernel

/-! ### Witnesses (step 7: structs and options) -/

/-- `tools/ncore/certify/struct_fields_read.nu`'s core IR (its `sum` lines
    and the program's `ty` lines; the file `a.nu`). -/
def irStruct : SIR := [
  ["fn", "sum", "i64", "1", "3", "a.nu", "0", ""], ["v", "0", "0", "0", "0", "3", "-1", "p", "%P"],
  ["scope"], ["line", "3"], ["eval", "scalar", "2", "v0/x", "v0/y"], ["ret", "c"], ["end"], ["endfn"],
  ["fn", "main", "i64", "0", "5", "a.nu", "0", ""], ["v", "0", "2", "1", "0", "6", "-1", "", "%P"],
  ["v", "1", "1", "1", "0", "6", "-1", "p", "%P"],
  ["scope"], ["line", "6"], ["let", "0", "agg", "-", "2", "c", "c", "%P"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["line", "7"], ["eval", "call", "sum", "1", "v1"], ["ret", "c"], ["end"], ["endfn"],
  ["ty", "%P", "1", "0-----", "P", "A", "0", "F", "2", "x", "i64", "y", "i64", "V", "0"],
  ["ty", "i64", "1", "0-----", "", "A", "0", "F", "0", "V", "0"],
  ["sum", "sum", "1", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"],
  ["sum", "main", "0", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"]]

/-- The term `nurl-cert translate` prints for it, written out: the struct is
    a pair of its numbers (`.prod .int .int`), its literal the pair of two
    temporaries, each field read through the pair into a temporary (`.fst`,
    `.snd`) before the statement that reads it. -/
def pStruct : Prog := [
  { params := [(.inp, .prod .int .int)], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 3 (.fst 0) (.letv 4 (.snd 0) (.letv 2 (.expr (.add .any (.lt
      (.add (.add (.lit 0) (.var 3)) (.var 4)) (.lit 0)))) (.assign 1 (.expr .any))))) (.exit 0)), nvars := 6 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 4 (.expr .any) (.letv 5 (.expr .any) (.letv 1 (.pair 4 5)
      (.letv 2 (.var 1) (.letcall 3 0 [2] (.assign 0 (.expr .any))))))) (.exit 0)), nvars := 7 }]

theorem elab_struct : elabIR (encIR irStruct) = some (pStruct, .letcall 0 1 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- `tools/ncore/certify/option_built_and_matched.nu`'s core IR. -/
def irOpt : SIR := [
  ["fn", "pick", "{ i1, i64 }", "1", "1", "a.nu", "0", ""], ["v", "0", "0", "0", "0", "1", "-1", "k", "i64"],
  ["v", "1", "2", "1", "0", "1", "-1", "", "void"], ["v", "2", "2", "2", "0", "1", "-1", "", "{ i1, i64 }"],
  ["v", "3", "2", "1", "0", "1", "-1", "", "{ i1, i64 }"],
  ["scope"], ["line", "1"], ["eval", "scalar", "2", "v0", "c"], ["let", "1", "none"], ["if", "c"], ["scope"],
  ["let", "2", "agg", "F", "0", "{", "i1,", "i64", "}"], ["ret", "v2"], ["drop", "2"], ["end"], ["else"], ["scope"],
  ["end"], ["end"], ["drop", "1"], ["let", "3", "agg", "T", "1", "v0", "{", "i1,", "i64", "}"], ["ret", "v3"],
  ["drop", "3"], ["end"], ["endfn"],
  ["fn", "main", "i64", "0", "3", "a.nu", "0", ""], ["v", "0", "2", "1", "0", "4", "-1", "", "{ i1, i64 }"],
  ["v", "1", "1", "1", "0", "4", "-1", "o", "{ i1, i64 }"], ["v", "2", "2", "1", "0", "5", "-1", "", "void"],
  ["v", "3", "1", "2", "0", "5", "-1", "x", "i64"],
  ["scope"], ["line", "4"], ["let", "0", "call", "pick", "1", "c"], ["let", "1", "use", "v0"], ["drop", "0"],
  ["line", "5"], ["let", "2", "none"], ["match", "v1"], ["arm", "T"], ["scope"], ["let", "3", "payload", "v1", "T", "0"],
  ["ret", "v3"], ["end"], ["arm", "F"], ["scope"], ["ret", "c"], ["end"], ["end"], ["drop", "2"], ["end"], ["endfn"],
  ["ty", "{ i1, i64 }", "1", "0c----", "", "A", "0", "F", "2", "", "i1", "", "i64", "V", "0"],
  ["sum", "pick", "1", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"],
  ["sum", "main", "0", "safe=1", "vkeeps=:", "vholds=:", "rviews=:", "body_done=1"]]

/-- The translator's term for it, written out: the option is `.sum .int
    .int`, `None` its first variant (`.inl` of a temporary), `Some k` its
    second (`.inr`); the match tests the tag (`.isl`), the `None` arm first,
    and the `T` arm lends the payload (`.getr`). -/
def pOpt : Prog := [
  { params := [(.inp, .int)], resTy := .sum .int .int, resOwn := true, lends := [], rholds := [],
    outHolds := [], body := .block (.seq (.letv 6 (.expr (.add .any (.lt (.add (.add (.lit 0) (.var 0)) .any)
      (.lit 0)))) (.letv 2 (.expr .any) (.seq (.ite .any (.seq (.letv 5 (.expr .any) (.letv 3 (.inl 5 .int)
      (.assign 1 (.var 3)))) (.exit 0)) .skip) (.letv 4 (.inr .int 0) (.assign 1 (.var 4)))))) (.exit 0)),
    nvars := 8 },
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := .block (.letv 5 (.expr .any) (.letcall 1 0 [5] (.letv 2 (.var 1) (.letv 3 (.expr .any)
      (.ite (.isl 2) (.seq (.assign 0 (.expr .any)) (.exit 0))
        (.seq (.letv 4 (.getr 2) (.assign 0 (.expr (.var 4)))) (.exit 0))))))), nvars := 7 }]

theorem elab_opt : elabIR (encIR irOpt) = some (pOpt, .letcall 0 1 [] .skip) :=
  elabIs_sound _ _ _ (by decide +kernel)

/-- A `main` with a struct `%S` (fields `a` of type `ta`, `b` of type `tb`):
    its literal of two untracked numbers into `v0`, moved into `v1`, a
    number `v2`, then `body`. -/
def tyS2 (ta tb : String) : SIR := [["ty", "%S", "1", "0-----", "S", "A", "0", "F", "2", "a", ta, "b", tb, "V", "0"]]
def vsS : SIR := [["v", "0", "2", "1", "0", "1", "-1", "", "%S"], ["v", "1", "1", "1", "0", "1", "-1", "s", "%S"],
  ["v", "2", "1", "1", "0", "1", "-1", "n", "i64"]]
def irS (tyl body : SIR) : SIR :=
  irM vsS ([["let", "0", "agg", "-", "2", "c", "c", "%S"], ["let", "1", "use", "v0"], ["drop", "0"]] ++ body ++
    [["ret", "c"]]) tyl

/-- A number field's value read into a variable is in the subset; an
    owning field's (a `Vec`) is refused, as the translator refuses it (it
    would move out of its struct); so is a nested path, and a field the
    struct does not have. -/
example : (elabS (irS (tyS2 "%Vec__i64" "i64") [["let", "2", "use", "v1/b"]])).isSome := by decide +kernel
example : (elabS (irS (tyS2 "%Vec__i64" "i64") [["let", "2", "use", "v1/a"]])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "i64" "i64") [["let", "2", "use", "v1/b/a"]])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "i64" "i64") [["let", "2", "use", "v1/z"]])).isNone := by decide +kernel

/-- Struct types, as the translator takes them: a field of raw text is
    refused (a `String` is not); so is a closure in a field, and a struct
    inside itself (through an option field; an option of a number is
    not). Stricter: two fields of one name. -/
example : (elabS (irS (tyS2 "i8*" "i64") [])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "%String" "i64") [])).isSome := by decide +kernel
example : (elabS (irS (tyS2 "{ i64 (i8*)*, i8* }" "i64") [])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "{ i1, %S }" "i64") [])).isNone := by decide +kernel
example : (elabS (irS (tyS2 "{ i1, i64 }" "i64") [])).isSome := by decide +kernel
example : (elabS (irS [["ty", "%S", "1", "0-----", "S", "A", "0", "F", "2", "a", "i64", "a", "i64", "V", "0"]] [])).isNone := by
  decide +kernel

/-- A struct of no fields, and one with no `ty` line, are refused. Stricter:
    a name the translator reads as a number behind its `%` (`%i64`), or as
    a channel (`%Channel__…`), is refused though a `ty` line gives it
    fields. -/
def irTy (t : String) (tyl : SIR) : SIR := irM [["v", "0", "1", "1", "0", "1", "-1", "x", t]] [["ret", "c"]] tyl
example : (elabS (irTy "%S" [["ty", "%S", "1", "0-----", "S", "A", "0", "F", "0", "V", "0"]])).isNone := by decide +kernel
example : (elabS (irTy "%S" [])).isNone := by decide +kernel
example : (elabS (irTy "%i64" [["ty", "%i64", "1", "0-----", "S", "A", "0", "F", "2", "a", "i64", "b", "i64", "V", "0"]])).isNone := by
  decide +kernel
example : (elabS (irTy "%Channel__i64" [["ty", "%Channel__i64", "1", "0-----", "S", "A", "0", "F", "2", "a", "i64", "b", "i64",
    "V", "0"]])).isNone := by decide +kernel
/-- …and an option of a closure (the translator: a closure inside a value). -/
example : (elabS (irTy "{ i1, { i64 (i8*)*, i8* } }" [])).isNone := by decide +kernel
example : (elabS (irTy "{ i1, %String }" [])).isSome := by decide +kernel

/-- A field read by a library call goes through the pairs (`rdF`); a field
    of a type that is no struct of the subset (a `Vec`'s handle `ctl`) is
    refused (stricter: the translator reads any type's `ty` line), and so is
    a field of a struct of one field named other than its field (stricter:
    the translator does not read the name). -/
def vsV : SIR := [["v", "0", "1", "1", "0", "1", "-1", "v", "%Vec__i64"]]
example : (elabS (irM vsV [["let", "0", "call", "vec_new__i64", "0"], ["eval", "call", "vec_len__i64", "1", "v0/ctl"],
    ["ret", "c"]] [["ty", "%Vec__i64", "0", "1c----", "Vec", "A", "1", "i64", "F", "1", "ctl", "i8*", "V", "0"]])).isNone := by
  decide +kernel
example : (elabS (irM vsV [["let", "0", "call", "vec_new__i64", "0"], ["eval", "call", "vec_len__i64", "1", "v0"],
    ["ret", "c"]] [["ty", "%Vec__i64", "0", "1c----", "Vec", "A", "1", "i64", "F", "1", "ctl", "i8*", "V", "0"]])).isSome := by
  decide +kernel
def irW (fld : String) : SIR := irM [["v", "0", "1", "1", "0", "1", "-1", "k", "i64"], ["v", "1", "1", "1", "0", "1", "-1", "w", "%W"]]
  [["let", "0", "use", "c"], ["let", "1", "agg", "-", "1", "v0", "%W"], ["eval", "scalar", "1", fld], ["ret", "c"]]
  [["ty", "%W", "1", "0-----", "W", "A", "0", "F", "1", "n", "i64", "V", "0"]]
example : (elabS (irW "v1/n")).isSome := by decide +kernel
example : (elabS (irW "v1/m")).isNone := by decide +kernel

/-- Literals: an option's only into a variable of an option type, and given
    a variable (an `eval` of one is refused, as the translator refuses it);
    a struct's of two operands at least, or of one. -/
def vsO (t : String) : SIR := [["v", "0", "1", "1", "0", "1", "-1", "o", t]]
example : (elabS (irM (vsO "{ i1, i64 }") [["let", "0", "agg", "F", "0", "{", "i1,", "i64", "}"], ["ret", "c"]] [])).isSome := by
  decide +kernel
example : (elabS (irM (vsO "i64") [["let", "0", "agg", "F", "0", "{", "i1,", "i64", "}"], ["ret", "c"]] [])).isNone := by
  decide +kernel
example : (elabS (irM (vsO "{ i1, i64 }") [["eval", "agg", "T", "1", "c", "{", "i1,", "i64", "}"], ["ret", "c"]] [])).isNone := by
  decide +kernel
example : (elabS (irS (tyS2 "i64" "i64") [["let", "2", "agg", "-", "0", "%S"]])).isNone := by decide +kernel

/-- An option's payload is read where its `T` arm matched (`payload v T 0`,
    `.getr`); any other payload is refused (the translator reads a result's
    error, `F`, only in a program that spawns, which is outside the
    subset). -/
def irM2 (arms : SIR) : SIR := irM [["v", "0", "1", "1", "0", "1", "-1", "o", "{ i1, i64 }"],
  ["v", "1", "1", "2", "0", "1", "-1", "x", "i64"]]
  ([["let", "0", "agg", "T", "1", "c", "{", "i1,", "i64", "}"], ["match", "v0"]] ++ arms ++ [["end"], ["ret", "c"]]) []
def armT (pl : SIR) : SIR := [["arm", "T"], ["scope"]] ++ pl ++ [["end"]]
def armF : SIR := [["arm", "F"], ["scope"], ["end"]]
example : (elabS (irM2 (armT [["let", "1", "payload", "v0", "T", "0"]] ++ armF))).isSome := by decide +kernel
example : (elabS (irM2 (armT [["let", "1", "payload", "v0", "F", "0"]] ++ armF))).isNone := by decide +kernel
/-- A match's arms are `T` and `F`, in either order; one name twice is
    refused, as the translator refuses it, and so are three arms (stricter:
    the translator takes the last block of a repeated name). -/
example : (elabS (irM2 (armF ++ armT []))).isSome := by decide +kernel
example : (elabS (irM2 (armT [] ++ armT []))).isNone := by decide +kernel
example : (elabS (irM2 (armT [] ++ armF ++ armT []))).isNone := by decide +kernel

end C.Elab
