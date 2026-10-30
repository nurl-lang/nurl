// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Extracts Lean 4 module graphs, declarations, theorem dependency graphs,
// ownership rules (formal/RULES.md), and the soundness hole corpus
// (formal/corpus/map.tsv + tools/fuzz/holes/*.nu) into:
//   1. webdocs/lib/formal-data.generated.ts (compact typed metadata, module DAGs, blueprint, rules, holes)
//   2. webdocs/public/formal-decls.json (all 1,766 declarations across A1 & A2 for the code browser)

import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, '..', '..');
const FORMAL_DIR = join(ROOT, 'formal');
const HOLES_DIR = join(ROOT, 'tools', 'fuzz', 'holes');
const OUTPUT_TS = join(ROOT, 'webdocs', 'lib', 'formal-data.generated.ts');
const OUTPUT_JSON = join(ROOT, 'webdocs', 'public', 'formal-decls.json');

const MODULE_LAYERS = {
  Syntax: {
    layer: 0,
    category: 'Syntax & Store',
    summaryFi: 'Tyypit, efektihila (Eff.kills), lausekkeet, lauseet ja muistipaikat (Mem, Slot, Val).',
    summaryEn: 'Types, effect & kill lattice (Eff.kills), expressions, statements, and store values (Mem, Slot, Val).',
  },
  Semantics: {
    layer: 0,
    category: 'Syntax & Store',
    summaryFi: 'Pienaskelsemantiikka (Step, Steps), puumuistin vapautus (Frees, DropSlot), kutsun avaus ja jumiutuminen (Stuck).',
    summaryEn: 'Small-step operational semantics (Step, Steps), tree deallocation (Frees, DropSlot), call expansion, and Stuck.',
  },
  Typing: {
    layer: 1,
    category: 'Flow-Sensitive Typing',
    summaryFi: 'Vuosensitiivinen tyyppikonteksti Γ, kill-operaatio, lauseiden ja kutsujen tyyppisäännöt (RhsT, StmtT, CallT, FnOK).',
    summaryEn: 'Flow-sensitive context Γ, kill operation, and typing rules for RHS, statements, calls, and functions (RhsT, StmtT, CallT, FnOK).',
  },
  Basic: {
    layer: 1,
    category: 'Flow-Sensitive Typing',
    summaryFi: 'Perusapulemmat muistipäivityksille (upd), arvojen alipuille ja konteksteille.',
    summaryEn: 'Foundational lemmas for store updates (upd), value subtrees, and contexts.',
  },
  Ctx: {
    layer: 1,
    category: 'Flow-Sensitive Typing',
    summaryFi: 'Kontekstin operaatioiden (kill, exitScope, derive) algebralliset ominaisuudet ja monotonisuus.',
    summaryEn: 'Algebraic properties and monotonicity of context operations (kill, exitScope, derive).',
  },
  TypingFacts: {
    layer: 1,
    category: 'Flow-Sensitive Typing',
    summaryFi: 'Inversiolemmat ja rakenteelliset ominaisuudet hyvin tyypitetyille lauseille (StmtT).',
    summaryEn: 'Inversion lemmas and structural properties of well-typed statements (StmtT).',
  },
  Invariant: {
    layer: 2,
    category: 'Memory Invariant',
    summaryFi: 'Konfiguraatioinvariantti (Inv, HeapOK, Covers, ValOK, ViewsOK): yksittäisomistajuus ja lainojen eheys.',
    summaryEn: 'Configuration invariant (Inv, HeapOK, Covers, ValOK, ViewsOK): single ownership and valid borrows/views.',
  },
  Stability: {
    layer: 2,
    category: 'Memory Invariant',
    summaryFi: 'Lainojen ja näkymien säilyvyys, kun muistia tai kontekstia päivitetään muualta.',
    summaryEn: 'Stability of borrows and views under store and context updates.',
  },
  Heap: {
    layer: 2,
    category: 'Memory Invariant',
    summaryFi: 'Kekoinvariantin (HeapOK: erilliset omistuspuut ja varatut osoitteet) säilyminen muistioperaatioissa.',
    summaryEn: 'Preservation of heap disjointness and allocation validity (HeapOK) across store operations.',
  },
  Values: {
    layer: 2,
    category: 'Memory Invariant',
    summaryFi: 'Arvojen, tietueiden (pair), summien (inl/inr) ja näkymien hyvinmuodostuneisuuslemmat.',
    summaryEn: 'Well-formedness lemmas for values, structs (pair), enums (inl/inr), and views.',
  },
  Wf: {
    layer: 2,
    category: 'Memory Invariant',
    summaryFi: 'Kontekstin sisäisen hyvinmuodostuneisuuden (WfCtx) säilyminen askeleissa.',
    summaryEn: 'Preservation of context well-formedness (WfCtx) across typing transitions.',
  },
  NameWf: {
    layer: 2,
    category: 'Memory Invariant',
    summaryFi: 'Sulkeumien nimikaappausten (Kind.name) hyvinmuodostuneisuus ja invariantit.',
    summaryEn: 'Well-formedness and invariants for by-name closure captures (Kind.name).',
  },
  Frame: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryFi: 'Ajonaikaisten kehysten (scope, rbind, frozen) vaikutus invarianttiin.',
    summaryEn: 'How runtime frames (scope, rbind, frozen) interact with the memory invariant.',
  },
  StepFrame: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryFi: 'Invariantin säilyminen kehysten sisällä ja paniikin purkamisen aikana.',
    summaryEn: 'Invariant preservation across frame steps and panic unwinding frames.',
  },
  Rhs: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryFi: 'Oikean puolen lausekkeiden (Rhs: move, borrow, vec_at, view, pop, pack) askeleet ja invariantit.',
    summaryEn: 'Stepping and invariant preservation for right-hand side evaluations (Rhs).',
  },
  Steps: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryFi: 'Yksittäisten lauseaskeleiden (letv, assign, push, free, unpair) säilyvyyslemmat.',
    summaryEn: 'Preservation lemmas for individual statement steps (letv, assign, push, free, unpair).',
  },
  Leak: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryFi: 'Muistivuodottomuusinvariantti (Covers): jokainen varattu osoite kuuluu jollekin elävälle omistajalle.',
    summaryEn: 'Leak-freedom invariant (Covers): every allocated address is owned by a live binding.',
  },
  Panic: {
    layer: 3,
    category: 'Step & Unwinding Lemmas',
    summaryFi: 'Paniikin purkaminen (panic_unwind): jokainen poistuva lohko vapauttaa omistamansa puut (drop journal).',
    summaryEn: 'Panic unwinding (panic_unwind): every exited scope drops its owned trees via the drop journal.',
  },
  Rename: {
    layer: 4,
    category: 'Calls & Closures',
    summaryFi: 'Funktion rungon muuttujien uudelleennimeäminen (alpha-renaming) kutsukohdan tuoreille muuttujille.',
    summaryEn: 'Alpha-renaming of function body variables to fresh variables at a call site.',
  },
  Call: {
    layer: 4,
    category: 'Calls & Closures',
    summaryFi: 'Funktiokutsun avauksen (callStmt) tyyppisääntöjen johtaminen funktion tiivistelmästä (FnOK + CallT).',
    summaryEn: 'Typing of expanded function calls (callStmt) from function summaries (FnOK + CallT).',
  },
  Bind: {
    layer: 4,
    category: 'Calls & Closures',
    summaryFi: 'Parametrien sitominen (in, inout, sink) kutsujan argumenteista kutsuttavan kontekstiin.',
    summaryEn: 'Binding call arguments (in, inout, sink) from caller context into callee frame.',
  },
  CallMem: {
    layer: 4,
    category: 'Calls & Closures',
    summaryFi: 'Muistin tila ja omistuspuut parametrien sitomisen jälkeen funktiokutsussa.',
    summaryEn: 'Store state and owned trees immediately after binding parameters in a call.',
  },
  CallInv: {
    layer: 4,
    category: 'Calls & Closures',
    summaryFi: 'Kokonaisinvariantin (callCase, recCase) säilyminen funktiokutsun ja recover-kehyksen avauksessa.',
    summaryEn: 'Full invariant preservation (callCase, recCase) across function call and recover expansion.',
  },
  Closure: {
    layer: 4,
    category: 'Calls & Closures',
    summaryFi: 'Sulkeuma- ja piirreoliokutsujen (callc, cloCase, cloProgress) avaaminen ja nimikaappausten tarkistus.',
    summaryEn: 'Closure and trait-object package calls (callc, cloCase, cloProgress) and by-name capture soundness.',
  },
  Codes: {
    layer: 4,
    category: 'Calls & Closures',
    summaryFi: 'Sulkeumapakettien koodiosoittimien eheys (ProgCodes, MemCodes, codes_step) jokaisen askeleen yli.',
    summaryEn: 'Package code-pointer integrity (ProgCodes, MemCodes, codes_step) across execution steps.',
  },
  Preservation: {
    layer: 5,
    category: 'Soundness Theorems',
    summaryFi: 'Preservation-lause (preserve): jokainen suoritusaskel säilyttää tyypityksen StmtT ja muisti-invariantin Inv.',
    summaryEn: 'Preservation theorem (preserve): every execution step preserves typing StmtT and memory invariant Inv.',
  },
  Progress: {
    layer: 5,
    category: 'Soundness Theorems',
    summaryFi: 'Progress-lause (progress): hyvin tyypitetty lause on joko valmis (.skip) tai voi ottaa askeleen (ei koskaan Stuck).',
    summaryEn: 'Progress theorem (progress): a well-typed statement is either .skip or can step (never Stuck).',
  },
  Soundness: {
    layer: 5,
    category: 'Soundness Theorems',
    summaryFi: 'Päälauseet: soundness, memory_safe, no_leak_end ja no_leak_panic.',
    summaryEn: 'Main theorems: soundness, memory_safe, no_leak_end, and no_leak_panic.',
  },
};

