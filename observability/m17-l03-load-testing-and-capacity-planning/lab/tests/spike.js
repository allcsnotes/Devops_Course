// spike test: the launch email goes out, traffic jumps from 5 to 150 requests a second
import http from 'k6/http';
import { check } from 'k6';
import { SLO, BASE, TAGS, student } from './slo.js';

export const options = {
  scenarios: {
    launch: {
      executor: 'ramping-arrival-rate',
      startRate: 5, timeUnit: '1s',
      preAllocatedVUs: 50, maxVUs: 500,
      stages: [
        { target: 5, duration: '10s' },     // a quiet evening
        { target: 150, duration: '10s' },   // the launch email lands
        { target: 150, duration: '20s' },   // everyone clicks
        { target: 5, duration: '10s' },
      ],
    },
  },
  thresholds: SLO,
};

export default function () {
  const res = http.get(`${BASE}/api/courses?user=${student()}`, TAGS);
  check(res, { 'status is 200': (r) => r.status === 200 });
}
