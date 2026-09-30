#!/usr/bin/env python3
"""Read-only Linux/cgroup-v2 radar memory recorder and conservative window check.

No deployment, SSH, environment reads, forced refreshes or load generation.
See docs/backend/librewxr-capacity-and-observability.md. A passing memory
screen is not production sign-off.
"""
import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.request

MIB = 1024 ** 2
CONTAINER = 'librewxr-librewxr-1'
METADATA = 'http://127.0.0.1:8080/public/weather-maps.json'
EVENT_KEYS = ('high', 'max', 'oom', 'oom_kill')
PHASES = {
    'ifs_start': 'Fetching ECMWF IFS:',
    'ifs_done': 'ECMWF IFS updated:',
    'nowcast_done': 'Nowcast generation: 6 frames',
    'refresh_done': 'fetch cycle complete in',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=20)
    # Never forward Docker errors: some contain configuration or log contents.
    require(result.returncode == 0, 'A required Docker read failed')
    return result.stdout


def pairs(raw):
    return {k: int(v) for k, v in (line.split() for line in raw.splitlines())}


def pressure(raw):
    result = {}
    for line in raw.splitlines():
        kind, *values = line.split()
        fields = dict(value.split('=') for value in values)
        result[kind] = {'avg10': float(fields['avg10']), 'total': int(fields['total'])}
    require(all(key in result for key in ('some', 'full')), 'Incomplete pressure data')
    return result


def identity(container):
    # Select individual safe fields; never inspect Config.Env or full State.
    template = '{"id":{{json .Id}},"image":{{json .Image}},"pid":{{.State.Pid}},' \
        '"started":{{json .State.StartedAt}},"restarts":{{.RestartCount}},' \
        '"running":{{.State.Running}},"dockerLimit":{{.HostConfig.Memory}}}'
    value = json.loads(command('docker', 'inspect', '--format', template, container))
    require(value['running'] and value['pid'] > 0, 'Radar container is not running')
    return value


def snapshot(container):
    ident = identity(container)
    entry = next(line[3:] for line in Path(f'/proc/{ident["pid"]}/cgroup').read_text().splitlines()
                 if line.startswith('0::'))
    cgroup = Path('/sys/fs/cgroup') / entry.lstrip('/')
    require(cgroup.resolve().is_relative_to(Path('/sys/fs/cgroup')), 'Invalid cgroup path')
    read = lambda name: (cgroup / name).read_text().strip()
    memory = {key: int(read('memory.' + key))
              for key in ('current', 'max', 'peak', 'swap.current')}
    memory['events'] = pairs(read('memory.events'))
    memory['pressure'] = pressure(read('memory.pressure'))
    memory['ioPressure'] = pressure(read('io.pressure'))
    meminfo = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    host = {key: int(meminfo[key].split()[0]) * 1024 for key in ('MemTotal', 'MemAvailable')}
    vmstat = pairs(Path('/proc/vmstat').read_text())
    host.update({key: vmstat[key] * os.sysconf('SC_PAGE_SIZE') for key in ('pswpin', 'pswpout')})
    host['pressure'] = pressure(Path('/proc/pressure/memory').read_text())
    with urllib.request.urlopen(METADATA, timeout=10) as response:
        payload = response.read(1024 * 1024 + 1)
    require(len(payload) <= 1024 * 1024, 'Unexpected metadata size')
    metadata = json.loads(payload)
    frames = {key: [frame['time'] for frame in metadata['radar'][key]]
              for key in ('past', 'nowcast')}
    frames['generated'] = metadata['generated']
    require(identity(container) == ident, 'Container changed during sample')
    return {'type': 'sample', 'at': time.time(), 'monotonic': time.monotonic(),
            'boot': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
            'identity': ident, 'memory': memory, 'host': host, 'frames': frames}


def phase_events(container, start, end):
    def iso(value):
        return dt.datetime.fromtimestamp(value, dt.timezone.utc).isoformat()
    # Only capture the selected time window; fail if the tail could be truncated.
    result = subprocess.run(['docker', 'logs', '--timestamps', '--since', iso(start),
                             '--until', iso(end), '--tail', '10000', container],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=20)
    require(result.returncode == 0, 'Could not read refresh phase evidence')
    lines = result.stdout.splitlines()
    require(len(lines) < 10000, 'Refresh log window may be truncated')
    events = []
    for line in lines:
        for kind, marker in PHASES.items():
            if marker in line:
                # Save the timestamp/category only, never arbitrary log text.
                stamp = line.split(' ', 1)[0]
                require(re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z', stamp),
                        'Unrecognized Docker log timestamp')
                at = dt.datetime.fromisoformat(stamp.replace('Z', '+00:00')).timestamp()
                events.append({'at': at, 'kind': kind})
    return sorted(events, key=lambda item: item['at'])


