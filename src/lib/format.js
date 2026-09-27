export function formatBytes(bytes) {
  if (!bytes || bytes < 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  const value = bytes / Math.pow(1024, i)
  return `${value.toFixed(i === 0 ? 0 : 1)} ${units[i]}`
}

const ICONS = {
  image: '🖼️',
  video: '🎬',
  audio: '🎵',
  document: '📄',
  archive: '🗜️',
  code: '🧩',
  app: '📦',
}

const EXT_MAP = {
  jpg: 'image', jpeg: 'image', png: 'image', gif: 'image', webp: 'image', heic: 'image', tiff: 'image', bmp: 'image', svg: 'image',
  mp4: 'video', mov: 'video', mkv: 'video', avi: 'video', webm: 'video', m4v: 'video',
  mp3: 'audio', wav: 'audio', flac: 'audio', aac: 'audio', m4a: 'audio', ogg: 'audio',
  pdf: 'document', doc: 'document', docx: 'document', txt: 'document', rtf: 'document', pages: 'document', xls: 'document', xlsx: 'document', ppt: 'document', pptx: 'document', csv: 'document', md: 'document',
  zip: 'archive', rar: 'archive', '7z': 'archive', tar: 'archive', gz: 'archive', dmg: 'archive',
  js: 'code', ts: 'code', jsx: 'code', tsx: 'code', json: 'code', html: 'code', css: 'code', py: 'code', swift: 'code', sh: 'code',
  app: 'app', bundle: 'app', pkg: 'app',
}

export function fileEmoji(name) {
  const ext = name.includes('.') ? name.split('.').pop().toLowerCase() : ''
  return ICONS[EXT_MAP[ext]] || '📄'
}
