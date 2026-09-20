# Managed external Omarchy plugins

Hyprland_Config keeps repository-owned Omarchy plugins under:

```text
omarchy/plugins/gendbyte.*
```

Third-party plugins are not vendored there. They are declared in
`omarchy/external-plugins.lua` and pinned to exact Git commits.

## Managed plugins

The initial manifest contains:

| Plugin | Omarchy id | Pinned commit |
| --- | --- | --- |
| Orbit | `io.github.rohan-patnaik.window-switcher` | `b9115759175be41b71516926037b480f92449e8f` |
| Clipboard Manager | `io.github.vuhuy.clipboard-manager` | `79c8f2a1cc09439ed56bcd69abacb2d1cabc543c` |
| Agent Orchestrator | `meviusisback.agent-orchestr` | `cb35aaa701b81b9372f43d7efb882b8b34fcd662` |

## Storage and ownership

Pinned source checkouts live under:

```text
~/.local/share/hyprland_config/external-plugins/<plugin-id>
```

Omarchy sees them through owned symlinks under:

```text
~/.config/omarchy/plugins/<plugin-id>
```

The manager refuses to replace an existing plugin target unless that target is
already a symlink to the exact Hyprland_Config-managed source path.

This means a manually installed plugin is not silently adopted or deleted.

## Sync

Run:

```bash
lua5.1 omarchy-plugins.lua sync
```

The sync operation:

1. validates every manifest entry;
2. requires an exact 40-character commit SHA;
3. fetches the requested commit into a staging checkout;
4. verifies the resulting Git revision;
5. verifies that upstream `manifest.json` contains the expected plugin id;
6. atomically replaces the previous managed source checkout;
7. creates an owned Omarchy symlink;
8. rescans Omarchy Shell;
9. enables or disables the plugin according to the manifest.

If Omarchy is not installed, sync exits successfully without changing the
generic Hyprland setup.

## Remove

Run:

```bash
lua5.1 omarchy-plugins.lua remove
```

Only owned symlinks and sources are removed. Conflicting user-managed plugin
paths are preserved and reported as errors.

## Updating a plugin

Do not change `rev` to `main`.

Instead:

1. inspect the upstream changes between the old pin and the proposed commit;
2. update the exact `rev` in `omarchy/external-plugins.lua`;
3. review the upstream plugin code because Omarchy plugins execute as your user;
4. run the test suite;
5. run `lua5.1 omarchy-plugins.lua sync`.

Pin changes are intentionally explicit and reviewable.
