<script lang="ts">
  import { t } from '$lib/state.svelte';
  import { IC } from '$lib/tablet/icons';
  import { restart } from '$lib/tablet/store.svelte';
  import Glyph from '$components/Glyph.svelte';
</script>

<div class="t-off">
  <button type="button" class="t-power" onclick={restart}><span class="t-disc"><Glyph d={IC.power} size={28} stroke={1.75} /></span><span class="t-label">{t('os_power_on')}</span></button>
</div>

<style>
  .t-off {
    position: absolute;
    inset: 0;
    z-index: 100;
    display: grid;
    place-items: center;
    background: #000;
  }
  .t-power {
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
  .t-disc {
    display: grid;
    place-items: center;
    width: 76px;
    height: 76px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 50%;
    transition: color 0.16s, border-color 0.16s;
  }
  .t-label {
    font-size: 13px;
    font-weight: 500;
  }
  .t-power:hover .t-disc {
    color: var(--accent);
    border-color: var(--accent);
  }
</style>
