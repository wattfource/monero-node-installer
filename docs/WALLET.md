# Pool Wallet Management

This guide covers managing the Monero wallet created during pool setup.

## Where is My Wallet?

The wallet was created during setup and stored securely:

| Item | Location |
|------|----------|
| Wallet files | `/var/lib/monero/wallets/pool-wallet` |
| Config (address, password, seed) | `/etc/monero/pool-wallet.conf` |

## View Wallet Details

```bash
# View address, password, and seed phrase
sudo cat /etc/monero/pool-wallet.conf
```

**Important:** This file contains your seed phrase. Anyone with access to it can steal your funds.

## How the Pool Wallet Works

```
Miners submit shares → Pool finds block → Block reward → Your Pool Wallet
                                              ↓
                              Pool fee (your cut) stays in wallet
                              Miner payouts sent from wallet
```

The pool wallet:
1. **Receives** block rewards when the pool finds blocks
2. **Holds** your pool fee percentage
3. **Sends** payouts to miners (configured in pool software)

## Accessing Your Wallet

### Option 1: View Balance (Quick)

Once your node is synced:

```bash
# Check if node is synced first
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
  -H 'Content-Type: application/json' | jq '.result | {synced: (.height == .target_height), height, target_height}'
```

### Option 2: Wallet CLI (Full Access)

```bash
# Get your wallet password
sudo grep WALLET_PASSWORD /etc/monero/pool-wallet.conf

# Open wallet (replace PASSWORD with actual password)
monero-wallet-cli \
  --wallet-file /var/lib/monero/wallets/pool-wallet \
  --daemon-address 127.0.0.1:18081

# Enter password when prompted
```

**Inside the wallet CLI:**

```
# Check balance
balance

# Show your address
address

# Show transaction history
show_transfers

# Send XMR to another address
transfer ADDRESS AMOUNT

# Exit wallet
exit
```

### Option 3: Import to GUI Wallet

You can import your wallet to the Monero GUI on another computer:

1. Download [Monero GUI Wallet](https://www.getmonero.org/downloads/)
2. Select "Restore wallet from keys or mnemonic seed"
3. Enter your seed phrase from `/etc/monero/pool-wallet.conf`
4. Set a new password
5. Connect to your node or a public node

## Security Best Practices

### Backup Your Seed Phrase

```bash
# View and copy your seed phrase
sudo grep -A 5 "SEED PHRASE" /etc/monero/pool-wallet.conf
```

Write it down on paper and store in a safe place. This is the **only way** to recover your funds if the server is lost.

### Restrict Config File Access

The setup script already does this, but verify:

```bash
# Check permissions (should be 600 = owner read/write only)
ls -la /etc/monero/pool-wallet.conf

# Fix if needed
sudo chmod 600 /etc/monero/pool-wallet.conf
sudo chown monero:monero /etc/monero/pool-wallet.conf
```

### Consider a Separate Withdrawal Wallet

For larger operations, consider:
1. Pool wallet receives rewards
2. Periodically transfer to a "cold" wallet you control elsewhere
3. Keep only operational funds in the pool wallet

## Wallet Commands Reference

| Command | Description |
|---------|-------------|
| `balance` | Show confirmed and unconfirmed balance |
| `address` | Show wallet address |
| `address new` | Generate a new subaddress |
| `show_transfers` | Show incoming/outgoing transactions |
| `transfer ADDRESS AMOUNT` | Send XMR |
| `sweep_all ADDRESS` | Send entire balance |
| `export_outputs FILE` | Export outputs (for view-only wallets) |
| `help` | Show all commands |
| `exit` | Close wallet safely |

## Troubleshooting

### "Wallet is not connected to daemon"

Your node isn't synced or isn't running:

```bash
# Check node status
sudo systemctl status monerod

# Check sync progress
curl -s http://127.0.0.1:18081/json_rpc \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' \
  -H 'Content-Type: application/json' | jq '.result.height, .result.target_height'
```

### "Error opening wallet"

Wrong password or corrupted wallet file:

```bash
# Verify password
sudo grep WALLET_PASSWORD /etc/monero/pool-wallet.conf

# Check wallet files exist
ls -la /var/lib/monero/wallets/
```

### Wallet Shows 0 Balance After Sync

If your node just synced, the wallet needs to scan the blockchain:

```bash
# Inside wallet CLI
refresh

# Or rescan from scratch
rescan_bc
```

## Pool Fee Revenue

Your pool fee is configured in the stratum/pool software (not the wallet). Example fee income:

| Pool Hashrate | Est. Blocks/Month | 1% Fee Income |
|---------------|-------------------|---------------|
| 10 MH/s | ~0.5 | ~0.003 XMR |
| 100 MH/s | ~5 | ~0.03 XMR |
| 1 GH/s | ~50 | ~0.3 XMR |

*Varies with network difficulty*

## Next Steps

Once your node is synced:
1. Verify wallet address matches pool software config
2. Set up pool software (stratum server)
3. Configure payout thresholds and fees

