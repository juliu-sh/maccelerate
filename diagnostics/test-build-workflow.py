#!/usr/bin/env python3
"""Check that local signing failures and channel mixups preserve prior builds."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class BuildWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='maccelerate-workflow-test-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        (self.root / 'dist').mkdir()
        (self.root / 'build').mkdir()
        (self.root / 'bin').mkdir()
        for script in ('build.sh', 'deploy-to-dmg.sh', 'archive-app.py'):
            shutil.copy2(ROOT / 'dist' / script, self.root / 'dist' / script)
        self.sentinel = self.root / 'build/previous-candidate'
        self.sentinel.write_text('Preserve this candidate')
        self.swift_log = self.root / 'swift-called'
        for name, body in [('security', 'exit 0'),
                           ('swift', 'touch "$TEST_WORKFLOW_LOG"; exit 1')]:
            command = self.root / 'bin' / name
            command.write_text('#!/bin/sh\n' + body + '\n')
            command.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + ':' + os.environ['PATH'],
                        TEST_WORKFLOW_LOG=str(self.swift_log),
                        MACCELERATE_DISTRIBUTION='0',
                        MACCELERATE_CODESIGN_IDENTITY='Unavailable test identity')

    def command(self, script, *args):
        return subprocess.run(['bash', 'dist/' + script, *args], cwd=self.root,
                              env=self.env, text=True, capture_output=True)

    def test_missing_identity_stops_before_clean_or_compilation(self):
        result = self.command('build.sh', '--clean')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Signing identity unavailable', result.stderr)
        self.assertTrue(self.sentinel.exists())
        self.assertFalse(self.swift_log.exists())

    def test_distribution_rejects_ad_hoc_before_clean_or_compilation(self):
        self.env.update(MACCELERATE_DISTRIBUTION='1', MACCELERATE_CODESIGN_IDENTITY='-')
        result = self.command('build.sh', '--clean')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Distribution requires', result.stderr)
        self.assertTrue(self.sentinel.exists())
        self.assertFalse(self.swift_log.exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'Archiving uses Apple ditto')
    def test_clean_preserves_the_prior_candidate_as_a_verified_archive(self):
        self.env['MACCELERATE_CODESIGN_IDENTITY'] = '-'
        result = self.command('build.sh', '--clean')
        # The fake compiler fails, but the prior candidate must already be safe.
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.swift_log.exists())
        self.assertFalse(self.sentinel.exists())
        archives = list((self.root / 'build-backups').glob('build-*.zip'))
        self.assertEqual(len(archives), 1)
        with zipfile.ZipFile(archives[0]) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.read('build/previous-candidate'), b'Preserve this candidate')

    @unittest.skipUnless(sys.platform == 'darwin', 'Packaging uses Apple PlistBuddy')
    def test_dmg_rejects_the_other_channel_before_touching_prior_assets(self):
        (self.root / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.3.0'}))
        cases = [('Maccelerate', 'source', [], 'official'),
                 ('Maccelerate Source', 'official', ['--source'], 'source')]
        for name, channel, args, expected in cases:
            with self.subTest(expected=expected):
                contents = self.root / 'build' / (name + '.app') / 'Contents'
                contents.mkdir(parents=True)
                (contents / 'Info.plist').write_bytes(plistlib.dumps({'MaccelerateBuildChannel': channel}))
                prior = self.root / 'build' / (name + '-1.3.0.dmg')
                prior.write_bytes(b'previous immutable candidate')
                result = self.command('deploy-to-dmg.sh', *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Expected ' + expected + ' build', result.stderr)
                self.assertEqual(prior.read_bytes(), b'previous immutable candidate')
                self.assertEqual(list((self.root / 'build').glob('dmg-staging.*')), [])

    @unittest.skipUnless(sys.platform == 'darwin', 'Packaging uses Apple PlistBuddy')
    def test_dmg_refuses_identity_mixups_with_a_matching_channel_field(self):
        (self.root / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.3.0'}))
        for name, channel, bundle_id, args in [
            ('Maccelerate', 'official', 'com.interversehq.Maccelerate', []),
            ('Maccelerate Source', 'source', 'com.interversehq.Maccelerate.source', ['--source']),
        ]:
            contents = self.root / 'build' / (name + '.app') / 'Contents'
            contents.mkdir(parents=True)
            valid = dict(MaccelerateBuildChannel=channel, CFBundleIdentifier=bundle_id,
                         CFBundleName=name, CFBundleDisplayName=name)
            for field in ('CFBundleIdentifier', 'CFBundleName', 'CFBundleDisplayName'):
                with self.subTest(channel=channel, field=field):
                    bad = dict(valid, **{field: 'the other app'})
                    (contents / 'Info.plist').write_bytes(plistlib.dumps(bad))
                    result = self.command('deploy-to-dmg.sh', *args)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('App identity does not match', result.stderr)
                    self.assertEqual(list((self.root / 'build').glob('dmg-staging.*')), [])

    @unittest.skipUnless(sys.platform == 'darwin', 'Archiving uses Apple ditto')
    def test_channel_change_retires_the_other_app_only_after_verified_backup(self):
        self.env['MACCELERATE_CODESIGN_IDENTITY'] = '-'
        other = self.root / 'build/Maccelerate.app'
        (other / 'Contents').mkdir(parents=True)
        payload = other / 'Contents/fixture'
        payload.write_bytes(b'previous official app content')
        result = self.command('build.sh')
        self.assertNotEqual(result.returncode, 0)  # Fake compiler fails after archiving.
        self.assertTrue(self.swift_log.exists())
        self.assertFalse(other.exists())
        archives = list((self.root / 'build-backups').glob('Maccelerate-*.zip'))
        self.assertEqual(len(archives), 1)
        with zipfile.ZipFile(archives[0]) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.read('Maccelerate.app/Contents/fixture'),
                             b'previous official app content')


if __name__ == '__main__':
    unittest.main()
