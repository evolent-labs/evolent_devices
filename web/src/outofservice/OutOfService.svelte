<script lang="ts">
  import { onMount } from 'svelte';
  import { brand, brandLook } from '$lib/brand.svelte';

  const query = new URLSearchParams(location.search);
  const host = (query.get('host') || '').replace(/[^\w-]/g, '');
  const browser = (query.get('browser') || '').replace(/[^\w-]/g, '');
  const secret = (new URLSearchParams(location.hash.slice(1)).get('s') || '').replace(/[^0-9a-f]/gi, '');

  let line = $state('This terminal has nothing to show yet.');
  let dim = $state<string>();

  function ready(attempt: number) {
    if (!host || !browser) return;

    fetch('https://' + host + '/device:ready', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ browser, s: secret, width: innerWidth, height: innerHeight }),
    }).catch(() => {
      if (attempt < 5) {
        setTimeout(() => ready(attempt + 1), 500);
      }
    });
  }

  function onmessage(event: MessageEvent) {
    const message = event.data;

    if (!message || typeof message !== 'object' || (secret && message.__s !== secret)) return;

    const look = message.brand ?? message.extra?.brand;

    if (look && typeof look === 'object') brandLook(look);
    if (message.type !== 'open' && message.type !== 'watch') return;

    const screen = (message.type === 'open' ? message.screen : message.extra && message.extra.screen) || {};

    if (typeof screen.message === 'string' && screen.message) {
      line = screen.message.slice(0, 160);
    }

    const bright = Number(screen.brightness);

    if (message.type === 'watch' && bright >= 20 && bright < 100) {
      dim = String(1 - bright / 100);
    }
  }

  onMount(() => {
    requestAnimationFrame(() => requestAnimationFrame(() => ready(0)));
  });
</script>

<svelte:window {onmessage} />

<div class="card">
  <div class="mark" aria-hidden="true"></div>
  <div>
    <div class="brand">{brand.name ? brand.name.toUpperCase() : 'EVOLENT DEVICES'}</div>
    <h1>Out of service</h1>
    <p id="line">{line}</p>
  </div>
</div>
<div id="dim" style:opacity={dim}></div>
