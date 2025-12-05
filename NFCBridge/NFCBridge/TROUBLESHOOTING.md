# Troubleshooting Guide

## Common Issues

### Server Won't Start

**Issue**: Bridge app shows "Server Stopped" status

**Possible Causes**:
- Port 8080 is already in use by another application
- Network permissions not granted
- iOS restrictions on localhost servers

**Solutions**:
1. Check if another app is using port 8080
2. Restart the bridge app
3. Ensure app has proper network permissions
4. Try rebooting the iOS device

### Web App Can't Connect

**Issue**: Web app shows "Disconnected" even when bridge app is running

**Possible Causes**:
- Bridge app not running
- Web app URL doesn't match device
- Safari blocking localhost connections
- WebSocket protocol mismatch

**Solutions**:
1. Verify bridge app is running and shows "Server Running"
2. Ensure web app is accessed from the same device as bridge app
3. Try accessing web app via `localhost` or device IP address
4. Check Safari console for connection errors
5. Verify WebSocket URL in web app code is `ws://localhost:8080`

### NFC Operations Fail

**Issue**: Public key reading or signing fails

**Possible Causes**:
- SECORA chip not compatible
- Chip not properly positioned
- NFC disabled in device settings
- App doesn't have NFC permissions

**Solutions**:
1. Verify chip is Infineon SECORA Blockchain compatible
2. Ensure chip is flat against back of iPhone
3. Check Settings → Privacy & Security → NFC
4. Verify app has NFC Tag Reading capability enabled
5. Try restarting bridge app
6. Check Xcode console for NFC errors

### App Crashes on NFC Operation

**Issue**: Bridge app crashes when trying to use NFC

**Possible Causes**:
- Missing NFC permissions
- Info.plist configuration incorrect
- Entitlements not properly set

**Solutions**:
1. Verify `NFCReaderUsageDescription` in Info.plist
2. Check NFC Tag Reading capability is enabled
3. Verify entitlements file includes NFC formats
4. Rebuild app in Xcode

### WebSocket Handshake Fails

**Issue**: Connection established but messages not working

**Possible Causes**:
- WebSocket protocol implementation issue
- Frame encoding/decoding error
- Masking key handling problem

**Solutions**:
1. Check Xcode console for WebSocket errors
2. Verify WebSocket frame format matches specification
3. Test with WebSocket client tool to isolate issue
4. Review WebSocketHandler.swift implementation

### Signature Validation Fails

**Issue**: Signatures from iOS bridge don't validate

**Possible Causes**:
- Recovery ID incorrect
- Signature normalization issue
- Message hash mismatch

**Solutions**:
1. Verify recovery ID handling (currently hardcoded to 1)
2. Check signature s-value normalization in APDUHandler
3. Ensure message hash matches what contract expects
4. Compare with desktop server signatures

## Debug Checklist

- [ ] Bridge app installed and running
- [ ] Server shows "Running" status
- [ ] Web app can connect (status updates)
- [ ] NFC chip is SECORA Blockchain compatible
- [ ] Chip properly positioned on device
- [ ] NFC enabled in iOS settings
- [ ] App has NFC permissions
- [ ] Web app accessed from same device
- [ ] WebSocket URL correct (ws://localhost:8080)
- [ ] No firewall blocking localhost
- [ ] Xcode console shows no errors
- [ ] Safari console shows no errors

## Getting Help

If issues persist:

1. **Check Logs**: Review Xcode console for detailed error messages
2. **Test Components**: Try each component separately (NFC, WebSocket, protocol)
3. **Compare with Desktop**: Test with desktop server to isolate iOS-specific issues
4. **Review Documentation**: Check README.md and SETUP.md for setup issues

## Known Limitations

- **Foreground Requirement**: NFC operations require app to be in foreground (iOS Core NFC limitation)
- **Background Termination**: iOS may terminate app if inactive for extended period
- **Recovery ID**: Hardcoded to 1 (key index 1, recovery ID 1)
- **WebSocket Protocol**: Simplified implementation; may need enhancement for production use
