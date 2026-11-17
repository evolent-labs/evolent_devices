import { confirmLeave } from './nav.svelte';
import { currentToken, post, setToken } from './nui';
import { app, clearToasts } from './state.svelte';

export function hidePanel() {
  app.visible = false;
  app.dialog?.resolve(null);
  app.dialog = null;
  app.dirty = false;
  app.placing = false;
  clearToasts();
  setToken('');
}

export async function closePanel(force = false) {
  if (!force && !(await confirmLeave())) return;

  const token = currentToken();

  hidePanel();
  post('close', { __t: token }).catch(() => null);
}
