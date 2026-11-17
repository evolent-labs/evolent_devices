<script lang="ts">
  import { fade } from 'svelte/transition';
  import { cueParts, prompt } from '../lib/prompt.svelte';
  import type { PromptData, PromptIcon, PromptOption, PromptSpot } from '../lib/prompt.svelte';

  let { data = undefined, at = null, bottom = undefined }: { data?: PromptData; at?: PromptSpot | null; bottom?: number } = $props();

  const shown = $derived(data ?? (prompt.visible ? prompt.data : null));
  const spot = $derived(data ? at : prompt.at);
  const empty = $derived(!shown || (!shown.options.length && !shown.title && !shown.why));
  let width = $state(typeof innerWidth === 'number' ? innerWidth : 0);
  let height = $state(typeof innerHeight === 'number' ? innerHeight : 0);
</script>

{#snippet glyph(name: PromptIcon, cls: string)}
  <svg class={cls} viewBox="0 0 24 24" aria-hidden="true">
    {#if name === 'lock'}
      <rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" />
    {:else if name === 'user'}
      <circle cx="12" cy="8" r="3.5" /><path d="M5 20c1.2-3.6 4-5 7-5s5.8 1.4 7 5" />
    {:else if name === 'clock'}
      <circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" />
    {:else}
      <circle cx="12" cy="12" r="8.5" /><path d="M12 11v5.5M12 7.6v.1" />
    {/if}
  </svg>
{/snippet}

{#snippet keyset(option: PromptOption)}
  <span class="pr-keys">
    {#each option.keys as key (key)}
      {#each key.split('+') as part, i (part)}
        {#if i > 0}<span class="pr-plus">+</span>{/if}
        <kbd class:go={option.main && !option.off} class:off={option.off}>{part}</kbd>
      {/each}
    {/each}
  </span>
{/snippet}

{#snippet plate(p: PromptData)}
  {#if !empty}
    <div class="pa pr-plate" class:hold={p.hold !== null}>
      {#if p.title}
        <p class="pa-title">{p.title}{#if p.context}<span>{p.context}</span>{/if}</p>
      {/if}
      {#each p.options as option (option.label)}
        {#if option.run}
          <button type="button" class="pa-opt pa-button" class:main={option.main && !option.off} class:off={option.off} disabled={option.off} onclick={option.run}>
            {@render keyset(option)}<span>{option.label}</span>
          </button>
        {:else}
          <span class="pa-opt" class:main={option.main && !option.off} class:off={option.off}>
            {@render keyset(option)}<span>{option.label}</span>
          </span>
        {/if}
      {/each}
      {#if p.why}
        <span class="pa-why">{@render glyph(p.icon, 'pr-ico')}{p.why}</span>
      {/if}
      {#if p.hold !== null}
        <span class="pa-track"></span>
        <span class="pa-fill" style:--p={p.hold}></span>
      {/if}
    </div>
  {/if}
  {#if p.cue}
    <p class="pa-cue pr-plate">
      {@render glyph(p.cueIcon, 'pr-ico')}
      <span>{#each cueParts(p.cue) as piece (piece.key)}{#if piece.num}<span class="num">{piece.part}</span>{:else}{piece.part}{/if}{/each}{#if p.note}{' '}<span class="mute">{p.note}</span>{/if}</span>
    </p>
  {/if}
{/snippet}

{#if shown && (!empty || shown.cue)}
  <div class="pr" bind:clientWidth={width} bind:clientHeight={height} transition:fade={{ duration: 120 }}>
    {#if spot && !empty}
      <div class="pr-at" style:transform="translate3d({Math.round(spot.x * width)}px, {Math.round(spot.y * height)}px, 0)">
        <span class="pr-stem"></span>
        <span class="pr-dot"></span>
        <div class="pr-above">{@render plate(shown)}</div>
      </div>
    {:else}
      <div class="pr-fixed" style:bottom={bottom === undefined ? undefined : `calc(${bottom} * var(--u))`}>{@render plate(shown)}</div>
    {/if}
  </div>
{/if}
