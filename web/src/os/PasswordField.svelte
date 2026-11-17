<script lang="ts">
  import { t } from '$lib/state.svelte';
  import Glyph from '$components/Glyph.svelte';
  import { IC } from './icons';
  import { setField } from './input';

  let {
    value = $bindable(''),
    input = $bindable(null),
    placeholder,
    max,
    large = false,
    error = false,
    oninput,
    onfocus,
    onblur,
  }: {
    value?: string;
    input?: HTMLInputElement | null;
    placeholder: string;
    max: number;
    large?: boolean;
    error?: boolean;
    oninput?: () => void;
    onfocus?: () => void;
    onblur?: () => void;
  } = $props();

  let shown = $state(false);

  function toggle() {
    shown = !shown;

    if (input) {
      setField(input);
    }
  }
</script>

<div class="pw-password" class:pw-large={large} class:pw-error={error}>
  <input
    bind:this={input}
    bind:value
    type={shown ? 'text' : 'password'}
    {placeholder}
    maxlength={max}
    spellcheck="false"
    autocomplete="off"
    {oninput}
    {onfocus}
    {onblur}
  />
  <button type="button" class="pw-eye" aria-label={shown ? t('os_password_hide') : t('os_password_show')} onclick={toggle}>
    <Glyph d={shown ? IC.eyeOff : IC.eye} size={large ? 20 : 18} />
  </button>
</div>

<style>
  .pw-password {
    display: flex;
    align-items: center;
    width: 220px;
    height: 40px;
    background: #0a0a0f;
    border: 1px solid #2a2a35;
    border-radius: 8px;
    transition: border-color 0.16s;
  }
  .pw-password:focus-within {
    border-color: var(--accent);
  }
  .pw-password.pw-error {
    border-color: #f82834;
  }
  .pw-password.pw-large {
    width: 100%;
    height: 52px;
    background: rgba(15, 15, 21, 0.8);
    border-radius: 12px;
  }
  input {
    flex: 1;
    min-width: 0;
    height: 100%;
    padding: 0 0 0 12px;
    background: transparent;
    border: 0;
    outline: none;
    color: #e4e4e7;
    font: 500 14px/1 Poppins, system-ui, sans-serif;
    user-select: text;
  }
  .pw-password input:focus-visible {
    outline: none;
  }
  .pw-large input {
    padding-left: 16px;
    font-size: 16px;
  }
  input[type='password'] {
    letter-spacing: 2px;
  }
  input::placeholder {
    color: #71717a;
    letter-spacing: 0;
  }
  .pw-eye {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 40px;
    height: 100%;
    padding: 0;
    background: transparent;
    border: 0;
    color: #71717a;
    cursor: pointer;
  }
  .pw-eye:hover {
    color: #e4e4e7;
  }
</style>
