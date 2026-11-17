<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon from './Icon.svelte';
  import { t } from '$lib/state.svelte';

  let {
    dirty,
    busy,
    problems = [],
    onsave,
    ondiscard,
    saveLabel,
    status,
    extra,
  }: { dirty: boolean; busy: boolean; problems?: string[]; onsave: () => void; ondiscard: () => void; saveLabel?: string; status?: string; extra?: Snippet } = $props();
</script>

<footer class="bar savebar">
  <div class="grow">
    {#if problems.length}
      <ul class="errors">{#each problems as problem (problem)}<li>{problem}</li>{/each}</ul>
    {:else}
      <span class={'small muted' + (dirty ? ' dirty' : '')}>{status ?? (dirty ? t('ui_unsaved_changes') : t('ui_all_saved'))}</span>
    {/if}
  </div>
  {#if extra}{@render extra()}{/if}
  <button class="button" disabled={busy || !dirty} onclick={ondiscard}><Icon name="x" />{t('ui_discard')}</button>
  <button class="button primary" disabled={busy || !dirty || problems.length > 0} onclick={onsave}><Icon name="check" />{saveLabel ?? t('ui_save')}</button>
</footer>
