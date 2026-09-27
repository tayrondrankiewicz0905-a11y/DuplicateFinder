export default function ScanProgress({ progress }) {
  const { hashed, total } = progress
  const indeterminate = !total
  const pct = total ? Math.round((hashed / total) * 100) : 0

  return (
    <div className="progress">
      <div className={`progress__bar ${indeterminate ? 'is-indeterminate' : ''}`}>
        <div className="progress__fill" style={indeterminate ? undefined : { width: `${pct}%` }} />
      </div>
      <div className="progress__label">
        {indeterminate ? 'Dateien werden gesammelt …' : `Prüfe Inhalte … ${hashed} / ${total} (${pct}%)`}
      </div>
    </div>
  )
}
