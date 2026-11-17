<script lang="ts">
  import { DEFAULT_ACCENT } from '$lib/brand.svelte';
  import { connectApp } from '$sdk/os-app';

  const params = new URLSearchParams(location.search);
  const label = params.get('label') || 'Sample app';
  const icon = params.get('icon') || 'M4 4h16v16H4z';
  const color = params.get('color') || DEFAULT_ACCENT;
  const size = 'Preview stand-in ' + innerWidth + ' x ' + innerHeight;
  const os = connectApp();

  function notify() {
    os.notify({ title: (params.get('label') || 'Sample') + ' says hi', body: 'A notification from the app page.' });
  }
</script>

<main>
  <svg viewBox="0 0 24 24" style:fill={color}><path id="icon" d={icon}></path></svg>
  <h1 id="label">{label}</h1>
  <p id="size">{size}</p>
  <input placeholder="Type here">
  <button id="notify" type="button" onclick={notify}>Send a notification</button>
</main>
