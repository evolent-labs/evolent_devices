import { app } from './state.svelte';
import type { FrameworkInfo } from './types';

const QBOX: FrameworkInfo = { id: 'qbox', label: 'Qbox', gangs: true, multiJob: true, homes: true, inventory: 'ox_inventory', metadata: true };

export function framework(): FrameworkInfo {
  return app.boot?.framework ?? QBOX;
}

export function citizenValid(value: string) {
  return /^[A-Za-z0-9:]{1,60}$/.test(value);
}
