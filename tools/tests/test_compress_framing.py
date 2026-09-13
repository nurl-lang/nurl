#!/usr/bin/env python3
"""RFC 1950/1951/1952 framing and output bounds against Python zlib/gzip.

Build first with ./nurl.sh tools/compress_gate.nu build/compress_gate.
COMPRESS_GATE selects an instrumented driver for the same independent corpus.
"""
import gzip
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]


class CompressionFramingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get('COMPRESS_GATE', ROOT/'build/compress_gate')).resolve()
        cls.work = tempfile.TemporaryDirectory(prefix='nurl-compress-framing-')
        cls.addClassCleanup(cls.work.cleanup)
        cls.source = Path(cls.work.name)/'input'
        cls.output = Path(cls.work.name)/'output'

    def call(self, mode, data, cap=0):
        self.source.write_bytes(data)
        self.output.unlink(missing_ok=True)
        run = subprocess.run([str(self.binary), mode, str(self.source), str(self.output), str(cap)],
                             capture_output=True, timeout=10)
        self.assertIn(run.returncode, (0, 1), run.stderr)
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        return run, self.output.read_bytes() if self.output.exists() else None

    def decode(self, mode, data, expected, cap=0):
        run, got = self.call(mode, data, cap)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(got, expected)

    def reject(self, mode, data, cap=0, error=b'CompressData'):
        run, got = self.call(mode, data, cap)
        self.assertEqual(run.returncode, 1, (mode, data.hex(), got))
        self.assertEqual(run.stderr.strip(), error)
        self.assertIsNone(got)

    @staticmethod
    def raw(data, level=6, strategy=zlib.Z_DEFAULT_STRATEGY):
        encoder = zlib.compressobj(level, zlib.DEFLATED, -15, 8, strategy)
        return encoder.compress(data)+encoder.flush()

    def test_bidirectional_reference_corpus(self):
        rng = random.Random(1952)
        corpus = [b'', b'a', bytes(range(256)), b'a'*100000,
                  bytes(rng.randrange(256) for _ in range(70000)),
                  b'The quick brown fox crosses the boundary.\n'*2500]
        corpus += [bytes(rng.randrange(256) for _ in range(n)) for n in range(2, 65)]
        for index, data in enumerate(corpus):
            for level in (0, 1, 6, 9):
                with self.subTest(index=index, length=len(data), level=level):
                    self.decode('gzip', gzip.compress(data, compresslevel=level, mtime=0), data)
                    self.decode('zlib', zlib.compress(data, level), data)
                    self.decode('raw', self.raw(data, level), data)
            for mode, decoder in [('gzip', gzip.decompress), ('zlib', zlib.decompress)]:
                run, encoded = self.call(mode+'-encode', data)
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertGreater(len(encoded), 0)
                self.assertEqual(decoder(encoded), data)

    def test_optional_gzip_headers_and_header_crc(self):
        data = b'header options payload'*5
        original = gzip.compress(data, mtime=0)
        for flags in range(32):
            header = bytearray(original[:10])
            header[3] = flags
            if flags & 4:
                header.extend(struct.pack('<H', 5)+b'a\x00b\xffc')
            if flags & 8:
                header.extend(b'file.name\x00')
            if flags & 16:
                header.extend(b'member comment\x00')
            crc_offset = len(header)
            if flags & 2:
                header.extend(struct.pack('<H', zlib.crc32(header) & 0xffff))
            framed = bytes(header)+original[10:]
            self.assertEqual(gzip.decompress(framed), data)
            self.decode('gzip', framed, data)
            if flags & 2:
                broken = bytearray(framed)
                broken[crc_offset] ^= 1
                self.reject('gzip', broken)
            for end in range(len(header)):
                self.reject('gzip', framed[:end])

    def test_gzip_members_suffix_and_aggregate_cap(self):
        first = gzip.compress(b'first', mtime=0)
        empty = gzip.compress(b'', mtime=0)
        second = gzip.compress(b'second', mtime=0)
        self.decode('gzip', first+empty+second+empty, b'firstsecond')
        self.decode('gzip', first+empty, b'first', cap=5)
        self.decode('gzip', empty*20, b'', cap=1)
        self.decode('gzip', first+empty+second, b'firstsecond', cap=11)
        self.reject('gzip', first+empty+second, cap=10, error=b'CompressBufTooSmall')
        self.reject('gzip', first+second, cap=5, error=b'CompressBufTooSmall')
        for suffix in [b'\x00', b'garbage', b'\x1f\x8b', second[:-1]]:
            self.reject('gzip', first+suffix)
        self.reject('gzip', zlib.compress(b'wrong format'))

    def test_header_trailer_and_truncation_rejections(self):
        data = b'framed payload with a trailer'*8
        for mode, framed in [('gzip', gzip.compress(data, mtime=0)), ('zlib', zlib.compress(data))]:
            for end in range(len(framed)):
                self.reject(mode, framed[:end])
            trailer_len = 8 if mode == 'gzip' else 4
            for offset in range(len(framed)-trailer_len, len(framed)):
                broken = bytearray(framed)
                broken[offset] ^= 1
                self.reject(mode, broken)
            self.reject(mode, framed+b'garbage')
            # Same valid checksum is not sufficient when bytes are inserted
            # after BFINAL but before the trailer.
            self.reject(mode, framed[:-trailer_len]+b'junk'+framed[-trailer_len:])
        gz = gzip.compress(data, mtime=0)
        for offset, value in [(0, 0), (1, 0), (2, 7), (3, 32), (3, 64), (3, 128)]:
            broken = bytearray(gz)
            broken[offset] = value
            self.reject('gzip', broken)
        zl = zlib.compress(data)
        for cmf, flags in [(0x79, 0), (0x88, 0), (0x78, 0x20)]:
            flags += (-((cmf << 8) | flags)) % 31
            self.reject('zlib', bytes([cmf, flags])+zl[2:])
        self.reject('zlib', bytes([zl[0], zl[1]^1])+zl[2:])

    def test_output_cap_before_all_block_encodings(self):
        data = b'A'*70000
        for level, strategy in [(0, zlib.Z_DEFAULT_STRATEGY), (6, zlib.Z_FIXED),
                                (6, zlib.Z_DEFAULT_STRATEGY)]:
            raw = self.raw(data, level, strategy)
            streams = [('raw', raw),
                       ('gzip', bytes.fromhex('1f8b08000000000000ff')+raw+
                        struct.pack('<II', zlib.crc32(data), len(data))),
                       ('zlib', b'\x78\x9c'+raw+struct.pack('>I', zlib.adler32(data)))]
            for mode, framed in streams:
                self.decode(mode, framed, data, cap=len(data))
                for cap in [1, 258, 65535, len(data)-1]:
                    self.reject(mode, framed, cap, b'CompressBufTooSmall')
        # LEN/NLEN disagreement is malformed data, never an output limit.
        self.reject('raw', b'\x01\x01\x00\x00\x00A', 1)
        self.reject('raw', b'\x07')  # reserved BTYPE

    def test_mutated_deflate_matches_reference(self):
        rng = random.Random(1951)
        data = (b'ABCDE'*200+b'01111222233334444'*200+bytes(range(64)))*3
        valid = self.raw(data)
        cases = [bytes(rng.randrange(256) for _ in range(rng.randrange(1, 40))) for _ in range(300)]
        for _ in range(700):
            mutated = bytearray(valid)
            for _ in range(rng.randrange(1, 4)):
                mutated[rng.randrange(len(mutated))] ^= 1 << rng.randrange(8)
            cases.append(bytes(mutated))
        for index, raw in enumerate(cases):
            with self.subTest(index=index, raw=raw.hex()):
                decoder = zlib.decompressobj(-15)
                try:
                    expected = decoder.decompress(raw, 200001)
                    good = decoder.eof and not decoder.unused_data and len(expected) <= 200000
                except zlib.error:
                    good = False
                run, got = self.call('raw', raw, 200000)
                if good:
                    self.assertEqual(run.returncode, 0, run.stderr)
                    self.assertEqual(got, expected)
                else:
                    self.assertEqual(run.returncode, 1, got)


if __name__ == '__main__':
    unittest.main(verbosity=2)
