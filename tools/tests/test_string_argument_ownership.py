#!/usr/bin/env python3
"""String argument lifetime must survive declaration order and address casts."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class StringArgumentOwnershipTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='nurl-string-arguments-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.compiler = Path(os.environ.get('NURLC', ROOT / 'build/nurlc')).resolve()
        cls.clang = os.environ.get('CLANG', 'clang')
        cls.sanitizers = ['-fsanitize=address,undefined', '-fno-sanitize-recover=all']
        cls.runtime = cls.directory / 'runtime.o'
        run = subprocess.run(
            [cls.clang, '-O1', '-g', *cls.sanitizers, '-I', str(ROOT),
             '-c', str(ROOT / 'stdlib/runtime.c'), '-o', str(cls.runtime)],
            capture_output=True, timeout=120)
        if run.returncode:
            raise RuntimeError(run.stderr.decode(errors='replace'))

    def run_source(self, source, expected, flags=()):
        path = self.directory / 'input.nu'
        ir = self.directory / 'input.ll'
        binary = self.directory / 'program'
        path.write_text(source)
        env = {**os.environ, 'NURL_STDLIB': str(ROOT), 'DEBUGINFOD_URLS': '',
               'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
               'LSAN_OPTIONS': 'use_stacks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'}
        compile_run = subprocess.run(
            [str(self.compiler), '--sanitize-address', *flags, str(path)],
            cwd=ROOT, env=env, capture_output=True, timeout=60)
        self.assertEqual(compile_run.returncode, 0,
                         compile_run.stderr.decode(errors='replace'))
        self.assertNotIn(b'Sanitizer', compile_run.stderr)
        ir.write_bytes(compile_run.stdout)
        link = subprocess.run(
            [self.clang, '-O1', '-g', *self.sanitizers, str(ir), str(self.runtime),
             '-lm', '-lpthread', '-ldl', '-o', str(binary)],
            capture_output=True, timeout=60)
        self.assertEqual(link.returncode, 0, link.stderr.decode(errors='replace'))
        run = subprocess.run([str(binary)], env=env, capture_output=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        self.assertEqual(run.stdout, expected.encode())

    def test_forward_consumers_on_normal_return_and_panic(self):
        self.run_source(
            (ROOT / 'compiler/tests/recover_forward_consumer.nu').read_text(),
            'normal argument\nstill alive\n')

    def test_dynamic_return_proof_survives_forward_chains_and_defer(self):
        for tail in ['^ ( leaf fresh )', '( leaf fresh )']:
            for fresh in ['T', 'F']:
                with self.subTest(tail=tail, fresh=fresh):
                    self.run_source("""$ `stdlib/core/string.nu`
@ relay b fresh → s {
    ; { ( clobber ) }
    """ + tail + """
}
@ main → i {
    : s value ( relay """ + fresh + """ )
    ( nurl_println value )
    ^ 0
}
@ leaf b fresh → s {
    ? fresh { ^ ( nurl_str_cat `live` ` value` ) } {}
    ^ `live value`
}
@ clobber → v { : s value ( noise ) }
@ noise → s { ^ `borrowed noise` }
""", 'live value\n')

    def test_return_proofs_are_isolated_between_threads(self):
        probe = self.directory / 'proof_threads.c'
        binary = self.directory / 'proof_threads'
        probe.write_text(r"""