function cleanComment(raw) {
  return raw
    .replace(/^\/-[-!]?\s*/, '')
    .replace(/\s*-\/$/, '')
    .split('\n')
    .map((line) => line.replace(/^\s{0,4}/, ''))
    .join('\n')
    .trim();
}

function parseLeanFile(phase, modName, filePath) {
  const content = readFileSync(filePath, 'utf8');
  const lines = content.split('\n');

  const imports = [];
  for (const line of lines) {
    const m = line.match(/^import\s+([A-Za-z0-9_.]+)/);
    if (m) imports.push(m[1]);
  }

  let moduleDoc = '';
  const nsMatch = content.match(/\bnamespace\s+A[12]\b/);
  const headerSlice = nsMatch ? content.slice(0, nsMatch.index) : content.slice(0, 1200);
  const docMatches = [...headerSlice.matchAll(/\/-[-!]?([\s\S]*?)-\//g)];
  if (docMatches.length > 0) {
    moduleDoc = docMatches.map((m) => cleanComment(m[0])).join('\n\n');
  }

  const decls = [];
  let pendingDoc = [];
  let inDoc = false;
  let currentDecl = null;

  const declRegex =
    /^(?:noncomputable\s+|private\s+|protected\s+)*(theorem|lemma|def|abbrev|inductive|structure)\s+([A-Za-z0-9_'.]+)/;

  function flushDecl(endLineIdx) {
    if (!currentDecl) return;
    while (endLineIdx > currentDecl.startLine - 1 && lines[endLineIdx - 1].trim() === '') {
      endLineIdx--;
    }
    const rawLines = lines.slice(currentDecl.startLine - 1, endLineIdx);
    const fullCode = rawLines.join('\n');

    let signature = '';
    if (currentDecl.kind === 'inductive' || currentDecl.kind === 'structure') {
      signature = rawLines.slice(0, Math.min(rawLines.length, 25)).join('\n');
    } else {
      const sigLines = [];
      for (const l of rawLines) {
        const byIdx = l.indexOf(':= by');
        if (byIdx !== -1) {
          sigLines.push(l.slice(0, byIdx).trimEnd());
          break;
        }
        const whereIdx = l.match(/\swhere\s*$/);
        if (whereIdx) {
          sigLines.push(l.slice(0, whereIdx.index).trimEnd());
          break;
        }
        const assignIdx = l.indexOf(' := ');
        if (assignIdx !== -1 && (currentDecl.kind === 'theorem' || currentDecl.kind === 'lemma')) {
          sigLines.push(l.slice(0, assignIdx).trimEnd());
          break;
        }
        sigLines.push(l);
        if (sigLines.length >= 10) break;
      }
      signature = sigLines.join('\n');
    }

    const keepFullModules = new Set([
      'Syntax',
      'Semantics',
      'Typing',
      'Invariant',
      'Panic',
      'Soundness',
      'Preservation',
      'Progress',
    ]);
    const maxLines = keepFullModules.has(modName) ? 110 : 40;
    let displayCode = fullCode;
    let truncated = false;
    if (rawLines.length > maxLines) {
      const head = rawLines.slice(0, maxLines - 5).join('\n');
      const tail = rawLines.slice(-3).join('\n');
      displayCode = `${head}\n  -- … [${rawLines.length - (maxLines - 2)} proof lines omitted in preview; see GitHub lines ${currentDecl.startLine}–${endLineIdx}] …\n${tail}`;
      truncated = true;
    }

    decls.push({
      id: `${phase}.${currentDecl.name}`,
      name: currentDecl.name,
      phase,
      module: modName,
      kind: currentDecl.kind,
      startLine: currentDecl.startLine,
      endLine: endLineIdx,
      lineCount: rawLines.length,
      doc: currentDecl.doc,
      signature,
      code: displayCode,
      truncated,
      _fullCode: fullCode,
    });
    currentDecl = null;
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    if (inDoc) {
      pendingDoc.push(line);
      if (trimmed.endsWith('-/')) {
        inDoc = false;
      }
      continue;
    }

    if (trimmed.startsWith('/--')) {
      flushDecl(i);
      pendingDoc = [line];
      if (!trimmed.endsWith('-/')) {
        inDoc = true;
      }
      continue;
    }

    if (
      trimmed.startsWith('/-!') ||
      trimmed.startsWith('end A1') ||
      trimmed.startsWith('end A2') ||
      trimmed === 'mutual' ||
      trimmed === 'end'
    ) {
      flushDecl(i);
      pendingDoc = [];
      continue;
    }

    const m = line.match(declRegex);
    if (m) {
      flushDecl(i);
      const kind = m[1] === 'lemma' ? 'theorem' : m[1];
      const name = m[2];
      const doc = pendingDoc.length > 0 ? cleanComment(pendingDoc.join('\n')) : '';
      pendingDoc = [];
      currentDecl = {
        kind,
        name,
        startLine: i + 1,
        doc,
      };
    } else if (trimmed !== '' && !trimmed.startsWith('--') && !currentDecl) {
      pendingDoc = [];
    }
  }
  flushDecl(lines.length);

  const layerInfo = MODULE_LAYERS[modName] ?? {
    layer: 3,
    category: 'Proof Infrastructure',
    summaryFi: '',
    summaryEn: '',
  };

  return {
    id: `${phase}.${modName}`,
    name: modName,
    phase,
    path: `formal/${phase}/${modName}.lean`,
    lineCount: lines.length,
    imports: imports.map((imp) => imp.replace(/^A[12]\./, '')),
    doc: moduleDoc,
    layer: layerInfo.layer,
    category: layerInfo.category,
    summaryFi: layerInfo.summaryFi,
    summaryEn: layerInfo.summaryEn,
    counts: {
      theorem: decls.filter((d) => d.kind === 'theorem').length,
      def: decls.filter((d) => d.kind === 'def' || d.kind === 'abbrev').length,
      inductive: decls.filter((d) => d.kind === 'inductive').length,
      structure: decls.filter((d) => d.kind === 'structure').length,
      total: decls.length,
    },
    decls,
  };
}

function buildPhaseData(phase) {
  const dir = join(FORMAL_DIR, phase);
  const files = readdirSync(dir)
    .filter((f) => f.endsWith('.lean'))
    .sort();

  const modules = files.map((f) => {
    const modName = f.replace(/\.lean$/, '');
    return parseLeanFile(phase, modName, join(dir, f));
  });

  const declByName = new Map();
  for (const mod of modules) {
    for (const d of mod.decls) {
      if (!declByName.has(d.name)) {
        declByName.set(d.name, d);
      }
    }
  }

  const identRegex = /[A-Za-z_][A-Za-z0-9_']*(?:\.[A-Za-z_][A-Za-z0-9_']*)*/g;
  const usedByMap = new Map();
  for (const name of declByName.keys()) {
    usedByMap.set(name, new Set());
  }

  for (const mod of modules) {
    for (const d of mod.decls) {
      const refs = new Set();
      const matches = d._fullCode.match(identRegex) ?? [];
      for (const token of matches) {
        if (token === d.name) continue;
        if (declByName.has(token)) {
          refs.add(token);
        } else if (token.includes('.')) {
          const parts = token.split('.');
          const base = parts[0];
          if (base !== d.name && declByName.has(base)) {
            refs.add(base);
          }
        }
      }
      d.deps = [...refs].slice(0, 24);
      for (const r of d.deps) {
        usedByMap.get(r)?.add(d.name);
      }
      delete d._fullCode;
    }
  }

  for (const mod of modules) {
    for (const d of mod.decls) {
      d.usedBy = [...(usedByMap.get(d.name) ?? [])].slice(0, 24);
    }
  }

  return modules;
}

function parseRulesMd() {
  const content = readFileSync(join(FORMAL_DIR, 'RULES.md'), 'utf8');
  const lines = content.split('\n');
  const rules = [];
  for (const line of lines) {
    if (!line.startsWith('| §')) continue;
    const cells = line
      .split('|')
      .slice(1, -1)
      .map((c) => c.trim());
    if (cells.length >= 5) {
      rules.push({
        section: cells[0],
        rule: cells[1],
        phase: cells[2],
        formalRule: cells[3],
        status: cells[4],
      });
    }
  }
  return rules;
}

function parseHolesCorpus() {
  const content = readFileSync(join(FORMAL_DIR, 'corpus', 'map.tsv'), 'utf8').trim();
  const lines = content.split('\n').slice(1);
  return lines.map((line) => {
    // old_id: the hNNN number from before Agora #212, `-` for a newer probe.
    const [probe, rule, phase, note, nurlc, oldId] = line.split('\t');
    const nuPath = join(HOLES_DIR, `${probe}.nu`);
    let code = '';
    if (existsSync(nuPath)) {
      code = readFileSync(nuPath, 'utf8').trim();
    }
    return {
      probe,
      id: oldId && oldId !== '-' ? oldId : probe.split('/').pop(),
      rule,
      phase,
      note,
      nurlc,
      code,
    };
  });
}

const BLUEPRINT_NODES = [
  {
    id: 'Ty',
    name: 'Ty',
    module: 'Syntax',
    kind: 'inductive',
    tier: 0,
    titleFi: 'Tyypit (Ty)',
    titleEn: 'Types (Ty)',
    explainFi:
      'Kuvaa NURLin muistirelevantit tyypit: kokonaisluvut (.int), omistetut dynaamiset puskurit (.vec t — kattaa myös Stringin), näkymät (.slice t), tietueet (.prod a b), summatyypit/Option (.sum a b) sekä sulkeuma/piirrepaketit (.fn ms).',
    explainEn:
      'Models NURL memory-relevant types: scalars (.int), owned growable buffers (.vec t, including String), borrowed views (.slice t), inline structs (.prod a b), tagged enums/Option (.sum a b), and closure/trait packages (.fn ms).',
    deps: [],
  },
  {
    id: 'Eff',
    name: 'Eff',
    module: 'Syntax',
    kind: 'inductive',
    tier: 0,
    titleFi: 'Efektihila (Eff)',
    titleEn: 'Effect Lattice (Eff)',
    explainFi:
      'Järjestää säiliöoperaatiot sen mukaan, mitä lainoja ne mitätöivät: none (vain luku) < realloc (vec_push voi siirtää puskurin) < drop (vec_pop pudottaa alkion) < replace (siirto, vapautus tai lohkon loppu).',
    explainEn:
      'Orders container effects by what they invalidate: none (read) < realloc (vec_push may move buffer) < drop (vec_pop drops element) < replace (move, free, assignment, or scope exit).',
    deps: [],
  },
  {
    id: 'Eff.kills',
    name: 'Eff.kills',
    module: 'Syntax',
    kind: 'def',
    tier: 0,
    titleFi: 'Mitätöintisääntö (Eff.kills)',
    titleEn: 'Invalidation Rule (Eff.kills)',
    explainFi:
      'Tarkka totuustaulu sille, milloin efekti e juurella r päättää riippuvuuden k (self, inner, view tai name). Esimerkiksi realloc tappaa näkymät (.view), mutta säilyttää alkiolainat (.inner).',
    explainEn:
      'Exact truth table deciding when effect e on root r invalidates a dependency of kind k (self, inner, view, or name). For instance, realloc kills .view but preserves .inner.',
    deps: ['Eff', 'Ty'],
  },
  {
    id: 'Mem',
    name: 'Mem',
    module: 'Syntax',
    kind: 'structure',
    tier: 0,
    titleFi: 'Ajonaikainen muisti (Mem & Slot)',
    titleEn: 'Runtime Store (Mem & Slot)',
    explainFi:
      'Kuvaa ajonaikaisen muistin: varatut keko-osoitteet (alloc : Nat → Bool) ja muuttujien paikat (st : Var → Option Slot), joissa jokaisella paikalla on omistajuuslippu (own : Bool) ja pudotuslippu (val : Option Val).',
    explainEn:
      'Models runtime memory: allocated heap addresses (alloc : Nat → Bool) and variable slots (st : Var → Option Slot) carrying ownership (own : Bool) and drop flag (val : Option Val).',
    deps: ['Ty'],
  },
  {
    id: 'DropSlot',
    name: 'DropSlot',
    module: 'Semantics',
    kind: 'inductive',
    tier: 1,
    titleFi: 'Automaattinen vapautus (DropSlot & Frees)',
    titleEn: 'Scope-Exit Drop (DropSlot & Frees)',
    explainFi:
      'Kun lohko päättyy (Step.scopeSkip) tai purkautuu paniikissa (Step.scopeP), omistava paikka ⟨true, some tree⟩ vapauttaa rekursiivisesti koko omistuspuunsa; jo siirretty ⟨true, none⟩ tai lainattu ⟨false, _⟩ ohitetaan turvallisesti.',
    explainEn:
      'When a scope exits normally (Step.scopeSkip) or unwinds on panic (Step.scopeP), an owning slot ⟨true, some tree⟩ recursively frees its entire tree; moved ⟨true, none⟩ or borrowed ⟨false, _⟩ slots are no-ops.',
    deps: ['Mem'],
  },
  {
    id: 'Step',
    name: 'Step',
    module: 'Semantics',
    kind: 'inductive',
    tier: 1,
    titleFi: 'Suoritusaskel (Step & Stuck)',
    titleEn: 'Operational Step (Step & Stuck)',
    explainFi:
      'Määrittelee pienaskelsemantiikan. Jokainen muistia lukeva tai vapauttava askel tarkistaa, että osoite on varattu (m.alloc c = true) ja indeksit rajoissa. Jos ohjelma yrittäisi use-after-free- tai double-free-operaatiota, sääntöä ei ole — konfiguraatio olisi Stuck.',
    explainEn:
      'Small-step operational semantics. Every memory access or free checks that the address is allocated (m.alloc c = true). Any use-after-free, double-free, or dangling view access has no step rule and becomes Stuck.',
    deps: ['Mem', 'DropSlot'],
  },
  {
    id: 'kill',
    name: 'kill',
    module: 'Typing',
    kind: 'def',
    tier: 1,
    titleFi: 'Kontekstin mitätöinti (kill & exitScope)',
    titleEn: 'Context Invalidation (kill & exitScope)',
    explainFi:
      'Päivittää tyyppikontekstin Γ: jokainen muuttuja, jonka polku (path) tai sisällön näkymät (held) riippuvat muutetusta juuresta r tavalla jonka Eff.kills lopettaa, merkitään kuolleeksi (live := false).',
    explainEn:
      'Updates typing context Γ: every binding whose borrow path or held views depend on root r with a kind killed by Eff.kills is marked dead (live := false).',
    deps: ['Eff.kills'],
  },
  {
    id: 'CallT',
    name: 'CallT',
    module: 'Typing',
    kind: 'structure',
    tier: 1,
    titleFi: 'Kutsun ja tiivistelmän tarkistus (CallT & FnOK)',
    titleEn: 'Call & Summary Check (CallT & FnOK)',
    explainFi:
      'Varmistaa kutsukohdassa, että sink- ja inout-argumentit eivät aliasoidu keskenään eivätkä ole lainattuja (F), ja laskee funktion tiivistelmästä (lends, rholds, outHolds) paluuarvon riippuvuudet.',
    explainEn:
      'Enforces at call sites that sink and inout arguments are disjoint and not frozen (F), and computes return/argument dependencies from the callee summary (lends, rholds, outHolds).',
    deps: ['kill', 'Eff.kills'],
  },
  {
    id: 'StmtT',
    name: 'StmtT',
    module: 'Typing',
    kind: 'inductive',
    tier: 2,
    titleFi: 'Vuosensitiivinen tyyppijärjestelmä (StmtT & RhsT)',
    titleEn: 'Flow-Sensitive Typing (StmtT & RhsT)',
    explainFi:
      'Tarkistaa lauseen s alkukontekstista Γ loppukontekstiin Δ (StmtT P Γ F s Δ). Jokainen luku vaatii elävän sidonnan (live = true), jokainen siirto tappaa lähteen, ja jokainen mutaatio ajaa kill-päivityksen.',
    explainEn:
      'Typechecks statement s from input context Γ to output context Δ (StmtT P Γ F s Δ). Every read requires live = true, every move kills its source, and every mutation applies kill.',
    deps: ['kill', 'CallT'],
  },
  {
    id: 'HeapOK',
    name: 'HeapOK',
    module: 'Invariant',
    kind: 'structure',
    tier: 2,
    titleFi: 'Yksittäisomistajuus (HeapOK)',
    titleEn: 'Single-Owner Disjoint Trees (HeapOK)',
    explainFi:
      'Takaa, että jokaisen omistajan puussa jokainen solmuosoite on varattu (m.alloc = true), esiintyy puussa korkeintaan kerran (Nodup), eikä mikään kahden eri omistajan puu jaa yhtään osoitetta.',
    explainEn:
      'Guarantees that every node in an owned tree is allocated (m.alloc = true), appears at most once in the tree (Nodup), and no two owners share any address.',
    deps: ['Mem'],
  },
  {
    id: 'Covers',
    name: 'Covers',
    module: 'Invariant',
    kind: 'def',
    tier: 2,
    titleFi: 'Vuodottomuusinvariantti (Covers)',
    titleEn: 'No-Orphan-Allocation Invariant (Covers)',
    explainFi:
      'Jokainen varattu keko-osoite (m.alloc i = true) kuuluu jonkin muistissa olevan omistajan o omistuspuuhun (i ∈ T.ids). Mikään varattu muisti ei koskaan jää orvoksi.',
    explainEn:
      'Every allocated heap address (m.alloc i = true) belongs to the owned tree of some live owner binding o in the store (i ∈ T.ids). No allocation is ever orphaned.',
    deps: ['Mem', 'HeapOK'],
  },
  {
    id: 'Inv',
    name: 'Inv',
    module: 'Invariant',
    kind: 'structure',
    tier: 3,
    titleFi: 'Kokonaisinvariantti (Inv m Γ F s)',
    titleEn: 'Configuration Invariant (Inv m Γ F s)',
    explainFi:
      'Yhdistää käännösaikaisen kontekstin Γ ja ajonaikaisen muistin m: sisältää HeapOK:n, Coversin, ja todistaa että jokainen Γ:ssa elävä (live = true) laina ja näkymä osoittaa voimassa olevaan omistuspuuhun.',
    explainEn:
      'Bridges compile-time context Γ and runtime store m: bundles HeapOK, Covers, and guarantees every live borrow and view in Γ resolves to a valid, in-bounds node in an owner tree.',
    deps: ['HeapOK', 'Covers', 'StmtT'],
  },
  {
    id: 'panic_unwind',
    name: 'panic_unwind',
    module: 'Panic',
    kind: 'theorem',
    tier: 3,
    titleFi: 'Paniikin purkaminen (panic_unwind)',
    titleEn: 'Panic Unwinding (panic_unwind)',
    explainFi:
      'Todistaa, että kun paniikki purkaa suorituspinoa (s.spine), jokaisen poistuvan lohkon omistamat puut vapautetaan (DropSlot) ja sekä HeapOK että Covers säilyvät.',
    explainEn:
      'Proves that when a panic unwinds the active scope spine (s.spine), every exited scope drops its owned trees while preserving both HeapOK and Covers.',
    deps: ['DropSlot', 'HeapOK', 'Covers'],
  },
  {
    id: 'callCase',
    name: 'callCase',
    module: 'CallInv',
    kind: 'theorem',
    tier: 3,
    titleFi: 'Funktiokutsun säilyvyys (callCase & recCase)',
    titleEn: 'Function Call Soundness (callCase & recCase)',
    explainFi:
      'Todistaa, että kun funktiokutsu (tai recover-kehys) avataan ajonaikaiseksi lohkoksi ja sen runko nimetään uudelleen (Rename), sekä tyyppitarkistus StmtT että muisti-invariantti Inv säilyvät.',
    explainEn:
      'Proves that expanding a function call (or recover frame) with alpha-renamed body variables preserves both typing StmtT and the memory invariant Inv.',
    deps: ['Inv', 'CallT'],
  },
  {
    id: 'cloCase',
    name: 'cloCase',
    module: 'Closure',
    kind: 'theorem',
    tier: 3,
    titleFi: 'Sulkeumakutsun säilyvyys (cloCase & cloProgress)',
    titleEn: 'Closure & Trait Call Soundness (cloCase & cloProgress)',
    explainFi:
      'Todistaa, että sulkeuman tai piirreolion (Val.pkg) kutsuminen rajapinnan läpi avautuu turvalliseksi kutsuksi, jossa sulkeuman ympäristö ja nimikaappaukset noudattavat efektirajojaan.',
    explainEn:
      'Proves that invoking a closure or trait-object package (Val.pkg) unpacks the owned environment and by-name captures safely within their effect bounds.',
    deps: ['Inv', 'CallT'],
  },
  {
    id: 'preserve',
    name: 'preserve',
    module: 'Preservation',
    kind: 'theorem',
    tier: 4,
    titleFi: 'Preservation (Säilyvyyslause)',
    titleEn: 'Preservation Theorem (preserve)',
    explainFi:
      'Jos konfiguraatio on hyvin tyypitetty (StmtT) ja täyttää invariantin (Inv), niin minkä tahansa suoritusaskeleen (Step) jälkeen uusi tila on edelleen hyvin tyypitetty jossakin kontekstissa Γ\' ja täyttää invariantin Inv.',
    explainEn:
      'If a configuration is well-typed (StmtT) and satisfies Inv, then after any normal step (Step P m s (.ok m\' s\')), the new configuration is well-typed in some Γ\' and satisfies Inv.',
    deps: ['Inv', 'callCase', 'cloCase', 'Step'],
  },
  {
    id: 'progress',
    name: 'progress',
    module: 'Progress',
    kind: 'theorem',
    tier: 4,
    titleFi: 'Progress (Etenemislause)',
    titleEn: 'Progress Theorem (progress)',
    explainFi:
      'Hyvin tyypitetty konfiguraatio, joka täyttää invariantin Inv, on joko valmis (s = .skip) tai pystyy ottamaan suorituksen askeleen (∃ r, Step P m s r). Se ei ole koskaan Stuck.',
    explainEn:
      'Every well-typed configuration satisfying Inv is either finished (s = .skip) or can take a step (∃ r, Step P m s r). It is never Stuck.',
    deps: ['Inv', 'Step', 'cloCase'],
  },
  {
    id: 'reach_ok',
    name: 'reach_ok',
    module: 'Soundness',
    kind: 'theorem',
    tier: 4,
    titleFi: 'Saavutettavien tilojen eheys (reach_ok & reach_panic)',
    titleEn: 'Reachable State Invariant (reach_ok & reach_panic)',
    explainFi:
      'Induktiolla yli moniaskelisen suorituksen (Steps): jokainen alkutilasta saavutettava tila säilyttää invariantin Inv, ja jokainen paniikkiin päättyvä suoritus purkaa koko pinon jättäen tyhjän muuttujavaraston.',
    explainEn:
      'By induction over multi-step execution (Steps): every reachable normal state preserves Inv, and every uncaught panic unwinds the entire spine leaving an empty variable store.',
    deps: ['preserve', 'panic_unwind'],
  },
  {
    id: 'memory_safe',
    name: 'memory_safe',
    module: 'Soundness',
    kind: 'theorem',
    tier: 5,
    titleFi: 'Muistiturvallisuus (A2.memory_safe & A1.memory_safe)',
    titleEn: 'Memory Safety Theorem (A2.memory_safe & A1.memory_safe)',
    explainFi:
      'PÄÄLAUSE 1: Jokainen hyvin tyypitetty lähdekielinen ohjelma, joka käynnistetään tyhjästä muistista (emptyMem), ei koskaan saavuta jumiutunutta tilaa (¬ Stuck P m\' s\') — ei use-after-free-, double-free- tai roikkuvan näkymän virheitä.',
    explainEn:
      'MAIN THEOREM 1: Every well-typed source program run from the empty store (emptyMem) never reaches a stuck configuration (¬ Stuck P m\' s\') — zero use-after-free, double-free, or dangling view reads.',
    deps: ['reach_ok', 'progress'],
  },
  {
    id: 'no_leak_end',
    name: 'no_leak_end',
    module: 'Soundness',
    kind: 'theorem',
    tier: 5,
    titleFi: 'Vuodottomuus valmistuessa (A2.no_leak_end)',
    titleEn: 'Zero Leaks on Normal Exit (A2.no_leak_end)',
    explainFi:
      'PÄÄLAUSE 2: Kun hyvin tyypitetty ohjelma suorittuu loppuun (.ok m\' .skip), jokainen sen suorituksen aikana varaama keko-osoite on vapautettu: ∀ i, m\'.alloc i = false.',
    explainEn:
      'MAIN THEOREM 2: When a well-typed program finishes (.ok m\' .skip), every heap allocation it ever made has been freed: ∀ i, m\'.alloc i = false.',
    deps: ['reach_ok', 'Covers'],
  },
  {
    id: 'no_leak_panic',
    name: 'no_leak_panic',
    module: 'Soundness',
    kind: 'theorem',
    tier: 5,
    titleFi: 'Vuodottomuus paniikissa (A2.no_leak_panic)',
    titleEn: 'Zero Leaks on Uncaught Panic (A2.no_leak_panic)',
    explainFi:
      'PÄÄLAUSE 3: Kun hyvin tyypitetty ohjelma päättyy kaappaamattomaan paniikkiin (.panic m\'), pinon purkaminen (drop journal) on vapauttanut jokaisen varauksen: ∀ i, m\'.alloc i = false.',
    explainEn:
      'MAIN THEOREM 3: When a well-typed program terminates via an uncaught panic (.panic m\'), unwinding has freed every heap allocation: ∀ i, m\'.alloc i = false.',
    deps: ['reach_ok', 'panic_unwind', 'Covers'],
  },
];

const a1Modules = buildPhaseData('A1');
const a2Modules = buildPhaseData('A2');
const rules = parseRulesMd();
const holes = parseHolesCorpus();

const stats = {
  leanToolchain: readFileSync(join(FORMAL_DIR, 'lean-toolchain'), 'utf8').trim(),
  axioms: ['propext', 'Classical.choice', 'Quot.sound'],
  sorryCount: 0,
  a1: {
    modules: a1Modules.length,
    lines: a1Modules.reduce((acc, m) => acc + m.lineCount, 0),
    theorems: a1Modules.reduce((acc, m) => acc + m.counts.theorem, 0),
    defs: a1Modules.reduce((acc, m) => acc + m.counts.def, 0),
    inductives: a1Modules.reduce((acc, m) => acc + m.counts.inductive + m.counts.structure, 0),
    totalDecls: a1Modules.reduce((acc, m) => acc + m.counts.total, 0),
  },
  a2: {
    modules: a2Modules.length,
    lines: a2Modules.reduce((acc, m) => acc + m.lineCount, 0),
    theorems: a2Modules.reduce((acc, m) => acc + m.counts.theorem, 0),
    defs: a2Modules.reduce((acc, m) => acc + m.counts.def, 0),
    inductives: a2Modules.reduce((acc, m) => acc + m.counts.inductive + m.counts.structure, 0),
    totalDecls: a2Modules.reduce((acc, m) => acc + m.counts.total, 0),
  },
  holesCount: holes.length,
  holesByPhase: {
    A1: holes.filter((h) => h.phase === 'A1').length,
    A2: holes.filter((h) => h.phase === 'A2').length,
    A3: holes.filter((h) => h.phase === 'A3').length,
    B: holes.filter((h) => h.phase === 'B').length,
  },
};

function stripModuleDecls(modules) {
  return modules.map(({ decls, ...rest }) => ({
    ...rest,
    declNames: decls.slice(0, 12).map((d) => d.name),
  }));
}

// Extract the landmark declarations from A2 for instant SSR rendering before formal-decls.json loads
const blueprintIds = new Set(BLUEPRINT_NODES.map((n) => n.name));
const initialDecls = {};
for (const mod of a2Modules) {
  for (const d of mod.decls) {
    if (blueprintIds.has(d.name) || mod.name === 'Soundness') {
      initialDecls[d.name] = d;
    }
  }
}

const tsPayload = {
  stats,
  blueprintNodes: BLUEPRINT_NODES,
  initialDecls,
  rules,
  holes,
  modules: {
    A2: stripModuleDecls(a2Modules),
    A1: stripModuleDecls(a1Modules),
  },
};

const jsonPayload = {
  A2: a2Modules,
  A1: a1Modules,
};

const typesHeader = `// Generated by webdocs/scripts/gen-formal-data.mjs — do not edit by hand.

export interface FormalDecl {
  id: string;
  name: string;
  phase: 'A1' | 'A2';
  module: string;
  kind: 'theorem' | 'def' | 'abbrev' | 'inductive' | 'structure';
  startLine: number;
  endLine: number;
  lineCount: number;
  doc: string;
  signature: string;
  code: string;
  truncated: boolean;
  deps: string[];
  usedBy: string[];
}

export interface FormalModuleSummary {
  id: string;
  name: string;
  phase: 'A1' | 'A2';
  path: string;
  lineCount: number;
  imports: string[];
  doc: string;
  layer: number;
  category: string;
  summaryFi: string;
  summaryEn: string;
  counts: {
    theorem: number;
    def: number;
    inductive: number;
    structure: number;
    total: number;
  };
  declNames: string[];
}

export interface FormalModuleFull extends Omit<FormalModuleSummary, 'declNames'> {
  decls: FormalDecl[];
}

export interface BlueprintNode {
  id: string;
  name: string;
  module: string;
  kind: string;
  tier: number;
  titleFi: string;
  titleEn: string;
  explainFi: string;
  explainEn: string;
  deps: string[];
}

export interface FormalRuleRow {
  section: string;
  rule: string;
  phase: string;
  formalRule: string;
  status: string;
}

export interface HoleProbe {
  probe: string;
  id: string;
  rule: string;
  phase: string;
  note: string;
  nurlc: string;
  code: string;
}

export interface FormalData {
  stats: {
    leanToolchain: string;
    axioms: string[];
    sorryCount: number;
    a1: { modules: number; lines: number; theorems: number; defs: number; inductives: number; totalDecls: number };
    a2: { modules: number; lines: number; theorems: number; defs: number; inductives: number; totalDecls: number };
    holesCount: number;
    holesByPhase: { A1: number; A2: number; A3: number; B: number };
  };
  blueprintNodes: BlueprintNode[];
  initialDecls: Record<string, FormalDecl>;
  rules: FormalRuleRow[];
  holes: HoleProbe[];
  modules: {
    A2: FormalModuleSummary[];
    A1: FormalModuleSummary[];
  };
}
`;

writeFileSync(OUTPUT_TS, `${typesHeader}\nexport const formalData: FormalData = ${JSON.stringify(tsPayload)};\n`);
writeFileSync(OUTPUT_JSON, JSON.stringify(jsonPayload));

console.log(
  `formal data → ${OUTPUT_TS} & ${OUTPUT_JSON}\n` +
    `  A2: ${stats.a2.modules} modules, ${stats.a2.lines.toLocaleString('en-US')} lines, ${stats.a2.theorems} theorems, ${stats.a2.totalDecls} total declarations\n` +
    `  A1: ${stats.a1.modules} modules, ${stats.a1.lines.toLocaleString('en-US')} lines, ${stats.a1.theorems} theorems, ${stats.a1.totalDecls} total declarations\n` +
    `  Holes: ${stats.holesCount} soundness probes (A1=${stats.holesByPhase.A1}, A2=${stats.holesByPhase.A2}, A3=${stats.holesByPhase.A3}, B=${stats.holesByPhase.B})`
);
