<script lang="ts">
  import { t } from '../lib/state.svelte';
  import { hints, ph, rail, readouts, slotBar, status } from '../lib/stepHud.svelte';
  import type { Hint } from '../lib/stepHud.svelte';

  const shown = $derived(hints(ph));
  const reads = $derived(readouts(ph));
  const tone = $derived(status(ph));
  const bar = $derived(slotBar(ph));
  const groups = $derived(ph.help && ph.mode === 'camera' ? rail(ph) : []);
  const cueShown = $derived(ph.cue !== '' && !ph.walking);
  const notesShown = $derived(tone.tone === 'warn' && !ph.edge && ph.notes.length > 0);
</script>

{#snippet keyset(list: string[], cls: string)}
  <span class="ph-keys">
    {#each list as key (key)}
      {#each key.split('+') as part, i (part)}
        {#if i > 0}<span class="ph-plus">+</span>{/if}
        <kbd class={cls}>{part}</kbd>
      {/each}
    {/each}
  </span>
{/snippet}

{#snippet hint(h: Hint)}
  <span class="ph-hint" class:go={h.go && !h.off} class:off={h.off}>
    {@render keyset(h.keys, h.go ? (h.off ? 'go off' : 'go') : h.off ? 'off' : '')}
    <span>{h.label}</span>
  </span>
{/snippet}

{#if ph.active}
  <div class="ph">
    <div class="ph-top">
      {#if ph.mode === 'walkup'}
        <div class="ph-hints">
          <p class="ph-title">{ph.title}{#if ph.context}<span>{ph.context}</span>{/if}</p>
          {#each shown as h (h.label)}{@render hint(h)}{/each}
        </div>
      {:else}
        {#if bar.pills.length}
          <div class="ph-bar" role="list">
            {#if bar.count}<span class="ph-count">{bar.count}</span>{/if}
            {#each bar.pills as pill (pill.key)}
              <p class="ph-pill {pill.state === 'add' ? 'todo' : pill.state}" class:solo={pill.key === 'one'} role="listitem">
                {#if pill.state === 'done'}
                  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12l5 5L20 7" /></svg>
                {:else if pill.state === 'add'}
                  <span class="ph-num"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14" /></svg></span>
                {:else if pill.key !== 'one'}
                  <span class="ph-num">{pill.num}</span>
                {/if}
                {pill.label}
                {#if pill.tag}<span class="ph-tag">{pill.tag}</span>{/if}
              </p>
            {/each}
          </div>
        {/if}
        <div class="ph-hints">
          {#each shown as h (h.label)}{@render hint(h)}{/each}
        </div>
        {#if cueShown}
          <p class="ph-cue">
            <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5" /><path d="M12 11v5.5M12 7.6v.1" /></svg>
            {ph.cue}
          </p>
        {/if}
      {/if}
    </div>
    {#if !ph.walking}
      <span class="ph-cross" aria-hidden="true"></span>
    {/if}
    <div class="ph-readout" class:many={reads.length > 1}>
      {#each reads as r (r.caption)}
        <div class="ph-read">
          <p class="ph-value">{r.value}{r.unit === '°' ? '°' : ` ${r.unit}`}</p>
          <p class="ph-caption">{r.caption}</p>
        </div>
      {/each}
    </div>
    <div class="ph-under">
      <div class="ph-status {tone.tone}" role="status"><span class="ph-dot"></span><span>{tone.text}</span></div>
      {#if notesShown}
        <ul class="ph-notes">
          {#each ph.notes as note (note)}<li>{note}</li>{/each}
        </ul>
      {/if}
    </div>
    <div class="ph-corner">
      <span class="ph-hint">{@render keyset([t('ui_key_backspace'), t('ui_key_right_click')], '')}<span>{t('ui_placement_corner_stop')}</span></span>
      {#if ph.mode === 'camera'}
        <span class="ph-hint">
          {@render keyset(['H'], 'hi')}
          <span>{t(ph.help ? 'ui_placement_corner_hide' : 'ui_placement_corner_all')}</span>
        </span>
      {/if}
    </div>
    {#if groups.length}
      <aside class="ph-rail">
        {#each groups as group (group.title)}
          <h3>{group.title}</h3>
          {#each group.rows as row (row.label)}
            <p class="ph-row"><span>{row.label}</span>{@render keyset(row.keys, '')}</p>
          {/each}
        {/each}
      </aside>
    {/if}
  </div>
{/if}
