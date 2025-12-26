# Mining Pool Configuration

Guide for setting up a Monero node as a mining pool backend.

## Overview

When you select **Mining Pool Backend** during setup, the script configures:

- `rpc-bind-ip=127.0.0.1` - RPC on localhost only (secure)
- `restricted-rpc=0` - Full RPC access for pool software
- `out-peers=64` / `in-peers=128` - Higher connection limits
- ZMQ notifications (optional) - Instant block updates

## Pool Software Connection

```
RPC Endpoint:  http://127.0.0.1:18081/json_rpc
ZMQ Endpoint:  tcp://127.0.0.1:18082 (if enabled)
```

Test RPC connection:

```bash
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
  -H 'Content-Type: application/json' | jq
```

## Block Notification Methods

### Option 1: RPC Polling (Recommended)

Most compatible method. Pool software polls for new blocks:

```bash
# Poll every 1-2 seconds
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_last_block_header"}' \
  -H 'Content-Type: application/json'
```

No additional configuration needed.

### Option 2: ZMQ Notifications

Instant push notifications. If enabled during setup:

```
ZMQ Publisher: tcp://127.0.0.1:18082
```

If ZMQ causes problems, disable it:

```bash
sudo sed -i 's/^zmq-pub=/#zmq-pub=/' /etc/monero/monerod.conf
sudo systemctl restart monerod
```

## Key RPC Methods

| Method | Description |
|--------|-------------|
| `get_block_template` | Get work for miners |
| `submit_block` | Submit found blocks |
| `get_last_block_header` | Check for new blocks |
| `get_info` | Node sync status |
| `get_block` | Get block by hash/height |
| `get_block_header_by_height` | Get header by height |

## Test Commands

```bash
# Check node sync status
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
  -H 'Content-Type: application/json' | jq '.result | {height, target_height, status}'

# Get block template for mining (requires wallet address)
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_block_template","params":{"wallet_address":"YOUR_WALLET_ADDRESS","reserve_size":8}}' \
  -H 'Content-Type: application/json' | jq

# Get last block header
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_last_block_header"}' \
  -H 'Content-Type: application/json' | jq

# Get current height
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_block_count"}' \
  -H 'Content-Type: application/json' | jq
```

## Pool Wallet

View wallet configuration:

```bash
sudo cat /etc/monero/pool-wallet.conf
```

See [Wallet Management](WALLET.md) for wallet operations.

## Example Configuration

```ini
# /etc/monero/monerod.conf (Mining Pool Mode)

data-dir=/var/lib/monero
log-file=/var/log/monero/monerod.log
log-level=0

# Network
p2p-bind-ip=0.0.0.0
p2p-bind-port=18080
out-peers=64
in-peers=128
limit-rate-up=2048
limit-rate-down=8192

# RPC (localhost only, unrestricted for pool)
rpc-bind-ip=127.0.0.1
rpc-bind-port=18081
confirm-external-bind=1
restricted-rpc=0

# ZMQ (optional)
# zmq-pub=tcp://127.0.0.1:18082

# Performance
db-sync-mode=safe
max-concurrency=4

# Blockchain mode
prune-blockchain=0
```

## Recommended Pool Software

- **[monero-stratum](https://github.com/sammy007/monero-stratum)** - Go-based stratum server
- **[nodejs-pool](https://github.com/Snipa22/nodejs-pool)** - Full Node.js pool solution
- **[pool.cryptonote.social](https://github.com/cryptonote-social/csmining-pool)** - Simple pool implementation

## Multi-Coin Architecture

```
┌─────────────────────────────────────┐
│       Pool Frontend + Database      │
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

Each coin needs its own node and stratum server.

## Algorithm Info

- **Algorithm:** RandomX (CPU-friendly)
- **Block Time:** ~2 minutes
- **ASIC Resistance:** Yes (designed for CPU mining)

## Failover Configuration

For high availability, configure your stratum server with multiple nodes:

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

## Troubleshooting

### Node not synced

Pool won't work until fully synced:

```bash
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
  -H 'Content-Type: application/json' | jq '.result | {height, target_height, synchronized: (.height == .target_height)}'
```

### RPC connection refused

1. Check service is running: `sudo systemctl status monerod`
2. Check config: `grep rpc /etc/monero/monerod.conf`
3. Check port: `sudo ss -tlnp | grep 18081`

### get_block_template fails

Ensure node is fully synced and you're providing a valid wallet address:

```bash
# Get your pool wallet address
sudo grep WALLET_ADDRESS /etc/monero/pool-wallet.conf
```

