// PITFALL, staged: the same student every time, so the API's cache answers almost everything
import http from 'k6/http';
import { check } from 'k6';
import { SLO, BASE, TAGS } from './slo.js';

export const options = {
  scenarios: {
    warm: {
      executor: 'constant-arrival-rate',
      rate: 150, timeUnit: '1s', duration: '30s',
      preAllocatedVUs: 20, maxVUs: 200,
    },
  },
  thresholds: SLO,
};

export default function () {
  const res = http.get(`${BASE}/api/courses?user=lukas`, TAGS);   // always lukas
  check(res, { 'status is 200': (r) => r.status === 200 });
}
