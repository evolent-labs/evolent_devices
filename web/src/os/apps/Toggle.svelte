<script lang="ts">
  let { label, help, on, disabled = false, ontoggle }: { label: string; help: string; on: boolean; disabled?: boolean; ontoggle: () => void } = $props();
</script>

<div class="tg-row">
  <div class="tg-words"><p class="tg-label">{label}</p><p class="tg-help">{help}</p></div>
  <button type="button" class="tg-switch" class:tg-on={on} aria-pressed={on} aria-label={label} {disabled} onclick={ontoggle}><span></span></button>
</div>

<style>
  .tg-row {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 14px 16px;
    background: #0f0f15;
    border: 1px solid #1f1f27;
    border-radius: 12px;
  }
  .tg-words {
    flex: 1;
  }
  .tg-label {
    font-size: 14px;
    font-weight: 600;
  }
  .tg-help {
    margin-top: var(--sub-pull);
    font-size: 12px;
    line-height: var(--sub-lh);
    color: #a1a1aa;
  }
  .tg-switch {
    position: relative;
    display: block;
    width: 40px;
    height: 22px;
    flex-shrink: 0;
    padding: 0;
    background: #2a2a35;
    border: 0;
    border-radius: 11px;
    cursor: pointer;
  }
  .tg-switch:disabled {
    cursor: default;
    opacity: 0.6;
  }
  .tg-switch span {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 16px;
    height: 16px;
    background: #71717a;
    border-radius: 50%;
    transition: left 0.16s;
  }
  .tg-switch.tg-on {
    background: var(--accent);
  }
  .tg-switch.tg-on span {
    left: 21px;
    background: #0a0a0f;
  }
</style>
