<script lang="ts" module>
  export type ToastTone = 'success' | 'error' | 'warning' | 'inform';
</script>

<script lang="ts">
  let { tone }: { tone: ToastTone } = $props();

  const CUTS: Record<ToastTone, { line?: string; fill?: string }> = {
    success: { line: 'M7 12.5l3 3 7-7' },
    error: { fill: 'M7 7h2v1h-2zM15 7h2v1h-2zM7 8h3v1h-3zM14 8h3v1h-3zM8 9h3v1h-3zM13 9h3v1h-3zM9 10h6v1h-6zM10 11h4v2h-4zM9 13h6v1h-6zM8 14h3v1h-3zM13 14h3v1h-3zM7 15h3v1h-3zM14 15h3v1h-3zM7 16h2v1h-2zM15 16h2v1h-2z' },
    warning: { fill: 'M11 6h2v8h-2zM11 16h2v2h-2z' },
    inform: { fill: 'M11 6h2v2h-2zM10 10h3v7h1v1h-4v-1h1v-6h-1z' },
  };

  const uid = $props.id();
  const id = 'toast-cut-' + uid;
  const cut = $derived(CUTS[tone] ?? CUTS.success);
</script>

<svg class="toast-mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
  <mask {id} maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">
    <rect width="24" height="24" fill="#fff" />
    {#if cut.line}<path d={cut.line} fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />{/if}
    {#if cut.fill}<path d={cut.fill} fill="#000" />{/if}
  </mask>
  <circle cx="12" cy="12" r="12" fill="currentColor" mask={'url(#' + id + ')'} />
</svg>

<style>
  .toast-mark {
    display: block;
    flex: 0 0 24px;
    width: 24px;
    height: 24px;
  }
</style>
