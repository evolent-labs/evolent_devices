import { t, toast } from './state.svelte';

export async function copyText(text: string) {
  let copied = false;

  try {
    if (navigator.clipboard) {
      await navigator.clipboard.writeText(text);
      copied = true;
    }
  } catch {
    copied = false;
  }

  if (!copied) {
    const area = document.createElement('textarea');

    area.value = text;
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();

    try {
      copied = document.execCommand('copy');
    } catch {
      copied = false;
    }

    area.remove();
  }

  toast(copied ? t('ui_copied') : t('ui_copy_failed'), copied ? 'success' : 'error');
}
