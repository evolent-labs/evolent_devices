<script lang="ts">
  import type { Win } from '../store.svelte';
  import Files from './Files.svelte';
  import Notes from './Notes.svelte';
  import Photos from './Photos.svelte';
  import Settings from './Settings.svelte';
  import Store from './Store.svelte';

  let { win }: { win: Win } = $props();
</script>

{#if win.id === 'notes'}
  <Notes {win} />
{:else if win.id === 'files'}
  <Files {win} />
{:else if win.id === 'photos'}
  <Photos {win} />
{:else if win.id === 'store'}
  <Store />
{:else if win.id === 'settings'}
  <Settings {win} />
{/if}
