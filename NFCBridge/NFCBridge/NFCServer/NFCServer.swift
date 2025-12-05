/**
 * WebSocket Server using Network Framework
 * Listens on localhost:8080 for connections from web app
 */

import Foundation
import Network

protocol NFCServerDelegate: AnyObject {
    func serverDidStart()
    func serverDidStop()
    func clientDidConnect()
    func clientDidDisconnect()
}

class NFCServer {
    private var listener: NWListener?
    private var connections: [NWConnection: WebSocketHandler] = [:]
    private let nfcService: NFCService
    private let protocolAdapter: ProtocolAdapter
    private let messageHandler: MessageHandler
    weak var delegate: NFCServerDelegate?
    
    init(nfcService: NFCService) {
        self.nfcService = nfcService
        self.protocolAdapter = ProtocolAdapter(nfcService: nfcService)
        self.messageHandler = MessageHandler(protocolAdapter: protocolAdapter)
    }
    
    /**
     * Start WebSocket server on localhost:8080
     */
    func start() {
        let parameters = NWParameters(tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        
        // Allow multiple connections
        let options = NWProtocolTCP.Options()
        options.enableKeepalive = true
        options.keepaliveIdle = 2
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        
        let port = NWEndpoint.Port(rawValue: 8080)!
        listener = try? NWListener(using: parameters, on: port)
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("NFC Bridge Server: Started on port 8080")
                self?.delegate?.serverDidStart()
            case .failed(let error):
                print("NFC Bridge Server: Failed with error: \(error)")
                self?.delegate?.serverDidStop()
            case .cancelled:
                print("NFC Bridge Server: Stopped")
                self?.delegate?.serverDidStop()
            default:
                break
            }
        }
        
        listener?.start(queue: .main)
    }
    
    /**
     * Stop WebSocket server
     */
    func stop() {
        listener?.cancel()
        connections.keys.forEach { $0.cancel() }
        connections.removeAll()
    }
    
    /**
     * Handle new client connection
     */
    private func handleConnection(_ connection: NWConnection) {
        let wsHandler = WebSocketHandler(connection: connection)
        connections[connection] = wsHandler
        delegate?.clientDidConnect()
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveHandshake(on: connection)
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.connections.removeValue(forKey: connection)
                connection.cancel()
                self?.delegate?.clientDidDisconnect()
            case .cancelled:
                self?.connections.removeValue(forKey: connection)
                self?.delegate?.clientDidDisconnect()
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    /**
     * Receive WebSocket handshake
     */
    private func receiveHandshake(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Handshake receive error: \(error)")
                return
            }
            
            if let data = data, !data.isEmpty {
                guard let httpRequest = String(data: data, encoding: .utf8),
                      let wsHandler = self.connections[connection] else {
                    connection.cancel()
                    return
                }
                
                do {
                    let response = try wsHandler.handleHandshake(httpRequest)
                    let responseData = response.data(using: .utf8)!
                    
                    connection.send(content: responseData, completion: .contentProcessed { error in
                        if let error = error {
                            print("Handshake send error: \(error)")
                            return
                        }
                        // Handshake complete, start receiving messages
                        self.receiveMessage(on: connection)
                    })
                } catch {
                    print("Handshake error: \(error)")
                    connection.cancel()
                }
            }
        }
    }
    
    /**
     * Receive messages from client
     */
    private func receiveMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            if let error = error {
                print("Receive error: \(error)")
                return
            }
            
            if let data = data, !data.isEmpty {
                self?.handleWebSocketMessage(data, on: connection)
            }
            
            if !isComplete {
                self?.receiveMessage(on: connection)
            }
        }
    }
    
    /**
     * Handle WebSocket message
     */
    private func handleWebSocketMessage(_ data: Data, on connection: NWConnection) {
        guard let wsHandler = connections[connection],
              wsHandler.isConnectionUpgraded() else {
            // Connection not upgraded yet
            receiveMessage(on: connection)
            return
        }
        
        do {
            // Decode WebSocket frame
            guard let messageText = try wsHandler.decodeFrame(data) else {
                receiveMessage(on: connection)
                return
            }
            
            // Handle message through protocol adapter
            messageHandler.handleMessage(messageText, connection: connection, wsHandler: wsHandler) { responseText in
                if let responseText = responseText {
                    let responseFrame = wsHandler.encodeFrame(responseText)
                    connection.send(content: responseFrame, completion: .contentProcessed { error in
                        if let error = error {
                            print("Send error: \(error)")
                        }
                    })
                }
            }
        } catch {
            print("Frame decode error: \(error)")
        }
        
        // Continue receiving
        receiveMessage(on: connection)
    }
}
