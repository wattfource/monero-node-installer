# Lessons Learned: Building the Monero Node Installer

This document captures the lessons learned while building the Monero node installer for Debian 13, designed specifically for mining pool usage.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Technical Lessons](#technical-lessons)
3. [Script Design Patterns](#script-design-patterns)
4. [Troubleshooting Discoveries](#troubleshooting-discoveries)
5. [Resource Management](#resource-management)
6. [Documentation Best Practices](#documentation-best-practices)
7. [Mining Pool Architecture](#mining-pool-architecture)
8. [Future Considerations](#future-considerations)

---

## Project Overview

### Goal
Build an interactive setup script for deploying Monero nodes on Debian 13 VMs running in Unraid, with specific optimization for mining pool backend usage.

### Key Requirements
- Interactive wizard-style installation
- Support for both standard (personal) and mining pool backend nodes
- Full and pruned blockchain options
- Automatic systemd service configuration
- Pool wallet creation during setup
- Self-updating script mechanism
- Clean uninstall capability

---

## Technical Lessons

### 0. STORAGE REQUIREMENTS - THE MOST IMPORTANT LESSON

> **THIS IS THE SINGLE MOST CRITICAL LESSON IN THIS DOCUMENT.**

**What happened:** We initially documented storage requirements as "220GB minimum, 300GB recommended" for full nodes. This was **catastrophically wrong**. The actual blockchain is ~230GB (Dec 2024), meaning 220GB minimum was already impossible, and 300GB gave only ~3 years of headroom.

**The consequences:**
- VM created with insufficient storage
- Discovered the error mid-sync after hours of downloading
- Had to expand VM disk (which is a painful process)
- Wasted significant time and effort

**The correct numbers (Dec 2024):**

| Mode | Blockchain | MINIMUM Disk | Recommended |
|------|------------|--------------|-------------|
| Full | ~230GB | **400GB** | 500GB |
| Pruned | ~95GB | **150GB** | 200GB |

**Why these numbers:**
- Blockchain: ~230GB now, grows ~20GB/year
- LMDB overhead: Can temporarily use 1.5x during compaction
- Logs/temp: ~5GB
- Growth headroom: At least 5 years (100GB)
- **400GB gives 8+ years of headroom**

**Rules for future documentation:**
1. **NEVER recommend minimum = blockchain size.** That's already too late.
2. **Always add 50% buffer PLUS 5 years of growth.**
3. **Storage is cheap. Developer time is not.**
4. **If someone asks "is X enough?", the answer is "go bigger."**
5. **Update these numbers every 6 months** - blockchain size changes.

**Calculation formula:**
```
Recommended = (Current Blockchain × 1.5) + (Years of headroom × Growth rate)

Example for Full Node:
  = (230GB × 1.5) + (8 years × 20GB/year)
  = 345GB + 160GB
  = 505GB → Round to 500GB
```

---

### 1. Monero Uses Pre-Built Binaries (Not Source Compilation)

Unlike Litecoin which requires compiling from source with Berkeley DB 4.8, Monero provides official pre-built binaries:

```
Download URL: https://downloads.getmonero.org/cli/linux64
```

**Benefits:**
- Faster installation (no compilation)
- Smaller VM requirements (no build tools needed)
- Simpler dependency list

**Verification:**
- GPG signature verification using binaryfate's key
- SHA256 hash verification against official hashes.txt

### 2. Pool Mode vs Standard Mode Configuration

**Standard Node:**
```ini
rpc-bind-ip=0.0.0.0
restricted-rpc=1          # Security: limits RPC methods
```

**Pool Backend Node:**
```ini
rpc-bind-ip=127.0.0.1     # Localhost only (pool software runs locally)
restricted-rpc=0          # Full RPC access for getblocktemplate
out-peers=64              # Higher peer limits
in-peers=128
limit-rate-up=2048        # Higher bandwidth
limit-rate-down=8192
```

**Key Insight:** Pool nodes need unrestricted RPC for `getblocktemplate` but should bind to localhost only for security.

### 3. ZMQ is Optional and Can Cause Issues

**Problem Encountered:**
```
ZMQ bind failed: Address already in use
Failed to create ZMQ/Pub listener: Unable to initialize ZMQ_XPUB socket
```

**Root Causes:**
1. Missing `libzmq5` library
2. Zombie processes holding the port
3. Library compatibility issues

**Solution:**
- Made ZMQ optional in the interactive setup (defaults to disabled)
- Added `libzmq5` to dependencies
- Pool software can use RPC polling instead of ZMQ push notifications

**Lesson:** Always make optional features truly optional with graceful fallbacks.

### 4. Wallet Creation Quirks

**Problem:** `monero-wallet-cli --command exit` doesn't work during wallet generation.

**Original (broken):**
```bash
monero-wallet-cli --generate-new-wallet ... --command exit
```

**Fixed approach:**
```bash
echo -e "${password}\n${password}\n0\n" | monero-wallet-cli --generate-new-wallet ...
# Then parse output for address and seed phrase
```

**Lesson:** Interactive CLI tools often don't support `--command` during generation flows. Use stdin piping instead.

### 5. Blockchain Storage Requirements (Updated Dec 2024)

| Mode | Blockchain Size | Disk You Need | Use Case |
|------|-----------------|---------------|----------|
| Full | ~230GB | **400GB minimum** | Block explorers, archival |
| Pruned | ~95GB | **150GB minimum** | Mining pools, most use cases |

**Insight:** Pruned nodes still validate ALL blocks - they just don't store old transaction data. This provides the same security level with ~60% less storage.

**Growth rate:** ~20GB/year for full, ~10GB/year for pruned.

> **See Lesson #0 above for detailed storage calculations. DO NOT SKIMP ON DISK SPACE.**

### 6. Port Forwarding Requirements

| Port | Service | Forward? | Notes |
|------|---------|----------|-------|
| 18080 | P2P | **YES** | Required for blockchain sync |
| 18081 | RPC | No* | Localhost only for pools |
| 18082 | ZMQ | No | Localhost only, optional |

*Only forward 18081 for remote wallet access on standard nodes.

**Lesson:** Pool backend nodes only need P2P port forwarded - RPC stays local.

---

## Monero-Specific Technical Details

### Release Verification

Monero releases are signed by **binaryfate** (official release manager). The verification process:

1. Import GPG key from keyserver
2. Download hashes.txt (GPG signed)
3. Verify signature on hashes.txt
4. Verify SHA256 of downloaded binary against hashes.txt

**Lesson:** Always verify downloads - the script automates this process.

### Monero Address Format

Monero addresses are **95 characters** and follow these patterns:

| Type | Starts With | Use Case |
|------|-------------|----------|
| Main address | `4` | Primary receiving address |
| Subaddress | `8` | Secondary addresses (same wallet) |
| Integrated | `4` (longer) | Includes payment ID |

### Wallet Components

When creating a Monero wallet, you receive several components:

| Component | Description | Security Level |
|-----------|-------------|----------------|
| **Seed phrase** | 25 words, recovers everything | CRITICAL - never share |
| **Spend key** | Required to send funds | Private - never share |
| **View key** | Can see incoming transactions | Semi-private - can share for auditing |
| **Address** | Receive funds | Public - safe to share |

**Lesson learned:** The view key concept is useful for pool monitoring - you can verify incoming block rewards without exposing spend capability.

### LMDB Database

Monero uses **LMDB** (Lightning Memory-Mapped Database) for blockchain storage:

- Location: `/var/lib/monero/lmdb/`
- Memory-mapped for performance
- Single-writer, multiple-reader
- Sensitive to disk I/O (explains HDD warning)

**Corruption recovery:** Remove the lmdb directory and resync from network.

### Monero JSON-RPC Format

Monero uses JSON-RPC 2.0 on port 18081. Key methods for pools:

| Method | Purpose |
|--------|---------|
| `get_block_template` | Get work for miners |
| `submit_block` | Submit found blocks |
| `get_last_block_header` | Check for new blocks |
| `get_info` | Node sync status |

### Monero Config File Format

Monero uses a simple `key=value` format with **dashes** (not underscores):

```ini
# Correct
rpc-bind-ip=127.0.0.1
p2p-bind-port=18080

# Wrong (won't work)
rpc_bind_ip=127.0.0.1
```

**Lesson:** Use dashes in config keys, not underscores. This differs from some other crypto configs.

### Release Naming Convention

Monero releases use element + scientist names:
- Current: **Fluorine Fermi** (v0.18.x)

This appears in daemon logs and helps identify versions quickly.

### RandomX Algorithm

Monero's mining algorithm **RandomX** is specifically designed to be:

- **CPU-optimized** - Favors general-purpose CPUs
- **ASIC-resistant** - Difficult to build specialized hardware
- **Memory-hard** - Requires significant RAM per mining thread

**Implications for pools:**
- Attracts CPU miners (not ASIC farms)
- More decentralized mining base
- Lower barrier to entry for miners

### Block Reward Structure

| Property | Value |
|----------|-------|
| Block time | ~2 minutes |
| Emission | Tail emission after main curve |
| Halving | None (smooth curve) |

**For pool operators:** Predictable rewards without sudden halvings to plan for.

---

## Script Design Patterns

### 1. Interactive Wizard with Boxed Options

```bash
┌─────────────────────────────────────────────────────────────────────┐
│  [1] STANDARD NODE                                                  │
│                                                                     │
│      • For personal wallet use                                      │
│      • Allows remote wallet connections                             │
└─────────────────────────────────────────────────────────────────────┘
```

**Lesson:** Clear visual separation of options prevents user confusion. Always show option numbers prominently.

### 2. Self-Update Mechanism

```bash
# Check remote VERSION file
remote_version=$(curl -fsSL "$VERSION_URL" 2>/dev/null)

if [[ "$remote_version" != "$SCRIPT_VERSION" ]]; then
    # Offer to download and replace
fi
```

**Lesson:** Keep a VERSION file in the repo for easy comparison. The script should check this at startup.

### 3. One-Liner Install Pattern

**Best approach (git clone):**
```bash
rm -rf /tmp/monero-setup && git clone REPO /tmp/monero-setup && cd /tmp/monero-setup && sudo ./setup-monero.sh
```

**Why git clone > curl:**
- `rm -rf` ensures fresh download every time
- Gets ALL files (setup, uninstall, docs)
- Consistent with professional installers

### 4. Robust Error Handling

**Don't use `set -e` in complex scripts:**
```bash
# Don't use set -e - we handle errors explicitly for better cleanup
# set -e
```

**Why:** `set -e` exits immediately on any error, which can leave systems in broken states during cleanup operations.

### 5. Uninstall Script Best Practices

Learned from comparing with Litecoin installer:

| Feature | Why It Matters |
|---------|----------------|
| Multiple stop methods | systemd → SIGTERM → SIGKILL → by-user |
| Detailed detection | Show user what will be removed |
| Verification step | Confirm everything was actually removed |
| Home directory cleanup | Remove ~/.monero configs |
| PID file cleanup | Prevent stale processes |

---

## Troubleshooting Discoveries

### 1. HDD Warning

```
The blockchain is on a rotating drive: this will be very slow, use an SSD if possible
```

**Impact:** HDD sync can take 1-2 weeks vs 1-3 days on SSD.

**Lesson:** Document this prominently - users on HDDs should expect slow sync.

### 2. Peer Connection Issues

**Diagnosis:**
```bash
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_connections"}' \
  -H 'Content-Type: application/json' | jq '.result.connections | length'
```

- < 8 peers: Port forwarding likely broken
- 8+ peers: Good
- 50+ peers: Excellent

### 3. Service Restart Loops

**Symptom:** `systemctl status` shows rapid restart cycling.

**Common causes:**
1. Port already in use (ZMQ issue)
2. Permission problems on data directory
3. Corrupted database

**Debug command:**
```bash
sudo journalctl -u monerod -n 100
```

### 4. Commands Not Found

**Problem:** `netstat` not available on minimal Debian.

**Solution:** Use `ss` instead:
```bash
sudo ss -tlnp | grep 18081
```

---

## Resource Management

### During Sync vs After Sync

| Resource | During Sync | After Sync |
|----------|-------------|------------|
| CPU | High (80-100%) | Low (5-15%) |
| RAM | 4-6GB | 1-2GB |
| Disk I/O | Very high | Low |
| Bandwidth | High (downloading) | Moderate (P2P) |

### VM Resource Recommendations

**During initial sync:**
- 4+ CPU cores
- 8GB RAM
- SSD storage

**After sync (can reduce):**
- 2 CPU cores sufficient
- 4GB RAM (2GB minimum)
- Can use HDD (but SSD preferred)

**Lesson:** Users can start with higher resources, then reduce after sync completes.

### Auto-Start Behavior

The systemd service is configured with:
```ini
[Install]
WantedBy=multi-user.target
```

**Behavior:**
- Node starts automatically on VM boot
- Resumes from where it left off
- No manual intervention needed

---

## Documentation Best Practices

### 1. README Structure

**Keep README minimal:**
- Requirements table
- One-liner install
- Basic usage commands
- Link to detailed docs

**Move details to docs/ folder:**
- `WALLET.md` - Wallet management
- `TROUBLESHOOTING.md` - Common issues
- `FIREWALL.md` - Port forwarding guides
- `MINING-POOL.md` - Pool-specific config

### 2. Litecoin as Reference

The Litecoin node installer served as an excellent reference:
- Similar structure and patterns
- Consistent user experience across crypto installers
- Reusable documentation templates

### 3. Include Uninstall Instructions

Always provide:
1. Interactive uninstall script with options
2. One-liner for complete removal
3. Options to preserve blockchain/wallets

---

## Mining Pool Architecture

### Multi-Coin Pool Structure

```
┌─────────────────────────────────────┐
│       Pool Frontend (Astro/Next)    │
│       + Database (PostgreSQL)       │
└──────────────────┬──────────────────┘
                   │
     ┌─────────────┼─────────────┐
     ▼             ▼             ▼
┌─────────┐  ┌─────────┐  ┌─────────┐
│   XMR   │  │   LTC   │  │   BTC   │
│ Stratum │  │ Stratum │  │ Stratum │
│ + Node  │  │ + Node  │  │ + Node  │
└─────────┘  └─────────┘  └─────────┘
```

**Key Insight:** Each cryptocurrency needs its own:
- Full node
- Stratum server (pool software)
- Wallet for receiving rewards

### Monero-Specific Pool Requirements

- **Algorithm:** RandomX (CPU-friendly, ASIC-resistant)
- **Block time:** ~2 minutes
- **RPC Method:** `get_block_template` (requires unrestricted RPC)
- **Block notifications:** RPC polling or ZMQ

### Failover Node Architecture

```json
{
  "daemon": {
    "host": "127.0.0.1",
    "port": 18081
  },
  "daemon_failover": [
    {"host": "backup1.example.com", "port": 18081},
    {"host": "backup2.example.com", "port": 18081}
  ]
}
```

**Lesson:** Multiple nodes in different data centers provide redundancy. Miners experience brief reconnection if primary fails, but no funds are lost.

### Recommended Pool Software for Monero

- **monero-stratum** - Go-based, lightweight
- **nodejs-pool** - Full-featured Node.js solution
- **cryptonote-social** - Simple implementation

---

## Future Considerations

### 1. Pool Wallet Management

The pool wallet created during setup:
- Receives block rewards
- Holds pool fee percentage
- Sends miner payouts

**Security consideration:** Consider periodic transfers to cold wallet for larger operations.

### 2. Pool Fee Strategy

| Fee | Pros | Cons |
|-----|------|------|
| 0% | Attracts miners initially | No revenue |
| 0.5% | Competitive, some revenue | Lower than average |
| 1% | Industry standard | May deter price-sensitive miners |

**Recommendation:** Start at 0% to build hashrate, increase to 0.5-1% after establishing reputation.

### 3. Renewable Energy Branding

The solar-powered pool concept ("Lightspeed Pool", "Wattfource Pool") is a strong differentiator:
- Appeals to environmentally-conscious miners
- Unique selling proposition vs generic pools
- Can leverage existing solar infrastructure credentials

### 4. Repository Structure

For the full mining pool project:

```
wattfource/
├── monero-node-installer/     # This repo
├── litecoin-node-installer/   # Litecoin repo
├── bitcoin-node-installer/    # Future
├── zcash-node-installer/      # Future
├── pool-stratum/              # Stratum servers (or per-coin)
└── pool-frontend/             # Web frontend (Astro/Svelte)
```

### 5. Downtime Impact

**Lesson learned:** Brief internet outages (1 hour) cause:
- Miners temporarily disconnect
- No fund loss
- Miners auto-reconnect when service restored
- Pool resumes from blockchain state

No catastrophic failures - just temporary unavailability.

---

## Summary

Building this Monero node installer taught us:

1. **Simplicity wins** - Pre-built binaries > source compilation
2. **Make features optional** - ZMQ issues led to making it opt-in
3. **Test edge cases** - Wallet creation, service restarts, port conflicts
4. **Document thoroughly** - Split README into focused doc files
5. **Plan for uninstall** - Clean removal is as important as installation
6. **Consider the full stack** - Node is just one piece of pool infrastructure
7. **Resource flexibility** - High during sync, reducible after

This foundation will serve the larger mining pool project well.

---

*Document created: December 2024*
*Project: Monero Node Installer for Mining Pool Backend*
*Repository: github.com/wattfource/monero-node-installer*

