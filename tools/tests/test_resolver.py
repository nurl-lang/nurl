#!/usr/bin/env python3
"""Resolve finite dependency graphs against an independent exhaustive oracle."""
import itertools
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[2]
REG = 'https://a.test/'


def version(number, deps=(), yanked=False):
    return {'version': f'{number}.0.0', 'checksum': f'hash-{number}', 'yanked': yanked,
            'deps': [{'name': name, 'req': req} for name, req in deps]}


def graph(indexes, roots):
    return {'indexes': {REG + name: {'name': name, 'versions': versions} for name, versions in indexes.items()},
            'roots': [{'name': name, 'req': req, 'registry': REG} for name, req in roots]}


def matches(req, value):
    # Deliberately tiny oracle grammar, independent of NURL's parser/solver.
    return req == '*' or int(req.removeprefix('^')) == int(value.split('.')[0])


def solutions(case):
    names = list(case['indexes'])
    domains = [[None] + [v for v in case['indexes'][name]['versions'] if not v.get('yanked')] for name in names]
    found = []
    for values in itertools.product(*domains):
        selected = dict(zip(names, values))
        queue = [(r['registry'] + r['name'], r['req']) for r in case['roots']]
        reached = set()
        valid = True
        for name, req in queue:
            candidate = selected.get(name)
            if candidate is None or not matches(req, candidate['version']):
                valid = False
                break
            if name not in reached:
                reached.add(name)
                registry = name.rsplit('/', 1)[0] + '/'
                queue += [(registry + d['name'], d['req']) for d in candidate.get('deps', [])]
        if valid and {name for name, candidate in selected.items() if candidate is not None} == reached:
            found.append({name: selected[name]['version'] for name in reached})
    return found


class ResolverTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-resolver-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.binary = os.environ.get('NURL_RESOLVER_PROBE')
        if not cls.binary:
            cls.binary = str(Path(cls.temp.name) / 'resolver')
            subprocess.run([str(ROOT / 'nurl.sh'), str(ROOT / 'tools/tests/fixtures/resolver_probe.nu'), cls.binary],
                           cwd=ROOT, capture_output=True, check=True, timeout=120)
        cls.env = {**os.environ, 'DEBUGINFOD_URLS': '',
                   # Ignore stale pointers in main's returned stack frame, as
                   # the corpus leak gate does; they must not hide leaked owners.
                   'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                   'LSAN_OPTIONS': 'use_stacks=0',
                   'UBSAN_OPTIONS': 'halt_on_error=1'}

    def resolve(self, case):
        run = subprocess.run([self.binary], input=json.dumps(case).encode(), env=self.env,
                             capture_output=True, timeout=15)
        self.assertIn(run.returncode, [0, 1], run.stderr)
        diagnostics = run.stderr.decode()
        self.assertNotIn('Sanitizer', diagnostics)
        self.assertNotIn('runtime error:', diagnostics)
        calls = diagnostics.splitlines()
        self.last_calls = calls
        self.assertTrue(all(c.startswith('FETCH ') for c in calls), diagnostics)
        self.assertEqual(len(calls), len(set(calls)), 'one fetch per identity per resolution')
        if run.returncode:
            self.assertTrue(run.stdout.startswith(b'Resolve'), run.stdout)
            self.last_error = run.stdout.decode().strip()
            return None
        data = tomllib.loads(run.stdout.decode())
        result = {p['source'].removeprefix('registry+') + p['name']: p['version'] for p in data.get('package', [])}
        self.assertEqual(len(result), len(data.get('package', [])))
        return result

    def test_downgrade_parent_to_resolve_conflicting_diamond(self):
        case = graph({'a': [version(1, [('c', '^1')]), version(2, [('c', '^2')])],
                      'b': [version(1, [('c', '^1')])], 'c': [version(1), version(2)]}, [('a', '*'), ('b', '*')])
        self.assertEqual(self.resolve(case), {REG+'a': '1.0.0', REG+'b': '1.0.0', REG+'c': '1.0.0'})

    def test_version_dependent_cycle_has_a_solution(self):
        case = graph({'a': [version(1), version(2, [('b', '^1')])],
                      'b': [version(1, [('a', '^1')])]}, [('a', '*')])
        self.assertEqual(self.resolve(case), {REG+'a': '1.0.0'})

    def test_missing_branch_dependency_can_be_abandoned(self):
        case = graph({'a': [version(1), version(2, [('absent', '*')])]}, [('a', '*')])
        self.assertEqual(self.resolve(case), {REG+'a': '1.0.0'})

    def test_cycles_are_checked_without_reselecting_assigned_nodes(self):
        for req in ['^1', '^2']:
            case = graph({'a': [version(1, [('b', '*')])], 'b': [version(1, [('a', req)])]}, [('a', '*')])
            possible = solutions(case)
            actual = self.resolve(case)
            self.assertTrue(actual in possible if possible else actual is None, (case, actual, possible))

    def test_transport_errors_abort_with_owned_context(self):
        for cause in ['503', '401', 'connect', 'timeout', 'tls', 'dns', 'invalid URL', 'transport']:
            with self.subTest(cause=cause):
                case = graph({'a': [version(1), version(2, [('b', '*')])]}, [('a', '*')])
                case['errors'] = {REG+'b': cause}
                self.assertIsNone(self.resolve(case))
                self.assertIn('ResolveFetch: '+REG+'index/b.json:', self.last_error)
                self.assertIn(cause, self.last_error)
                self.assertEqual(self.last_calls, ['FETCH '+REG+'a', 'FETCH '+REG+'b'])

    def test_small_graphs_match_exhaustive_oracle_and_input_permutations(self):
        rng = random.Random(4904)
        for number in range(400):
            names = ['a', 'b', 'c', 'd'][:rng.randrange(2, 5)]
            indexes = {name: [version(v, [(dep, rng.choice(['*', '^1', '^2']))
                                         for dep in names if rng.random() < .24], rng.random() < .1)
                              for v in [1, 2]] for name in names}
            case = graph(indexes, [(name, rng.choice(['*', '^1', '^2']))
                                   for name in rng.sample(names, rng.randrange(1, len(names) + 1))])
            with self.subTest(number=number):
                possible = solutions(case)
                actual = self.resolve(case)
                self.assertTrue(actual in possible if possible else actual is None, (case, actual, possible))
                case['roots'].reverse()
                for index in case['indexes'].values():
                    index['versions'].reverse()
                    for candidate in index['versions']:
                        candidate['deps'].reverse()
                self.assertEqual(self.resolve(case), actual)

    def test_empty_roots_duplicate_requirements_and_lazy_dependencies(self):
        case = graph({'a': [version(1, [('absent', '*')]), version(2)]}, [])
        self.assertEqual(self.resolve(case), {})
        self.assertEqual(self.last_calls, [])
        case['roots'] = [{'name': 'a', 'req': '*', 'registry': REG}] * 2
        self.assertEqual(self.resolve(case), {REG+'a': '2.0.0'})
        self.assertEqual(self.last_calls, ['FETCH '+REG+'a'])

    def test_semver_build_ties_and_duplicate_versions(self):
        a, b = version(1), version(1)
        a['version'], b['version'] = '1.0.0+a', '1.0.0+z'
        case = graph({'a': [a, b]}, [('a', '*')])
        self.assertEqual(self.resolve(case), {REG+'a': '1.0.0+z'})
        case['indexes'][REG+'a']['versions'].reverse()
        self.assertEqual(self.resolve(case), {REG+'a': '1.0.0+z'})
        case['indexes'][REG+'a']['versions'] = [a, a]
        self.assertIsNone(self.resolve(case))

    def test_invalid_metadata_and_root_requirements_fail(self):
        case = graph({'a': [version(1)]}, [('../escape', '*')])
        self.assertIsNone(self.resolve(case))
        self.assertEqual(self.last_error, 'ResolveBadPackage')
        self.assertEqual(self.last_calls, [])
        case = graph({'a': [version(1)]}, [('a', 'not-a-range')])
        self.assertIsNone(self.resolve(case))
        self.assertEqual(self.last_error, 'ResolveBadRequirement')
        self.assertEqual(self.last_calls, [])
        case = graph({'a': [version(1), version(2, [('b', 'not-a-range')])]}, [('a', '^1')])
        self.assertIsNone(self.resolve(case))
        self.assertEqual(self.last_error, 'ResolveBadIndex')
        case = graph({'a': [version(1), version(2, [('../escape', '*')])]}, [('a', '^1')])
        self.assertIsNone(self.resolve(case))
        self.assertEqual(self.last_error, 'ResolveBadIndex')

    def test_conflict_skips_unrelated_version_combinations(self):
        indexes = {f'a{i:02}': [version(1), version(2)] for i in range(28)}
        indexes['z'] = [version(1, [('w', '^1')]), version(2, [('w', '^2')])]
        indexes['w'] = [version(1, [('z', '^2')]), version(2, [('z', '^1')])]
        case = graph(indexes, [(f'a{i:02}', '*') for i in range(28)] + [('z', '*')])
        self.assertIsNone(self.resolve(case))
        # Adding redundant wildcard edges must not make those choices causes.
        for key, index in case['indexes'].items():
            if key.rsplit('/', 1)[1].startswith('a'):
                for candidate in index['versions']:
                    candidate['deps'] = [{'name': 'z', 'req': '*'}]
        self.assertIsNone(self.resolve(case))

    def test_long_chain_has_no_round_or_call_stack_limit(self):
        count = 600
        case = graph({f'p{i}': [version(1, [(f'p{i+1}', '*')] if i+1 < count else [])]
                      for i in range(count)}, [('p0', '*')])
        resolved = self.resolve(case)
        self.assertIsNotNone(resolved)
        self.assertEqual(resolved, {REG+f'p{i}': '1.0.0' for i in range(count)})


if __name__ == '__main__':
    unittest.main(verbosity=2)
