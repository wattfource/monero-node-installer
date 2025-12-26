# VM Requirements & Specifications

Detailed hardware requirements for running a Monero node.

## Quick Reference

| Resource | Minimum | Recommended (Mining Pool) |
|----------|---------|---------------------------|
| RAM | 4GB | 8GB |
| Disk (Full) | 220GB SSD | 300GB NVMe/SSD |
| Disk (Pruned) | 80GB SSD | 120GB NVMe/SSD |
| CPU | 2 cores | 4 cores |
| Network | 100Mbps | 1Gbps |
| OS | Debian 13 (Trixie) | |

## Storage Requirements

| Component | Size |
|-----------|------|
| Full Blockchain | ~180GB |
| Pruned Blockchain | ~65GB |
| Build/Binaries | ~500MB |
| Logs + Overhead | ~5GB |
| **Total (Full Node)** | **~200GB** |
| **Total (Pruned)** | **~75GB** |
| **Recommended** | **250GB+ (Full) / 120GB+ (Pruned)** |

> The Monero blockchain grows ~20-30GB per year due to privacy features.

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

| Connection | Full Node | Pruned Node |
|------------|-----------|-------------|
| 100 Mbps + SSD | 24-72 hours | 12-24 hours |
| 1 Gbps + NVMe | 12-24 hours | 6-12 hours |
| 100 Mbps + HDD | 1-3 weeks | 3-7 days |

> Monero sync is I/O bound, not bandwidth bound. SSD makes a massive difference.

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
VM Configuration:
├── CPU: 4 cores (host passthrough recommended)
├── RAM: 8192 MB
├── Disk: 250GB (virtio-scsi, SSD backend)
├── Network: virtio, bridged
└── BIOS: UEFI or SeaBIOS
```

**Proxmox CLI example:**

```bash
qm create 100 \
  --name monero-node \
  --cores 4 \
  --memory 8192 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:250,ssd=1 \
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

