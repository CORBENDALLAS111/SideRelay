# isideload 0.5.0 (MIT)

Source: https://crates.io/crates/isideload/0.5.0

SideRelay changes:
- Reuse refreshed anisette client-provided data in both SRP init and complete after an Apple hsc=434 resync. Previously complete used stale data.
- Keep exhausted HTTP 429 as a typed reqwest error for private, structured diagnostics.

Original copyright and license are retained. No SideInstaller source is included.
- Preserve typed Apple errors in anisette provisioning, and HTTP failures in the URL bag lookup. Bound Apple HTTP requests to 30 seconds.
- Test-only loopback SRP server checks refreshed CPD in both init and complete.
