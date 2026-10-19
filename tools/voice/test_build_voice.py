"""Offline regression tests for the drill-pack voice builder."""
import importlib.util
import io
import os
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch


_spec = importlib.util.spec_from_file_location(
    'build_voice_under_test', Path(__file__).with_name('build_voice.py'))
build_voice = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build_voice)


class BuildEnvironmentTest(unittest.TestCase):
    def test_cmd_build_keeps_environment_and_removes_only_proxies(self):
        preserved = {
            'PATH': r'C:\review-tools\ffmpeg;C:\Windows\System32',
            'SystemRoot': r'C:\Windows',
            'VOICE_BUILD_CUSTOM': 'keep-this-value',
        }
        proxies = {
            'hTtP_pRoXy': 'http://localhost:8001',
            'HTTPS_PROXY': 'http://localhost:8002',
            'all_proxy': 'socks5://localhost:8003',
        }
        observed = {}

        async def render_without_io(unique, budget_end):
            self.assertEqual(unique, {})
            observed['preserved'] = {key: os.environ.get(key) for key in preserved}
            observed['proxy_keys'] = [
                key for key in os.environ
                if key.lower() in ('http_proxy', 'https_proxy', 'all_proxy')
            ]
            return True

        render = AsyncMock(side_effect=render_without_io)
        with (
            patch.dict(os.environ, {**preserved, **proxies}, clear=True),
            patch.object(build_voice, 'jobs_from_packs', return_value=[]),
            patch.object(build_voice, 'render', render),
            patch.object(build_voice, '_tts', new_callable=AsyncMock) as tts,
            patch.object(build_voice.P, 'read_json') as read_pack,
            patch.object(build_voice.P, 'write_json') as write_pack,
            patch('sys.stdout', new_callable=io.StringIO),
        ):
            build_voice.cmd_build(SimpleNamespace(budget=1))

            self.assertEqual(observed['preserved'], preserved)
            self.assertEqual(observed['proxy_keys'], [])
            self.assertEqual({key: os.environ.get(key) for key in preserved}, preserved)
            render.assert_awaited_once()
            tts.assert_not_awaited()
            read_pack.assert_not_called()
            write_pack.assert_not_called()


if __name__ == '__main__':
    unittest.main()
