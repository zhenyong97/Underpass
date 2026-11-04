# Underpass native macOS interface

Operate mode. Jade, native macOS controls and the portal identity carry forward from the approved visual direction. On 2026-11-04 the user approved replacing the long vertical page with a compact list/detail layout, following a running-state screenshot showing the bottom actions outside the first screen.

Default window 820 × 580 pt; minimum 700 × 480 pt. A compact top bar contains v2rayN/protocol/session readiness, refresh, import and management. A native HSplitView places a 250–300 pt channel sidebar beside the selected channel detail. Each pane scrolls independently. The footer and detail action buttons stay visible. A new scene ID avoids restoring the old tall layout on first launch of 1.1.

Channel rows are approximately 52 pt, with icon, name, actual state, a small native switch, and a discoverable ellipsis menu. Version, origin and full summary belong in details. Search covers name, summary and stable ID, preserving installation order. The enabled filter uses actual runtime activity. Search/filter changes do not change selected channel or runtime state; removing the selected channel uses the model's existing selection fallback.

The selected channel has Overview, Connections and Configuration tabs. Its open/test actions are above the tab content and remain fixed. Overview distinguishes kernel readiness, HTTPS reachability, and manual media playback. Connections lists only currently matching connections and their bytes, never a shared aggregate. Configuration exposes metadata, DNS, collapsible rule groups and original JSON/local editing through the existing editor sheet.

Import is a compact toolbar action with ⇧⌘I. The entire sidebar accepts file drops; its drag overlay appears only during a drag. Empty states explain import and filter recovery. ⌘F focuses search. Transient notices occupy at most two lines, with full text in a popover and undo where applicable. Long operational errors cannot expand the whole page.

Use semantic system colors, SF Symbols and system text styles, with one adaptive jade tint. Native switches, segmented controls, menus, lists, split view and sheets preserve keyboard and accessibility behavior. Avoid extra motion; dynamic lists and counts update in place. JSON and host data use monospace; product copy does not.

Layout QA uses a separate native host with its own bundle IDs and temporary catalog. It never starts a managed session. Standard (two channels) and compact (twenty channels, long name/result) fixtures exercise the actual product views. See Docs/VALIDATION-1.1.md for completed checks and limits.
