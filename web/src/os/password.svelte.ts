import { wrongText } from '$lib/password';
import { reasonText, t } from '$lib/state.svelte';
import { osCall } from './bridge';
import { activeField, setField } from './input';
import { mergeNotices } from './shell';
import { os } from './store.svelte';

export const password = $state({
  entry: '',
  error: false,
  message: '',
  busy: false,
  shake: 0,
  waitUntil: 0,
});

let field: HTMLInputElement | null = null;
let waitTimer: ReturnType<typeof setInterval> | null = null;

export function setPasswordField(next: HTMLInputElement | null) {
  field = next;
}

export function focusPassword() {
  if (field && activeField() !== field) {
    setField(field);
  }
}

export const passwordBlocked = () => password.busy || password.waitUntil > Date.now();

export function resetPassword() {
  password.entry = '';
  password.error = false;
  password.message = '';
  password.busy = false;
}

export function typedPassword() {
  if (password.waitUntil > Date.now()) return;

  password.error = false;
  password.message = '';
}

function waitText() {
  const left = Math.max(0, Math.ceil((password.waitUntil - Date.now()) / 1000));

  if (left <= 0) {
    if (waitTimer) {
      clearInterval(waitTimer);
    }

    waitTimer = null;
    password.waitUntil = 0;
    password.error = false;
    password.message = '';

    return;
  }

  password.message = t('os_password_wait', left);
}

function startWait(seconds: number) {
  password.waitUntil = Date.now() + Math.max(1, seconds) * 1000;
  password.error = true;

  if (waitTimer) {
    clearInterval(waitTimer);
  }

  waitTimer = setInterval(waitText, 500);
  waitText();
}

function wrong(message: string) {
  password.entry = '';
  password.error = true;
  password.message = message;
  password.shake += 1;
}

export async function submitPassword(done: () => void) {
  if (passwordBlocked()) return;

  if ([...password.entry].length < os.system.limits.passwordMin) {
    wrong(t('os_password_short', os.system.limits.passwordMin));

    return;
  }

  password.busy = true;

  const answer = await osCall<{ left?: number; seconds?: number; notices?: unknown }>('unlock', password.entry);

  password.busy = false;

  if (answer.ok) {
    os.notices = mergeNotices(os.notices, answer.data?.notices, Date.now());
    resetPassword();
    done();

    return;
  }

  if (answer.reason === 'password_wait') {
    password.entry = '';
    password.shake += 1;
    startWait(Number(answer.data?.seconds ?? 60));

    return;
  }

  if (answer.reason === 'password_wrong') {
    wrong(wrongText(Number(answer.data?.left ?? 0)));

    return;
  }

  wrong(reasonText({ reason: answer.reason ?? 'no_response' }));
}
