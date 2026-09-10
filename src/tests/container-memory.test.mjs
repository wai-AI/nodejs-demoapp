import test from 'node:test'
import assert from 'node:assert/strict'
import { containerMemory } from '../lib/container-memory.mjs'

const reader = (files) => (path) => {
  if (!(path in files)) throw Error('ENOENT')
  return files[path]
}

test('reads cgroup v2 memory usage and limit', () => {
  assert.deepEqual(
    containerMemory(
      reader({
        '/sys/fs/cgroup/memory.current': '100\n',
        '/sys/fs/cgroup/memory.max': '200\n',
      }),
      1000,
    ),
    { memUsedBytes: 100, memTotalBytes: 200 },
  )
})

test('handles unlimited cgroup v2 memory', () => {
  assert.deepEqual(
    containerMemory(
      reader({
        '/sys/fs/cgroup/memory.current': '100',
        '/sys/fs/cgroup/memory.max': 'max',
      }),
      1000,
    ),
    { memUsedBytes: 100, memTotalBytes: 1000 },
  )
})

test('falls back to cgroup v1 and caps its unlimited sentinel', () => {
  assert.deepEqual(
    containerMemory(
      reader({
        '/sys/fs/cgroup/memory/memory.usage_in_bytes': '100',
        '/sys/fs/cgroup/memory/memory.limit_in_bytes': '9223372036854771712',
      }),
      1000,
    ),
    { memUsedBytes: 100, memTotalBytes: 1000 },
  )
})

test('missing cgroup files do not break the monitoring endpoint', () => {
  const memory = containerMemory(reader({}))
  assert.ok(Number.isFinite(memory.memUsedBytes))
  assert.ok(memory.memTotalBytes > 0)
})
