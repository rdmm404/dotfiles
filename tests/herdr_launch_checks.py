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
        # Resolved: macOS temp folders sit behind the /var -> /private/var link.
        self.home = Path(self.tmp.name).resolve()
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

    def launch_with_picks(self, picks, shell=True):
        self.env.update(HERDR_LAUNCH_SKIP_MACHINE='1',
                        XDG_CACHE_HOME=str(self.home / 'cache'),
                        XDG_STATE_HOME=str(self.home / 'state'))
        cache = self.home / 'cache/herdr-launch'
        cache.mkdir(parents=True)
        (cache / 'repos').touch()
        (self.home / 'picks.json').write_text(json.dumps(picks))
        self.write_bin('fzf', '''#!/usr/bin/env python3
import json, os, pathlib, sys
sys.stdin.read()
home = pathlib.Path(os.environ['HOME'])
file = home / 'picks.json'
picks = json.loads(file.read_text())
pick = picks.pop(0)
file.write_text(json.dumps(picks))
with (home / 'fzf-calls').open('a') as out:
    out.write(json.dumps(sys.argv[1:]) + '\\n')
print(pick[1], end='')
sys.exit(pick[0])
''')
        self.write_bin('herdr', '''#!/usr/bin/env python3
import json, os, pathlib, sys
if sys.argv[1:] == ['api', 'snapshot']:
    print('{"result":{"snapshot":{"workspaces":[],"panes":[]}}}')
else:
    with (pathlib.Path(os.environ['HOME']) / 'launch-calls').open('a') as out:
        out.write(json.dumps(sys.argv[1:]) + '\\n')
    print('{"result":{"root_pane":{"pane_id":"pane"},"tab":{"tab_id":"tab"}}}')
''')
        for name in ('fd', 'zoxide'):
            self.write_bin(name, '#!/bin/sh\nexit 0\n')
        self.write_bin('pi', '#!/bin/sh\nexit 0\n')
        return subprocess.run(['bash', str(LAUNCH), *(['--shell'] if shell else [])],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def new_directory_pick(self):
        return [0, f'\nctrl-n\ndir\t-\t{self.home}\tparent\n']

    def test_new_directory_with_spaces_opens_workspace(self):
        result = self.launch_with_picks([self.new_directory_pick(), [1, 'new project\n']])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / 'new project').is_dir())
        calls = (self.home / 'launch-calls').read_text()
        self.assertIn(json.dumps(['workspace', 'create', '--cwd',
                                 str(self.home / 'new project'), '--no-focus']), calls)
        self.assertFalse((self.home / 'new project/.git').exists())

    def test_cancel_name_creates_nothing(self):
        result = self.launch_with_picks([self.new_directory_pick(), [130, ''], [130, '']])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / 'launch-calls').exists())

    def test_invalid_and_existing_names_are_rejected(self):
        result = self.launch_with_picks([self.new_directory_pick(),
            [1, '../outside\n'], [1, 'bin\n'], [1, '.\n'], [1, 'valid\n']])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / 'valid').is_dir())
        prompts = (self.home / 'fzf-calls').read_text()
        self.assertIn('no slashes', prompts)
        self.assertIn('already exists', prompts)

    def test_agent_back_returns_to_name_without_creating(self):
        result = self.launch_with_picks([self.new_directory_pick(), [1, 'first\n'],
            [130, ''], [1, 'second\n'], [0, 'pi\n']], shell=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / 'first').exists())
        self.assertTrue((self.home / 'second').is_dir())
        self.assertIn('["pane", "run", "pane", "pi"]',
                      (self.home / 'launch-calls').read_text())


if __name__ == '__main__':
    unittest.main()
