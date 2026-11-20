# Lab 05 — Storage: filesystems, inodes, mounts and block I/O

## Theory

- A block device exposes logical sectors; a partition is a region of a block device. A filesystem structures data into blocks/extents and metadata. A mounted filesystem appears at a mountpoint in a mount namespace.
- `df` reports filesystem-wide allocated/available blocks and inodes. `du` walks directory entries and sums visible file usage; it can disagree with `df` because of deleted-open files, sparse files, hard links, reserved blocks, snapshots, and mount boundaries.
- Inodes represent filesystem objects and metadata; file content is stored separately. A filesystem can run out of inodes while free bytes remain, or run out of bytes while inodes remain. `findmnt` reports the configured filesystem type; `stat -f` may report the generic ext2/ext3 family name for an ext4 `statfs` implementation.
- A mount namespace controls which mounts a process sees. Bind mounts and container overlay layers change the view without necessarily creating a new physical disk.
- `/proc/diskstats` counters are cumulative. IOPS counts completed I/O operations; throughput measures sectors/bytes per time; completion latency is averaged over completed operations. A short idle sample cannot establish storage performance.
- LVM divides physical volumes into extents and composes volume groups/logical volumes. This lab explains the model but never runs `pvcreate`, `vgcreate`, `lvcreate`, `mkfs`, `fsck`, `mount`, or `dd`.

## Architecture

```mermaid
flowchart LR
  P[Block device] --> Q[Partition, if present]
  Q --> F[Filesystem metadata and data blocks]
  F --> M[Mountpoint in a mount namespace]
  M --> A[Processes and files]
  D[df / statfs] -. capacity and inodes .-> F
  U[du directory walk] -. visible file usage .-> M
  S[/proc/diskstats] -. block I/O counters .-> P
```

## Commands

From Windows PowerShell in the repository root:

```powershell
.\scripts\run-remote.ps1 -Phase lab-05
```

Equivalent read-only Linux commands:

```bash
lsblk -o TYPE,SIZE,ROTA,FSTYPE,MOUNTPOINTS
findmnt -T /
df -hT /
df -ih /
stat -f /
du -x -s /var/log /var/cache /tmp
cat /proc/diskstats
```

The script omits device names, serials, UUIDs and raw block counters where they could identify the host. `du` has a ten-second timeout. Source: [`scripts/lab05-storage.sh`](../../scripts/lab05-storage.sh).

## Hands-on exercises

1. Compare filesystem total/used/available bytes with inode total/used/free counts. Explain which resource could be exhausted first.
2. Compare `df` with bounded `du` for selected directories. List reasons they may not reconcile.
3. Identify mountpoint, filesystem type, mount options and read-only/read-write state. Do not remount anything.
4. Explain what `ROTA=0` reports and why it cannot prove the provider's physical-media type or latency.
5. Convert one-second diskstats counter deltas into operations/sec, MB/sec and mean completion time. With no completed operations, record latency as `NOT TESTED`.
6. Draw a PV → VG → LV → filesystem → mountpoint chain. Do not create any LVM metadata on the VPS.

## Actual runtime results

Fill after the helper has completed. Keep the committed summary free of block device names, UUIDs, mount IDs and raw counters.

| Check | Result | Limit |
|---|---|---|
| Block topology, filesystem and mount | Disk size `42,949,672,960` bytes; root filesystem ext4; `ROTA=0` | Device names, serials and UUIDs omitted. This is virtual-device metadata, not proof of physical media. |
| Root blocks and inodes | 6% block use; 3% inode use; `findmnt` says ext4 and `stat -f` returns generic ext2/ext3 family | `df`/`stat` are snapshots; no host/device identifiers committed. |
| Bounded directory usage | `/var/log` 9,724 KiB, `/var/cache` 361,412 KiB, `/tmp` 144 KiB | `du` was bounded to 10 seconds and stayed within one filesystem. |
| One-second disk I/O sample | 0 reads, 1 write, 0.025 MB/s write; fewer than 10 operations so both latency measurements `NOT TESTED` | A single write is too sparse for device performance conclusions; no synthetic I/O generated. |
| LVM tools/state | Tools detected; LVM metadata query `NOT TESTED` | No volume metadata or filesystem was changed. |

## Troubleshooting

| Symptom | Cause to investigate | Safe next step |
|---|---|---|
| `df` has free bytes but writes fail | Inode exhaustion, quota, read-only mount, permissions or reserved blocks | Check `df -i`, `findmnt`, `stat`, and service quota read-only. |
| `df` usage exceeds `du` | Deleted-open files, hidden mount contents, snapshots, reserved blocks or hard-link accounting | Inspect process descriptors and mount boundaries; do not delete files by guess. |
| `findmnt` says ext4 but `stat -f` says ext2/ext3 | The generic `statfs` type label reflects a shared filesystem magic/driver family | Use `findmnt` for the mounted filesystem type; treat `stat -f` as block/inode accounting. |
| `du` times out | Large/slow tree or storage wait | Record `NOT TESTED`; narrow the approved path or inspect `iowait`/PSI. |
| Diskstats show no operations | Device idle during the sample | Report zero measured operations and `NOT TESTED` latency; do not synthesize writes. |

## Interview questions and answers

1. **Why can `df` and `du` disagree?** They measure different layers: filesystem allocation versus files visible while walking directories. Deleted-open files, reserved blocks, snapshots and mount boundaries affect the result.
2. **What is an inode?** A filesystem object record that stores metadata and references to content blocks; it is a separate capacity dimension from bytes.
3. **Does `ROTA=0` prove NVMe storage?** No. It is a kernel topology hint about rotational behavior; virtualized providers can abstract the physical device.
4. **What does mounting do?** It attaches a filesystem tree at a mountpoint within a mount namespace; it does not itself prove a new disk was provisioned.
5. **What are LVM extents?** Fixed-size allocation units used to map logical volumes onto physical-volume space inside a volume group.
6. **Can a one-second idle sample prove high IOPS?** No. It only describes that interval; fewer than ten operations is treated as insufficient to report mean latency, and capability requires a planned benchmark on an appropriate disposable device.

## Verification and cleanup

Verification is the live read-only output plus remote `bash -n` and helper cleanup. This lab performs no mount, unmount, write, format, partition, filesystem repair or LVM operation, so there is no disk state to rollback. Any future write benchmark requires a disposable target, explicit size/duration bounds, backup and separate approval.
