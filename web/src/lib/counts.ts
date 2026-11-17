import { call } from './nui';
import { app } from './state.svelte';
import type { Counts } from './types';

export async function refreshCounts() {
  const result = await call<{ counts: Counts }>('evdev:admin:list', { limit: 1 });

  if (result.ok && result.data?.counts) {
    app.counts = result.data.counts;
  }
}
