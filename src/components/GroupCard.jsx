import { fileEmoji, formatBytes } from '../lib/format.js'
import { wastedBytes } from '../lib/scan.js'

export default function GroupCard({ group, selected, onToggle, onSelectAll, onClearAll }) {
  const { hash, files } = group
  const wasted = wastedBytes(files)

  return (
    <section className="group">
      <header className="group__head">
        <div>
          <div className="group__title">
            {files.length} identische Dateien
            <span className="group__hash" title="SHA-256">{hash.slice(0, 12)}…</span>
          </div>
          <div className="group__meta">Einsparbar: {formatBytes(wasted)}</div>
        </div>
        <div className="group__actions">
          <button type="button" onClick={() => onSelectAll(group)}>Alle außer erste</button>
          <button type="button" className="ghost" onClick={() => onClearAll(group)}>Auswahl aufheben</button>
        </div>
      </header>

      <ul className="filelist">
        {files.map((file, index) => {
          const isFirst = index === 0
          return (
            <li key={file.path} className={`file ${selected.has(file.path) ? 'is-selected' : ''}`}>
              <label className="file__check">
                <input
                  type="checkbox"
                  checked={selected.has(file.path)}
                  onChange={() => onToggle(file.path)}
                />
              </label>
              <span className="file__icon" aria-hidden>{fileEmoji(file.name)}</span>
              <div className="file__body">
                <div className="file__name">
                  {file.name}
                  {isFirst && <span className="badge">behalten</span>}
                </div>
                <div className="file__path" title={file.path}>{file.path}</div>
              </div>
              <span className="file__size">{formatBytes(file.size)}</span>
            </li>
          )
        })}
      </ul>
    </section>
  )
}
