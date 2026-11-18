(() => {
  const N = Navigator.prototype;
  delete N.globalPrivacyControl;
  delete N.modelContext;
  // Chrome for Android has no desktop-only hardware / window APIs.
  if (navigator.userAgentData && navigator.userAgentData.mobile) {
    for (const k of ['hid', 'serial', 'keyboard', 'windowControlsOverlay', 'ink', 'managed', 'getInstalledRelatedApps', 'setAppBadge', 'clearAppBadge']) delete N[k];
  } else {
    // devicePosture only ships on foldable-capable (Android) builds.
    delete N.devicePosture;
  }
  if (typeof window === 'undefined' || 'chrome' in window) return;
  const native = (fn, name, len) => {
    const b = fn.bind(null);
    Object.defineProperty(b, 'name', { value: name });
    Object.defineProperty(b, 'length', { value: len });
    return b;
  };
  const t0 = Date.now() / 1000;
  const app = {
    isInstalled: false,
    InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
    RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' },
    getDetails: native(function () { return null; }, 'getDetails', 0),
    getIsInstalled: native(function () { return false; }, 'getIsInstalled', 0),
    installState: native(function () { return 'not_installed'; }, 'installState', 1),
    runningState: native(function () { return 'cannot_run'; }, 'runningState', 0),
  };
  const csi = native(function () {
    return { startE: Math.round(t0 * 1000), onloadT: Math.round(t0 * 1000) + 120, pageT: performance.now(), tran: 15 };
  }, 'csi', 0);
  const loadTimes = native(function () {
    return {
      requestTime: t0, startLoadTime: t0, commitLoadTime: t0 + 0.05, finishDocumentLoadTime: t0 + 0.12,
      finishLoadTime: t0 + 0.2, firstPaintTime: t0 + 0.13, firstPaintAfterLoadTime: 0, navigationType: 'Other',
      wasFetchedViaSpdy: true, wasNpnNegotiated: true, npnNegotiatedProtocol: 'h2', wasAlternateProtocolAvailable: false,
      connectionInfo: 'h2',
    };
  }, 'loadTimes', 0);
  Object.defineProperty(window, 'chrome', {
    value: { app, csi, loadTimes }, writable: true, enumerable: true, configurable: false,
  });
})();
