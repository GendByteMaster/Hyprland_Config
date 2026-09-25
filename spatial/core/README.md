# gendbyte-spatial core

Phase 1 native core for Issue #24.

The pure camera/state/protocol library is intentionally buildable without Hyprland:

```bash
cmake -S spatial/core -B build/spatial-core \
  -DCMAKE_BUILD_TYPE=Release \
  -DSPATIAL_BUILD_PLUGIN=OFF \
  -DSPATIAL_BUILD_TESTS=ON
cmake --build build/spatial-core
ctest --test-dir build/spatial-core --output-on-failure
```

## Hyprland plugin build

The plugin is deliberately version-bound to the installed Hyprland development headers. Hyprland's plugin API passes C++ objects across the boundary and does not guarantee ABI compatibility.

Build only on a system whose development packages match the running compositor:

```bash
pkg-config --modversion hyprland
hyprctl version

cmake -S spatial/core -B build/spatial-plugin \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSPATIAL_BUILD_PLUGIN=ON \
  -DSPATIAL_BUILD_TESTS=ON

cmake --build build/spatial-plugin --parallel
ctest --test-dir build/spatial-plugin --output-on-failure
```

The resulting shared object is:

```text
build/spatial-plugin/gendbyte-spatial.so
```

For Phase 1 development, do not install or autoload it system-wide. Test with an absolute path in a disposable/nested Hyprland session:

```bash
hyprctl plugin load /absolute/path/to/gendbyte-spatial.so
hyprctl plugin list
hyprctl plugin unload /absolute/path/to/gendbyte-spatial.so
```

The plugin performs an additional server/client build-hash comparison during `PLUGIN_INIT` and refuses to initialize when the hashes differ.

Current lifecycle scope is intentionally minimal:

- no function hooks;
- no event hooks yet;
- no background thread;
- no daemon;
- no persistent state;
- no window projection;
- no automatic installer integration.
