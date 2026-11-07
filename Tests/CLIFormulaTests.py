#!/usr/bin/env python3
"""Offline release gate tests; no real release, tap or installation is created."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import unittest
import subprocess
import tempfile
import struct
import zipfile

spec = importlib.util.spec_from_file_location('formula', Path(__file__).resolve().parents[1] / 'scripts/prepare-cli-formula.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FormulaTests(unittest.TestCase):
    def setUp(self):
        self.tag = 'cli-v1.0.0'
        self.sha = 'a' * 40
        self.binary = struct.pack('<8I', 0xFEEDFACF, 0x0100000C, 0, 0, 0, 0, 0, 0) + b'fixture, never executed'
        self.usage_mode = 0o100644
        self.manifest = dict(sourceSHA=self.sha, candidateOnly=False, releaseVersion='1.0.0',
                             architectures=['arm64'], minimumMacOS='14.0', schemaVersion=10,
                             binarySHA256=hashlib.sha256(self.binary).hexdigest())
        self.run = dict(head_sha=self.sha, conclusion='success', status='completed',
                        path='.github/workflows/build.yml')
        self.release = dict(tag_name=self.tag, draft=False, prerelease=False, published_at='2026-01-01')

    def responses(self):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w') as z:
            entry = zipfile.ZipInfo('istk')
            entry.external_attr = 0o100755 << 16
            z.writestr(entry, self.binary)
            for name, mode, data in [('manifest.json', 0o100644, json.dumps(self.manifest)),
                                      ('USAGE.txt', self.usage_mode, 'synthetic fixture')]:
                entry = zipfile.ZipInfo(name)
                entry.external_attr = mode << 16
                z.writestr(entry, data)
        archive = buf.getvalue()
        report = dict(sourceSHA=self.sha, isolatedCLIRegression='passed', ciRunID=123,
                      standaloneCLI=dict(archive='istk-1.0.0-macos-arm64.zip',
                        sha256=hashlib.sha256(archive).hexdigest(), verification='passed',
                        binarySHA256=hashlib.sha256(self.binary).hexdigest()))
        responses = {f'{module.API}/commits/{self.tag}': json.dumps({'sha': self.sha}).encode(),
                     f'{module.API}/actions/runs/123': json.dumps(self.run).encode()}
        assets = []
        for name, data in [('verification.json', json.dumps(report).encode()),
                           ('istk-1.0.0-macos-arm64.zip', archive)]:
            url = f'https://github.com/{module.REPO}/releases/download/{self.tag}/{name}'
            responses[url] = data
            assets.append(dict(name=name, state='uploaded', browser_download_url=url,
                               digest='sha256:' + hashlib.sha256(data).hexdigest()))
        release = copy.deepcopy(self.release)
        release['assets'] = assets
        responses[f'{module.API}/releases/tags/{self.tag}'] = json.dumps(release).encode()
        return responses

    def test_verified_release_formula(self):
        formula = module.prepare(self.tag, self.responses().__getitem__)
        self.assertIn('depends_on arch: :arm64', formula)
        self.assertIn('isolated profile', formula)
        self.assertIn('/releases/download/cli-v1.0.0/istk-1.0.0-macos-arm64.zip', formula)
        self.assertNotIn('post_install', formula)

    def test_generated_ruby_syntax(self):
        with tempfile.TemporaryDirectory(prefix='istk formula ') as temp:
            path = Path(temp) / 'istk.rb'
            path.write_text(module.prepare(self.tag, self.responses().__getitem__))
            result = subprocess.run(['ruby', '-c', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_candidate_never_promoted(self):
        self.manifest['candidateOnly'] = True
        with self.assertRaisesRegex(ValueError, 'cannot be promoted'):
            module.prepare(self.tag, self.responses().__getitem__)

    def test_ci_wrong_head_or_failed(self):
        for field, value in [('head_sha', 'b' * 40), ('conclusion', 'failure')]:
            old = self.run[field]
            self.run[field] = value
            with self.assertRaisesRegex(ValueError, 'successful repository CI'):
                module.prepare(self.tag, self.responses().__getitem__)
            self.run[field] = old

    def test_draft_and_prerelease(self):
        for key in ('draft', 'prerelease'):
            self.release[key] = True
            with self.assertRaisesRegex(ValueError, 'published non-draft'):
                module.prepare(self.tag, self.responses().__getitem__)
            self.release[key] = False

    def test_download_tampering(self):
        responses = self.responses()
        key = next(k for k in responses if k.endswith('.zip'))
        responses[key] += b'tampering'
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            module.prepare(self.tag, responses.__getitem__)

    def test_architecture_and_source_mismatch(self):
        for field, value in [('architectures', ['x86_64']), ('sourceSHA', 'b' * 40)]:
            old = self.manifest[field]
            self.manifest[field] = value
            with self.assertRaisesRegex(ValueError, 'Unsupported source'):
                module.prepare(self.tag, self.responses().__getitem__)
            self.manifest[field] = old

    def test_symlink_document_rejected(self):
        self.usage_mode = 0o120777
        with self.assertRaisesRegex(ValueError, 'Every archive entry'):
            module.prepare(self.tag, self.responses().__getitem__)

    def test_non_macho_rejected(self):
        self.binary = b'not an ARM64 executable' * 3
        self.manifest['binarySHA256'] = hashlib.sha256(self.binary).hexdigest()
        with self.assertRaisesRegex(ValueError, 'Mach-O header'):
            module.prepare(self.tag, self.responses().__getitem__)

    def test_tag_cannot_inject_formula(self):
        with self.assertRaisesRegex(ValueError, 'exact stable'):
            module.prepare('latest\"; system(\"bad\")', lambda url: self.fail('must not fetch'))


if __name__ == '__main__':
    unittest.main()
