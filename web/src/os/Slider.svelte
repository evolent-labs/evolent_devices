<script lang="ts">
  let { value, label, disabled = false, onchange }: { value: number; label: string; disabled?: boolean; onchange: (value: number) => void } = $props();

  let track: HTMLElement | undefined = $state();
  let dragging = $state(false);

  function at(event: MouseEvent) {
    if (!track) return;

    const rect = track.getBoundingClientRect();

    if (rect.width <= 0) return;

    const share = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));

    onchange(Math.round(share * 100));
  }

  function down(event: MouseEvent) {
    if (disabled || event.button !== 0) return;

    event.preventDefault();
    event.stopPropagation();
    dragging = true;
    at(event);
  }

  function move(event: MouseEvent) {
    if (dragging) at(event);
  }

  function up() {
    dragging = false;
  }
</script>

<svelte:window onmousemove={move} onmouseup={up} onblur={up} />

<div
  class="slider"
  class:dragging
  class:disabled
  role="slider"
  tabindex="-1"
  aria-label={label}
  aria-valuemin="0"
  aria-valuemax="100"
  aria-valuenow={value}
  bind:this={track}
  onmousedown={down}
>
  <span class="track"><span class="fill" style:width={value + '%'}></span></span>
  <span class="knob" style:left={value + '%'}></span>
</div>

<style>
  .slider {
    position: relative;
    flex: 1;
    height: 24px;
    cursor: pointer;
  }
  .slider.disabled {
    cursor: default;
    opacity: 0.5;
  }
  .track {
    position: absolute;
    top: 9px;
    left: 0;
    right: 0;
    height: 6px;
    background: #1f1f27;
    border-radius: 6px;
    overflow: hidden;
  }
  .fill {
    display: block;
    height: 100%;
    background: var(--accent);
    border-radius: 6px;
  }
  .knob {
    position: absolute;
    top: 3px;
    width: 18px;
    height: 18px;
    margin-left: -9px;
    background: var(--accent);
    border: 3px solid #0a0a0f;
    border-radius: 50%;
    transition: transform 0.12s;
  }
  .slider:hover .knob,
  .dragging .knob {
    transform: scale(1.12);
  }
</style>
