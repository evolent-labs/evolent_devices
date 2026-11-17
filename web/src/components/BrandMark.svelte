<script lang="ts">
  import { brand } from '$lib/brand.svelte';

  let { src, cls = '' }: { src?: string; cls?: string } = $props();

  const logo = $derived(src ?? brand.logo);
</script>

{#if logo}<img class={'brand-logo ' + cls} src={logo} alt="" />{:else}<svg class={'brand-mark ' + cls} viewBox="-4.6 -5.3 9.2 10.6" aria-hidden="true"
    ><g fill="currentColor" stroke="currentColor" stroke-width=".18" stroke-linejoin="round"
      ><path d="M-4.330,-2.500 L0.000,-5.000 L1.732,-4.000 L-4.330,-0.500 Z"></path><path
        d="M-4.330,1.500 L3.464,-3.000 L4.330,-2.500 L4.330,-1.500 L-1.732,2.000 L0.000,3.000 L4.330,0.500 L4.330,2.500 L0.000,5.000 L-4.330,2.500 Z"
      ></path></g
    ></svg
  >{/if}
