<script lang="ts">
  import { kindPicture } from '$lib/kinds';
  import { KIND_ICONS } from '$lib/state.svelte';
  import Icon from './Icon.svelte';
  import Tinted from './Tinted.svelte';

  let { kind, cls = '' }: { kind: string; cls?: string } = $props();

  let failed = $state('');

  const src = $derived(kindPicture(kind));
</script>

<span class={'kind-picture ' + cls}>
  {#if src && failed !== src}<Tinted {src} onfail={() => (failed = src)} />{:else}<span class="kind-art"><Icon name={KIND_ICONS[kind] ?? 'monitor'} /></span>{/if}
</span>
