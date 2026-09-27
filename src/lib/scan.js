// Duplicate detection: group by size first, then confirm with a SHA-256
// content hash — the same strategy as the original macOS app.

const SKIP_PACKAGE_EXTENSIONS = [
  '.app', '.bundle', '.framework', '.pkg', '.plugin', '.kext', '.xcodeproj',
]

// Hidden files and package descendants are skipped by default.
export function shouldSkip(name) {
  if (!name || name.startsWith('.')) return true
  const lower = name.toLowerCase()
  return SKIP_PACKAGE_EXTENSIONS.some((ext) => lower.endsWith(ext))
}

async function* walk(dirHandle, path) {
  for await (const handle of dirHandle.values()) {
    if (shouldSkip(handle.name)) continue
    const entryPath = path ? `${path}/${handle.name}` : handle.name
    if (handle.kind === 'file') {
      yield { handle, parentHandle: dirHandle, path: entryPath }
    } else if (handle.kind === 'directory') {
      yield* walk(handle, entryPath)
    }
  }
}

// Collect every file under a FileSystemDirectoryHandle (File System Access API).
export async function collectEntries(dirHandle) {
  const entries = []
  for await (const { handle, parentHandle, path } of walk(dirHandle, '')) {
    const file = await handle.getFile()
    entries.push({ name: handle.name, path, size: file.size, file, parentHandle })
  }
  return entries
}

// Fallback for <input type="file" webkitdirectory> (read-only, no delete).
export function entriesFromFileList(fileList) {
  return Array.from(fileList)
    .filter((f) => {
      const segments = (f.webkitRelativePath || f.name).split('/')
      return !segments.some(shouldSkip)
    })
    .map((f) => ({
      name: f.name,
      path: f.webkitRelativePath || f.name,
      size: f.size,
      file: f,
      parentHandle: null,
    }))
}

export async function hashFile(file) {
  const buffer = await file.arrayBuffer()
  const digest = await crypto.subtle.digest('SHA-256', buffer)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export function wastedBytes(files) {
  return files.slice(1).reduce((sum, f) => sum + f.size, 0)
}

export function regroupByHash(entries) {
  const byHash = new Map()
  for (const entry of entries) {
    if (!entry.hash) continue
    if (!byHash.has(entry.hash)) byHash.set(entry.hash, [])
    byHash.get(entry.hash).push(entry)
  }
  return [...byHash.entries()]
    .filter(([, files]) => files.length > 1)
    .map(([hash, files]) => ({
      hash,
      files: [...files].sort((a, b) => a.path.localeCompare(b.path)),
    }))
    .sort((a, b) => wastedBytes(b.files) - wastedBytes(a.files))
}

export async function findDuplicates(entries, { onProgress } = {}) {
  const bySize = new Map()
  for (const entry of entries) {
    if (!bySize.has(entry.size)) bySize.set(entry.size, [])
    bySize.get(entry.size).push(entry)
  }

  // Only files that share a size can be byte-identical.
  const candidates = []
  for (const group of bySize.values()) {
    if (group.length > 1) candidates.push(...group)
  }

  const hashed = []
  let done = 0
  onProgress?.({ hashed: 0, total: candidates.length })
  for (const entry of candidates) {
    try {
      const hash = await hashFile(entry.file)
      hashed.push({ ...entry, hash })
    } catch {
      // Unreadable file — skip it.
    }
    done += 1
    onProgress?.({ hashed: done, total: candidates.length })
  }

  return regroupByHash(hashed)
}
