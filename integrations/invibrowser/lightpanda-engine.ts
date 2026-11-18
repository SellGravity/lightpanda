/**
 * InviPanda engine adapter for the InviBrowser launcher (gravbrowser).
 *
 * Drop this file into gravbrowser/electron/modules/lightpanda/ and, in
 * gravity-chromium.launcher.ts, spawn through `buildLightpandaSpawn()` when a
 * profile's engine is 'lightpanda'. Everything else stays as for Chromium:
 *
 *   - the SAME args from chromiumConfig.build(...) are passed through:
 *     InviPanda translates --user-agent, --hardware-concurrency, --window-size,
 *     --proxy-server, --timezone, --lang, --location-mode, --webgl-*, the noise
 *     flags, --font-exclusion-list, --remote-debugging-port ... and ignores
 *     Chromium-only switches, --load-extension and startup URLs;
 *   - CDP is served on the same --remote-debugging-port, so waitForCdpReady()
 *     and cdp.service.ts work unchanged (WSL2 forwards localhost);
 *   - user-data-dir only seeds the per-profile noise (stable fingerprint).
 *
 * InviPanda is a Linux binary: on Windows it runs inside WSL2 (see
 * scripts/invipanda-install-wsl.sh in the fork).
 */

import { spawn, type ChildProcess, type SpawnOptions } from 'child_process'

export interface LightpandaRuntime {
  /** WSL distribution name (`wsl -l -v`). */
  wslDistro: string
  /** Absolute path of the launcher script inside the distro. */
  binary: string
}

export const DEFAULT_RUNTIME: LightpandaRuntime = {
  wslDistro: 'Ubuntu-24.04',
  binary: '/opt/invipanda/invipanda',
}

/** C:\Users\a\b -> /mnt/c/Users/a/b (WSL view of a Windows path). */
export function toWslPath(winPath: string): string {
  const m = /^([A-Za-z]):[\\/](.*)$/.exec(winPath)
  if (!m) return winPath.replace(/\\/g, '/')
  return `/mnt/${m[1].toLowerCase()}/${m[2].replace(/\\/g, '/')}`
}

/** Launcher args that only make sense for a windowed Chromium. */
const DROP_PREFIXES = ['--load-extension=']

/**
 * Rewrites the Chromium arg list for InviPanda: Windows paths in
 * --user-data-dir become WSL paths, extension loading is dropped.
 */
export function adaptArgs(chromeArgs: string[]): string[] {
  const out: string[] = []
  for (const arg of chromeArgs) {
    if (DROP_PREFIXES.some((p) => arg.startsWith(p))) continue
    if (arg.startsWith('--user-data-dir=')) {
      out.push(`--user-data-dir=${toWslPath(arg.slice('--user-data-dir='.length))}`)
      continue
    }
    out.push(arg)
  }
  return out
}

export interface LightpandaSpawn {
  command: string
  args: string[]
  options: SpawnOptions
}

/**
 * The command the launcher spawns instead of chrome.exe. On non-Windows hosts
 * the binary is executed directly.
 */
export function buildLightpandaSpawn(
  chromeArgs: string[],
  runtime: LightpandaRuntime = DEFAULT_RUNTIME,
): LightpandaSpawn {
  const args = adaptArgs(chromeArgs)
  const options: SpawnOptions = {
    detached: false,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
    env: { ...process.env, LIGHTPANDA_DISABLE_TELEMETRY: 'true' },
  }
  if (process.platform === 'win32') {
    return {
      command: 'wsl.exe',
      args: ['-d', runtime.wslDistro, '-e', runtime.binary, ...args],
      options,
    }
  }
  return { command: runtime.binary, args, options }
}

export function spawnLightpanda(chromeArgs: string[], runtime?: LightpandaRuntime): ChildProcess {
  const s = buildLightpandaSpawn(chromeArgs, runtime)
  return spawn(s.command, s.args, s.options)
}

/*
 * Integration sketch for gravity-chromium.launcher.ts (around `spawn(chromeExe, finalArgs, ...)`):
 *
 *   const child = profile.engine === 'lightpanda'
 *     ? spawnLightpanda(finalArgs)
 *     : spawn(chromeExe, finalArgs, { ... })
 *
 * and pass `--ua-full-version=<full Chrome build>` from the fingerprint so
 * high-entropy client hints carry a real build number instead of x.0.0.0.
 */
