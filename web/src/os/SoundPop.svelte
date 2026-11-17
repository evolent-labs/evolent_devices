<script lang="ts">
  import { t } from '$lib/state.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import Slider from './Slider.svelte';
  import { layout, openApp, os, setPrefs } from './store.svelte';

  const WIDTH = 340;

  let lastVolume = os.prefs.volume || 70;

  const left = $derived(Math.round(Math.max(12, Math.min(layout.width - WIDTH - 12, (os.soundPop?.x ?? 0) - WIDTH / 2))));

  function mute() {
    if (os.prefs.volume > 0) {
      lastVolume = os.prefs.volume;
      setPrefs({ volume: 0 });
    } else {
      setPrefs({ volume: lastVolume || 70 });
    }
  }
</script>

<div class="pop" data-pop="s" style:left="{left}px" role="dialog" tabindex="-1" onmousedown={(event) => event.stopPropagation()}>
  <div class="top">
    <p class="title">{t('os_sound')}</p>
    <span class="value mono">{os.prefs.volume}</span>
  </div>
  <div class="row">
    <button type="button" class="mute" aria-label={t('os_sound_mute')} onclick={mute}><Glyph d={os.prefs.volume > 0 ? IC.volume : IC.volumeOff} size={20} stroke={2} /></button>
    <Slider value={os.prefs.volume} label={t('os_sound_volume')} onchange={(volume) => setPrefs({ volume })} />
  </div>
  <p class="help">{t('os_sound_volume_help')}</p>
  <button type="button" class="more" onclick={() => openApp('settings', null, { section: 'sound' })}>{t('os_sound_settings')}<Glyph d={IC.arrowRight} size={14} stroke={2} /></button>
</div>

<style>
  .pop {
    position: absolute;
    bottom: 92px;
    z-index: 70;
    width: 340px;
    padding: 16px 18px 14px;
    background: rgba(12, 12, 17, 0.94);
    border: 1px solid #2a2a35;
    border-radius: 18px;
    backdrop-filter: blur(24px);
    animation: eos-pop 0.22s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .top {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .title {
    font-size: 16px;
    font-weight: 600;
  }
  .value {
    font-size: 15px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: #a1a1aa;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-top: 14px;
  }
  .mute {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    flex-shrink: 0;
    padding: 0;
    background: #0f0f15;
    border: 1px solid #2a2a35;
    border-radius: 10px;
    color: #e4e4e7;
    cursor: pointer;
  }
  .mute:hover {
    border-color: var(--accent);
  }
  .help {
    margin-top: 12px;
    font-size: 12px;
    color: #a1a1aa;
  }
  .more {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin-top: 10px;
    padding: 0;
    background: transparent;
    border: 0;
    color: #a1a1aa;
    font: 500 12px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .more:hover {
    color: var(--accent);
  }
</style>
