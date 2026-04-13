import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:64529'

export const options = {
    scenarios: {
        create_users: {
            exec: 'createUsersScenario',
            executor: 'constant-arrival-rate',
            rate: 10,
            timeUnit: '1s',
            duration: '5m',
            preAllocatedVUs: 10,
            maxVUs: 20,
        },
        get_users: {
            exec: 'getUsersScenario',
            executor: 'constant-vus',
            vus: 4,
            duration: '5m',
            tags: { scenario: 'get_users' },
        },
    },
}

function randomSuffix() {
  return `${Date.now()}-${__VU}-${__ITER}-${Math.random().toString(16).slice(2, 8)}`
}

export function createUsersScenario() {
    const suffix = randomSuffix();
    const payload = JSON.stringify({
        username: `Test User ${suffix}`,
        email: `testuser${suffix}@example.com`,
        password: 'password'
    })

    const res = http.post(`${BASE_URL}/users`, payload, {
        headers: { 'Content-Type': 'application/json' },
        tags: { endpoint: 'POST /users' },
    })

    check(res, {
        'create user status is 201': (r) => r.status === 201,
        'create user has id': (r) => {
            if (r.status !== 201) return false
            const body = r.json()
            return body && body.id
        },
    })

  sleep(0.2)
}

export function getUsersScenario() {
  const res = http.get(`${BASE_URL}/users?offset=0&limit=50`, {
    tags: { endpoint: 'GET /users' },
  })

  check(res, {
    'get users status is 200': (r) => r.status === 200,
    'get users contains users array': (r) => {
      if (r.status !== 200) return false
      const body = r.json()
      return body && Array.isArray(body.users)
    },
  })

  sleep(0.2)
}
