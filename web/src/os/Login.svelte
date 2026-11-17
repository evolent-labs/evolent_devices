<script lang="ts">
  import { reasonText, t } from '$lib/state.svelte';
  import { osCall } from './bridge';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { activeField, setField } from './input';
  import { page, watching } from './params';
  import { password, passwordBlocked, resetPassword, setPasswordField, submitPassword, typedPassword } from './password.svelte';
  import PasswordField from './PasswordField.svelte';
  import { mergeNotices } from './shell';
  import { os } from './store.svelte';

  let { onsignin, onback, onrestart, onshutdown }: { onsignin: () => void; onback: () => void; onrestart: () => void; onshutdown: () => void } = $props();

  let forgetting = $state(false);
  let field = $state<HTMLInputElement | null>(null);

  const device = $derived(os.device || t('kind_' + page.kind));
  const locked = $derived(os.system.password);
  const shake = $derived(password.error && password.shake > 0 ? (password.shake % 2 ? 'eos-shake .4s' : 'eos-shake2 .4s') : 'none');

  $effect(() => {
    resetPassword();

    return resetPassword;
  });

  $effect(() => {
    const input = field;

    if (watching || !locked || !input) return;

    setPasswordField(input);
    setField(input);

    return () => {
      setPasswordField(null);

      if (activeField() === input) {
        setField(null);
      }
    };
  });

  function submit(event: SubmitEvent) {
    event.preventDefault();
    submitPassword(onsignin);
  }

  async function forgot() {
    if (!forgetting) {
      forgetting = true;

      return;
    }

    forgetting = false;

    const answer = await osCall<{ notices?: unknown }>('forgot');

    if (answer.ok) {
      os.notices = mergeNotices(os.notices, answer.data?.notices, Date.now());
      os.system.password = false;
      resetPassword();
      onsignin();
    } else {
      password.error = true;
      password.message = reasonText({ reason: answer.reason ?? 'no_response' });
    }
  }
</script>

<div class="login">
  {#if watching}
    <span class="avatar"><Glyph d={IC.user} size={40} stroke={2} /></span>
    <i class="bone name-bone"></i>
    <i class="bone who-bone"></i>
  {:else}
    <span class="avatar">{os.user?.initials ?? ''}</span>
    <p class="name">{os.user?.name ?? ''}</p>
    <p class="who"><span class="chip">{device}</span></p>
  {/if}
  {#if locked}
    <form class="entry" style:animation={watching ? 'none' : shake} onsubmit={submit}>
      {#if watching}
        <PasswordField large placeholder={t('os_password_field')} max={os.system.limits.passwordMax} />
      {:else}
        <PasswordField
          large
          bind:value={password.entry}
          bind:input={field}
          error={password.error}
          placeholder={t('os_password_field')}
          max={os.system.limits.passwordMax}
          oninput={typedPassword}
        />
      {/if}
      <button type="submit" class="go" aria-label={t('os_sign_in')} disabled={!watching && passwordBlocked()}><Glyph d={IC.arrowRight} size={20} stroke={2} /></button>
    </form>
    <p class="message" class:error={!watching && password.error}>{watching ? '' : password.message}</p>
    {#if !watching && os.system.owner}
      <button type="button" class="link" onclick={forgot}>{forgetting ? t('os_password_forgot_sure') : t('os_password_forgot')}</button>
    {/if}
  {:else}
    <button type="button" class="sign-in" onclick={onsignin}>{t('os_sign_in')}<Glyph d={IC.arrowRight} size={18} stroke={2} /></button>
  {/if}
  <div class="corner">
    <button type="button" aria-label={t('os_back_to_lock')} onclick={onback}><Glyph d={IC.back} size={16} /></button>
    <button type="button" aria-label={t('os_restart')} onclick={onrestart}><Glyph d={IC.restart} size={16} /></button>
    <button type="button" class="power" aria-label={t('os_shut_down')} onclick={onshutdown}><Glyph d={IC.power} size={16} /></button>
  </div>
</div>

<style>
  .login {
    position: absolute;
    inset: 0;
    z-index: 100;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: rgba(5, 5, 8, 0.62);
    backdrop-filter: blur(26px);
    animation: eos-fade 0.25s;
  }
  .avatar {
    display: grid;
    place-items: center;
    width: 96px;
    height: 96px;
    background: var(--accent);
    border-radius: 50%;
    color: var(--accent-content);
    font-size: 30px;
    font-weight: 600;
    letter-spacing: -0.02em;
    animation: eos-logo 0.4s cubic-bezier(0.2, 0.8, 0.2, 1) both;
  }
  .name {
    margin-top: 18px;
    font-size: 24px;
    font-weight: 600;
    letter-spacing: -0.02em;
  }
  .who {
    display: flex;
    gap: 8px;
    margin-top: 8px;
  }
  .chip {
    padding: 3px 9px;
    background: rgba(15, 15, 21, 0.7);
    border: 1px solid #2a2a35;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 500;
    color: #a1a1aa;
  }
  .bone {
    display: block;
    background: rgba(255, 255, 255, 0.1);
    border-radius: 6px;
  }
  .name-bone {
    width: 190px;
    height: 22px;
    margin-top: 24px;
  }
  .who-bone {
    width: 120px;
    height: 12px;
    margin-top: 12px;
  }
  .entry {
    display: flex;
    gap: 10px;
    width: 340px;
    margin-top: 32px;
  }
  .go {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 52px;
    height: 52px;
    padding: 0;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 12px;
    color: var(--accent);
    cursor: pointer;
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .go:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .go:disabled {
    cursor: default;
    opacity: 0.6;
  }
  .message {
    height: 20px;
    margin-top: 14px;
    font-size: 13px;
    color: #a1a1aa;
  }
  .message.error {
    color: #f82834;
  }
  .link {
    margin-top: 20px;
    padding: 0;
    background: transparent;
    border: 0;
    color: #a1a1aa;
    font: 500 13px/1 Poppins, system-ui, sans-serif;
    text-decoration: underline;
    cursor: pointer;
  }
  .link:hover {
    color: #e4e4e7;
  }
  .sign-in {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    height: 48px;
    margin-top: 32px;
    padding: 0 22px 0 26px;
    background: var(--accent-bg);
    border: 1px solid var(--accent-line);
    border-radius: 12px;
    color: var(--accent);
    font: 600 15px/1 Poppins, system-ui, sans-serif;
    cursor: pointer;
    transition: background 0.16s, color 0.16s, border-color 0.16s;
  }
  .sign-in:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .corner {
    position: absolute;
    bottom: 48px;
    right: 48px;
    display: flex;
    gap: 6px;
  }
  .corner button {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    background: rgba(15, 15, 21, 0.8);
    border: 1px solid #2a2a35;
    border-radius: 10px;
    color: #a1a1aa;
    cursor: pointer;
  }
  .corner button:hover {
    color: #e4e4e7;
    border-color: #3a3a45;
  }
  .corner .power:hover {
    color: #f82834;
    border-color: #3a1a1f;
  }
</style>
