<script lang="ts">
  import { untrack } from 'svelte';
  import { brand } from '$lib/brand.svelte';
  import { tinted, tintedNow } from '$lib/tint';
  import { probe, shows, WALLPAPER, wallSource } from '$lib/walls';

  let { wall, cls = '', accent = '' }: { wall: string; cls?: string; accent?: string } = $props();

  const source = $derived(wallSource(wall, brand.walls));

  let picture = $state('');

  $effect(() => {
    const shade = accent || brand.accent;
    const { src, own } = source;
    const ready = own ? shows(src) : false;

    if (ready === true) {
      picture = src;
      return;
    }

    const now = ready === undefined ? null : tintedNow(WALLPAPER, shade);

    if (now !== null) {
      picture = now;
      return;
    }

    let live = true;
    const timer = setTimeout(
      () => {
        (own ? probe(src) : Promise.resolve(false))
          .then((ok) => (ok ? src : tinted(WALLPAPER, shade)))
          .then((url) => {
            if (live) picture = url;
          });
      },
      untrack(() => picture) ? 90 : 0
    );

    return () => {
      live = false;
      clearTimeout(timer);
    };
  });

  const background = $derived(picture ? `url("${picture}") center / cover #0a0a0f` : '#0a0a0f');
</script>

<div class={cls} style:background></div>
