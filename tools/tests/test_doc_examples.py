#!/usr/bin/env python3
"""Controls for tools/check_doc_examples.py.

The wrapping rules are checked on their own (no compiler needed); the
end-to-end cases compile throwaway Markdown with build/nurlc and are
skipped when it has not been built.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tools/check_doc_examples.py'
sys.path.insert(0, str(ROOT / 'tools'))
import check_doc_examples as cde  # noqa: E402

NURLC = ROOT / 'build/nurlc'


def seg(*lines):
    return [(l, ('blk', n)) for n, l in enumerate(lines)]


class WrapTest(unittest.TestCase):
    def text(self, *segs, **kw):
        return [l for l, _ in cde.wrap(list(segs), **kw)]

    def test_program_with_main_is_left_alone(self):
        s = seg('@ main → i {', '    ^ 0', '}')
        self.assertEqual(self.text(s), ['@ main → i {', '    ^ 0', '}'])

    def test_statements_go_into_main_and_imports_are_hoisted(self):
        out = self.text(seg(': i n 1', '$ `stdlib/core/vec.nu`', '( nurl_println_int n )'))
        self.assertEqual(out[0], '$ `stdlib/core/vec.nu`')
        self.assertEqual(out[1], '@ main → i {')
        self.assertEqual(out[-2:], ['    ^ 0', '}'])

    def test_globals_between_declarations_stay_top_level(self):
        out = self.text(seg(': ~ i g 0', '@ f → v {', '    = g 1', '}', '( f )'))
        self.assertEqual(out[:4], [': ~ i g 0', '@ f → v {', '    = g 1', '}'])
        self.assertIn('    ( f )', out)

    def test_bindings_after_the_last_declaration_are_statements(self):
        out = self.text(seg('@ f i x → i { ^ x }', ': i y ( f 1 )'))
        self.assertEqual(out[0], '@ f i x → i { ^ x }')
        self.assertIn('    : i y ( f 1 )', out)

    def test_each_segment_splits_on_its_own(self):
        # A prelude binding is a statement even though the block declares
        # a function after it.
        out = self.text(seg(': i n 2'), seg('@ f → v {}', '( f )'))
        self.assertEqual(out[0], '@ f → v {}')
        self.assertEqual(out[2], '    : i n 2')

    def test_a_trailing_return_gets_no_extra_return(self):
        out = self.text(seg(': i n 1', '^ n'))
        self.assertEqual(out[-2:], ['    ^ n', '}'])

    def test_params_make_a_function_of_the_snippet(self):
        out = self.text(seg('( g x )'), params='i x')
        self.assertEqual(out[0], '@ __doctest_snippet i x → v {')
        self.assertEqual(out[-1], '}')
        self.assertNotIn('    ^ 0', out)

    def test_unsafe(self):
        self.assertEqual(self.text(seg('( g )'), unsafe=True)[0], 'unsafe @ main → i {')


class ScanTest(unittest.TestCase):
    def scan(self, text, strict=True):
        with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False, dir=ROOT / 'build') as f:
            f.write(text)
        self.addCleanup(os.unlink, f.name)
        return cde.scan(os.path.relpath(f.name, ROOT), strict)

    def test_untagged_fence_is_a_problem_in_strict_files(self):
        _, problems = self.scan('x\n```\n: i n 0\n```\n')
        self.assertEqual(len(problems), 1)
        self.assertIn('untagged fence', problems[0])
        _, problems = self.scan('x\n```\n: i n 0\n```\n', strict=False)
        self.assertEqual(problems, [])

    def test_attributes_and_prelude(self):
        blocks, _ = self.scan('<!-- doctest-prelude\n: i k 1\n-->\n'
                              '```nurl expect-error="a b" expect-error="c" params="i x"\n'
                              '( f )\n```\n')
        b, = blocks
        self.assertEqual(b.expect_errors, ['a b', 'c'])
        self.assertEqual(b.attrs['params'], 'i x')
        self.assertEqual([l.strip() for l in b.prelude if l.strip()], [': i k 1'])

    def test_a_backtick_in_the_info_string_is_a_problem(self):
        _, problems = self.scan('```nurl ignore="see `x`"\n( f )\n```\n')
        self.assertTrue(any('backtick' in p for p in problems))


class JudgeTest(unittest.TestCase):
    def test_a_diagnostic_without_a_column_fails_the_block(self):
        # `file:line: error:` is the shape the deferred supertrait check
        # used to print; it is never mapped onto the block, so even an
        # error the annotation expects must not pass in that form.
        blk = cde.Block('x.md', 1, 'expect-error="supertrait"', [], [], 0)
        diags = [('error', "type 'i' … not its supertrait 'R'", 'no-column')]
        self.assertIn('without a column', cde.judge(blk, 1, diags))

    def test_the_column_is_required_to_map_a_diagnostic(self):
        self.assertIsNone(cde.LOC.match('a.nu:3: error: x'))
        self.assertIsNotNone(cde.NO_COL.match('a.nu:3: error: x'))
        self.assertIsNotNone(cde.LOC.match('a.nu:3:7: error: x'))


@unittest.skipUnless(NURLC.exists(), 'build/nurlc not built')
class EndToEndTest(unittest.TestCase):
    def run_on(self, text):
        with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False, dir=ROOT / 'build') as f:
            f.write(text)
        self.addCleanup(os.unlink, f.name)
        return subprocess.run([sys.executable, str(SCRIPT), f.name], cwd=ROOT,
                              capture_output=True, text=True, timeout=120)

    MOVED = ('$ `stdlib/core/vec.nu`\n\n'
             ': ( Vec i ) v ( vec_new [i] )\n'
             '( vec_free [i] v )\n'
             '( nurl_println_int ( vec_len [i] v ) )\n')

    def test_a_good_snippet_passes(self):
        r = self.run_on('```nurl\n$ `stdlib/core/vec.nu`\n\n'
                        ': ( Vec i ) v ( vec_new [i] )\n( vec_push [i] v 1 )\n```\n')
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn('PASS 1 · FAIL 0', r.stdout)

    def test_a_missing_import_fails_at_its_markdown_line(self):
        r = self.run_on('text\n\n```nurl\n: ( Vec i ) v ( vec_new [i] )\n```\n')
        self.assertEqual(r.returncode, 1)
        self.assertRegex(r.stdout, r'\.md:3: FAIL — does not compile')
        self.assertRegex(r.stdout, r'\.md:4:\d+: error: unknown generic type')

    def test_expected_error_matches(self):
        r = self.run_on('```nurl expect-error="use of moved value \'v\'"\n' + self.MOVED + '```\n')
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_expected_error_with_the_wrong_class_fails(self):
        r = self.run_on('```nurl expect-error="cannot mutate"\n' + self.MOVED + '```\n')
        self.assertEqual(r.returncode, 1)
        self.assertIn('an error the annotation does not expect', r.stdout)

    def test_expected_error_that_compiles_fails(self):
        r = self.run_on('```nurl expect-error="use of moved value"\n: i n 1\n```\n')
        self.assertEqual(r.returncode, 1)
        self.assertIn('expected a compile error, but the block compiled', r.stdout)

    def test_ignore_needs_a_reason(self):
        r = self.run_on('```nurl ignore\n( nope )\n```\n')
        self.assertEqual(r.returncode, 1)
        self.assertIn('needs a reason', r.stdout)
        r = self.run_on('```nurl ignore="grammar sketch"\n( nope )\n```\n')
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn('IGNORED 1', r.stdout)

    def test_a_missing_supertrait_is_located_with_a_column(self):
        r = self.run_on('```nurl expect-error="not its supertrait"\n'
                        '% R [T] { @ r T s → i }\n'
                        '% S [T] : R { @ s T s → i }\n'
                        '% S i { @ s i x → i { ^ x } }\n```\n')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_continue_prepends_the_previous_block(self):
        r = self.run_on('```nurl\n@ twice i x → i { ^ * 2 x }\n```\n\n'
                        '```nurl continue\n: i y ( twice 4 )\n```\n')
        self.assertEqual(r.returncode, 0, r.stdout)


if __name__ == '__main__':
    unittest.main()
