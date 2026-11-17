<script lang="ts">
  import { t } from '$lib/state.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { openApp, os } from './store.svelte';

  let { onlock }: { onlock: () => void } = $props();

  const items = $derived(
    os.menu?.app
      ? [
        {
          key: 'open',
          label: t('os_open'),
          icon: IC.arrowRight,
          hint: t('os_key_enter'),
          run: () => openApp(os.menu?.app ?? ''),
        },
      ]
      : [{ key: 'lock', label: t('os_lock'), icon: IC.lock, hint: t('os_key_lock'), run: onlock }],
  );

  function run(action: () => void) {
    os.menu = null;
    action();
  }
</script>

{#if os.menu}
  <div class="menu" data-pop="m" role="menu" tabindex="-1" style={`left:${os.menu.x}px;top:${os.menu.y}px`} onmousedown={(event) => event.stopPropagation()}>
    {#each items as item (item.key)}
      <button type="button" role="menuitem" onclick={() => run(item.run)}><Glyph d={item.icon} size={17} /><span class="label">{item.label}</span><span class="hint mono">{item.hint}</span></button>
    {/each}
  </div>
{/if}

<style>
  .menu {
    position: absolute;
    z-index: 90;
    width: 264px;
    padding: 6px;
    background: rgba(15, 15, 21, 0.96);
    border: 1px solid #2a2a35;
    border-radius: 12px;
    backdrop-filter: blur(20px);
    animation: eos-menu 0.16s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  button {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    height: 40px;
    padding: 0 12px;
    background: transparent;
    border: 0;
    border-radius: 8px;
    color: #e4e4e7;
    font: 500 14px/1 Poppins, system-ui, sans-serif;
    text-align: left;
    cursor: pointer;
  }
  button:hover {
    background: #17171f;
  }
  .label {
    flex: 1;
  }
  .hint {
    font-size: 11px;
    color: #71717a;
  }
</style>
