<script lang="ts">
  import ToastMark from '$components/ToastMark.svelte';
  import { tablet } from '$lib/tablet/store.svelte';
</script>

{#if tablet.toast}
  {#key tablet.toast.id}
    <div class="t-wrap" role="status" aria-live="polite">
      <div class="t-toast" class:t-bad={tablet.toast.bad} class:t-out={tablet.toast.out}>
        <ToastMark tone={tablet.toast.bad ? 'error' : 'success'} />
        <span class="t-text">{tablet.toast.text}</span>
      </div>
    </div>
  {/key}
{/if}

<style>
  .t-wrap {
    position: absolute;
    left: 0;
    right: 0;
    top: 48px;
    z-index: 210;
    display: flex;
    justify-content: center;
    pointer-events: none;
  }
  .t-toast {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 40px;
    max-width: 560px;
    padding: 0 18px 0 8px;
    background: var(--accent);
    border-radius: 999px;
    color: var(--accent-content);
    font: 600 13px/1.4 'Poppins', system-ui, sans-serif;
    white-space: nowrap;
    overflow: hidden;
    animation: du-unfold 0.6s cubic-bezier(0.4, 0, 0.2, 1);
  }
  .t-toast.t-bad {
    background: #f82834;
    color: #fff;
  }
  .t-toast.t-out {
    animation: du-fold 0.4s cubic-bezier(0.4, 0, 0.2, 1) forwards;
  }
  .t-toast :global(.toast-mark) {
    color: var(--accent-content);
  }
  .t-toast.t-bad :global(.toast-mark) {
    color: #0a0a0f;
  }
  .t-text {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    animation: du-tin 0.6s;
  }
  .t-out .t-text {
    animation: du-tout 0.2s forwards;
  }
</style>
