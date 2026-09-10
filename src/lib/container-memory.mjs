import fs from 'node:fs'
import os from 'node:os'

// AL2023 and modern Docker use cgroup v2; older hosts may still use v1.
export function containerMemory(read = (path) => fs.readFileSync(path, 'utf8'), total = os.totalmem()) {
  const paths = [
    ['/sys/fs/cgroup/memory.current', '/sys/fs/cgroup/memory.max'],
    ['/sys/fs/cgroup/memory/memory.usage_in_bytes', '/sys/fs/cgroup/memory/memory.limit_in_bytes'],
  ]
  for (const [usagePath, limitPath] of paths) {
    try {
      const used = Number(read(usagePath).trim())
      const limit = Number(read(limitPath).trim())
      if (!Number.isFinite(used) || used < 0) continue
      return {
        memUsedBytes: used,
        memTotalBytes: Number.isFinite(limit) && limit > 0 ? Math.min(limit, total) : total,
      }
    } catch {
      // Try the other cgroup layout, then fall back to OS memory statistics.
    }
  }
  return { memUsedBytes: total - os.freemem(), memTotalBytes: total }
}
