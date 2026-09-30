# Coordinate grid memory fix

`chetiwa-float32-coordinate-grids.patch` replaces three int64-grid-then-float32
allocations with directly allocated float32 grids. It preserves shapes, ordering,
coordinate values, forecast steps and wrapped-map behavior. It does not change
the radar region selection, resolution, refresh interval or forecast duration.

`chetiwa-sparse-coordinate-grids.patch` is its successor. It retains float32
coordinate axes as `(height, 1)` and `(1, width)` views, which broadcast against
dense flow into the same dense remap arrays. The production NumPy/OpenCV versions
produced identical native remap output in 1536 representative cases, including
wrapped, cached, clamped, upscaled and non-C-contiguous flow. Internal map strides
can differ for Fortran-order flow; native output equivalence was verified.

`chetiwa-chunked-nowcast-remap.patch` then bounds inverse-map workspaces to 512
destination rows. Every remap still reads the complete source frame, preserving
cross-row interpolation and wrap behavior; output is cropped only after all rows
are assembled. Full-resolution flow, clamping, source pixels and forecast count
remain unchanged. Native validation passed 5760 byte-identical output cases,
including dense cached grids and nonmultiple chunk boundaries, with 257472
checks confirming OpenCV wrote the provided destination slice.

Deploy only this change to the existing single-service Hetzner installation:

```sh
bash deploy/librewxr/deploy-float32-coordinate-grids.sh root@116.203.124.254
```

After that baseline is installed, deploy the sparse successor with the same
rollback controller:

```sh
bash deploy/librewxr/deploy-sparse-coordinate-grids.sh root@116.203.124.254
```

After sparse axes are installed, deploy bounded row remapping:

```sh
bash deploy/librewxr/deploy-chunked-nowcast-remap.sh root@116.203.124.254
```

Each deployment backs up the exact source and image currently running, so the
sparse rollout restores the working float32 version if it fails, and chunked
remapping restores the working sparse version. The controller only accepts these
three versioned patches. Each command recognizes its installed successors and
skips without rebuilding or restarting.

The script verifies the active Compose image and the equality of host source,
image source and installed package before applying the patch. The existing
Compose environment and automatic override file are preserved. A deployment lock
prevents simultaneous runs of this script. An already applied patch in both
source and running image exits without a build or restart.

Before building, the script preserves the source mode/ownership/timestamp with
`cp -p` and tags the exact image ID used by the running container. It builds a
small overlay of that local image containing only the patched source and installed
Python module. There is no dependency installation, base-image update, cache
pruning or volume cleanup. The build uses `--pull=false --network=none`.

Only `librewxr` is recreated, with `--no-build --pull never --no-deps`. Local
weather-map health must include at least one past radar frame, the container must
use the candidate image ID, and its installed module hash must match the patched
source. Failure or HUP/INT/TERM triggers one EXIT rollback restoring the source,
retagging the original image, and recreating only radar when restart was attempted.
The rollback checks the restored image ID and radar-frame health.

Backups are retained beside the source checkout under
`librewxr-coordinate-backups/<release-id>/`, and the original image remains tagged
as `chetiwa-librewxr-coordinate-rollback:<release-id>`. Keep these until the change
has been observed over complete ingestion/nowcast cycles. This deployment does
not measure production memory improvement automatically.

The full `deploy-production-profile.sh` applies float32, sparse, then chunked
remapping, and reverses this order before older patches. Use the targeted scripts for this
targeted update; the full profile script performs additional profile/service work.

Controller regression tests (no network or live Docker):

```sh
python3 deploy/librewxr/test-coordinate-deploy.py
```

Twenty-seven fixture tests cover all three patches with real application, mode-preserving backups, success,
idempotence, failed builds, failed health, partially failed restarts, signal
handling, source/image mismatch, and concurrent-run rejection. Numerical and
full-module compile validation is recorded separately in the production audit.
