# xean

This is the xean menu bar cleaner fork. The Swift target, bundle, and data paths retain BlitzClean
compatibility names. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the active components.

For changes to visible UI, interactions, or product copy, read [docs/DESIGN.md](docs/DESIGN.md).
Verify changed screens in the running macOS app as well as compiling them.

When you delete files on this Mac by hand, write a report to
`~/Library/Application Support/BlitzClean/reports/storage-cleanup-YYYYMMDD-HHMMSS.json` with
`{"started": {"at": <unix>}, "removed": [{"path", "allocatedBytes", "freeBefore", "freeAfter", "time"}]}`.
The shared cleanup-history tooling uses this report format. Keep the record even though xean does not
expose the inherited dashboard removal-log interface.
