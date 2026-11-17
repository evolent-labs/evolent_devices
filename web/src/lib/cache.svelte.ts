import { call } from './nui';
import { explain, list } from './state.svelte';
import type { Group, Provider } from './types';

export const cache = $state({
  jobs: null as Group[] | null,
  gangs: null as Group[] | null,
  providers: null as Provider[] | null,
});

let groupsLoading: Promise<void> | null = null;
let providersLoading: Promise<void> | null = null;

export function resetCache() {
  cache.jobs = null;
  cache.gangs = null;
  cache.providers = null;
  groupsLoading = null;
  providersLoading = null;
}

export function loadGroups() {
  if (!groupsLoading) {
    groupsLoading = call<{ jobs: Group[]; gangs: Group[] }>('evdev:admin:groups').then((result) => {
      if (!result.ok) {
        explain(result);
        groupsLoading = null;

        return;
      }

      cache.jobs = list<Group>(result.data!.jobs).map((group) => ({ ...group, grades: list(group.grades) }));
      cache.gangs = list<Group>(result.data!.gangs).map((group) => ({ ...group, grades: list(group.grades) }));
    });
  }

  return groupsLoading;
}

export function loadProviders(force = false) {
  if (!providersLoading || force) {
    providersLoading = call<{ providers: Provider[] }>('evdev:admin:providers').then((result) => {
      if (!result.ok) {
        providersLoading = null;

        return;
      }

      setProviders(result.data!.providers);
    });
  }

  return providersLoading;
}

export function setProviders(value: unknown) {
  cache.providers = list<Provider>(value).map((provider) => ({
    ...provider,
    options: list(provider.options),
    levels: list(provider.levels),
  }));
}
