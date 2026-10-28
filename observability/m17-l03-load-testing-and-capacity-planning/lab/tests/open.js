// the open model: 20 new requests every second, even while the API is stuck
import http from 'k6/http';
import { BASE, TAGS, student } from './slo.js';

export const options = {
  scenarios: {
    open: {
      executor: 'constant-arrival-rate',
      rate: 20, timeUnit: '1s', duration: '40s',
      preAllocatedVUs: 120, maxVUs: 200,   // enough VUs to wait out a stall
    },
  },
};

export default function () {
  http.get(`${BASE}/api/courses?user=${student()}`, TAGS);
}
