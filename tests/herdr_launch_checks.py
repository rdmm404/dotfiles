import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LAUNCH = ROOT / 'global/.local/bin/herdr-launch'


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=str(self.bin) + ':' + os.environ['PATH'],
                        HERDR_BIN_PATH=str(self.bin / 'herdr'),
                        HERDR_LAUNCH_SKIP_MACHINE='',
                        HERDR_LAUNCH_OWNERS='')
        self.write_bin('herdr', '''#!/usr/bin/env python3
import os, sys
if sys.argv[1:] == ['machine', 'list', '--json']:
    print(os.environ['MACHINES'])
else:
    print('{"result":{"snapshot":{"workspaces":[],"panes":[]}}}')
''')
        self.write_bin('fzf', '#!/bin/sh\ncat >/dev/null\nprintf "%s\\n" "$PICKED"\n')
        self.write_bin('ssh', '#!/bin/sh\nprintf "%s\\n" "$@" >"$HOME/ssh-args"\nexit "${SSH_EXIT:-0}"\n')

    def write_bin(self, name, text):
        file = self.bin / name
        file.write_text(text)
        file.chmod(0o755)

    def remote(self, session='agents', args=()):
        self.env['MACHINES'] = json.dumps([dict(id='opaque', label='Work',
            target='work-host', session=session, enabled=True)])
        self.env['PICKED'] = 'opaque\tWork\twork-host\t' + session
        return subprocess.run(['bash', str(LAUNCH), *args], env=self.env,
                              text=True, capture_output=True)

    def test_remote_uses_saved_host_and_session_not_local_paths(self):
        result = self.remote()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.home / 'ssh-args').read_text().splitlines()
        self.assertEqual(args[:3], ['-t', '--', 'work-host'])
        self.assertIn("HERDR_SESSION='agents'", args[3])
        self.assertIn('HERDR_LAUNCH_SKIP_MACHINE=1', args[3])
        self.assertIn('"$SHELL" -lic', args[3])
        self.assertIn("'exec herdr-launch'", args[3])
        self.assertNotIn(str(self.home), args[3])

    def test_shell_mode_and_shell_quoting(self):
        result = self.remote("dev's session", ('--shell',))
        self.assertEqual(result.returncode, 0, result.stderr)
        command = (self.home / 'ssh-args').read_text().splitlines()[3]
        # Parse the actual remote shell command with an inert env executable.
        self.write_bin('env', '#!/bin/sh\nprintf "%s\\n" "$@"\n')
        parsed = subprocess.run(['/bin/sh', '-c', command], env=self.env,
                                capture_output=True, text=True, check=True).stdout
        self.assertIn("HERDR_SESSION=dev's session\n", parsed)
        self.assertIn('exec herdr-launch --shell\n', parsed)

    def test_failed_ssh_never_falls_back_to_local(self):
        self.env['SSH_EXIT'] = '255'
        result = self.remote()
        self.assertEqual(result.returncode, 1)
        self.assertIn('remote launcher failed', result.stderr)

    def test_internal_helpers_skip_machine_picker(self):
        result = subprocess.run(['bash', str(LAUNCH), '--rows'], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / 'ssh-args').exists())

    def test_no_enabled_machines_skips_machine_step(self):
        self.env['MACHINES'] = json.dumps([dict(id='disabled', enabled=False)])
        self.write_bin('fzf', '#!/bin/sh\ncat >/dev/null\nprintf "%s\\n" "$@" >"$HOME/fzf-args"\nexit 130\n')
        self.write_bin('gh', '#!/bin/sh\nexit 0\n')
        result = subprocess.run(['bash', str(LAUNCH), '--shell'], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--prompt=where> ', (self.home / 'fzf-args').read_text())
        self.assertFalse((self.home / 'ssh-args').exists())

    def test_machine_cancel_does_not_launch_anything(self):
        self.write_bin('fzf', '#!/bin/sh\ncat >/dev/null\nexit 130\n')
        result = self.remote()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / 'ssh-args').exists())


if __name__ == '__main__':
    unittest.main()
