<script lang="ts">
  import Icon from './Icon.svelte';
  import RuleList from './RuleList.svelte';
  import type { Access, Mode, RuleType } from '$lib/types';

  export interface AccessChoice {
    mode: Mode;
    icon: string;
    label: string;
    help?: string;
  }

  let {
    access = $bindable(),
    choices,
    types,
    keysAllowed = false,
    disabled = false,
    plain = false,
  }: { access: Access; choices: AccessChoice[]; types: RuleType[]; keysAllowed?: boolean; disabled?: boolean; plain?: boolean } = $props();

  function pick(mode: Mode) {
    if (disabled || access.mode === mode) return;

    access.mode = mode;
  }
</script>

<div class="choices" role="radiogroup">
  {#each choices as choice (choice.mode)}
    <button type="button" class="choice" role="radio" aria-checked={access.mode === choice.mode} {disabled} onclick={() => pick(choice.mode)}>
      <span class="radio"></span>
      {#if !plain}<span class="opt-icon"><Icon name={choice.icon} /></span>{/if}
      <span class="grow"><b>{choice.label}</b>{#if choice.help}<small>{choice.help}</small>{/if}</span>
    </button>
  {/each}
</div>
{#if access.mode === 'rules'}
  <div class="access-rules"><RuleList bind:rules={access.rules} {types} {keysAllowed} {disabled} /></div>
{/if}
