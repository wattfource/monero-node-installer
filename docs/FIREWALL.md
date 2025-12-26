# Firewall & Port Forwarding Guide

How to configure your network to allow Monero node traffic.

## Ports Overview

| Port | Protocol | Service | Required? |
|------|----------|---------|-----------|
| 18080 | TCP | P2P (peer network) | **Yes** - blockchain sync |
| 18081 | TCP | RPC (wallet/pool) | Depends on mode |
| 18082 | TCP | ZMQ (notifications) | Optional |

## What to Forward Based on Node Type

### Mining Pool Backend

**Forward only port 18080:**

| Port | Forward to VM? | Why |
|------|----------------|-----|
| **18080** | **YES** | Blockchain sync, peer connections |
| 18081 | NO | Localhost only (pool software runs locally) |
| 18082 | NO | Localhost only (if ZMQ enabled) |

### Standard Node (Personal Use)

**Minimum (local wallets only):**

| Port | Forward to VM? |
|------|----------------|
| **18080** | **YES** |
| 18081 | NO |

**With remote wallet access:**

| Port | Forward to VM? |
|------|----------------|
| **18080** | **YES** |
| **18081** | **YES** |

## Router Configuration

### Generic Router Steps

1. Log into your router admin panel (usually `192.168.1.1` or `192.168.0.1`)
2. Find "Port Forwarding" or "NAT" settings
3. Add new rule:
   - **External Port:** 18080
   - **Internal IP:** Your VM's IP (e.g., `192.168.1.100`)
   - **Internal Port:** 18080
   - **Protocol:** TCP
4. Save and apply

### Ubiquiti UniFi

1. Open UniFi Controller
2. Go to **Settings → Routing & Firewall → Port Forwarding**
3. Click **Create New Port Forward**
4. Configure:
   ```
   Name: Monero P2P
   From: Any
   Port: 18080
   Forward IP: [Your VM IP]
   Forward Port: 18080
   Protocol: TCP
   ```
5. Click **Apply**

### Ubiquiti EdgeRouter

```bash
configure
set port-forward rule 1 description "Monero P2P"
set port-forward rule 1 forward-to address 192.168.1.100
set port-forward rule 1 forward-to port 18080
set port-forward rule 1 original-port 18080
set port-forward rule 1 protocol tcp
commit
save
```

### pfSense

1. Go to **Firewall → NAT → Port Forward**
2. Click **Add**
3. Configure:
   - Interface: WAN
   - Protocol: TCP
   - Destination port range: 18080-18080
   - Redirect target IP: [VM IP]
   - Redirect target port: 18080
4. Save and Apply

### OPNsense

1. Go to **Firewall → NAT → Port Forward**
2. Add rule:
   - Interface: WAN
   - TCP
   - Destination port: 18080
   - Redirect IP: [VM IP]
   - Redirect port: 18080
3. Apply

## UFW (VM Firewall)

The setup script configures UFW automatically. To verify or modify:

```bash
# Check current rules
sudo ufw status verbose

# Manually allow ports
sudo ufw allow 18080/tcp comment 'Monero P2P'
sudo ufw allow 18081/tcp comment 'Monero RPC'  # Only if needed

# Remove a rule
sudo ufw delete allow 18081/tcp

# Reload
sudo ufw reload
```

## Verify Port is Open

### From the VM (internal)

```bash
# Check if monerod is listening
sudo ss -tlnp | grep monerod

# Expected output:
# LISTEN  0  128  0.0.0.0:18080  *  users:(("monerod",pid=1234,fd=10))
# LISTEN  0  128  127.0.0.1:18081  *  users:(("monerod",pid=1234,fd=11))
```

### From Outside Your Network

**Using netcat:**
```bash
nc -zv YOUR_PUBLIC_IP 18080
# Success: "Connection to YOUR_PUBLIC_IP 18080 port [tcp/*] succeeded!"
```

**Using online tools:**
- https://www.yougetsignal.com/tools/open-ports/
- https://canyouseeme.org/

### Check Peer Connections

A good test that port forwarding is working:

```bash
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_connections"}' \
  -H 'Content-Type: application/json' | jq '.result.connections | length'
```

- **< 8 peers:** Port forwarding may not be working
- **8+ peers:** Good, you're accepting incoming connections
- **50+ peers:** Excellent connectivity

## Common Issues

### Port Shows Closed But Service is Running

1. **Check UFW on VM:**
   ```bash
   sudo ufw status
   # Make sure 18080 is allowed
   ```

2. **Check router forwarding:**
   - Is the rule active?
   - Is the VM IP correct?
   - Did router IP change? (DHCP lease expired)

3. **Check ISP blocking:**
   - Some ISPs block non-standard ports
   - Try from a mobile hotspot to test

### Double NAT

If your network setup is:
```
Internet → ISP Router → Your Router → VM
```

You need to forward ports on BOTH routers, or put ISP router in bridge mode.

### VM Network Mode

If using VirtualBox/VMware/Proxmox:

| Network Mode | Port Forward Needed? |
|--------------|---------------------|
| **Bridged** | Forward on router only |
| **NAT** | Forward on router AND VM host |
| **Host-only** | Can't access from internet |

For Unraid VMs, use **br0 (bridged)** mode for simplest setup.

## Security Notes

- **Never expose RPC (18081) without authentication** on a public IP
- Mining pool mode keeps RPC on localhost (127.0.0.1) for security
- P2P port (18080) is safe to expose - it's designed for public access
- Consider using a VPN if your ISP blocks crypto traffic

## Finding Your VM's IP

```bash
# On the VM
ip addr show | grep "inet " | grep -v 127.0.0.1

# Or
hostname -I
```

## Static IP Recommendation

To prevent port forwarding from breaking when DHCP lease changes:

1. **Option A:** Assign static IP on VM
2. **Option B:** Create DHCP reservation on router for VM's MAC address

