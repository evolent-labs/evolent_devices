const root = import.meta.dirname;

const noRegions = {
  name: 'no-regions',
  renderChunk: (code: string) => code.replace(/^[\t ]*\/\/#(?:end)?region\b.*\r?\n/gm, ''),
};

export default {
  root,
  logLevel: 'warn',
  plugins: [noRegions],
  build: {
    outDir: root + '/dist',
    emptyOutDir: false,
    target: 'chrome103',
    minify: false,
    lib: {
      entry: root + '/src/os-app.ts',
      name: 'EvolentOS',
      formats: ['es', 'iife'],
      fileName: (format: string) => (format === 'es' ? 'os-app.js' : 'os-app.iife.js'),
    },
    rolldownOptions: { output: { comments: false } },
  },
};
