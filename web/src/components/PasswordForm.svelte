<script lang="ts">
  import { wrongText } from '$lib/password';
  import { reasonText, t } from '$lib/state.svelte';
  import PasswordField from '../os/PasswordField.svelte';
  import { passwordValid, type Limits } from '../os/system';

  interface Answer {
    ok: boolean;
    reason?: string;
    data?: { left?: number; owner?: boolean };
  }

  let {
    on,
    can,
    ownerName,
    limits,
    call,
    say,
    onchange,
    onsecret,
  }: {
    on: boolean;
    can: boolean;
    ownerName: string;
    limits: Limits;
    call: (action: 'set' | 'clear', data: Record<string, string>) => Promise<Answer>;
    say: (text: string, bad?: boolean) => void;
    onchange: (on: boolean, owner: boolean) => void;
    onsecret?: (on: boolean) => void;
  } = $props();

  let current = $state('');
  let draft = $state('');
  let busy = $state(false);

  function failed(answer: Answer) {
    if (answer.reason === 'password_wrong') {
      current = '';
      say(wrongText(Number(answer.data?.left ?? 0)), true);
    } else {
      say(reasonText({ reason: answer.reason ?? 'no_response' }), true);
    }
  }

  function needsCurrent() {
    if (!on || current !== '') return false;

    say(t('os_password_need_current'), true);

    return true;
  }

  async function send(action: 'set' | 'clear', data: Record<string, string>, done: string) {
    busy = true;

    const answer = await call(action, data);

    busy = false;

    if (!answer.ok) {
      failed(answer);

      return;
    }

    current = '';
    draft = '';
    onchange(action === 'set', answer.data?.owner === true);
    say(done);
  }

  function save() {
    if (!passwordValid(draft, limits)) {
      say(t('os_password_rule', limits.passwordMin, limits.passwordMax), true);

      return;
    }

    if (!needsCurrent()) {
      send('set', { password: draft, current }, t('os_password_saved'));
    }
  }

  function clear() {
    if (!needsCurrent()) {
      send('clear', { current }, t('os_password_removed'));
    }
  }
</script>

<div class="pf-card">
  <div class="pf-top">
    <div class="pf-grow"><p class="pf-label">{t('os_password_title')}</p><p class="pf-help">{on ? t('os_password_on') : t('os_password_off')}</p></div>
    <span class="pf-pill mono" class:pf-lime={on}>{on ? t('os_on') : t('os_off')}</span>
  </div>
  {#if can}
    <div class="pf-form">
      {#if on}
        <PasswordField bind:value={current} placeholder={t('os_password_current')} max={limits.passwordMax} onfocus={() => onsecret?.(true)} onblur={() => onsecret?.(false)} />
      {/if}
      <PasswordField bind:value={draft} placeholder={t('os_password_new')} max={limits.passwordMax} onfocus={() => onsecret?.(true)} onblur={() => onsecret?.(false)} />
    </div>
    <div class="pf-buttons">
      <button type="button" class="pf-tone" disabled={busy} onclick={save}>{on ? t('os_password_change') : t('os_password_save')}</button>
      {#if on}<button type="button" class="pf-danger" disabled={busy} onclick={clear}>{t('os_password_remove')}</button>{/if}
    </div>
    <p class="pf-help pf-note">{t('os_password_rule', limits.passwordMin, limits.passwordMax)}{#if on}<br />{t('os_password_current_rule')}{/if}</p>
  {:else}
    <p class="pf-help pf-note">{ownerName ? t('os_password_owner_only') : t('os_password_admin_only')}</p>
  {/if}
</div>

<style>
  .pf-card {
    margin-top: 10px;
    padding: 16px 18px;
    background: #0f0f15;
    border: 1px solid #1f1f27;
    border-radius: 12px;
  }
  .pf-top {
    display: flex;
    align-items: center;
    gap: 16px;
  }
  .pf-grow {
    flex: 1;
    min-width: 0;
  }
  .pf-label {
    font-size: 14px;
    font-weight: 600;
  }
  .pf-help {
    margin-top: 2px;
    font-size: 12px;
    color: #a1a1aa;
  }
  .pf-help.pf-note {
    margin-top: 10px;
  }
  .pf-label + .pf-help {
    margin-top: var(--sub-pull);
    line-height: var(--sub-lh);
  }
  .pf-pill {
    padding: 4px 9px;
    background: #17171f;
    border: 1px solid #2a2a35;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 600;
    line-height: 1.3;
    color: #a1a1aa;
    white-space: nowrap;
  }
  .pf-pill.pf-lime {
    background: var(--accent-bg);
    border-color: var(--accent-line);
    color: var(--accent);
  }
  .pf-form {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 12px;
  }
  .pf-buttons {
    display: flex;
    gap: 8px;
    margin-top: 8px;
  }
  .pf-tone,
  .pf-danger {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 40px;
    padding: 0 16px;
    border-radius: 8px;
    font: 600 13px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
  }
  .pf-tone {
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    color: var(--accent);
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .pf-tone:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .pf-danger {
    background: #0a0a0f;
    border: 1px solid #3a1a1f;
    color: #f82834;
    font-weight: 500;
    font-size: 12px;
  }
  .pf-danger:hover {
    border-color: #f82834;
  }
  .pf-tone:disabled,
  .pf-danger:disabled {
    cursor: default;
    opacity: 0.55;
  }
</style>
