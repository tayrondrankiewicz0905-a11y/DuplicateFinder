// Fallback deletion for browsers that do not support the File System Access API
// (Firefox, Safari, and restricted embedding modes). A web page is not allowed
// to delete files on disk there, so instead we hand the user a small script
// that removes exactly the duplicates they selected.

function isWindowsPlatform() {
  const platform = navigator.userAgentData?.platform || navigator.platform || ''
  return /win/i.test(platform)
}

// Directory-picker paths are relative to the picked folder, while the
// <input webkitdirectory> fallback prefixes them with the folder name.
function toRelativePaths(paths, rootName) {
  if (!rootName) return paths
  const prefix = `${rootName}/`
  return paths.map((p) => (p.startsWith(prefix) ? p.slice(prefix.length) : p))
}

export function buildDeleteScript(paths, rootName) {
  const relative = toRelativePaths(paths, rootName)

  if (isWindowsPlatform()) {
    return {
      filename: 'duplikate-loeschen.ps1',
      content: [
        '# Duplicate Finder – löscht die markierten Duplikate endgültig.',
        '# Dieses Skript in den gescannten Ordner legen und dort ausführen:',
        '#   Rechtsklick > "Mit PowerShell ausführen"',
        '',
        ...relative.map(
          (p) => `Remove-Item -LiteralPath '${p.replace(/'/g, "''")}' -ErrorAction SilentlyContinue`,
        ),
        '',
      ].join('\r\n'),
    }
  }

  return {
    filename: 'duplikate-loeschen.sh',
    content: [
      '#!/bin/bash',
      '# Duplicate Finder – löscht die markierten Duplikate endgültig.',
      '# Dieses Skript in den gescannten Ordner legen und dort ausführen:',
      '#   bash duplikate-loeschen.sh',
      '',
      ...relative.map((p) => `rm -f -- '${p.replace(/'/g, "'\\''")}'`),
      '',
    ].join('\n'),
  }
}

export function downloadDeleteScript(paths, rootName) {
  const { filename, content } = buildDeleteScript(paths, rootName)
  const url = URL.createObjectURL(new Blob([content], { type: 'text/plain;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
}
