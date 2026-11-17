<script lang="ts">
  import { t } from '$lib/state.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';

  let { onpower }: { onpower: () => void } = $props();
</script>

<div class="off">
  <button type="button" onclick={onpower}><span class="disc"><Glyph d={IC.power} size={28} /></span><span class="label">{t('os_power_on')}</span></button>
</div>

<style>
  .off {
    position: absolute;
    inset: 0;
    z-index: 100;
    display: grid;
    place-items: center;
    background: #000;
  }
  button {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 14px;
    padding: 0;
    background: transparent;
    border: 0;
    color: #a1a1aa;
    cursor: pointer;
  }
  .disc {
    display: grid;
    place-items: center;
    width: 76px;
    height: 76px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 50%;
    transition: color 0.16s, border-color 0.16s;
  }
  .label {
    font-size: 13px;
    font-weight: 500;
  }
  button:hover .disc {
    color: var(--accent);
    border-color: var(--accent);
  }
</style>