#include <assert.h>
#include <pthread.h>
extern long long nurl_ret_owned_get(void);
extern void nurl_ret_owned_set(long long);
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static int phase;
static void *worker(void *unused) {
    pthread_mutex_lock(&mutex);
    nurl_ret_owned_set(0);
    phase = 1;
    pthread_cond_broadcast(&changed);
    while (phase != 2) pthread_cond_wait(&changed, &mutex);
    assert(nurl_ret_owned_get() == 0);
    nurl_ret_owned_set(0);
    phase = 3;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&mutex);
    return 0;
}
int main(void) {
    pthread_t thread;
    assert(pthread_create(&thread, 0, worker, 0) == 0);
    pthread_mutex_lock(&mutex);
    while (phase != 1) pthread_cond_wait(&changed, &mutex);
    nurl_ret_owned_set(1);
    phase = 2;
    pthread_cond_broadcast(&changed);
    while (phase != 3) pthread_cond_wait(&changed, &mutex);
    assert(nurl_ret_owned_get() == 1);
    pthread_mutex_unlock(&mutex);
    assert(pthread_join(thread, 0) == 0);
    return 0;
}
""")
        link = subprocess.run([self.clang, '-O1', *self.sanitizers,
            str(probe), str(self.runtime), '-lm', '-lpthread', '-ldl',
            '-o', str(binary)], capture_output=True, timeout=60)
        self.assertEqual(link.returncode, 0, link.stderr.decode(errors='replace'))
        run = subprocess.run([str(binary)], capture_output=True, timeout=30,
            env={**os.environ, 'DEBUGINFOD_URLS': '',
                 'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1',
                 'UBSAN_OPTIONS': 'halt_on_error=1'})
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
        self.assertEqual(run.stderr, b'')

    def test_indirect_string_returns_publish_their_own_proof(self):
        for tail in ['^ ( nurl_str_cat `live` ` value` )',
                     '( nurl_str_cat `live` ` value` )', '^ `live value`',
                     '`live value`']:
            for through_parameter in [False, True]:
                with self.subTest(tail=tail, through_parameter=through_parameter):
                    invoke = '( apply callback )' if through_parameter else '( callback )'
                    self.run_source(r"""$ `stdlib/core/string.nu`
@ main → i {
    : callback \ → s { """ + tail + """ }
    : s value """ + invoke + """
    ( nurl_println value )
    ^ 0
}
@ apply ( @ s ) callback → s { ^ ( callback ) }
""", 'live value\n')

    def test_bound_dynamic_returns_preserve_owner_and_opaque_borrow(self):
        for explicit in [False, True]:
            for fresh in ['T', 'F']:
                with self.subTest(explicit=explicit, fresh=fresh):
                    tail = '^ value' if explicit else 'value'
                    self.run_source("""$ `stdlib/core/string.nu`
@ relay b fresh → s { : s value ( leaf fresh ) """ + tail + """ }
@ main → i {
    : s value ( relay """ + fresh + """ )
    """ + ('( nurl_println value )' if fresh == 'T' else
             '( nurl_println_int # i value )') + """
    ^ 0
}
@ leaf b fresh → s {
    ? fresh { ^ ( nurl_str_cat `live` ` value` ) } {}
    ^ # s 42
}
""", 'live value\n' if fresh == 'T' else '42\n')

    def test_guarded_store_in_inner_block_survives_function_exit(self):
        for flags in [(), ('--no-borrowck',)]:
            with self.subTest(flags=flags):
                self.run_source("""$ `stdlib/core/string.nu`
