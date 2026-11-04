# 暗渡 · Underpass

<!-- impeccable:product-schema 1 -->

## Platform
macos

## Stack
Native macOS SwiftUI / AppKit, Foundation, SystemConfiguration; Apple Silicon, macOS 13+. Local sing-box 1.13.14 and Xray 26.7.11. No web wrapper.

## Users
The Mac owner using v2rayN on a company network, choosing individual service channels while preserving other traffic's supported original path.

## Product Purpose
Reuse the selected v2rayN node for declarative, independently removable service packages. QQ Music and Bilibili ship as packages using exactly the import format.

## Capabilities and Constraints
Packages describe domain/application/process matches, two implemented DNS policies, HTTPS tests and open entries. No scripts, credentials or arbitrary core plugins. Multiple active channels share one privileged supervised session. Opening the app never starts channels. Imported updates are incremental and previewed; local conflicts are retained. A closed channel stops extra routing and does not promise direct access.

## Product Principles
- Kernel-confirmed states, recoverable updates, and accurate test scope.
- Preserve original proxy fields where still owned; do not overwrite later client changes.
- Keep credentials local, transient and out of source packages.
- User-approved jade native macOS panel: compact searchable channel list, independent switches, fixed node status, selected-channel detail tabs, drag/import and discoverable menus.

## Evidence on Hand
The old QQ Music route was tested by the user. New code has read-only real-node validation and loopback core integration coverage. Privileged TUN, system recovery and company-network playback still need field validation. See Docs/VALIDATION.md.
