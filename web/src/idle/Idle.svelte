<script lang="ts">
  import { onMount } from 'svelte';
  import { H, start, W } from './screen';

  let canvas: HTMLCanvasElement;

  onMount(() => start(canvas));
</script>

<canvas bind:this={canvas} width={W} height={H}></canvas>

<style>
  :global(body) {
    margin: 0;
    background: #070708;
    overflow: hidden;
  }

  canvas {
    position: fixed;
    inset: 0;
    width: 100%;
    height: 100%;
    display: block;
  }
</style>
