#!/usr/bin/env python3
# GENERATED SAMPLE: a week of the API's info log (13-20 Oct 2026), in the format api.py writes, never rotated.
# Usage: gen_week.py FILE SIZE_BYTES   (adapted from M02-L05 gen_fill.py)
import sys, random, time
p, size = sys.argv[1], int(sys.argv[2]); r = random.Random(2410)
t = time.mktime(time.strptime('2026-10-13 00:00:01', '%Y-%m-%d %H:%M:%S')); end = time.mktime(time.strptime('2026-10-20 05:40:00', '%Y-%m-%d %H:%M:%S'))
n = 0; step = (end - t) / (size / 62)
with open(p, 'w') as f:
    while n < size:
        t += r.random() * 2 * step
        lvl = r.choice(['INFO'] * 19 + ['WARN'])
        msg = f'GET /api/courses/{r.randint(1, 240)} 200 {r.randint(4, 90)}ms' if lvl == 'INFO' else f'GET /api/courses/{r.randint(1, 240)} slow response {r.randint(900, 2400)}ms'
        s = time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(min(t, end))) + f' {lvl} {msg}\n'
        f.write(s); n += len(s)
print(p, n)
