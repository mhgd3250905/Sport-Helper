"""Validate schema-3 solid raw timings and render light/dark x five scenes."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re

SCENARIOS = ('planCardScroll', 'longChatScroll', 'pageEntry', 'bottomBarSwitch', 'trainingPlayback')
EXPECTED = tuple(f'{theme}__{scene}' for theme in ('light', 'dark') for scene in SCENARIOS)
MINIMUM_US = {'planCardScroll': 30000000, 'longChatScroll': 30000000, 'pageEntry': 3000000,
              'bottomBarSwitch': 10000000, 'trainingPlayback': 20000000}
COMMON_KEYS = ('appSource', 'sourceFingerprint', 'appVersion', 'sdkRef', 'buildMode', 'flavor',
               'deviceModel', 'renderer', 'rendererBackend', 'rendererVerified', 'isEmulator')

def exact(values):
    if not values or any(type(value) is not int or value < 0 for value in values):
        raise ValueError('Missing original integer timing samples')
    values = sorted(values)
    rank = lambda p: values[(p * len(values) + 99) // 100 - 1]
    return {'count': len(values), 'p50Us': rank(50), 'p90Us': rank(90), 'p99Us': rank(99),
            'maxUs': values[-1], 'over8_33msCount': sum(value > 8330 for value in values),
            'over8_33msRatio': sum(value > 8330 for value in values) / len(values),
            'overExact120HzPeriodCount': sum(value * 120 > 1000000 for value in values)}

def load_report(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def case_frames(report, case):
    if 'rawFrames' in case:
        frames = case['rawFrames']
    else:
        table, indices = report.get('rawFrames'), case.get('rawFrameIndices')
        if not isinstance(table, list) or not isinstance(indices, list):
            raise ValueError('Missing raw-frame table/references')
        if any(type(index) is not int or index < 0 or index >= len(table) for index in indices):
            raise ValueError('A raw-frame reference is missing or invalid')
        frames = [table[index] for index in indices]
    if not frames or len(frames) != case.get('rawFrameCount'):
        raise ValueError('Missing/truncated raw frames')
    if len({frame['frameNumber'] for frame in frames}) != len(frames):
        raise ValueError('Duplicate engine frame numbers')
    for frame in frames:
        phases = frame.get('phasesUs', {})
        for name in ('vsyncStart', 'buildStart', 'buildFinish', 'rasterStart', 'rasterFinish'):
            if type(phases.get(name)) is not int:
                raise ValueError('Original FramePhase timestamps are missing')
        if (frame.get('vsyncStartUs') != phases['vsyncStart'] or
            frame.get('buildUs') != phases['buildFinish'] - phases['buildStart'] or
            frame.get('rasterUs') != phases['rasterFinish'] - phases['rasterStart']):
            raise ValueError('Published duration does not match original engine phases')
    return sorted(frames, key=lambda frame: frame['vsyncStartUs'])

def validate_case(report, case_id, case):
    theme, scene = case_id.split('__')
    if (case.get('id') != case_id or case.get('theme') != theme or case.get('scenario') != scene
            or case.get('material') != 'solid' or case.get('completed') is not True
            or case.get('comparisonReady') is not True):
        raise ValueError('Incomplete or invalid real-workload case')
    if case.get('sampleDurationUs', 0) < MINIMUM_US[scene] or case.get('rawFrameOverflowCount') != 0:
        raise ValueError('Case duration/retention does not meet the protocol')
    conditions = case.get('conditions')
    if not isinstance(conditions, list) or len(conditions) != 1:
        raise ValueError('Actual render conditions are mixed or missing')
    condition = conditions[0]
    hz = condition.get('refreshRateHz')
    if (type(hz) not in (int, float) or not 10 <= hz <= 1000
            or condition.get('refreshRateVerified') is not True
            or condition.get('theme') != theme or condition.get('rendererVerified') is not True
            or condition.get('material') != 'solid' or type(condition.get('starfield')) is not bool):
        raise ValueError('Actual theme/rate/renderer/material is unverified')
    dimensions = {key: condition.get(key) for key in ('viewportWidth', 'viewportHeight', 'devicePixelRatio', 'textScale')}
    if any(type(value) not in (int, float) or value <= 0 for value in dimensions.values()):
        raise ValueError('Viewport or text scale is missing')
    frames = case_frames(report, case)
    if any(frame.get('refreshRateHz') != hz for frame in frames):
        raise ValueError('Frame display rates do not match the actual condition')
    if frames[0]['vsyncStartUs'] != case.get('firstVsyncStartUs') or frames[-1]['vsyncStartUs'] != case.get('lastVsyncStartUs'):
        raise ValueError('Raw boundaries do not match the case receipt')
    if scene == 'longChatScroll' and case.get('messageCount', 0) < 60:
        raise ValueError('Long chat is not the declared workload')
    pages = set(case.get('pages', []))
    if scene == 'pageEntry' and 'action_library' not in pages:
        raise ValueError('The real entry target was not observed')
    if scene == 'bottomBarSwitch' and not {'chat', 'action_library'} <= pages:
        raise ValueError('The real dock/drawer/library flow was not observed')
    if scene == 'trainingPlayback' and 'training' not in pages:
        raise ValueError('The real training page was not observed')
    selected = frames if scene == 'pageEntry' else [
        frame for frame in frames if frame['vsyncStartUs'] - frames[0]['vsyncStartUs'] >= 2000000]
    build = exact([frame['buildUs'] for frame in selected])
    raster = exact([frame['rasterUs'] for frame in selected])
    window = 'allFrames' if scene == 'pageEntry' else 'steadyState'
    published = case[window]
    for thread, recalculated in [('uiBuild', build), ('raster', raster)]:
        for key, value in recalculated.items():
            if published[thread].get(key) != value:
                raise ValueError('Published statistics do not match raw exact nearest-rank')
    budget = 8330
    over_rate = sum(frame['rasterUs'] > 1000000 / hz for frame in selected)
    return {'caseId': case_id, 'theme': theme, 'scenario': scene, 'material': 'solid',
            'acceptanceWindow': window, 'refreshRateHz': hz, 'acceptanceBudgetUs': budget,
            'build': build, 'raster': raster, 'actualPeriodOverBudgetFrames': over_rate,
            'actualFrameBudgetUs': 1000000 / hz, 'is120HzDeviceSample': abs(hz - 120) < .25,
            'actualPeriodOverBudgetRatio': over_rate / len(selected),
            'rasterP99Pass': raster['p99Us'] < budget,
            'conditionsIdentity': {**dimensions, 'starfield': condition['starfield'],
                                   'renderer': condition['renderer'], 'rendererBackend': condition['rendererBackend']}}

def build_matrix(reports):
    cells, identity, conditions_identity = {}, None, None
    for report in reports:
        if (report.get('schema') != 3 or report.get('app') != 'smartfit'
                or report.get('reportType') != 'solid_frame_performance' or report.get('material') != 'solid'):
            raise ValueError('Only schema-3 solid raw-frame reports are accepted')
        metadata = report.get('metadata', {})
        if (not re.fullmatch(r'[0-9a-f]{40}', str(metadata.get('appSource', '')))
                or not re.fullmatch(r'[0-9a-f]{64}', str(metadata.get('sourceFingerprint', '')))
                or metadata.get('buildMode') not in ('profile', 'release')
                or metadata.get('flavor') != 'internal' or metadata.get('rendererVerified') is not True
                or metadata.get('isEmulator') is not False):
            raise ValueError('Real-device source/build/renderer identity is missing')
        common = {key: metadata.get(key) for key in COMMON_KEYS}
        if any(value is None for value in common.values()):
            raise ValueError('Required source/device identity is unavailable')
        if identity is None:
            identity = common
        elif identity != common:
            raise ValueError('Different build sources/devices/renderers cannot fill the same matrix')
        for case_id, case in report.get('cases', {}).items():
            if case_id not in EXPECTED or case_id in cells:
                raise ValueError('Unsupported or duplicate case ID')
            value = validate_case(report, case_id, case)
            if conditions_identity is None:
                conditions_identity = value['conditionsIdentity']
            elif conditions_identity != value['conditionsIdentity']:
                raise ValueError('Viewport/text scale/starfield/backend differs between cells')
            cells[case_id] = value
    missing = [case for case in EXPECTED if case not in cells]
    return {'schema': 'smartfit-solid-matrix@1', 'material': 'solid', 'identity': identity,
            'expectedCells': 10, 'capturedCells': len(cells), 'missing': missing,
            'allTenP99Pass': not missing and all(cell['rasterP99Pass'] for cell in cells.values()),
            'represents120HzDeviceAcceptance': not missing and all(cell['is120HzDeviceSample'] for cell in cells.values()),
            'requiresUserOverBudgetReview': True,
            'cells': cells, 'statistics': 'Original integer us; exact nearest-rank; 120Hz P99 <8330us, counts >8330us separately.',
            'limits': 'No measured display-present FPS, dropped-frame rate or hardware GPU completion is inferred.'}

def render(matrix):
    rows = ['# Solid surface real-workload matrix', '',
            '| Theme | Workload | Frames | UI P99 ms | Raster P99 ms | >8.33ms | >actual period | P99 |',
            '| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |']
    for case_id in EXPECTED:
        theme, scene = case_id.split('__')
        cell = matrix['cells'].get(case_id)
        if cell is None:
            rows.append(f'| {theme} | {scene} | — | — | — | — | — | missing |')
            continue
        r, b = cell['raster'], cell['build']
        rows.append(f"| {theme} | {scene} | {r['count']} | {b['p99Us']/1000:.3f} | {r['p99Us']/1000:.3f} | "
                    f"{r['over8_33msCount']} | {cell['actualPeriodOverBudgetFrames']} | "
                    f"{'PASS' if cell['rasterP99Pass'] else 'FAIL'} |")
    rows += ['', matrix['statistics'], '', matrix['limits'], '',
             'P99 is only one criterion. Over-budget count/rate requires user review; no overall acceptance is inferred.',
             'A non-120Hz sample cannot represent acceptance on a 120Hz display even if its P99 is below 8.33ms.',
             'Bottom-bar workload means the existing input/drawer/library/back flow, not navigation tabs.',
             'Historical +18 light plan-card 4.607ms is a histogram upper-bound reference from another build; no paired causal delta is computed.']
    return '\n'.join(rows) + '\n'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reports', nargs='+')
    parser.add_argument('-o', '--output')
    parser.add_argument('--json-output')
    args = parser.parse_args()
    matrix = build_matrix([load_report(path) for path in args.reports])
    contents = render(matrix)
    if args.output:
        with Path(args.output).open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(contents)
    else:
        print(contents, end='')
    if args.json_output:
        with Path(args.json_output).open('x', encoding='utf-8', newline='\n') as stream:
            json.dump(matrix, stream, indent=2); stream.write('\n')

if __name__ == '__main__':
    main()
