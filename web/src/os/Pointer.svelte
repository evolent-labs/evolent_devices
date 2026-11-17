<script lang="ts">
  import { layout } from './store.svelte';

  let { pointer }: { pointer: { u: number; v: number } } = $props();
</script>

<svg class="pointer" viewBox="0 0 24 24" style={`left:${pointer.u * layout.width}px;top:${pointer.v * layout.height}px`} aria-hidden="true">
  <path d="M5 3l14 8.2-6.1 1.3 3.6 6.9-2.6 1.4-3.6-6.9L5.6 18z"></path>
</svg>

<style>
  .pointer {
    position: absolute;
    z-index: 300;
    width: 26px;
    height: 26px;
    margin: -3px 0 0 -5px;
    fill: #fff;
    stroke: #0a0a0f;
    stroke-width: 1.4;
    stroke-linejoin: round;
    filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.5));
    transition: left 0.2s linear, top 0.2s linear;
    pointer-events: none;
  }
</style>
