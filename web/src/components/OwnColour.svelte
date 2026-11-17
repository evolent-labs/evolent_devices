<script lang="ts">
  import { slide } from 'svelte/transition';
  import ColorPicker from './ColorPicker.svelte';
  import Icon from './Icon.svelte';
  import { t } from '$lib/state.svelte';

  let {
    value,
    on = false,
    label = '',
    disabled = false,
    every = 0,
    open = $bindable(false),
    onpick,
  }: {
    value: string;
    on?: boolean;
    label?: string;
    disabled?: boolean;
    every?: number;
    open?: boolean;
    onpick: (hex: string, final: boolean) => void;
  } = $props();
</script>

<button type="button" class="colour-chip own-colour" aria-pressed={on} aria-expanded={open} {disabled} onclick={() => (open = !open)}>
  <i class="colour-dot" style:--swatch={value}></i>{label || t('ui_own_colour')}<Icon name="chev" />
</button>
{#if open}
  <div class="own-colour-panel" transition:slide={{ duration: 180 }}>
    <ColorPicker {value} {disabled} {every} {onpick} />
  </div>
{/if}