@ store *i slot → v {
    : s value ( later )
    ? T { = . slot 0 # i value } {}
}
@ main → i {
    : *i slot # *i ( nurl_alloc 8 )
    ( store slot )
    : i address . slot 0
    ( nurl_println # s address )
    ( nurl_free # s address )
    ( nurl_free # s slot )
    ^ 0
}
@ later → s { ^ ( nurl_str_cat `live` ` value` ) }
""", 'live value\n', flags)

    def test_guarded_return_cleans_the_nonreturning_path(self):
        for fresh in ['T', 'F']:
            with self.subTest(fresh=fresh):
                self.run_source("""$ `stdlib/core/string.nu`
@ choose b fresh → s {
    : s value ( later fresh )
    ? != 0 ( nurl_str_len value ) { ^ value } {}
    ^ ( nurl_str_cat `live` ` value` )
}
@ main → i {
    : s result ( choose """ + fresh + """ )
    ( nurl_println result )
    ^ 0
}
@ later b fresh → s {
    ? fresh { ^ ( nurl_str_cat `live` ` value` ) } {}
    ^ ( nurl_str_cat `` `` )
}
""", 'live value\n')

    def test_guarded_binding_is_reclaimed_on_panic(self):
        self.run_source(r"""$ `stdlib/std/panic.nu`
@ main → i {
    ?? ( recover \ → v {
        : s value ( later )
        ( nurl_println value )
        ( panic `expected` )
    } ) {
        T _ → { ^ 2 }
        F info → { ( panic_info_free info ) }
    }
    ^ 0
}
@ later → s { : s value ( leaf ) ^ value }
@ leaf → s { ^ ( nurl_str_cat `live` ` value` ) }
""", 'live value\n')

    def test_guarded_escaping_binding_outlives_inner_panic(self):
        self.run_source(r"""$ `stdlib/std/panic.nu`
@ main → i {
    : *i saved_slot # *i ( nurl_alloc 8 )
    ?? ( recover \ → v {
        : s value ( later )
        = . saved_slot 0 # i value
        ( panic `expected` )
    } ) {
        T _ → { ^ 2 }
        F info → { ( panic_info_free info ) }
    }
    : i saved . saved_slot 0
    ( nurl_println # s saved )
    ( nurl_free # s saved )
    ( nurl_free # s saved_slot )
    ^ 0
}
@ later → s { : s value ( leaf ) ^ value }
@ leaf → s { ^ ( nurl_str_cat `live` ` value` ) }
""", 'live value\n')

    def test_returned_address_remains_live_in_both_declaration_orders(self):
        main = '''@ main → i {
    : i address ( address_of ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println # s address )
    ( nurl_free # s address )
    ^ 0
}
'''
        # Direct and named casts must retain the same buffer. The integer is
        # used as an address after the callee returns, not as a scalar result.
        for body in ['^ # i value', ': i address # i value ^ address',
                     '# i value', ': i address # i value address',
                     '^ + # i value 0', '^ ^^ # i value 0',
                     '^ | # i value 0', '^ & # i value -1',
                     '^ << # i value 0', '^ ~ ~ # i value',
                     '^ ? T # i value 0', '^ ? F 0 { # i value }',
                     '^ { : i address # i value address }',
                     '^ ?? T { T → # i value F → 0 }',
                     ': ~ i address 0 = address # i value ^ address']:
            helper = f'@ address_of s value → i {{ {body} }}\n'
            for forward in [False, True]:
                for flags in [(), ('--no-borrowck',)]:
                    with self.subTest(body=body, forward=forward, flags=flags):
                        source = '$ `stdlib/core/string.nu`\n'
                        source += main + helper if forward else helper + main
                        self.run_source(source, 'still alive\n', flags)

    def test_scalar_conversion_does_not_claim_argument_address(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ length s value → i { ^ # i ( nurl_str_len value ) }
@ main → i {
    ( nurl_println_int ( length ( nurl_str_cat `still` ` alive` ) ) )
    ^ 0
}
''', '11\n')

    def test_owned_copy_does_not_retain_the_original_address(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ copy s value → s { : s result ( nurl_str_cat value `` ) ^ result }
@ main → i {
    : s result ( copy ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println result )
    ^ 0
}
''', 'still alive\n')

    def test_mutable_string_alias_still_returns_the_borrowed_address(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ alias s value → s { : ~ s result value ^ result }
@ main → i {
    : s result ( alias ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println result )
    ( nurl_free result )
    ^ 0
}
''', 'still alive\n')

    def test_named_argument_obeys_the_same_lifetime_proof(self):
        for forward in [False, True]:
            with self.subTest(forward=forward):
                helper = '@ address_of s value → i { ^ # i value }\n'
                main = '''@ main → i {
    : i address ( address_of value : ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println # s address )
    ( nurl_free # s address )
    ^ 0
}
'''
                self.run_source('$ `stdlib/core/string.nu`\n' +
                                (main + helper if forward else helper + main),
                                'still alive\n')

    def test_forward_inferred_sink_is_not_freed_again_by_named_call(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ main → i {
    ( consume ( nurl_str_cat `positional` ` owner` ) )
    ( consume value : ( nurl_str_cat `named` ` owner` ) )
    ^ 0
}
@ consume s value → v { ( nurl_free value ) }
''', '')

    def test_address_provenance_survives_a_forward_call_inside_a_cast(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ address_of s value → i { ^ # i ( identity_later value ) }
@ identity_later s value → s { ^ value }
@ main → i {
    : i address ( address_of ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println # s address )
    ( nurl_free # s address )
    ^ 0
}
''', 'still alive\n')

    def test_loop_carried_address_reaches_the_return_summary(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ address_of s value → i {
    : ~ i previous 0
    : ~ i current 0
    : ~ i iteration 0
    ~ < iteration 2 {
        = previous current
        = current # i value
        = iteration + iteration 1
    }
    ^ previous
}
@ main → i {
    : i address ( address_of ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println # s address )
    ( nurl_free # s address )
    ^ 0
}
''', 'still alive\n')

    def test_nonfirst_argument_and_large_arity_preserve_only_its_address(self):
        for position in (1, 69):
            for flags in ((), ('--no-borrowck',)):
                with self.subTest(position=position, flags=flags):
                    params = ' '.join(f'i p{k}' for k in range(position))
                    zeros = ' '.join('0' for _ in range(position))
                    self.run_source(f'''$ `stdlib/core/string.nu`
@ main → i {{
    : i address ( address_of {zeros} ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println # s address )
    ( nurl_free # s address )
    ^ 0
}}
@ address_of {params} s value → i {{ ^ # i ( later value ) }}
@ later s value → s {{ ^ value }}
''', 'still alive\n', flags)

    def test_return_dependency_chain_has_no_round_limit(self):
        functions = ''.join(
            f'@ link{k} s value → i {{ ^ ( link{k+1} value ) }}\n'
            for k in range(80))
        functions += '@ link80 s value → i { ^ # i value }\n'
        self.run_source('''$ `stdlib/core/string.nu`
@ main → i {
    : i address ( link0 ( nurl_str_cat `still` ` alive` ) )
    ( nurl_println # s address )
    ( nurl_free # s address )
    ^ 0
}
''' + functions, 'still alive\n')

    def test_consumption_through_alias_and_cast(self):
        for flags in ((), ('--no-borrowck',)):
            with self.subTest(flags=flags):
                self.run_source('''$ `stdlib/core/string.nu`
@ main → i {
    ( consume 0 ( nurl_str_cat `one` ` owner` ) )
    ^ 0
}
@ consume i ignored s value → v {
    : i address # i value
    ( release address )
}
@ release i address → v { ( nurl_free # s address ) }
''', '', flags)

    def test_freeing_closure_environment_does_not_consume_captures(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ run ( @ v ) action → i {
    : *u function # *u action 0
    : *u environment # *u action 1
    : i result ( nurl_recover function environment )
    ( nurl_free # s environment )
    ^ result
}
@ main → i {
    : s text ( nurl_str_cat `still` ` alive` )
    : i result ( run \\ → v { ( nurl_println text ) } )
    ( nurl_println text )
    ^ result
}
''', 'still alive\nstill alive\n')


    def test_forward_owned_results_used_directly_as_arguments(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ main → i {
    ( nurl_println ( produce ) )
    ( print_value value : ( produce ) )
    ( consume ( produce ) )
    ^ 0
}
@ produce → s { ^ ( nurl_str_cat `still` ` alive` ) }
@ print_value s value → v { ( nurl_println value ) }
@ consume s value → v { ( nurl_free value ) }
''', 'still alive\nstill alive\n')

    def test_closure_parameter_consumption_is_scoped_to_the_closure(self):
        self.run_source('''$ `stdlib/core/string.nu`
@ inspect s value → v {
    : ( @ v s ) consume \\ s item → v { ( nurl_free item ) }
    ( consume ( nurl_alloc 8 ) )
    ( nurl_println value )
}
@ main → i {
    : s value ( nurl_str_cat `still` ` alive` )
    ( inspect value )
    ( nurl_println value )
    ^ 0
}
''', 'still alive\nstill alive\n')


    def test_indirect_stores_retain_argument_buffers(self):
        for store in ('= . slot 0 value',
                      '( nurl_poke # s slot 0 # i value )'):
            for forward in (False, True):
                for flags in ((), ('--no-borrowck',)):
                    with self.subTest(store=store, forward=forward, flags=flags):
                        helper = f'@ keep *s slot s value → v {{ {store} }}\n'
                        main = '''@ main → i {
    : *s slot # *s ( nurl_alloc 8 )
    ( keep slot ( nurl_str_cat `still` ` alive` ) )
    : s value . slot 0
    ( nurl_println value )
    ( nurl_free value )
    ( nurl_free # s slot )
    ^ 0
}
'''
                        self.run_source('$ `stdlib/core/string.nu`\n' +
                                        (main + helper if forward else helper + main),
                                        'still alive\n', flags)

    def test_vector_owns_the_inserted_string_temporary(self):
        self.run_source('''$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
@ main → i {
    : ( Vec s ) values ( vec_new [s] )
    ( vec_push [s] values ( nurl_str_cat `still` ` alive` ) )
    ?? ( vec_get [s] values 0 ) {
        T value → { ( nurl_println value ) ( nurl_free value ) }
        F → { ^ 1 }
    }
    ( vec_free [s] values )
    ^ 0
}
''', 'still alive\n')



if __name__ == '__main__':
    unittest.main(verbosity=2)
