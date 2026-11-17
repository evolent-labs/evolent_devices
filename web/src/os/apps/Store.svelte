<script lang="ts">
  import AppStore from '$components/AppStore.svelte';
  import { t } from '$lib/state.svelte';
  import { page, watching } from '../params';
  import { installApp, openApp, os, removeApp, storeApps } from '../store.svelte';
</script>

{#if watching}
  <div class="bones">
    {#each [0, 1, 2, 3] as index (index)}<div class="bone-card"><i class="wide"></i><i></i></div>{/each}
  </div>
{:else}
  <AppStore
    apps={storeApps()}
    bars={os.signal.bars}
    wired={os.signal.wired}
    device={t('kind_word_' + page.kind)}
    install={installApp}
    remove={os.system.canManage ? removeApp : undefined}
    open={(id) => openApp(id)}
  />
{/if}

<style>
  .bones {
    position: absolute;
    inset: 0;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    grid-auto-rows: 110px;
    gap: 12px;
    padding: 84px 24px 24px;
  }
  .bone-card {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 16px;
    background: #0f0f15;
    border: 1px solid #1f1f27;
    border-radius: 14px;
  }
  .bone-card i {
    display: block;
    width: 120px;
    height: 10px;
    background: rgba(255, 255, 255, 0.07);
    border-radius: 6px;
  }
  .bone-card i.wide {
    width: 200px;
  }
</style>
