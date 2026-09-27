import { useCallback, useMemo, useRef, useState } from 'react'
import { collectEntries, entriesFromFileList, findDuplicates, regroupByHash, wastedBytes } from './lib/scan.js'
import { formatBytes } from './lib/format.js'
import { downloadDeleteScript } from './lib/deleteScript.js'
import GroupCard from './components/GroupCard.jsx'
import ScanProgress from './components/ScanProgress.jsx'

const supportsFsAccess = typeof window !== 'undefined' && 'showDirectoryPicker' in window

function defaultSelection(groups) {
  const next = new Set()
  for (const group of groups) {
    for (const file of group.files.slice(1)) next.add(file.path)
  }
  return next
}

export default function App() {
  const [groups, setGroups] = useState([])
  const [entries, setEntries] = useState([])
  const [selected, setSelected] = useState(() => new Set())
  const [phase, setPhase] = useState('idle') // idle | scanning | done
  const [progress, setProgress] = useState({ hashed: 0, total: 0 })
  const [status, setStatus] = useState('Wähle einen Ordner zum Scannen.')
  const [error, setError] = useState(null)
  const [canDelete, setCanDelete] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [sourceName, setSourceName] = useState(null)

  const rootHandleRef = useRef(null)
  const inputRef = useRef(null)

  const stats = useMemo(() => {
    const duplicateCount = groups.reduce((n, g) => n + g.files.length, 0)
    const reclaimable = groups.reduce((n, g) => n + wastedBytes(g.files), 0)
    return { duplicateCount, groupCount: groups.length, reclaimable }
  }, [groups])

  const runScan = useCallback(async (getEntries) => {
    setError(null)
    setGroups([])
    setEntries([])
    setSelected(new Set())
    setProgress({ hashed: 0, total: 0 })
    setPhase('scanning')
    try {
      setStatus('Dateien werden gesammelt …')
      const collected = await getEntries()
      if (collected.length === 0) {
        setPhase('done')
        setStatus('Keine Dateien gefunden.')
        return
      }
      setStatus('Duplikate werden gesucht …')
      const found = await findDuplicates(collected, {
        onProgress: (p) => setProgress(p),
      })
      const hashedEntries = found.flatMap((g) => g.files)
      setGroups(found)
      setEntries(hashedEntries)
      setSelected(defaultSelection(found))
      setPhase('done')
      setStatus(
        found.length
          ? `${found.length} Duplikat-Gruppe(n) gefunden.`
          : 'Keine Duplikate gefunden. 🎉',
      )
    } catch (err) {
      if (err?.name === 'AbortError') {
        setPhase('idle')
        setStatus('Abgebrochen.')
        return
      }
      setError(err?.message || String(err))
      setPhase('done')
    }
  }, [])

  const pickFolder = useCallback(async () => {
    if (!supportsFsAccess) {
      inputRef.current?.click()
      return
    }
    try {
      const handle = await window.showDirectoryPicker({ id: 'duplicate-finder' })
      rootHandleRef.current = handle
      setCanDelete(true)
      setSourceName(handle.name)
      await runScan(() => collectEntries(handle))
    } catch (err) {
      if (err?.name === 'AbortError') return
      // The picker can be unavailable or blocked (e.g. embedded/restricted
      // modes) even when the API exists — fall back to the read-only picker.
      inputRef.current?.click()
    }
  }, [runScan])

  const onInputChange = useCallback(async (event) => {
    const files = event.target.files
    event.target.value = ''
    if (!files?.length) return
    rootHandleRef.current = null
    setCanDelete(false)
    setSourceName(files[0].webkitRelativePath?.split('/')[0] || 'Auswahl')
    await runScan(async () => entriesFromFileList(files))
  }, [runScan])

  const toggle = useCallback((path) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(path)) next.delete(path)
      else next.add(path)
      return next
    })
  }, [])

  const selectAllInGroup = useCallback((group) => {
    setSelected((prev) => {
      const next = new Set(prev)
      for (const file of group.files.slice(1)) next.add(file.path)
      return next
    })
  }, [])

  const clearGroup = useCallback((group) => {
    setSelected((prev) => {
      const next = new Set(prev)
      for (const file of group.files) next.delete(file.path)
      return next
    })
  }, [])

  const deleteSelected = useCallback(async () => {
    const handle = rootHandleRef.current
    if (!handle || selected.size === 0) return
    const ok = window.confirm(
      `${selected.size} Datei(en) werden ENDGÜLTIG gelöscht — im Browser gibt es keinen Papierkorb. Fortfahren?`,
    )
    if (!ok) return

    setDeleting(true)
    setError(null)
    try {
      const permission = await handle.requestPermission?.({ mode: 'readwrite' })
      if (permission && permission !== 'granted') {
        setError('Schreibzugriff auf den Ordner wurde verweigert.')
        return
      }
      const byPath = new Map(entries.map((e) => [e.path, e]))
      const failed = []
      let deleted = 0
      for (const path of selected) {
        const entry = byPath.get(path)
        if (!entry?.parentHandle) continue
        try {
          await entry.parentHandle.removeEntry(entry.name)
          deleted += 1
        } catch {
          failed.push(path)
        }
      }
      const remaining = entries.filter((e) => !selected.has(e.path) || failed.includes(e.path))
      const regrouped = regroupByHash(remaining)
      setEntries(remaining)
      setGroups(regrouped)
      setSelected(defaultSelection(regrouped))
      setStatus(`${deleted} Datei(en) gelöscht.${failed.length ? ` ${failed.length} fehlgeschlagen.` : ''}`)
    } finally {
      setDeleting(false)
    }
  }, [entries, selected])

  const downloadScript = useCallback(() => {
    if (selected.size === 0) return
    downloadDeleteScript([...selected], sourceName)
  }, [selected, sourceName])

  const busy = phase === 'scanning'

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="brand__mark" aria-hidden>🔍</span>
          <div>
            <h1>Duplicate Finder</h1>
            <p>Findet exakte Datei-Duplikate über SHA-256-Inhaltsvergleich — alles lokal im Browser.</p>
          </div>
        </div>
        <div className="topbar__actions">
          <button type="button" className="primary" onClick={pickFolder} disabled={busy || deleting}>
            {busy ? 'Scannt …' : 'Ordner wählen'}
          </button>
          <input
            ref={inputRef}
            type="file"
            webkitdirectory=""
            directory=""
            multiple
            hidden
            onChange={onInputChange}
          />
        </div>
      </header>

      <main className="content">
        <div className="statusline">
          <span className="statusline__text">{status}</span>
          {sourceName && <span className="statusline__source">Ordner: {sourceName}</span>}
        </div>

        {error && <div className="alert">{error}</div>}

        {busy && <ScanProgress progress={progress} />}

        {!busy && groups.length > 0 && (
          <>
            <div className="stats">
              <div className="stat">
                <span className="stat__value">{stats.groupCount}</span>
                <span className="stat__label">Gruppen</span>
              </div>
              <div className="stat">
                <span className="stat__value">{stats.duplicateCount}</span>
                <span className="stat__label">Dateien</span>
              </div>
              <div className="stat">
                <span className="stat__value">{formatBytes(stats.reclaimable)}</span>
                <span className="stat__label">Einsparbar</span>
              </div>
              <div className="stat">
                <span className="stat__value">{selected.size}</span>
                <span className="stat__label">Ausgewählt</span>
              </div>
            </div>

            <div className="toolbar">
              <button type="button" onClick={() => setSelected(defaultSelection(groups))}>
                Duplikate markieren (erste behalten)
              </button>
              <button type="button" className="ghost" onClick={() => setSelected(new Set())}>
                Auswahl leeren
              </button>
              {canDelete ? (
                <button
                  type="button"
                  className="danger"
                  onClick={deleteSelected}
                  disabled={selected.size === 0 || deleting}
                >
                  {deleting ? 'Lösche …' : `Ausgewählte löschen (${selected.size})`}
                </button>
              ) : (
                <button
                  type="button"
                  className="danger"
                  onClick={downloadScript}
                  disabled={selected.size === 0}
                >
                  Lösch-Skript herunterladen ({selected.size})
                </button>
              )}
            </div>

            {!canDelete && (
              <div className="note">
                Dein Browser erlaubt kein direktes Löschen von Dateien. Lade das Lösch-Skript
                herunter und führe es im gescannten Ordner aus – so klappt das Aufräumen in jedem
                Browser.
              </div>
            )}

            <div className="groups">
              {groups.map((group) => (
                <GroupCard
                  key={group.hash}
                  group={group}
                  selected={selected}
                  onToggle={toggle}
                  onSelectAll={selectAllInGroup}
                  onClearAll={clearGroup}
                />
              ))}
            </div>
          </>
        )}

        {!busy && groups.length === 0 && phase === 'done' && (
          <div className="empty">
            <div className="empty__icon" aria-hidden>✅</div>
            <p>{status}</p>
          </div>
        )}

        {phase === 'idle' && (
          <div className="empty">
            <div className="empty__icon" aria-hidden>📁</div>
            <p>Wähle einen Ordner, um nach exakten Duplikaten zu suchen.</p>
            <p className="empty__hint">
              Versteckte Dateien und Paket-Inhalte (z. B. .app) werden übersprungen.
            </p>
          </div>
        )}
      </main>
    </div>
  )
}
