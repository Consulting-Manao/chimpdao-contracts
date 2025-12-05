# Debug NFC Server

## Step 1: Test blocksec2go Commands

Run this to see what blocksec2go actually outputs:

```bash
cd nfc-server
node test-blocksec2go.js
```

This will show you:
- What `get_card_info` returns
- What commands are available
- Exact output format

## Step 2: Update Commands Based on Output

Once you see the actual commands and output format, update `index-blocksec2go.js`:

1. Find the command to read public key
2. Find the command to sign message
3. Update the regex patterns to match actual output

## Step 3: Test Server Manually

```bash
cd nfc-server
bun install ws
node index-blocksec2go.js
```

Watch for:
- "WebSocket server started on port 8080" ✓
- "Running: uv run..." (shows commands being executed)
- "STDOUT: ..." (shows command output)
- "Chip detected!" (when chip is placed)

## Common Issues

### "Nothing happens"

**Check:**
1. Is WebSocket server actually starting? Should see "WebSocket server started"
2. Are commands running? Should see "Running: uv run..."
3. Is chip detected? Should see output from get_card_info

### Fix: Add More Logging

The updated `index-blocksec2go.js` now logs everything:
- Every command executed
- STDOUT and STDERR
- Parse results
- Chip detection changes

### If Commands Aren't Running

Check if `uv` and `blocksec2go` are in PATH:
```bash
which uv
uv run --with blocksec2go blocksec2go --help
```

## Alternative: Just Use Python Directly

Instead of wrapping blocksec2go, create a Python server:

```python
# nfc-server.py
from blocksec2go import BlockSec2Go
import asyncio
import websockets
import json

async def handler(websocket):
    async for message in websocket:
        request = json.loads(message)
        # Handle requests...
```

This might be simpler than wrapping the CLI!

