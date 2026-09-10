import test from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
import { createServer } from 'node:net'
import http from 'node:http'
import { fileURLToPath } from 'node:url'
import { setTimeout as delay } from 'node:timers/promises'

test('AWS runtime: custom port, readiness, keep-alive and graceful shutdown', { timeout: 20000 }, async () => {
  const probe = createServer()
  probe.listen(0, '127.0.0.1')
  await once(probe, 'listening')
  const port = probe.address().port
  await new Promise((resolve) => probe.close(resolve))
  const child = spawn(process.execPath, ['server.mjs'], {
    cwd: fileURLToPath(new URL('../', import.meta.url)),
    env: { ...process.env, PORT: String(port), NODE_ENV: 'test' },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  let logs = ''
  child.stdout.on('data', (data) => {
    logs += data
  })
  child.stderr.on('data', (data) => {
    logs += data
  })
  const agent = new http.Agent({ keepAlive: true, maxSockets: 1 })
  const request = (path) =>
    new Promise((resolve, reject) => {
      http
        .get({ host: '127.0.0.1', port, path, agent }, (response) => {
          const socket = response.socket
          let body = ''
          response.on('data', (data) => {
            body += data
          })
          response.on('end', () => resolve({ status: response.statusCode, headers: response.headers, socket, body }))
        })
        .on('error', reject)
    })
  try {
    let ready
    for (let i = 0; i < 100; i++) {
      assert.equal(child.exitCode, null, logs)
      try {
        ready = await request('/healthz')
        break
      } catch {
        await delay(100)
      }
    }
    assert.ok(ready, logs)
    assert.equal(ready.status, 200)
    assert.deepEqual(JSON.parse(ready.body), { status: 'ok' })
    assert.match(ready.headers['keep-alive'], /timeout=65/)
    const home = await request('/')
    assert.equal(home.status, 200)
    // Regression: Node's default closes this socket after five seconds.
    await delay(6000)
    const afterIdle = await request('/healthz')
    assert.equal(afterIdle.status, 200)
    assert.equal(afterIdle.socket, home.socket)
    const exited = once(child, 'exit')
    child.kill('SIGTERM')
    const [code, signal] = await exited
    assert.equal(code, 0, logs)
    assert.equal(signal, null)
  } finally {
    agent.destroy()
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL')
  }
})
