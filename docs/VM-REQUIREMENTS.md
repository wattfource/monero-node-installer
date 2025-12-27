# VM Requirements & Specifications

Detailed hardware requirements for running a Monero node.

## Quick Reference

| Resource | Minimum | Recommended | Long-term (5+ years) |
|----------|---------|-------------|----------------------|
| RAM | 4GB | 8GB | 8GB |
| Disk (Full) | 280GB SSD | 400GB NVMe/SSD | 500GB NVMe/SSD |
| Disk (Pruned) | 120GB SSD | 150GB NVMe/SSD | 200GB NVMe/SSD |
| CPU | 2 cores | 4 cores | 4 cores |
| Network | 100Mbps | 1Gbps | 1Gbps |
| OS | Debian 13 (Trixie) | | |

## Storage Requirements (Updated Dec 2024)

| Component | Full Node | Pruned Node |
|-----------|-----------|-------------|
| Blockchain | ~230GB | ~95GB |
| LMDB Overhead | ~20-40GB | ~10-20GB |
| Binaries + Logs | ~5GB | ~5GB |
| **Current Total** | **~260GB** | **~110GB** |
| **Recommended** | **400GB+** | **150GB+** |

### Growth Projections

| Timeframe | Full Node | Pruned Node |
|-----------|-----------|-------------|
| Now (Dec 2024) | ~230GB | ~95GB |
| +1 year | ~250GB | ~105GB |
| +2 years | ~270GB | ~115GB |
| +3 years | ~290GB | ~125GB |
| +5 years | ~330GB | ~145GB |

> **Growth Rate**: ~19-20GB per year for full nodes, ~10GB for pruned.
>
> The Monero blockchain grows steadily due to ring signatures and privacy features.

## Why SSD is Required for Mining Pools

Mining pool nodes have specific I/O requirements:

- **Fast Block Verification** - Pool must verify new blocks instantly
- **RPC Response Time** - Pool software expects <100ms response from get_block_template
- **Random Reads** - Block verification requires random database access
- **Database Cache** - Frequent reads/writes to LMDB database

| Storage Type | Performance | Suitable for Pool? |
|--------------|-------------|-------------------|
| HDD | ~100 IOPS | No - too slow |
| SSD | ~10,000+ IOPS | Yes |
| NVMe | ~100,000+ IOPS | Ideal |

> **Warning**: Running monerod on a spinning HDD will result in extremely slow sync times (weeks instead of days) and poor RPC performance.

## Initial Sync Time Estimates

| Connection | Full Node (~230GB) | Pruned Node (~95GB) |
|------------|-----------|-------------|
| 100 Mbps + SSD | 24-72 hours | 12-24 hours |
| 1 Gbps + NVMe | 12-24 hours | 6-12 hours |
| 100 Mbps + HDD | 1-3 weeks | 3-7 days |

> Monero sync is I/O bound, not bandwidth bound. SSD makes a massive difference.

## Storage Planning Guide

**How long will my storage last?**

```
Years of headroom = (Your Storage - Current Blockchain) / 20GB per year

Examples:
- 300GB: (300 - 230) / 20 = 3.5 years ⚠️
- 400GB: (400 - 230) / 20 = 8.5 years ✅
- 500GB: (500 - 230) / 20 = 13.5 years ✅
```

**Recommendation by deployment type:**

| Deployment | Recommended | Rationale |
|------------|-------------|-----------|
| Testing/Learning | 300GB | Adequate, can expand later |
| Personal Node | 400GB | 8+ years, good balance |
| Mining Pool | 400-500GB | Critical uptime, don't risk running low |
| Set-and-forget | 500GB | Maximum peace of mind |

> **Tip**: If using cloud providers with easy resize (Hetzner, Vultr, etc.), start with 300GB and expand when needed. For self-hosted VMs where resizing is painful, provision 400GB+ upfront.

## Memory Usage

During operation:
- Base daemon: ~300MB
- Database cache: 1-4GB (auto-managed)
- Peer connections: ~50MB
- Transaction pool: ~100-300MB
- **Total typical: 1-2GB (pruned) / 2-4GB (full)**

During initial sync, memory usage can spike to 4-6GB. If you have less than 4GB RAM, add swap:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
# Make permanent:
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Cloud Provider Instances

| Provider | Instance | vCPUs | RAM | Est. Monthly |
|----------|----------|-------|-----|--------------|
| Hetzner | CPX31 | 4 | 8GB | ~$15-20 |
| Hetzner | CPX41 | 8 | 16GB | ~$30-40 |
| OVH | B2-30 | 4 | 8GB | ~$40-50 |
| Vultr | High Freq 4 | 4 | 8GB | ~$60-80 |
| DigitalOcean | s-4vcpu-8gb | 4 | 8GB | ~$80-100 |
| AWS | t3.xlarge | 4 | 16GB | ~$120-150 |

> Best value: Hetzner for European locations, offers excellent price/performance.

## Self-Hosted VM (Proxmox/VMware)

```
VM Configuration (Full Node):
├── CPU: 4 cores (host passthrough recommended)
├── RAM: 8192 MB
├── Disk: 400GB (virtio-scsi, SSD backend)
├── Network: virtio, bridged
└── BIOS: UEFI or SeaBIOS

VM Configuration (Pruned Node):
├── CPU: 2-4 cores
├── RAM: 4096-8192 MB
├── Disk: 150GB (virtio-scsi, SSD backend)
├── Network: virtio, bridged
└── BIOS: UEFI or SeaBIOS
```

**Proxmox CLI example (Full Node - Recommended):**

```bash
qm create 100 \
  --name monero-node \
  --cores 4 \
  --memory 8192 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:400,ssd=1 \
  --boot c --bootdisk scsi0
```

**Proxmox CLI example (Pruned Node - Minimal):**

```bash
qm create 101 \
  --name monero-node-pruned \
  --cores 2 \
  --memory 4096 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:150,ssd=1 \
  --boot c --bootdisk scsi0
```

## Network Requirements

| Traffic | Bandwidth |
|---------|-----------|
| P2P Sync (initial) | 10-100 Mbps |
| P2P Steady State | 1-5 Mbps |
| RPC (Pool) | 1-10 Mbps |

**Required Ports:**
- `18080/tcp` - P2P (forward this for better connectivity)
- `18081/tcp` - RPC (localhost only for pools)
- `18082/tcp` - ZMQ (localhost only, if enabled)
- `22/tcp` - SSH (restrict to your IP)

## Static IP Recommendation

For stable P2P connections, use a static IP:

**Option A: Static IP on VM**

```bash
# /etc/network/interfaces
auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 1.1.1.1 8.8.8.8
```

**Option B: DHCP Reservation**

Create a DHCP reservation on your router for the VM's MAC address.

## Monero-Specific Considerations

### RandomX Memory Requirements

If you plan to solo mine on the same node, be aware that RandomX mining requires an additional **2.5GB of RAM** for the RandomX dataset. This is separate from the node requirements.

### Privacy Considerations

For maximum privacy:
- Consider running monerod over Tor (see User Guides on getmonero.org)
- Use a VPN if your ISP monitors or blocks cryptocurrency traffic
- Disable incoming RPC connections if not needed

### LMDB Database

Monero uses LMDB (Lightning Memory-mapped Database):
- Very fast but requires adequate RAM
- Performs poorly on HDD due to random read patterns
- Database size is ~equal to blockchain size

