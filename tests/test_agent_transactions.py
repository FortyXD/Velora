"""Durability and conflict tests use only a private temporary tree."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import runpy
from unittest.mock import patch
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/velora-agentd/python/transactions.py'


class TransactionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='velora-tx-')
        self.root = Path(self.temp.name)
        self.work = self.root / 'work'
        self.work.mkdir()
        self.env = {**os.environ, 'XDG_STATE_HOME': str(self.root / 'state')}
        self.call('begin', submission_id='one', conversation_id='chat')

    def tearDown(self):
        self.temp.cleanup()

    def call(self, operation, error=False, **params):
        request = {'operation': operation, 'transaction_id': 'one', **params}
        result = subprocess.run(['/usr/bin/python3', str(SCRIPT)], input=json.dumps(request), text=True, capture_output=True, env=self.env, check=True)
        value = json.loads(result.stdout)
        if error: self.assertIn('error', value, value)
        else: self.assertNotIn('error', value, value)
        return value

    def prepare(self, kind, **args):
        return self.call('prepare_files', kind=kind, args={k:str(v) for k,v in args.items()})

    def apply(self, plan):
        return self.call('apply', plan=plan['plan'])

    def test_existing_shared_state_parent_0755_keeps_its_mode_with_private_journal(self):
        state = self.root/'shared-state'
        parent = state/'velora'; parent.mkdir(parents=True, mode=0o755)
        parent.chmod(0o755)
        self.env['XDG_STATE_HOME'] = str(state)
        initialized = self.call('initialize')
        self.assertEqual(Path(initialized['root']), parent/'transactions')
        self.assertEqual(parent.stat().st_mode & 0o777, 0o755)
        self.assertEqual((parent/'transactions').stat().st_mode & 0o777, 0o700)
        self.call('begin', submission_id='fresh', transaction_id='fresh', conversation_id='chat')

    def test_unsafe_or_symlinked_shared_state_parent_is_rejected(self):
        for mode in (0o775, 0o777):
            with self.subTest(mode=oct(mode)):
                state = self.root/('writable-'+str(mode))
                parent = state/'velora'; parent.mkdir(parents=True)
                parent.chmod(mode)
                self.env['XDG_STATE_HOME'] = str(state)
                self.call('initialize', error=True)
                self.assertEqual(parent.stat().st_mode & 0o777, mode)
                self.assertFalse((parent/'transactions').exists())
        state = self.root/'linked-state'; state.mkdir()
        target = self.root/'linked-target'; target.mkdir(mode=0o700)
        (state/'velora').symlink_to(target, target_is_directory=True)
        self.env['XDG_STATE_HOME'] = str(state)
        self.call('initialize', error=True)
        self.assertFalse((target/'transactions').exists())

    def test_executor_policy_and_native_paths_are_immutable_and_excluded_from_staging(self):
        helper = runpy.run_path(str(SCRIPT))
        execute = helper['execute']; namespace = execute.__globals__
        checkout = self.root/'checkout'
        fake_helper = checkout/'tools/velora-agentd/python/transactions.py'
        fake_helper.parent.mkdir(parents=True); fake_helper.write_text('immutable executor')
        frontend = checkout/'dots/.config/quickshell/ii/services/Assistant.qml'
        frontend.parent.mkdir(parents=True); frontend.write_text('immutable UI policy')
        ordinary = checkout/'dots/.config/hypr/hyprland.conf'
        ordinary.parent.mkdir(parents=True); ordinary.write_text('ordinary project config')
        home = self.root/'home'; home.mkdir()
        config = home/'.config'
        protected = [fake_helper, checkout/'tools/velora-agentd/src/tools.rs',
                     checkout/'tools/velora-agentd/new-policy.py', checkout/'tools/target/release/velora-agentd',
                     frontend, checkout/'dots/.config/quickshell/ii/services/Ai.qml',
                     checkout/'dots/.config/quickshell/ii/services/LauncherSearch.qml',
                     checkout/'dots/.config/quickshell/ii/services/IntentRouter.js',
                     checkout/'dots/.config/quickshell/ii/modules/common/Config.qml',
                     config/'quickshell/ii/services/Assistant.qml', config/'illogical-impulse/config.json',
                     home/'.local/bin/velora-agentd', home/'.local/bin/python3']
        with patch.dict(os.environ, {**self.env, 'HOME':str(home), 'XDG_CONFIG_HOME':str(config)}), patch.dict(namespace, {'__file__':str(fake_helper)}):
            for path in protected:
                with self.subTest(path=path):
                    with self.assertRaisesRegex(ValueError, 'Protected executor'):
                        namespace['safe_path'](path)
            self.assertEqual(namespace['safe_path'](ordinary), ordinary)
            stage = execute({'operation':'stage','transaction_id':'one','cwd':str(checkout)})
            copied = Path(stage['path'])
            self.assertFalse((copied/'tools/velora-agentd').exists())
            self.assertFalse((copied/'dots/.config/quickshell').exists())
            self.assertEqual((copied/'dots/.config/hypr/hyprland.conf').read_text(), 'ordinary project config')
            injected = copied/'tools/velora-agentd/python/transactions.py'
            injected.parent.mkdir(parents=True); injected.write_text('disable security')
            with self.assertRaisesRegex(ValueError, 'Protected executor'):
                execute({'operation':'prepare_stage','transaction_id':'one','stage':stage['stage']})
        self.assertEqual(fake_helper.read_text(), 'immutable executor')
        self.assertEqual(frontend.read_text(), 'immutable UI policy')

    def test_guarded_read_rejects_benign_hardlink_to_protected_file(self):
        protected = self.work/'.ssh'; protected.mkdir()
        secret = protected/'id_rsa'; secret.write_text('synthetic-private-key')
        alias = self.work/'report.txt'; os.link(secret, alias)
        info = alias.stat()
        failure = self.call('read_file', path=str(alias), device=info.st_dev, inode=info.st_ino, error=True)
        self.assertIn('Hard-linked', failure['error'])
        self.assertNotIn('synthetic-private-key', json.dumps(failure))
        self.assertEqual(self.call('check_paths', paths=[str(alias)])['paths'], [])

    def test_guarded_read_rejects_leaf_and_ancestor_swaps_after_policy_check(self):
        helper = runpy.run_path(str(SCRIPT))
        guarded = helper['guarded_read']
        namespace = guarded.__globals__
        original_check = namespace['safe_path']
        protected = self.work/'.ssh'; protected.mkdir()
        secret = protected/'note'; secret.write_text('synthetic-secret')
        for kind in ('leaf', 'ancestor', 'replacement'):
            with self.subTest(kind=kind):
                folder = self.work/kind; folder.mkdir()
                source = folder/'note'; source.write_text('ordinary text')
                before = source.stat()
                changed = False
                def swap(value, root=False):
                    nonlocal changed
                    checked = original_check(value, root)
                    if not changed:
                        changed = True
                        if kind == 'ancestor':
                            folder.rename(self.work/(kind+'-original'))
                            folder.symlink_to(protected, target_is_directory=True)
                        else:
                            source.rename(folder/'original')
                            if kind == 'leaf': source.symlink_to(secret)
                            else: source.write_text('replacement text')
                    return checked
                with patch.dict(namespace, {'safe_path':swap}):
                    with self.assertRaises((ValueError, OSError)):
                        guarded({'path':str(source),'device':before.st_dev,'inode':before.st_ino})
                self.assertEqual(secret.read_text(), 'synthetic-secret')

    def test_guarded_read_is_bounded_and_returns_only_verified_text(self):
        source = self.work/'note'; source.write_text('hello' * 600)
        info = source.stat()
        value = self.call('read_file', path=str(source), device=info.st_dev, inode=info.st_ino)
        self.assertEqual(len(value['text']), 2500)
        self.assertTrue(value['truncated'])
        self.assertTrue(value['untrusted'])
        source.write_bytes(b'x' * (128 * 1024 + 1))
        self.call('read_file', path=str(source), device=info.st_dev, inode=info.st_ino, error=True)

    def test_atomic_new_file_publication_recovers_after_post_rename_crash(self):
        helper = runpy.run_path(str(SCRIPT))
        execute = helper['execute']
        namespace = execute.__globals__
        rename = namespace['rename_at']
        source = self.work/'source'; source.write_text('published data')
        target = self.work/'created'
        plan = self.prepare('copy', source=source, target=target)
        class SimulatedCrash(BaseException): pass
        def crash_after_rename(fd, original, destination, flags):
            rename(fd, original, destination, flags)
            if destination == 'created' and flags == 1:
                raise SimulatedCrash()
        with patch.dict(os.environ, self.env), patch.dict(namespace, {'rename_at':crash_after_rename}):
            with self.assertRaises(SimulatedCrash):
                execute({'operation':'apply','transaction_id':'one','plan':plan['plan']})
        self.assertEqual(target.read_text(), 'published data')
        self.assertEqual(target.stat().st_nlink, 1)
        recovered = self.call('recover')['transactions'][0]
        self.assertEqual(recovered['state'], 'rolled_back')
        self.assertFalse(target.exists())
        self.assertEqual(source.read_text(), 'published data')
        self.assertEqual(list(self.work.glob('.velora-*')), [])

    def test_enospc_during_checkpoint_and_journal_save_never_mutates_original(self):
        helper = runpy.run_path(str(SCRIPT))
        execute = helper['execute']
        source = self.work/'original'; source.write_text('must survive')
        def no_snapshot_space(original, checkpoint):
            checkpoint.write_bytes(b'partial checkpoint')
            raise OSError(28, 'injected checkpoint ENOSPC')
        with patch.dict(os.environ, self.env), patch.dict(execute.__globals__, {'copied':no_snapshot_space}):
            with self.assertRaises(OSError) as failure:
                execute({'operation':'prepare_files','transaction_id':'one','kind':'trash','args':{'source':str(source)}})
            self.assertEqual(failure.exception.errno, 28)
        self.assertEqual(source.read_text(), 'must survive')
        self.call('recover')
        self.assertEqual(source.read_text(), 'must survive')
        self.call('begin', transaction_id='save-failure', submission_id='save-failure', conversation_id='chat')
        prepared = self.call('prepare_files', transaction_id='save-failure', kind='trash', args={'source':str(source)})
        def no_journal_space(path, value):
            path.with_name(path.name+'.new').write_text('{')
            raise OSError(28, 'injected journal ENOSPC')
        with patch.dict(os.environ, self.env), patch.dict(execute.__globals__, {'save':no_journal_space}):
            with self.assertRaises(OSError) as failure:
                execute({'operation':'apply','transaction_id':'save-failure','plan':prepared['plan']})
            self.assertEqual(failure.exception.errno, 28)
        self.assertEqual(source.read_text(), 'must survive')
        self.call('recover')
        self.assertEqual(source.read_text(), 'must survive')
        self.assertEqual(list(self.work.glob('.velora-*')), [])

    def test_snapshot_copy_falls_back_when_reflink_is_unavailable(self):
        helper = runpy.run_path(str(SCRIPT))
        source = self.work/'source'; source.write_bytes(b'synthetic snapshot bytes')
        target = self.work/'snapshot'
        with patch('fcntl.ioctl', side_effect=OSError(95, 'unsupported filesystem')) as clone:
            helper['copied'](source, target)
        clone.assert_called_once()
        self.assertEqual(target.read_bytes(), source.read_bytes())
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_nested_move_recovers_after_process_crash(self):
        source = self.work / 'source'; source.mkdir()
        (source / 'nested').mkdir(); (source / 'nested/file').write_text('before')
        target = self.work / 'target'
        plan = self.prepare('move', source=source, target=target)
        self.apply(plan)
        self.assertFalse(source.exists())
        self.assertEqual((target/'nested/file').read_text(), 'before')
        # A different helper process performs startup recovery with no model or approvals.
        recovered = self.call('recover')['transactions'][0]
        self.assertEqual(recovered['state'], 'rolled_back')
        self.assertEqual((source/'nested/file').read_text(), 'before')
        self.assertFalse(target.exists())

    def test_user_edit_conflicts_preserve_new_content_and_checkpoint(self):
        destination = self.work/'new'; source = self.work/'original'; source.write_text('old')
        self.apply(self.prepare('copy', source=source, target=destination))
        self.call('commit')
        destination.write_text('user edited')
        result = self.call('rollback')
        self.assertEqual(result['state'], 'rollback_conflict')
        self.assertEqual(result['conflicts'], [str(destination)])
        self.assertEqual(destination.read_text(), 'user edited')
        self.call('delete', confirmed=True, error=True)

    def test_removal_restores_bytes_mode_and_mtime(self):
        source = self.work/'original'; source.write_text('saved')
        source.chmod(0o640); os.utime(source, ns=(123000000000, 123000000000))
        self.apply(self.prepare('trash', source=source)); self.assertFalse(source.exists())
        self.call('commit'); self.call('rollback')
        self.assertEqual(source.read_text(), 'saved')
        self.assertEqual(source.stat().st_mode & 0o777, 0o640)
        self.assertEqual(source.stat().st_mtime_ns, 123000000000)

    def test_duplicate_submission_and_reapply_are_blocked(self):
        plan = self.prepare('mkdir', target=self.work/'new')
        self.apply(plan)
        self.call('apply', plan=plan['plan'], error=True)
        self.call('begin', submission_id='one', conversation_id='chat', error=True)
        self.call('commit')
        self.call('delete', confirmed=False, error=True)
        self.call('delete', confirmed=True)
        self.call('begin', submission_id='one', conversation_id='chat', error=True)

    def test_symlink_swap_after_prepare_cannot_escape(self):
        original = self.work/'folder'; original.mkdir()
        other = self.root/'other'; other.mkdir()
        plan = self.prepare('mkdir', target=original/'new')
        original.rmdir(); original.symlink_to(other, target_is_directory=True)
        self.call('apply', plan=plan['plan'], error=True)
        self.assertFalse((other/'new').exists())

    def test_identical_replacement_after_prepare_is_not_overwritten(self):
        source = self.work/'original'; source.write_text('old')
        plan = self.prepare('trash', source=source)
        source.rename(self.work/'kept')
        source.write_text('old')
        self.call('apply', plan=plan['plan'], error=True)
        self.assertEqual(source.read_text(), 'old')

    def test_budget_and_sensitive_paths_fail_before_write(self):
        self.call('begin', transaction_id='small', submission_id='small', conversation_id='chat', budget=1024*1024)
        source = self.work/'big'; source.write_bytes(b'x' * (2*1024*1024))
        self.call('prepare_files', transaction_id='small', kind='copy', args={'source':str(source),'target':str(self.work/'out')}, error=True)
        self.assertFalse((self.work/'out').exists())
        self.call('check', path='/etc/passwd', error=True)
        secret = self.work/'.env'; secret.write_text('secret')
        self.call('check', path=str(secret), error=True)
        config = self.work/'.config'; config.mkdir()
        ordinary = config/'app.ini'; ordinary.write_text('color=blue')
        allowed = self.call('check_paths', paths=[str(secret), '/etc/passwd', str(ordinary)])
        self.assertEqual(allowed['paths'], [str(ordinary)])

    def test_stage_only_publishes_reviewed_diff_and_excludes_secrets(self):
        (self.work/'note').write_text('original')
        (self.work/'.env').write_text('secret')
        stage = self.call('stage', cwd=str(self.work))
        staged = Path(stage['path'])
        self.assertFalse((staged/'.env').exists())
        (staged/'note').write_text('changed'); (staged/'new').write_text('created')
        self.assertEqual((self.work/'note').read_text(), 'original')
        plan = self.call('prepare_stage', stage=stage['stage'])
        self.assertEqual(len(plan['diff']), 2)
        self.assertTrue(any('-original' in d.get('diff','') and '+changed' in d.get('diff','') for d in plan['diff']))
        self.apply(plan); self.call('commit')
        self.assertEqual((self.work/'note').read_text(), 'changed')
        self.call('rollback')
        self.assertEqual((self.work/'note').read_text(), 'original')
        self.assertFalse((self.work/'new').exists())
        self.assertEqual((self.work/'.env').read_text(), 'secret')


if __name__ == '__main__': unittest.main()
