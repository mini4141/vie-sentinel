// Short k6 load test. Usage: k6 run -e BASE_URL=... -e API_KEY=... scripts/load.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 5,
  duration: '30s',
  thresholds: { http_req_failed: ['rate<0.01'], http_req_duration: ['p(95)<1500'] },
};

const run = Date.now();

export default function () {
  const body = JSON.stringify({
    idempotencyKey: `k6-${run}-${__VU}-${__ITER}`,
    userId: `k6-user-${run}-${__VU}-${Math.floor(__ITER / 3)}`,
    deviceId: `k6-dev-${run}-${__VU}`,
    ip: '10.1.1.1',
    type: 'INSTALL',
    occurredAt: new Date().toISOString(),
  });
  const res = http.post(`${__ENV.BASE_URL}/events`, body, {
    headers: { 'Content-Type': 'application/json', 'X-API-Key': __ENV.API_KEY },
  });
  check(res, { 'status 200': (r) => r.status === 200 });
}
