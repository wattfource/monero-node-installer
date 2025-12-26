# Troubleshooting Guide

Common issues and solutions for the Monero node setup.

## Quick Diagnostics

Run these commands to check your node's health:

```bash
# Is the service running?
sudo systemctl status monerod

# Check recent logs
sudo journalctl -u monerod -n 50

# Check sync progress
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
  -H 'Content-Type: application/json' | jq '.result | {height, target_height, status}'

# Check peer connections
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_connections"}' \
  -H 'Content-Type: application/json' | jq '.result.connections | length'
```

## Common Issues

### Node Won't Start

**Symptom:** Service fails to start or keeps restarting

**Check logs:**
```bash
sudo journalctl -u monerod -n 100
```

**Common causes:**

1. **Port already in use:**
   ```bash
   sudo ss -tlnp | grep -E "18080|18081|18082"
   # Kill any rogue processes
   sudo pkill -9 monerod
   sudo systemctl start monerod
   ```

2. **Permission issues:**
   ```bash
   sudo chown -R monero:monero /var/lib/monero
   sudo chown -R monero:monero /var/log/monero
   sudo chmod 700 /var/lib/monero
   ```

3. **Disk full:**
   ```bash
   df -h /var/lib/monero
   # Need ~180GB for full node, ~65GB for pruned
   ```

4. **Corrupted database:**
   ```bash
   sudo systemctl stop monerod
   # Remove database (will re-sync from scratch!)
   sudo rm -rf /var/lib/monero/lmdb
   sudo systemctl start monerod
   ```

### ZMQ Errors

**Symptom:** `ZMQ bind failed: Address already in use` or `Failed to initialize zmq_pub`

**Solution - Disable ZMQ:**
```bash
# Comment out ZMQ in config
sudo sed -i 's/^zmq-pub=/#zmq-pub=/' /etc/monero/monerod.conf
sudo systemctl restart monerod
```

ZMQ is optional - pool software will use RPC polling instead.

**Solution - Fix ZMQ:**
```bash
# Install ZMQ library
sudo apt install -y libzmq5

# Kill any zombie processes
sudo pkill -9 monerod
sudo fuser -k 18082/tcp 2>/dev/null

# Restart
sudo systemctl restart monerod
```

### Sync is Extremely Slow

**Symptom:** Syncing at < 100 blocks/second

**Causes and solutions:**

1. **Spinning HDD (not SSD):**
   - The warning "blockchain is on a rotating drive" means you're using an HDD
   - SSDs are 10-50x faster for blockchain sync
   - If stuck with HDD, be patient (may take 1-2 weeks)

2. **Low peer connections:**
   ```bash
   # Check peer count
   curl -s http://127.0.0.1:18081/json_rpc \
     -d '{"jsonrpc":"2.0","id":"0","method":"get_connections"}' \
     -H 'Content-Type: application/json' | jq '.result.connections | length'
   
   # Should be > 8 for good sync speed
   ```

3. **Port 18080 not accessible:**
   - Check firewall allows 18080/tcp
   - Check router forwards port 18080 to your VM

4. **Network bandwidth:**
   ```bash
   # Check bandwidth limits in config
   grep "limit-rate" /etc/monero/monerod.conf
   # Increase if needed (0 = unlimited)
   ```

### Can't Connect to RPC

**Symptom:** `Connection refused` when accessing port 18081

**Check service:**
```bash
sudo systemctl status monerod
```

**Check RPC binding:**
```bash
grep "rpc-bind" /etc/monero/monerod.conf
# Mining pool mode: 127.0.0.1 (localhost only)
# Standard mode: 0.0.0.0 (all interfaces)
```

**Check firewall:**
```bash
sudo ufw status
# For remote access, port 18081 must be allowed
```

### Node Stuck / Not Syncing

**Symptom:** Block height not increasing

**Force refresh peers:**
```bash
sudo systemctl restart monerod
```

**Check if banned:**
```bash
# Some ISPs/networks block crypto traffic
# Try using a VPN or different network
```

**Clear peer database:**
```bash
sudo systemctl stop monerod
sudo rm /var/lib/monero/p2pstate.bin
sudo systemctl start monerod
```

### Out of Disk Space

**Check space:**
```bash
df -h /var/lib/monero
```

**Switch to pruned mode:**
```bash
sudo systemctl stop monerod

# Edit config
sudo nano /etc/monero/monerod.conf
# Change: prune-blockchain=0
# To:     prune-blockchain=1

# Prune existing blockchain
sudo -u monero /opt/monero/monerod --data-dir=/var/lib/monero --prune-blockchain

# Restart
sudo systemctl start monerod
```

### High Memory Usage

**Symptom:** System becomes unresponsive during sync

Monero can use 4-8GB RAM during sync. Solutions:

1. **Add swap space:**
   ```bash
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
   ```

2. **Reduce database cache:**
   ```bash
   # Add to /etc/monero/monerod.conf
   db-sync-mode=safe:sync
   ```

## Complete Reset

If all else fails, use the uninstall script to start fresh:

### Keep Blockchain Data (Fastest Recovery)

```bash
# Uninstall but keep blockchain for quick reinstall
sudo ./uninstall-monero.sh --keep-blockchain

# Re-run setup (will reuse existing blockchain in /var/lib/monero)
sudo ./setup-monero.sh
```

### Keep Wallet Files Only

```bash
# Remove everything except wallet files
sudo ./uninstall-monero.sh --keep-wallets

# Re-run setup
sudo ./setup-monero.sh
```

### Manual Reset (Alternative)

```bash
# Stop service
sudo systemctl stop monerod
sudo systemctl disable monerod

# Remove config (not blockchain!)
sudo rm -rf /etc/monero
sudo rm -f /etc/systemd/system/monerod.service
sudo rm -f /usr/local/bin/monero*
sudo rm -rf /opt/monero

# Remove user
sudo userdel monero 2>/dev/null

# Reload systemd
sudo systemctl daemon-reload

# Re-run setup (will reuse existing blockchain in /var/lib/monero)
sudo ./setup-monero.sh
```

## Full Uninstall

### Using Uninstall Script (Recommended)

```bash
# Interactive uninstall - will confirm before deleting data
sudo ./uninstall-monero.sh

# Silent complete removal (no prompts - dangerous!)
sudo ./uninstall-monero.sh --force --quiet
```

The uninstall script will:
- Stop and disable the monerod service
- Remove all Monero binaries and symlinks
- Delete configuration files
- Remove log files
- Delete blockchain data (with confirmation)
- Remove firewall rules
- Delete the system user
- Clean up temporary files

### One-Liner Removal (Alternative)

Remove everything including blockchain:

```bash
sudo systemctl stop monerod; sudo systemctl disable monerod; sudo rm -rf /opt/monero /etc/monero /var/log/monero /var/lib/monero; sudo rm -f /etc/systemd/system/monerod.service /usr/local/bin/monero*; sudo userdel monero 2>/dev/null; sudo systemctl daemon-reload
```

## Getting Help

If you're still stuck:

1. **Check logs carefully:**
   ```bash
   sudo journalctl -u monerod -n 200 | grep -i error
   ```

2. **Monero community:**
   - [Reddit r/Monero](https://www.reddit.com/r/Monero/)
   - [Monero Stack Exchange](https://monero.stackexchange.com/)
   - [Monero IRC/Matrix](https://www.getmonero.org/community/hangouts/)

3. **Include in your question:**
   - Output of `sudo systemctl status monerod`
   - Last 50 lines of logs
   - Your config (remove any passwords!)
   - Debian version: `cat /etc/debian_version`

