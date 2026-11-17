export interface TabletParts {
  tablet: { visible: boolean };
  openTablet(data: unknown): void;
  hideTablet(): void;
  tabletMessage(message: Record<string, unknown>): void;
}

export function tabletGate<T extends TabletParts>(load: () => Promise<T>, failed: (data: unknown) => void) {
  let parts: T | null = null;
  let loading: Promise<void> | null = null;
  let waiting: ((parts: T) => void)[] = [];

  function start(data?: unknown) {
    loading ??= load().then(
      (loaded) => {
        parts = loaded;

        for (const step of waiting.splice(0)) {
          step(loaded);
        }
      },
      () => {
        loading = null;
        waiting = [];
        failed(data);
      }
    );

    return loading;
  }

  function run(step: (parts: T) => void) {
    if (parts) {
      step(parts);
    } else if (loading) {
      waiting.push(step);
    }
  }

  return {
    load: () => start(),
    open(data: unknown) {
      start(data);
      run((loaded) => loaded.openTablet(data));
    },
    close() {
      run((loaded) => loaded.hideTablet());
    },
    message(message: Record<string, unknown>) {
      run((loaded) => {
        if (loaded.tablet.visible) {
          loaded.tabletMessage(message);
        }
      });
    },
  };
}
