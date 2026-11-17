<script lang="ts">
  import { browserPreview } from '$lib/nui';
  import { t } from '$lib/state.svelte';
  import { initials } from '$lib/tablet/clock';
  import { IC } from '$lib/tablet/icons';
  import { forgotPassword, powerOff, restart, submitPassword, tablet, toLock, typedPassword } from '$lib/tablet/store.svelte';
  import { IC as OS } from '../../os/icons';
  import PasswordField from '../../os/PasswordField.svelte';
  import Glyph from '$components/Glyph.svelte';

  let field = $state<HTMLInputElement | null>(null);
  let forgetting = $state(false);

  const shake = $derived(tablet.pinErr ? (tablet.shakeN % 2 ? 'eot-shake .4s' : 'eot-shake2 .4s') : 'none');
  const blocked = $derived(tablet.checking || tablet.waitUntil > 0);

  $effect(() => {
    field?.focus({ preventScroll: true });
  });

  function submit(event: SubmitEvent) {
    event.preventDefault();
    submitPassword();
  }

  function forgot() {
    if (forgetting) forgotPassword();

    forgetting = !forgetting;
  }
</script>

<div class="t-login">
  <span class="t-avatar">{initials(tablet.user.name)}</span>
  <p class="t-name">{tablet.user.name}</p>
  {#if tablet.user.role || tablet.user.org}
    <p class="t-role">{#if tablet.user.role}<span class="t-chip">{tablet.user.role}</span>{/if}{#if tablet.user.org}<span>{tablet.user.org}</span>{/if}</p>
  {/if}
  <form class="t-entry" style:animation={shake} onsubmit={submit}>
    <PasswordField large bind:value={tablet.entry} bind:input={field} error={tablet.pinErr} placeholder={t('os_password_field')} max={tablet.system.limits.passwordMax} oninput={typedPassword} />
    <button type="submit" class="t-go" aria-label={t('os_sign_in')} disabled={blocked}><Glyph d={OS.arrowRight} size={20} stroke={2} /></button>
  </form>
  <p class="t-message" class:t-error={tablet.pinErr}>{tablet.loginMsg}</p>
  {#if tablet.system.owner}
    <button type="button" class="t-link" onclick={forgot}>{forgetting ? t('os_password_forgot_sure') : t('os_password_forgot')}</button>
  {/if}
  {#if import.meta.env.DEV && browserPreview}
    <p class="t-demo mono"><span>DEMO</span><span>evolent</span></p>
  {/if}
  <div class="t-corner">
    <button type="button" class="t-small" aria-label={t('os_back_to_lock')} onclick={toLock}><Glyph d={IC.back} size={17} stroke={1.75} /></button>
    <button type="button" class="t-small" aria-label={t('os_restart')} onclick={restart}><Glyph d={IC.restart} size={17} stroke={1.75} /></button>
    <button type="button" class="t-small t-off" aria-label={t('os_power_off')} onclick={powerOff}><Glyph d={IC.power} size={17} stroke={1.75} /></button>
  </div>
</div>

<style>
  .t-login {
    position: absolute;
    inset: 0;
    z-index: 100;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: rgba(5, 5, 8, 0.62);
    backdrop-filter: blur(26px);
    animation: eot-fade 0.25s;
  }
  .t-avatar {
    display: grid;
    place-items: center;
    width: 92px;
    height: 92px;
    background: var(--accent);
    border-radius: 50%;
    color: var(--accent-content);
    font-size: 30px;
    font-weight: 600;
    letter-spacing: -0.02em;
    animation: eot-logo 0.4s cubic-bezier(0.2, 0.8, 0.2, 1) both;
  }
  .t-name {
    margin-top: 16px;
    font-size: 24px;
    font-weight: 600;
    letter-spacing: -0.02em;
  }
  .t-role {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 2px;
    font-size: 13px;
    color: #a1a1aa;
  }
  .t-chip {
    padding: 1px 7px;
    background: #17171f;
    border: 1px solid #2a2a35;
    border-radius: 5px;
    font: 500 11px/1.4 'Poppins', system-ui, sans-serif;
    color: #a1a1aa;
  }
  .t-entry {
    display: flex;
    gap: 10px;
    width: 360px;
    margin-top: 28px;
  }
  .t-go {
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
  .t-go:hover {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--accent-content);
  }
  .t-go:disabled {
    cursor: default;
    opacity: 0.6;
  }
  .t-message {
    height: 20px;
    margin-top: 12px;
    font-size: 13px;
    color: #a1a1aa;
  }
  .t-message.t-error {
    color: #f82834;
  }
  .t-link {
    margin-top: 16px;
    padding: 0;
    background: transparent;
    border: 0;
    color: #a1a1aa;
    font: 500 13px/1 'Poppins', system-ui, sans-serif;
    text-decoration: underline;
    cursor: pointer;
  }
  .t-link:hover {
    color: #e4e4e7;
  }
  .t-demo {
    position: absolute;
    bottom: 40px;
    left: 48px;
    display: flex;
    gap: 10px;
    font: 500 11px/1.4 'JetBrains Mono', monospace;
    letter-spacing: 1.2px;
    color: #71717a;
  }
  .t-corner {
    position: absolute;
    bottom: 36px;
    right: 40px;
    display: flex;
    gap: 6px;
  }
  .t-small {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    background: rgba(15, 15, 21, 0.8);
    border: 1px solid #2a2a35;
    border-radius: 12px;
    color: #a1a1aa;
    cursor: pointer;
  }
  .t-small:hover {
    color: #e4e4e7;
    border-color: #3a3a45;
  }
  .t-small.t-off:hover {
    color: #f82834;
    border-color: #3a1a1f;
  }
</style>