def emit(value):
    print(json.dumps(value, separators=(',', ':'), allow_nan=False), flush=True)


def record(args):
    require(5 <= args.interval <= 60, 'Interval must be 5–60 seconds')
    require(60 <= args.duration <= 7200, 'Duration must be 60–7200 seconds')
    emit({'type': 'start', 'schema': 1, 'interval': args.interval})
    first = snapshot(args.container)
    emit(first)
    last = first
    deadline = time.monotonic() + args.duration
    while time.monotonic() < deadline:
        time.sleep(min(args.interval, max(0, deadline - time.monotonic())))
        last = snapshot(args.container)
        emit(last)
    emit({'type': 'phases', 'events': phase_events(args.container, first['at'], last['at'])})
    emit({'type': 'complete'})


def number(value):
    require(isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and value >= 0, 'Invalid or missing numeric measurement')
    return value


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def frame_state(sample):
    """Validate metadata separately so it cannot erase kernel failure evidence."""
    frames = sample['frames']
    require(len(frames['past']) == 4 and len(frames['nowcast']) in (5, 6),
            'Expected four past and five transitional or six complete forecasts')
    for key in ('past', 'nowcast'):
        for stamp in frames[key]:
            number(stamp)
        require(all(b - a == 600 for a, b in zip(frames[key], frames[key][1:])),
                'Frame cadence must remain ten minutes')
    require(frames['nowcast'][0] == frames['past'][-1] + 600,
            'Forecast window is not aligned with latest observation')
    number(frames['generated'])
    require(-60 <= sample['at'] - frames['past'][-1] <= 1200,
            'Latest observed frame is stale or future-dated')
    require(-60 <= sample['at'] - frames['generated'] <= 1200,
            'Metadata generation is stale or future-dated')
    return frames


def transition_evidence(samples, states):
    """A newly observed frame may expire one old forecast while six regenerate.

    Only a coherent five-frame remainder restored within 120 seconds is
    tolerated. This is a conservative diagnostic allowance, not a freshness SLA.
    """
    transitions, issues = [], []
    index = 0
    while index < len(states):
        if states[index] is None or len(states[index]['nowcast']) != 5:
            index += 1
            continue
        begin = index
        while index < len(states) and states[index] is not None and len(states[index]['nowcast']) == 5:
            index += 1
        state = states[begin]
        previous = states[begin - 1] if begin else None
        following = states[index] if index < len(states) else None
        end_time = samples[index]['at'] if index < len(samples) else samples[-1]['at']
        # Include the preceding sample interval in the upper bound when known.
        duration_bound = end_time - samples[max(0, begin - 1)]['at']
        unchanged = all(s['past'] == state['past'] and s['nowcast'] == state['nowcast']
                        for s in states[begin:index])
        expiry_matches = previous is None or (
            previous['past'][1:] + [previous['nowcast'][0]] == state['past']
            and previous['nowcast'][1:] == state['nowcast'])
        restored = bool(following and len(following['nowcast']) == 6
                        and following['past'] == state['past']
                        and following['nowcast'][:5] == state['nowcast'])
        accepted = unchanged and expiry_matches and restored and duration_bound <= 120
        transitions.append({'start': samples[begin]['at'], 'end': end_time,
                            'samples': index - begin, 'durationUpperBoundSeconds': round(duration_bound, 1),
                            'priorCompleteSampleObserved': previous is not None,
                            'sixForecastsRestored': restored, 'accepted': accepted})
        if not accepted:
            issues.append('Five-forecast transition is unaligned, persists over 120 seconds, or did not restore six forecasts')
    return transitions, issues


