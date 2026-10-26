"""Synthetic fixtures exercise validation only; never save them as device evidence."""
import unittest
from raster_matrix import EXPECTED, build_matrix, exact, render

def fixture(case_id='light__pageEntry', raster=8329, indexed=True):
    theme, scene = case_id.split('__')
    hz = 120.0
    pages = {'pageEntry': ['action_library'], 'bottomBarSwitch': ['chat', 'action_library'],
             'trainingPlayback': ['training']}.get(scene, ['performance_chat'])
    frames = []
    for number, start in enumerate((1000000, 4000000)):
        frames.append({'frameNumber': number, 'vsyncStartUs': start, 'buildUs': 1000,
                       'rasterUs': raster, 'refreshRateHz': hz,
                       'phasesUs': {'vsyncStart': start, 'buildStart': start + 100,
                                    'buildFinish': start + 1100, 'rasterStart': start + 1100,
                                    'rasterFinish': start + 1100 + raster}})
    stats = {'uiBuild': exact([1000, 1000]), 'raster': exact([raster, raster])}
    steady = {'uiBuild': exact([1000]), 'raster': exact([raster])}
    case = {'id': case_id, 'theme': theme, 'scenario': scene, 'material': 'solid',
            'completed': True, 'comparisonReady': True, 'sampleDurationUs': 32000000,
            'rawFrameOverflowCount': 0, 'rawFrameCount': 2, 'messageCount': 72, 'pages': pages,
            'firstVsyncStartUs': 1000000, 'lastVsyncStartUs': 4000000,
            'allFrames': stats, 'steadyState': steady,
            'conditions': [{'material': 'solid', 'theme': theme, 'starfield': True,
                            'renderer': 'impeller', 'rendererBackend': 'vulkan', 'rendererVerified': True,
                            'refreshRateHz': hz, 'refreshRateVerified': True,
                            'viewportWidth': 390, 'viewportHeight': 844,
                            'devicePixelRatio': 3, 'textScale': 1}]}
    report = {'schema': 3, 'app': 'smartfit', 'reportType': 'solid_frame_performance',
              'material': 'solid', 'metadata': {'appSource': 'a' * 40, 'sourceFingerprint': 'b' * 64,
                'appVersion': 'unit-fixture', 'sdkRef': 'unit-fixture', 'buildMode': 'profile',
                'flavor': 'internal', 'deviceModel': 'synthetic-not-measurement',
                'renderer': 'impeller', 'rendererBackend': 'vulkan', 'rendererVerified': True,
                'isEmulator': False}, 'cases': {case_id: case}}
    if indexed:
        report['rawFrames'] = frames; case['rawFrameIndices'] = [0, 1]
    else:
        case['rawFrames'] = frames
    return report

class MatrixTests(unittest.TestCase):
    def test_exact_integer_rank(self):
        self.assertEqual(exact(list(range(1, 101)))['p99Us'], 99)
    def test_strict_boundary_and_distinct_counts(self):
        for value, passed in [(8329, True), (8330, False), (8331, False)]:
            result = build_matrix([fixture(raster=value)])
            self.assertEqual(result['cells']['light__pageEntry']['rasterP99Pass'], passed)
            self.assertEqual(result['cells']['light__pageEntry']['raster']['over8_33msCount'], 2 if value > 8330 else 0)
    def test_all_ten_without_pooling(self):
        result = build_matrix([fixture(case_id) for case_id in EXPECTED])
        self.assertTrue(result['allTenP99Pass']); self.assertEqual(result['capturedCells'], 10)
        self.assertTrue(result['requiresUserOverBudgetReview'])
    def test_missing_cells_cannot_pass(self):
        result = build_matrix([fixture()])
        self.assertFalse(result['allTenP99Pass']); self.assertEqual(len(result['missing']), 9)
        self.assertIn('missing', render(result))
    def test_standalone_case_raw_export(self):
        self.assertEqual(build_matrix([fixture(indexed=False)])['capturedCells'], 1)
    def test_inconsistent_phase_is_rejected(self):
        data = fixture(); data['rawFrames'][0]['rasterUs'] += 1
        with self.assertRaises(ValueError): build_matrix([data])
    def test_truncated_table_is_rejected(self):
        data = fixture(); data['cases']['light__pageEntry']['rawFrameIndices'][0] = None
        with self.assertRaises(ValueError): build_matrix([data])
    def test_duplicate_case_is_rejected(self):
        with self.assertRaises(ValueError): build_matrix([fixture(), fixture()])
    def test_mixed_source_is_rejected(self):
        a, b = fixture(), fixture('dark__pageEntry')
        b['metadata']['sourceFingerprint'] = 'c' * 64
        with self.assertRaises(ValueError): build_matrix([a, b])
    def test_wrong_actual_theme_is_rejected(self):
        data = fixture(); data['cases']['light__pageEntry']['conditions'][0]['theme'] = 'dark'
        with self.assertRaises(ValueError): build_matrix([data])
    def test_unknown_renderer_is_rejected(self):
        data = fixture(); data['metadata']['rendererVerified'] = False
        with self.assertRaises(ValueError): build_matrix([data])
    def test_source_fingerprint_is_required(self):
        data = fixture(); data['metadata'].pop('sourceFingerprint')
        with self.assertRaises(ValueError): build_matrix([data])
    def test_raw_statistics_cannot_be_replaced_by_an_estimate(self):
        data = fixture(); data['cases']['light__pageEntry']['allFrames']['raster']['p99Us'] += 1
        with self.assertRaises(ValueError): build_matrix([data])
    def test_obsolete_schema_is_rejected(self):
        data = fixture(); data['schema'] = 2
        with self.assertRaises(ValueError): build_matrix([data])
    def test_no_frames_does_not_create_numbers(self):
        data = fixture(); data['rawFrames'].clear()
        with self.assertRaises(ValueError): build_matrix([data])
    def test_60_hz_cannot_relax_literal_p99_or_represent_120_hz_acceptance(self):
        data = fixture(raster=12000)
        data['cases']['light__pageEntry']['conditions'][0]['refreshRateHz'] = 60
        for frame in data['rawFrames']:
            frame['refreshRateHz'] = 60
        result = build_matrix([data])
        self.assertFalse(result['cells']['light__pageEntry']['rasterP99Pass'])
        self.assertFalse(result['cells']['light__pageEntry']['is120HzDeviceSample'])
        self.assertEqual(result['cells']['light__pageEntry']['actualPeriodOverBudgetFrames'], 0)
        self.assertEqual(result['cells']['light__pageEntry']['raster']['over8_33msCount'], 2)

if __name__ == '__main__':
    unittest.main()
