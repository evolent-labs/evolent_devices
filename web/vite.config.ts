import { defineConfig, type Plugin } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import fs from 'node:fs';
import path from 'node:path';

const samplePictures = (): Plugin => ({
  name: 'sample-pictures',
  apply: 'serve',
  configureServer(server) {
    server.middlewares.use((request, _response, next) => {
      const name = /^\/wallpapers\/([\w-]+\.(?:webp|jpe?g|png))(?:\?.*)?$/i.exec(request.url ?? '')?.[1];

      if (name && !fs.existsSync(path.resolve(import.meta.dirname, 'public/wallpapers', name)) && fs.existsSync(path.resolve(import.meta.dirname, 'preview/wallpapers', name))) {
        request.url = '/preview/wallpapers/' + name;
      }

      next();
    });
  },
});

export default defineConfig({
  root: import.meta.dirname,
  base: './',
  plugins: [svelte(), samplePictures()],
  resolve: {
    alias: {
      $lib: path.resolve(import.meta.dirname, 'src/lib'),
      $components: path.resolve(import.meta.dirname, 'src/components'),
      $views: path.resolve(import.meta.dirname, 'src/views'),
      $os: path.resolve(import.meta.dirname, 'src/os'),
      $sdk: path.resolve(import.meta.dirname, '../sdk/src'),
    },
  },
  server: { fs: { allow: ['..'] } },
  build: {
    outDir: 'build',
    emptyOutDir: true,
    target: 'chrome103',
    modulePreload: false,
    assetsInlineLimit: 0,
    rolldownOptions: {
      input: {
        index: path.resolve(import.meta.dirname, 'index.html'),
        os: path.resolve(import.meta.dirname, 'os.html'),
        idle: path.resolve(import.meta.dirname, 'idle.html'),
        out_of_service: path.resolve(import.meta.dirname, 'out_of_service.html'),
      },
    },
  },
});
