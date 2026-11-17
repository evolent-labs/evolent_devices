<script lang="ts">
  import { frameTones } from '$lib/tablet/frame';

  let { hex }: { hex: string } = $props();

  const tones = $derived(frameTones(hex));
  const button = $derived(`background:linear-gradient(${tones.btnTop},${tones.btnBot})`);
</script>

<span class="t-key t-power" style={button} aria-hidden="true"></span>
<span class="t-key t-up" style={button} aria-hidden="true"></span>
<span class="t-key t-down" style={button} aria-hidden="true"></span>
<div class="t-body" style="border-color:{tones.border};box-shadow:inset 0 0 0 3px {tones.rim},inset 0 0 0 4px #08080b,inset 0 1px 0 rgba(255,255,255,.08)" aria-hidden="true"></div>
<span class="t-camera" aria-hidden="true"></span>

<style>
  .t-key {
    position: absolute;
    top: -4px;
    height: 9px;
    border-radius: 3px 3px 0 0;
    transition: background 0.35s;
  }
  .t-power {
    left: 96px;
    width: 68px;
  }
  .t-up {
    right: 160px;
    width: 52px;
  }
  .t-down {
    right: 96px;
    width: 52px;
  }
  .t-body {
    position: absolute;
    inset: 0;
    background: linear-gradient(160deg, #15151b 0%, #0c0c10 55%, #121218 100%);
    border: 1px solid;
    border-radius: 22px;
    transition: border-color 0.35s, box-shadow 0.35s;
  }
  .t-camera {
    position: absolute;
    top: 13px;
    left: 50%;
    box-sizing: content-box;
    width: 8px;
    height: 8px;
    margin-left: -4px;
    background: radial-gradient(circle at 35% 35%, #2b3140, #07070a 65%);
    border: 1px solid #2c2c36;
    border-radius: 50%;
  }
</style>
