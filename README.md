# Monero Node Setup for Debian 13

Interactive setup script for deploying Monero nodes on Debian 13, supporting both personal use and mining pool backends.

## ⚠️ CRITICAL: Storage Requirements

> **DO NOT SKIMP ON DISK SPACE.** The Monero blockchain is **~230GB** as of Dec 2024 and grows **~20GB/year**.
> Expanding VMs after the fact is painful. Provision correctly the first time.

| Mode | Blockchain Size | **YOU NEED** | Why |
|------|-----------------|--------------|-----|
| **Full Node** | ~230GB | **400GB minimum** | Gives 8+ years headroom |
| **Pruned Node** | ~95GB | **150GB minimum** | Gives 5+ years headroom |

**If in doubt: 500GB for full, 200GB for pruned.** Storage is cheap. Your time is not.

## Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 4GB | 8GB |
| **Disk (Full)** | **400GB SSD** | **500GB NVMe** |
| **Disk (Pruned)** | **150GB SSD** | **200GB NVMe** |
| CPU | 2 cores | 4 cores |
| OS | Debian 13 (Trixie) | |

> ⚠️ **SSD is required.** HDD sync takes weeks and performs poorly for pools.
>
> ⚠️ **Do not provision less than the minimum.** Expanding VMs mid-sync is painful.

## Quick Start

### One-Liner Install

```bash
sudo apt update && sudo apt install -y git curl jq && rm -rf /tmp/monero-setup && git clone https://github.com/wattfource/monero-node-installer.git /tmp/monero-setup && cd /tmp/monero-setup && chmod +x setup-monero.sh && sudo ./setup-monero.sh
```

### Manual Install

```bash
git clone https://github.com/wattfource/monero-node-installer.git
cd monero-node-installer
sudo ./setup-monero.sh
```

## Setup Options

The interactive wizard guides you through:

| Step | Options |
|------|---------|
| **Node Type** | Standard (personal) or Mining Pool Backend |
| **Blockchain** | Full (~230GB) or Pruned (~95GB) |
| **Network** | RPC binding, firewall rules |
| **Pool Wallet** | Create new or use existing (pool mode) |

## After Installation

```bash
# Check status
sudo systemctl status monerod

# View sync progress
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
  -H 'Content-Type: application/json' | jq '.result | {height, target_height}'

# View logs
sudo journalctl -u monerod -f

# Re-run setup (update/reconfigure)
sudo ./setup-monero.sh
```

## Port Forwarding

| Port | Purpose | Forward? |
|------|---------|----------|
| **18080** | P2P network | **Yes** - required |
| 18081 | RPC | No (localhost only for pools) |
| 18082 | ZMQ | No (optional, localhost only) |

See [Firewall Guide](docs/FIREWALL.md) for router configuration.

## Uninstall

### Complete Removal (One-Liner)

Downloads a fresh uninstall script and removes **everything** installed by the setup script:

```bash
rm -rf /tmp/monero-setup && git clone https://github.com/wattfource/monero-node-installer.git /tmp/monero-setup && sudo /tmp/monero-setup/uninstall-monero.sh --force && rm -rf /tmp/monero-setup
```

### Interactive Uninstall

For more control over what gets removed:

```bash
# Download fresh and run interactively
rm -rf /tmp/monero-setup && git clone https://github.com/wattfource/monero-node-installer.git /tmp/monero-setup && sudo /tmp/monero-setup/uninstall-monero.sh
```

### Uninstall Options

```bash
# Keep blockchain data (faster reinstall)
sudo ./uninstall-monero.sh --keep-blockchain

# Keep wallet files only
sudo ./uninstall-monero.sh --keep-wallets

# Silent complete removal (no prompts)
sudo ./uninstall-monero.sh --force --quiet
```

## File Locations

| Path | Description |
|------|-------------|
| `/opt/monero/` | Binaries |
| `/var/lib/monero/` | Blockchain data |
| `/etc/monero/monerod.conf` | Configuration |
| `/var/log/monero/` | Logs |

## Documentation

| Guide | Description |
|-------|-------------|
| [VM Requirements](docs/VM-REQUIREMENTS.md) | Hardware specs, cloud instances, SSD requirements |
| [Mining Pool Setup](docs/MINING-POOL.md) | Pool-specific configuration and RPC methods |
| [Wallet Management](docs/WALLET.md) | Wallet CLI, backups, security |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Common issues and fixes |
| [Firewall Setup](docs/FIREWALL.md) | Port forwarding for different routers |
| [Lessons Learned](docs/LESSONS-LEARNED.md) | Development notes and architecture decisions |

## Resources

- [Monero Website](https://www.getmonero.org/)
- [Monero GitHub](https://github.com/monero-project/monero)

## License

MIT License
