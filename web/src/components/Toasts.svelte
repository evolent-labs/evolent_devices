<script lang="ts">
  import { app, type Toast } from '$lib/state.svelte';
  import ToastMark from './ToastMark.svelte';

  let { list }: { list?: Toast[] } = $props();

  const entries = $derived(list ?? app.toasts);
  const nodes: Record<number, HTMLElement | null> = $state({});

  $effect(() => {
    for (const entry of entries) {
      const node = nodes[entry.id];

      if (!node || !entry.unfolded || entry.out) {
        continue;
      }

      const box = node.getBoundingClientRect();

      if (box.height > parseFloat(getComputedStyle(node).minHeight)) {
        entry.fold = { height: box.height + 'px', width: node.lastElementChild!.getBoundingClientRect().width + 'px' };
      }
    }
  });
</script>

<div class="toasts" aria-live="polite">
  {#each entries as entry (entry.id)}
    <div bind:this={nodes[entry.id]} class={'toast ' + entry.kind} class:unfolded={entry.unfolded} class:out={entry.out} class:wrapped={!!entry.fold} style:--fold-h={entry.fold?.height} style:--fold-w={entry.fold?.width} onanimationend={(event) => event.target === event.currentTarget && !entry.out && (entry.unfolded = true)}>
      <ToastMark tone={entry.kind} />
      <span>{entry.text}</span>
    </div>
  {/each}
</div>
