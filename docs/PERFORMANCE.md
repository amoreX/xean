# xean performance

This describes the active cleaner's implementation, not benchmark results from BlitzClean's historical
dashboard. There is no fixed scan-time promise: traversal time depends on tree size, permissions, open-file
checks, Git commands, and disk activity.

## Work performed

| Operation | Policy |
| --- | --- |
| Optional menu bar metrics | Host CPU/memory/disk sample every two seconds; timer stops when stats are disabled |
| Background scheduler | Wakes its task every minute to see whether the fixed 25-minute check is due |
| Category expansion | Reuses a completed manual scan for up to 30 seconds; otherwise clears old rows and scans |
| Manual Clean | Scans only missing/expired selected categories, then freshly validates every deletion |
| Automatic cleanup | Fresh scan with automatic age policy, followed by another free-space measurement |
| Popover / disclosure motion | 180 ms custom transitions; Reduce Motion makes them immediate |

## Large directories

Cleaner tree traversal and project discovery have no arbitrary entry-count, depth, project-count, or
elapsed-time cutoff. Traversal is depth-first, releases completed paths, and checks cancellation.
Root symlinks are protected and nested links are not followed. Discovery prunes generated directories and
starts at configured roots, so removing scan caps does not make it an unrestricted full-disk search.

Native driver work runs in utility tasks. External Git, activity, and Docker commands still have hang
protection. An unreadable or changed target is preserved instead of using a partial scan as deletion proof.
The dropdown's 50 MB minimum reduces visible rows; it does not cap scanning or alter bulk eligibility.

## Verification

Run focused checks without touching real cleanup candidates:

```sh
swift test --no-parallel -j 2 --filter Cleaner
```

`CleanerLargeScanTests` covers trees beyond the former scan cap. Inventory and symlink suites cover
measurement and link boundaries. Model tests use fixture drivers to verify 30-second reuse, invalidation,
automatic checks, progress, partial failures, and closing the panel during cleanup. Popover and menu bar
animator tests cover presentation and anchor behavior.

For a performance change, record the Mac, OS, build mode, fixture tree size, elapsed time, and main-thread
responsiveness. Compare like-for-like disposable fixtures and run measurements sequentially to avoid disk
contention. Inherited `PerformanceBenchmarks` exercise other storage/dashboard paths; their timing limits
and historical results are not xean cleaner guarantees.
