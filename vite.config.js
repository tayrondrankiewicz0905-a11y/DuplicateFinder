import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Dev server must be reachable from the Base44 preview proxy:
// - bind 0.0.0.0 and accept the external preview host (allowedHosts: true)
// - poll the filesystem so hot reload fires across the bind mount
export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
    strictPort: true,
    allowedHosts: true,
    watch: { usePolling: true, interval: 300 },
  },
})