def assess(rows, expected_radar_mib):
    require(expected_radar_mib > 0, 'Expected radar memory must be positive')
    require(len(rows) >= 5 and rows[0] == {'type': 'start', 'schema': 1, 'interval': rows[0].get('interval')}
            and rows[-1] == {'type': 'complete'} and rows[-2]['type'] == 'phases',
            'Incomplete recording; collect a new complete window')
    interval = number(rows[0]['interval'])
    require(5 <= interval <= 60, 'Unsupported sample interval')
    samples = rows[1:-2]
    require(len(samples) >= 3 and all(s['type'] == 'sample' for s in samples), 'Missing samples')
    first, last = samples[0], samples[-1]
    limit = expected_radar_mib * MIB
    issues = set()
    frame_issues = set()
    frame_states = []
    for sample in samples:
        require(sample['identity'] == first['identity'] and sample['boot'] == first['boot'],
                'Container, image, restart count or host changed during window')
        memory, host = sample['memory'], sample['host']
        for key in ('current', 'max', 'peak', 'swap.current'):
            number(memory[key])
        for key in ('MemTotal', 'MemAvailable', 'pswpin', 'pswpout'):
            number(host[key])
        for key in EVENT_KEYS:
            number(memory['events'][key])
        for metric in (memory['pressure'], memory['ioPressure'], host['pressure']):
            for kind in ('some', 'full'):
                number(metric[kind]['avg10'])
                number(metric[kind]['total'])
        require(number(sample['at']) and number(sample['monotonic']), 'Invalid time')
        require(memory['max'] == limit and sample['identity']['dockerLimit'] == limit,
                'Docker/kernel limits do not match the expected radar allowance')
        require(host['MemTotal'] == first['host']['MemTotal'], 'Host RAM changed during window')
        try:
            frame_states.append(frame_state(sample))
        except (ValueError, KeyError, TypeError, IndexError) as error:
            frame_states.append(None)
            frame_issues.add(str(error) if type(error) is ValueError else 'Missing or malformed frame metadata')
    duration = last['monotonic'] - first['monotonic']
    coverage = []
    if duration < 600:
        coverage.append('At least ten minutes of continuous evidence is required')
    swap_rates = []
    for before, after in zip(samples, samples[1:]):
        elapsed = after['monotonic'] - before['monotonic']
        require(0 < elapsed <= interval + 45, 'Gap in kernel samples; repeat observation')
        require(abs(after['at'] - before['at'] - elapsed) <= 5, 'Clock jumped during observation')
        for key in EVENT_KEYS:
            require(after['memory']['events'][key] >= before['memory']['events'][key],
                    'Memory counters reset during observation')
        for group, key in (('memory', 'pressure'), ('memory', 'ioPressure'), ('host', 'pressure')):
            for kind in ('some', 'full'):
                require(after[group][key][kind]['total'] >= before[group][key][kind]['total'],
                        'Pressure counters reset during observation')
        changes = [after['host'][key] - before['host'][key] for key in ('pswpin', 'pswpout')]
        require(min(changes) >= 0, 'Host swap counters reset during observation')
        swap_rates.append(sum(changes) / elapsed / MIB)
    for before, after in zip(frame_states, frame_states[1:]):
        if before and after and after['past'][-1] < before['past'][-1]:
            frame_issues.add('Observed frame timestamp regressed')
    transitions, transition_issues = transition_evidence(samples, frame_states)
    frame_issues.update(transition_issues)
    events = rows[-2]['events']
    require(all(e['kind'] in PHASES and first['at'] <= number(e['at']) <= last['at'] for e in events),
            'Refresh phases fall outside recording')
    # Require a complete hourly IFS -> nowcast -> publication sequence within
    # the baseline, with 60 seconds of subsequent kernel samples to settle.
    cursor = first['at']
    for kind in ('ifs_start', 'ifs_done', 'nowcast_done', 'refresh_done'):
        candidates = [e['at'] for e in events if e['kind'] == kind and e['at'] > cursor]
        if not candidates:
            coverage.append('Missing complete hourly IFS / nowcast / refresh phase evidence')
            break
        cursor = min(candidates)
    baseline_frames = frame_states[0]
    published = [s for s, frames in zip(samples, frame_states)
                 if frames and baseline_frames and len(frames['nowcast']) == 6 and s['at'] >= cursor
                 and frames['past'][-1] > baseline_frames['past'][-1]
                 and frames['generated'] > baseline_frames['generated']]
    final_frames = frame_states[-1]
    settled = final_frames and all(frames and len(frames['nowcast']) == 6
                                  and frames['past'][-1] == final_frames['past'][-1]
                                  for s, frames in zip(samples, frame_states) if s['at'] >= last['at'] - 60)
    if not published or last['at'] - published[0]['at'] < 60 or not settled:
        coverage.append('Missing new complete publication plus 60-second settling interval')
    coverage.extend(sorted(frame_issues))
    deltas = {key: last['memory']['events'][key] - first['memory']['events'][key] for key in EVENT_KEYS}
    if any(deltas.values()):
        issues.add('New memory-high/limit/OOM events occurred')
    ram_peak = max(s['memory']['current'] for s in samples)
    host_min = min(s['host']['MemAvailable'] for s in samples)
    swap_growth = max(s['memory']['swap.current'] for s in samples) - first['memory']['swap.current']
    psi = [s['memory']['pressure']['some']['avg10'] for s in samples]
    host_psi = [s['host']['pressure']['some']['avg10'] for s in samples]
    if ram_peak > limit * .9:
        issues.add('Sampled radar RAM exceeded 90% of its limit')
    if host_min < 512 * MIB:
        issues.add('Host available RAM fell below 512 MiB')
    if swap_growth > 64 * MIB:
        issues.add('Radar swap grew by more than 64 MiB')
    if percentile(swap_rates, .95) > 1:
        issues.add('Host swap I/O p95 exceeded 1 MiB/s')
    if max(psi + host_psi) > 5 or max(percentile(psi, .95), percentile(host_psi, .95)) > 1:
        issues.add('Memory some-PSI exceeded 5% peak or 1% p95')
    return {'memoryScreen': 'fail' if issues else 'incomplete' if coverage else 'pass',
            'productionReady': False, 'issues': sorted(issues), 'missingCoverage': coverage,
            'sampleCount': len(samples), 'durationSeconds': round(duration, 1),
            'frameTransitions': transitions,
            'hostBudgetInformation': {
                'hostTotalMiB': round(first['host']['MemTotal'] / MIB, 1),
                'radarLimitMiB': expected_radar_mib, 'assumedApiLimitMiB': 384,
                'remainingAfterLimitsMiB': round(first['host']['MemTotal'] / MIB - expected_radar_mib - 384, 1),
                'note': 'Informational: verify actual service inventory separately. The proposed larger-host reserve is not imposed on this memory screen.'},
            'memoryEventsDelta': deltas, 'radarRamPeakMiB': round(ram_peak / MIB, 1),
            'radarRamFinalMiB': round(last['memory']['current'] / MIB, 1),
            'kernelLifetimePeakStartMiB': round(first['memory']['peak'] / MIB, 1),
            'kernelLifetimePeakEndMiB': round(last['memory']['peak'] / MIB, 1),
            'hostAvailableMinMiB': round(host_min / MIB, 1),
            'radarSwapStartMiB': round(first['memory']['swap.current'] / MIB, 1),
            'radarSwapFinalMiB': round(last['memory']['swap.current'] / MIB, 1),
            'radarSwapGrowthMiB': round(swap_growth / MIB, 1),
            'hostSwapIoP95MiBps': round(percentile(swap_rates, .95), 3),
            'hostSwapIoPeakMiBps': round(max(swap_rates), 3),
            'radarMemoryPsiPeakPct': max(psi), 'hostMemoryPsiPeakPct': max(host_psi),
            'radarIoPsiPeakPct': max(s['memory']['ioPressure']['some']['avg10'] for s in samples),
            'radarMemoryStallPct': round((last['memory']['pressure']['some']['total'] - first['memory']['pressure']['some']['total']) / duration / 10000, 3),
            'next': 'Review service inventory, peak/settled memory and I/O PSI; correlate bounded concurrent API/tile latency tests. This window does not establish production traffic capacity.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    capture = commands.add_parser('record')
    capture.add_argument('--container', default=CONTAINER)
    capture.add_argument('--duration', type=int, default=4800)
    capture.add_argument('--interval', type=int, default=10)
    report = commands.add_parser('assess')
    report.add_argument('recording', type=Path)
    report.add_argument('--expected-radar-mib', type=int, required=True)
    args = parser.parse_args()
    try:
        if args.action == 'record':
            record(args)
            return 0
        rows = [json.loads(line) for line in args.recording.read_text().splitlines()]
        result = assess(rows, args.expected_radar_mib)
        emit(result)
        return {'pass': 0, 'fail': 1, 'incomplete': 2}[result['memoryScreen']]
    except (ValueError, KeyError, TypeError, IndexError, StopIteration, OSError,
            subprocess.SubprocessError, urllib.error.URLError) as error:
        # ValueError messages are controlled here except parse errors; never
        # print exception details from external commands, endpoints or files.
        emit({'memoryScreen': 'incomplete', 'productionReady': False,
              'error': str(error) if type(error) is ValueError else 'Required evidence is missing or unreadable'})
        return 2
    except KeyboardInterrupt:
        emit({'type': 'interrupted'})
        return 2


if __name__ == '__main__':
    sys.exit(main())
