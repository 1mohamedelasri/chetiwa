# Chetiwa capacity upgrade — alternative only, not authorized

**30 September 2026 owner direction: keep the current server size.** The owner
explicitly objected to scaling during release preparation. Work must focus on
code fixes and measured operation within the existing CX23 / 4 GB host and
3 GiB radar container. No resize, shutdown for resizing, or extra recurring
charge was applied. The steps below are a historical proposal, not the active
release plan or authorization to execute it.

The console still listed CX33 at €8.49/month excluding VAT on 30 September,
but marked that plan unavailable at the current location. Do not treat that
listing as an executable quote or substitute a more expensive plan.

The 19 September 2026 console quote was CX33,
4 vCPU / 8 GB RAM, €8.49/month excluding VAT, versus CX23 at €5.49/month.
The proposed CPU-and-RAM-only rescale keeps the existing 40 GB disk and permits
a later downgrade. Hetzner requires the server to be stopped for a few minutes.
No paid backups, additional disk, new server, or provider subscription is part
of this proposal.

The current radar container has a 3 GiB limit on a nominal 4 GB host. The final
audited refresh published all frames but added 931 memory-limit events and
increased swap from 54 to 866 MiB. The allocation fixes remain installed and
pixel-equivalent; they do not establish adequate production headroom.

## Memory budget

Increasing VM RAM alone does not increase Docker's radar limit. Conversely,
raising the container limit on the present host is not the proposed fix.

The current nominal 4 GB guest reports only 3.725 GiB in `/proc/meminfo`.
Measure the resized guest rather than assuming that an advertised 8 GB means
8 GiB available to Linux. Start with **5.5 GiB (`5632M`) for radar**, provided
actual `MemTotal` is at least 7.375 GiB. This leaves:

| Allocation | Budget |
| --- | --- |
| Radar container | 5,632 MiB |
| API container | 384 MiB, unchanged |
| Operating system, Docker, tunnel, monitoring and transient work | At least 1,536 MiB combined |

The host-reserve figure includes the tunnel and monitoring; it is not available
for extra application containers. Inventory any new service before applying the
budget. Do not use 6 GiB plus a separate 1.5 GiB host reserve and 384 MiB API
without at least 7.875 GiB actual host RAM.

## Proposed execution sequence — do not run

Do not begin this sequence unless the owner subsequently requests the upgrade
and approves its current recurring charge and downtime. Existing administrator
SSH access worked on 30 September without changing firewall rules; do not
restore an old audit IP merely because it appears in this historical sequence.

1. Recheck the quote and select CPU-and-RAM-only CX33. Preserve disk size,
   existing IPs, deletion protection and the decision to leave paid backups off.
   If the charge or required action differs, stop for a revised decision.
2. Stop the server gracefully, rescale, and start it. Verify the console reports
   CX33 and the public API/radar recover. Do not rebuild or replace images.
3. Temporarily restore only the approved audit source `160.179.244.112/32` for
   SSH TCP 22, retaining the existing administrator source. Check actual host
   RAM, CPU count, available disk, running containers and failed systemd units.
4. Record the live radar image ID, container limits, Compose service topology,
   `.env` memory setting and any Compose overrides. Keep a root-only backup of
   the environment/configuration and the exact running image. Do not print or
   transfer secret values. Confirm that the deployed image still contains the
   audited allocation fixes.
5. Prepare a targeted change to the existing radar memory setting only:
   `LIBREWXR_MEMORY=5632M`, retaining `LIBREWXR_MEMORY_LIMIT_MB=0` so the internal
   monitor reads the cgroup ceiling. Render and compare effective Compose
   configuration privately before restarting; only the intended memory setting
   may differ. Inspect any explicit memory-and-swap ceiling as well: it must
   not conflict with the new RAM limit. Keep the existing host safety swap;
   do not disable it or change swappiness as an unmeasured workaround.
6. Recreate only `librewxr` using the existing Compose environment/overrides,
   `--no-build --pull never --no-deps`, and the exact recorded image. Keep the
   API and tunnel running. Verify Docker and kernel cgroup limits agree with
   the intended allowance and that the image ID is unchanged.
7. Check public API readiness, radar metadata and valid observed/forecast PNG
   tiles. Then capture a baseline after startup and compare within-container
   memory-event, swap and PSI deltas through a complete radar publication,
   an hourly IFS model refresh, and representative concurrent reads. Require
   all four past and six future frames and a settling interval. Do not infer
   memory improvement merely from reset counters after a restart.
8. If service recovery fails, restore the backed-up memory configuration and
   exact image using the existing Compose topology, then verify public health.
   The larger VM can remain temporarily; downgrading is a separate controlled
   outage and must not happen while the larger container limit is configured.
9. Remove the temporary SSH source after verification and confirm the firewall
   is fully applied. Record the actual capacity results in the production audit.

Do not run `deploy-production-profile.sh` as the resize procedure: it replaces
the complete `.env` with `hetzner-small.env`, reinstates the 3 GiB limit, rebuilds
images and performs unrelated service work. After a successful capacity change,
version the measured new profile and its host-RAM guard before the next full
profile deployment. The current small profile remains the pre-upgrade template.

## Release decision

The upgrade is a capacity hypothesis supported by measured pressure, not a
guarantee of a particular number of users. An unchanged cap-event count with
clear RAM reserve, no sustained swap I/O/PSI, timely fresh frames and acceptable
API/tile latency would support the next controlled traffic test. If pressure
persists, investigate the measured resident working set before raising limits
again. Provider rights, push delivery, signed-device tests and recovery readiness
remain separate public-launch gates.

Evidence: [production audit](../release/production-audit-2026-09-19.md),
[memory measurements](../../tmp/production-audit/server-memory.md), and
[capacity/observability commands](librewxr-capacity-and-observability.md).
