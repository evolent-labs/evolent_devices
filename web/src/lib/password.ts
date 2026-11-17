import { t } from './state.svelte';

export function wrongText(left: number) {
  return left > 0 && left <= 2 ? t('os_password_wrong_left', left) : t('os_password_wrong');
}
