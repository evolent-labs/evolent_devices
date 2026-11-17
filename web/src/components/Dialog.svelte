<script lang="ts">
  import Dropdown from './Dropdown.svelte';
  import Icon from './Icon.svelte';
  import { app, t } from '$lib/state.svelte';

  let values = $state<Record<string, unknown>>({});
  let error = $state('');
  let shown = $state<Record<string, boolean>>({});
  let overlay: HTMLElement | undefined = $state();

  $effect(() => {
    const dialog = app.dialog;

    if (!dialog) return;

    const initial: Record<string, unknown> = {};

    for (const field of dialog.fields ?? []) {
      initial[field.key] = field.value ?? (field.type === 'checkbox'
        ? false
        : field.type === 'select' ? field.options?.[0]?.value ?? '' : '');
    }

    values = initial;
    shown = {};
    error = '';
  });

  function finish(ok: boolean) {
    const dialog = app.dialog;

    if (!dialog) return;

    if (ok) {
      for (const field of dialog.fields ?? []) {
        const value = values[field.key];

        if (field.required && (value === '' || value === null || value === undefined)) {
          error = t('ui_required', field.label);

          return;
        }

        if (field.type === 'number' && value !== '' && value !== null) {
          const number = Number(value);

          if (!Number.isFinite(number) || (field.min !== undefined && number < field.min) || (field.max !== undefined && number > field.max)) {
            error = t('ui_number_range', field.label, field.min ?? '-', field.max ?? '-');

            return;
          }

          values[field.key] = Math.floor(number);
        }
      }
    }

    app.dialog = null;
    dialog.resolve(ok ? { ...values } : null);
  }

  function keydown(event: KeyboardEvent) {
    if (!app.dialog || !overlay || overlay.getClientRects().length === 0) return;

    if ((event.target as HTMLElement)?.closest?.('.dropdown[aria-expanded=true], .dropdown-menu')) return;

    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      finish(false);
    } else if (event.key === 'Enter' && (event.target as HTMLElement)?.tagName !== 'BUTTON') {
      event.preventDefault();
      finish(true);
    }
  }
</script>

<svelte:window onkeydowncapture={keydown} />

{#if app.dialog}
  <div class="overlay" role="presentation" bind:this={overlay}>
    <div class="dialog" role="dialog" aria-modal="true" aria-label={app.dialog.title}>
      <div class="dialog-head"><h2>{app.dialog.title}</h2></div>
      <div class="dialog-body">
      {#if app.dialog.message}<p class="message">{app.dialog.message}</p>{/if}
      {#each app.dialog.fields ?? [] as field (field.key)}
        {#if field.type === 'checkbox'}
          <label class="check"><span><strong>{field.label}</strong>{#if field.help}<small>{field.help}</small>{/if}</span><input type="checkbox" bind:checked={values[field.key] as boolean} /></label>
        {:else}
          <label class="field">
            {field.label}
            {#if field.type === 'select'}
              <Dropdown bind:value={values[field.key]} options={field.options ?? []} />
            {:else if field.type === 'password'}
              <span class="secret">
                <input type={shown[field.key] ? 'text' : 'password'} placeholder={field.placeholder} autocomplete="off" spellcheck="false" bind:value={values[field.key]} />
                <button type="button" class="eye" aria-label={shown[field.key] ? t('ui_password_hide') : t('ui_password_show')} onclick={() => (shown[field.key] = !shown[field.key])}><Icon name={shown[field.key] ? 'eyeOff' : 'eye'} /></button>
              </span>
            {:else if field.type === 'number'}
              <input type="number" min={field.min} max={field.max} placeholder={field.placeholder} bind:value={values[field.key]} />
            {:else}
              <input type="text" placeholder={field.placeholder} bind:value={values[field.key]} />
            {/if}
            {#if field.help}<small>{field.help}</small>{/if}
          </label>
        {/if}
      {/each}
      {#if error}<p class="small" style="color:var(--error);margin-top:12px">{error}</p>{/if}
      </div>
      <div class="buttons">
        <button class="button" onclick={() => finish(false)}>{t('ui_cancel')}</button>
        <button class={'button ' + (app.dialog.danger ? 'danger' : 'primary')} onclick={() => finish(true)}>{app.dialog.confirm}</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .secret {
    position: relative;
    display: block;
  }
  .secret input:not([type='checkbox']) {
    padding-right: 44px;
  }
  .eye {
    position: absolute;
    top: 8px;
    right: 0;
    bottom: 0;
    display: grid;
    place-items: center;
    width: 44px;
    padding: 0;
    background: transparent;
    border: 0;
    color: var(--dim);
    cursor: pointer;
  }
  .eye:hover {
    color: var(--text);
  }
</style>
