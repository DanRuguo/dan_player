# Verified installer update handoff

`InstallerLauncher.instance.launchForUpdate(installer:, sha256:, version:)`
does not quit the application. It returns only after a verified installer has
confirmed this running player as its parent. The update UI can then shut down
normally. Failure leaves the player running and retains manual installation.

## Trust and file identity

- Only absolute local-drive `.exe` paths are accepted, never ZIP/shell commands,
  UNC paths, alternate data streams or a caller-supplied target/PID.
- The native worker opens the installer read-only with write/delete sharing
  denied. It rejects reparse files and hard links, obtains the canonical path,
  locks its canonical ancestors against rename, and rechecks file identity.
  Locks remain held through the handshake. The running executable is resolved
  with `GetModuleFileNameW`, not from settings or downloaded metadata.
- SHA-256 is streamed from that same handle. Both files must pass Windows
  Authenticode trust (including chain revocation policy). Their verified leaf
  signing-certificate SHA-256 values must match exactly. Matching CN text or the
  release certificate's thumbprint alone is not trust. No root or certificate
  is imported; an untrusted self-signed release fails safely.
- The locked, signed installer must have `ProductName=Dan Player Installer`
  and a `ProductVersion` exactly matching the requested release, including any
  prerelease suffix. Certificate rotation therefore requires an explicitly
  coordinated player release/manual update, not a permissive name match.

## Bounded two-way handoff

`CreateProcessW` receives an explicit verified executable and independently
quoted Unicode arguments: `/DANUPDATE=1`, `/DIR=<current EXE directory>`,
`/DANPARENTPID=<current PID>`, `/DANUPDATEVERSION=<version>` and
`/DANUPDATEEVENT=Local\DanPlayer.Update.<256-bit random hex>`.
There is no shell, elevation broker, inherited handle, or process termination.

The launcher creates READY and `<READY>.Accepted` manual-reset events before
starting the installer. The installer verifies/holds its actual parent process
and image before signalling READY. The launcher waits up to 30 seconds, then
signals Accepted only if READY arrived and the operation is still active.
Only Accepted permits the installer to wait for parent exit and then modify
the installation. A late READY retained by an installer cannot revive a timed
out or cancelled authorization. Failure never triggers a delayed retry/start.
The installer owns its additional bounded parent-exit wait and transaction.

Hash/trust/launch work runs on a native worker. Results are dispatched back to a
message-only HWND on the Flutter platform thread. Active-job-only polling backs
up message posting; shutdown cancels the job and discards the pending result
before the engine/messenger are destroyed, without joining a trust/network call.
The 30-second bound applies to READY, not to Windows' trust-provider work.

## Evidence and limits

The dedicated `installer_launch_test` target never starts an installer. It uses
synthetic Unicode files, an unsigned resource fixture, real file sharing/hash/
Windows untrusted-signature checks, and an injected process/trust backend for
successful and failed handshakes. Dart tests mock the MethodChannel. These are
not proof of a signed end-to-end upgrade, UAC interaction or a visible installer.

Primary API references:

- [WinVerifyTrust: only zero means trusted; noninteractive verification](https://learn.microsoft.com/en-us/windows/win32/api/wintrust/nf-wintrust-winverifytrust)
- [WINTRUST_FILE_INFO: verify an existing readable file handle](https://learn.microsoft.com/en-us/windows/win32/api/wintrust/ns-wintrust-wintrust_file_info)
- [WTHelperGetProvSignerFromChain: identity of the verified signer](https://learn.microsoft.com/en-us/windows/win32/api/wintrust/nf-wintrust-wthelpergetprovsignerfromchain)
- [CreateFileW: sharing modes and reparse-point handles](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)
- [CreateProcessW: explicit application, writable Unicode command line](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)
