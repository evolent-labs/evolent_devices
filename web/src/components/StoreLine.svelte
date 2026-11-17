<script lang="ts" module>
  const LINE: Record<string, string> = {
    wifi: 'M2 8.8a15 15 0 0 1 20 0M5.2 12.3a10.5 10.5 0 0 1 13.6 0M8.6 15.8a5.6 5.6 0 0 1 6.8 0M12 19.5h.01',
    eye: 'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12zM9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0',
    cover: 'M3 3l18 18M10.6 5.1A10.4 10.4 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.2M6.6 6.6C3.8 8.4 2 12 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6M9.9 9.9a3 3 0 0 0 4.2 4.2',
    bell: 'M18 9.5a6 6 0 0 0-12 0v5l-2 2.5h16L18 14.5zM10 19.5a2 2 0 0 0 4 0',
    devices: 'M3 5h13v9H3zM1 17h17M19 9h3v10h-3z',
    key: 'M3 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0M11 12h10M18 12v3M15 12v2',
    pin: 'M12 21s-7-6.2-7-11.5a7 7 0 0 1 14 0C19 14.8 12 21 12 21zM9.5 9.5a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0',
    offline: 'M4 5h16v11H4zM8 20h8M12 16v4',
    disk: 'M4 4h13l3 3v13H4zM8 4v5h8V4M8 20v-6h8v6',
    lock: 'M6 11h12v10H6zM8 11V7a4 4 0 0 1 8 0v4M12 15v2',
    shield: 'M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6zM9 12l2 2 4-4',
    search: 'M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0M20 20l-4-4',
    x: 'M6 6l12 12M18 6L6 18',
    back: 'M19 12H5M11 6l-6 6 6 6',
    chevR: 'M9 6l6 6-6 6',
    chevL: 'M15 6l-6 6 6 6',
    check: 'M5 12.5l4.5 4.5L19 7',
    down: 'M12 4v11M7 10l5 5 5-5M5 20h14',
    grid: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
    briefcase: 'M3 8h18v12H3zM9 8V5h6v3M3 13h18',
    shop: 'M4 9l1.5-5h13L20 9M4 9h16v1a3 3 0 0 1-5.3 1.9A3 3 0 0 1 12 13a3 3 0 0 1-2.7-1.1A3 3 0 0 1 4 10zM5 13v8h14v-8M10 21v-5h4v5',
    wrench: 'M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z',
    sparkle: 'M12 3l2 5.5L19.5 10.5 14 12.5 12 18l-2-5.5L4.5 10.5 10 8.5zM19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z',
  };
</script>

<script lang="ts">
  let { name, size = 16, stroke = 1.8 }: { name: string; size?: number; stroke?: number } = $props();
</script>

<svg class="as-line" viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" stroke-width={stroke} stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d={LINE[name] ?? LINE.check}></path></svg>

<style>
  .as-line {
    display: block;
    flex-shrink: 0;
  }
</style>
