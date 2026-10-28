// average-load test: the open model, a fixed arrival rate, whatever the API does
import http from 'k6/http';
import { check } from 'k6';
import { SLO, BASE, TAGS, student } from './slo.js';

const RATE = Number(__ENV.RATE || 20);

export const options = {
  scenarios: {
    average: {
      executor: 'constant-arrival-rate',
      rate: RATE,              // new iterations ...
      timeUnit: '1s',          // ... per second
      duration: __ENV.DURATION || '40s',
      preAllocatedVUs: 20,     // VUs ready to start iterations
      maxVUs: 200,
    },
  },
  thresholds: SLO,
};

export default function () {
  const res = http.get(`${BASE}/api/courses?user=${student()}`, TAGS);
  check(res, { 'status is 200': (r) => r.status === 200 });
}
