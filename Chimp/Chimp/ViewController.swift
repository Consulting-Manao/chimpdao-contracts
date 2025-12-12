//
//  ViewController.swift
//  Chimp
//
//  Based on Infineon BlockchainSecurity2Go-iOS template
//

import UIKit
import CoreNFC

/// Simple confetti animation view for success celebrations
class ConfettiView: UIView {
    private var emitterLayer: CAEmitterLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupConfetti()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupConfetti()
    }

    private func setupConfetti() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY - 100)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterShape = .line
        emitter.birthRate = 0 // Start stopped

        // Create confetti particles
        var cells = [CAEmitterCell]()

        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemPurple, .systemOrange, .systemPink]
        let shapes = ["circle", "triangle", "square"]

        for (index, color) in colors.enumerated() {
            let cell = CAEmitterCell()
            cell.birthRate = 1.0
            cell.lifetime = 7.0
            cell.velocity = 150 + CGFloat(index * 20)
            cell.velocityRange = 50
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 4
            cell.spin = 2
            cell.spinRange = 3
            cell.scale = 0.1
            cell.scaleRange = 0.05
            cell.alphaSpeed = -0.1

            // Create small colored shapes
            let shapeSize = CGSize(width: 8, height: 8)
            UIGraphicsBeginImageContextWithOptions(shapeSize, false, 0)
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: shapeSize)).fill()
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            cell.contents = image?.cgImage
            cells.append(cell)
        }

        emitter.emitterCells = cells
        layer.addSublayer(emitter)
        emitterLayer = emitter
    }

    func startConfetti() {
        emitterLayer?.birthRate = 1.0

        // Stop after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.stopConfetti()
        }
    }

    func stopConfetti() {
        emitterLayer?.birthRate = 0
    }
}

/// Contains the user interface controller code of the main screen
class ViewController: UIViewController {
    let TAG: String = "MainViewController"
    
    var publicKeyLabel: UILabel!
    var scanButton: UIButton!
    var signButton: UIButton!
    var claimButton: UIButton!
    var addressLabel: UILabel!
    var settingsButton: UIButton!
    
    var nfc_helper: NFCHelper?
    var walletService: WalletService!
    var claimService: ClaimService!
    var confettiView: ConfettiView?
    
    /// Stores the key index selected by the user. Default value is 1
    var selected_keyindex: UInt8  = 0x01
    
    /// Operation type: true for signature, false for read
    var isSignOperation: Bool = false
    
    // MARK: - View controller events
    override func viewDidLoad() {
        super.viewDidLoad()
        
        walletService = WalletService()
        claimService = ClaimService()
        
        ConfigureViews()
        ResetDefaults()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Check for stored wallet after view is in hierarchy
        if walletService.getStoredWallet() == nil {
            showLoginView()
        } else {
            updateUIForLoggedInState()
        }
    }
    
    // MARK: - Event handlers
    @objc func ScanButtonTapped() {
        print(TAG + ": Read card button clicked")
        
        ResetDefaults()
        selected_keyindex = 0x01
        isSignOperation = false
        BeginNFCReadSession()
    }
    
    @objc func SignButtonTapped() {
        print(TAG + ": Sign message button clicked")
        
        ResetDefaults()
        selected_keyindex = 0x01
        isSignOperation = true
        BeginNFCReadSession()
    }
    
    @objc func ClaimButtonTapped() {
        print(TAG + ": Claim button clicked")
        
        guard walletService.getStoredWallet() != nil else {
            showLoginView()
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            let alert = UIAlertController(
                title: "Contract ID Required",
                message: "Please set the contract ID in Settings",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        
        ResetDefaults()
        publicKeyLabel.text = "Preparing claim...\nHold chip near device"
        claimButton.isEnabled = false
        
        BeginNFCClaimSession()
    }
    
    @objc func SettingsButtonTapped() {
        let settingsView = SettingsView()
        settingsView.onLogout = { [weak self] in
            self?.showLoginView()
        }
        let navController = UINavigationController(rootViewController: settingsView)
        present(navController, animated: true)
    }
    
    // MARK: - Private helpers: UI
    /// Configures the user interface elements and assigns the respective event handlers
    func ConfigureViews(){
        view.backgroundColor = .systemBackground
        title = "Chimp"
        
        // Settings button
        let settingsBtn = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(SettingsButtonTapped)
        )
        navigationItem.rightBarButtonItem = settingsBtn
        settingsButton = UIButton()
        
        // Address label
        let addrLabel = UILabel()
        addrLabel.text = ""
        addrLabel.textAlignment = .center
        addrLabel.numberOfLines = 0
        addrLabel.font = .systemFont(ofSize: 12, weight: .regular)
        addrLabel.textColor = .secondaryLabel
        addrLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addrLabel)
        addressLabel = addrLabel
        
        // Create scan button
        let button = UIButton(type: .system)
        button.setTitle("Scan NFC Chip", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(ScanButtonTapped), for: .touchUpInside)
        view.addSubview(button)
        scanButton = button
        
        // Create sign button
        let signBtn = UIButton(type: .system)
        signBtn.setTitle("Sign Message", for: .normal)
        signBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        signBtn.backgroundColor = .systemGreen
        signBtn.setTitleColor(.white, for: .normal)
        signBtn.layer.cornerRadius = 10
        signBtn.translatesAutoresizingMaskIntoConstraints = false
        signBtn.addTarget(self, action: #selector(SignButtonTapped), for: .touchUpInside)
        view.addSubview(signBtn)
        signButton = signBtn
        
        // Create claim button
        let claimBtn = UIButton(type: .system)
        claimBtn.setTitle("Claim NFT", for: .normal)
        claimBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        claimBtn.backgroundColor = .systemPurple
        claimBtn.setTitleColor(.white, for: .normal)
        claimBtn.layer.cornerRadius = 10
        claimBtn.translatesAutoresizingMaskIntoConstraints = false
        claimBtn.addTarget(self, action: #selector(ClaimButtonTapped), for: .touchUpInside)
        view.addSubview(claimBtn)
        claimButton = claimBtn
        
        // Create label for public key/signature
        let label = UILabel()
        label.text = ""
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        publicKeyLabel = label

        // Create confetti view for success celebrations
        let confetti = ConfettiView(frame: view.bounds)
        confetti.translatesAutoresizingMaskIntoConstraints = false
        confetti.isHidden = true
        view.addSubview(confetti)
        confettiView = confetti
        
        // Layout constraints
        NSLayoutConstraint.activate([
            addrLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            addrLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            addrLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -100),
            button.widthAnchor.constraint(equalToConstant: 200),
            button.heightAnchor.constraint(equalToConstant: 50),
            
            signBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signBtn.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 20),
            signBtn.widthAnchor.constraint(equalToConstant: 200),
            signBtn.heightAnchor.constraint(equalToConstant: 50),
            
            claimBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            claimBtn.topAnchor.constraint(equalTo: signBtn.bottomAnchor, constant: 20),
            claimBtn.widthAnchor.constraint(equalToConstant: 200),
            claimBtn.heightAnchor.constraint(equalToConstant: 50),

            // Confetti view fills entire screen
            confetti.topAnchor.constraint(equalTo: view.topAnchor),
            confetti.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            confetti.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            confetti.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            label.topAnchor.constraint(equalTo: claimBtn.bottomAnchor, constant: 40),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    func updateUIForLoggedInState() {
        if let wallet = walletService.getStoredWallet() {
            addressLabel.text = "Address: \(wallet.address)"
            claimButton.isHidden = false
        } else {
            addressLabel.text = ""
            claimButton.isHidden = true
        }
    }
    
    func showLoginView() {
        // Only show if not already presented
        guard presentedViewController == nil else {
            return
        }
        
        let loginView = LoginView()
        loginView.onLoginSuccess = { [weak self] in
            self?.dismiss(animated: true) {
                self?.updateUIForLoggedInState()
            }
        }
        let navController = UINavigationController(rootViewController: loginView)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    /// Resets the user interface elements to the initial state
    func ResetDefaults() {
        self.publicKeyLabel.text = ""
        self.publicKeyLabel.textColor = .label // Reset to default color
        self.confettiView?.stopConfetti()
        self.confettiView?.isHidden = true
    }
    
    // MARK: - Private helpers: NFC
    /// Begins NFC session for claim operation
    func BeginNFCClaimSession() {
        guard NFCTagReaderSession.readingAvailable else {
            let alert = UIAlertController(
                title: "No NFC",
                message: "NFC is not available on this device",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            claimButton.isEnabled = true
            return
        }
        
        nfc_helper = NFCHelper()
        nfc_helper?.OnTagEvent = self.OnClaimTagEvent(success:tag:session:error:)
        nfc_helper?.BeginSession()
    }
    
    /// Handles tag events for claim operation
    func OnClaimTagEvent(success: Bool, tag: NFCISO7816Tag?,
                        session: NFCTagReaderSession?, error: String?) {
        if success {
            if let tag = tag, let session = session {
                Task {
                    do {
                        let txHash = try await claimService.executeClaim(
                            tag: tag,
                            session: session,
                            keyIndex: selected_keyindex
                        ) { progress in
                            DispatchQueue.main.async {
                                self.publicKeyLabel.text = progress
                            }
                        }
                        
                        await MainActor.run {
                            // Show confetti animation for success
                            self.confettiView?.isHidden = false
                            self.confettiView?.startConfetti()

                            // Minimalistic success message following Apple guidelines
                            self.publicKeyLabel.text = "✓ NFT Claimed Successfully"
                            self.publicKeyLabel.textColor = .systemGreen
                            self.claimButton.isEnabled = true

                            session.alertMessage = "Claim successful"
                            session.invalidate()
                        }
                    } catch {
                        await MainActor.run {
                            // Clean error message following Apple guidelines
                            let errorMessage = error.localizedDescription.contains("tokenAlreadyClaimed")
                                ? "This NFT has already been claimed"
                                : "Claim failed. Please try again."

                            self.publicKeyLabel.text = "✗ \(errorMessage)"
                            self.publicKeyLabel.textColor = .systemRed
                            self.claimButton.isEnabled = true

                            session.invalidate(errorMessage: "Claim failed")
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.publicKeyLabel.text = "Failed to detect tag: \(error ?? "Unknown error")"
                self.claimButton.isEnabled = true
            }
        }
    }
    
    /// Checks for NFC support and begins a tag reader session
    func BeginNFCReadSession() {
        
        // Check whether NFC is supported in this device
        guard NFCTagReaderSession.readingAvailable else {
            print(TAG + ": Device doesn't support NFC")
            
            let alert = UIAlertController(
                title: "No NFC",
                message: "NFC is not available on this device",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(
                title: "OK",
                style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }
        
        // Begin the NFC reader session
        nfc_helper = NFCHelper()
        nfc_helper?.OnTagEvent = self.OnTagEvent(success:tag:session:error:)
        nfc_helper?.BeginSession()
    }
    
    /// Handles the initial tag events such as tag presented, timeout, etc. of the NFCHelper class
    /// - Parameters:
    ///   - success: Indicates whether the tag is detected successfully
    ///   - tag: ISO7816 tag handle for further communication with the tag. nil if tag not detected.
    ///   - session: NFCTagReaderSession handle for further communication with the tag. nil if tag not detected.
    ///   - error: Error description in case of tag detection failure
    func OnTagEvent(success: Bool, tag: NFCISO7816Tag?,
                    session: NFCTagReaderSession?, error: String?) {
        if(success){
            // If the tag reader session handle is available, start sending the commands
            if(tag != nil && session != nil){
                SendBlockchainCommand(tag: tag!, session: session!)
            }
        }
        else {
            // Failed to detect tag. Display failure
            var error_message: String = "Failed to detect tag. "
            if(error != nil) {
                error_message += error!
            }
            DispatchQueue.main.async {
                self.publicKeyLabel.text = "✗ \(error_message)"
                self.publicKeyLabel.textColor = .systemRed
            }
        }
    }
    
    /// Exchanges Blockchain commands to read the public key or generate signature from the tag
    /// - Parameters:
    ///   - tag: ISO7816 tag handle for communication with the tag
    ///   - session: NFCTagReaderSession handle for communication with the tag
    func SendBlockchainCommand(tag: NFCISO7816Tag, session: NFCTagReaderSession)
    {
        let command_handler: BlockchainCommandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
        
        if isSignOperation {
            // Test hash from command-line example: 53d79d1d1cdcb175a480d34dddf359d3bf9f441d35d5e86b8a3ea78afba9491b
            let testHashHex = "53d79d1d1cdcb175a480d34dddf359d3bf9f441d35d5e86b8a3ea78afba9491b"
            guard let messageDigest = Data(hexString: testHashHex) else {
                print(TAG + ": Error: Failed to parse test hash")
                DispatchQueue.main.async {
                    self.publicKeyLabel.text = "Error: Invalid test hash"
                }
                session.invalidate(errorMessage: "Invalid test hash")
                return
            }
            
            print(TAG + ": Starting signature generation")
            print(TAG + ": Key index: \(selected_keyindex)")
            print(TAG + ": Message digest (hex): \(testHashHex)")
            command_handler.ActionGenerateSignature(key_index: selected_keyindex, message_digest: messageDigest, completion_handler: OnSignCommandCompleted)
        } else {
            command_handler.ActionGetKey(key_index: selected_keyindex, completion_handler: OnCommandCompleted)
        }
    }
    
    /// Handles the action completed event for BlockchainCommandHandler. This processes the result of the APDU exchanges.
    /// - Parameters:
    ///   - success: Indicates whether the GetKey action is completed successfully
    ///   - response: APDU response of GetKey command without SW
    ///   - session: NFCTagReaderSession handle for invalidating the session
    /// - Returns: Nothing
    func OnCommandCompleted(success: Bool, response: Data?, error: String?, session: NFCTagReaderSession) -> Void{
        
        var result: Bool = false
        var error_msg: String = ""
        if(error != nil) {
            error_msg = error!
        }
        
        if(success && (response != nil)){
            print(TAG + ": Response from card: " + (response?.hexEncodedString() ?? ""))
            
            // Extract public key (skip first 9 bytes: 4 bytes global counter + 4 bytes signature counter + 1 byte 0x04)
            if response!.count >= 73 {
                let publicKeyData = response!.subdata(in: 9..<73) // 64 bytes of public key
                let publicKeyHex = publicKeyData.map { String(format: "%02x", $0) }.joined()
                
                result = true
                // Display the result
                DispatchQueue.main.async {
                    self.publicKeyLabel.text = "Public Key (64 bytes):\n\(publicKeyHex)"
                }
                print(TAG + ": Success: Public key displayed")
            } else {
                error_msg = "Invalid response length"
                print(TAG + ": Invalid response length: \(response!.count)")
            }
        }

        if(result)
        {
            // Success
            session.alertMessage = "Completed successfully"
            session.invalidate()
        } else {
            
            DispatchQueue.main.async {
                self.publicKeyLabel.text = "✗ Failed to read tag"
                self.publicKeyLabel.textColor = .systemRed
            }
             session.invalidate(errorMessage: "Failed to read tag. ")
        }
    }
    
    /// Handles the signature generation completed event for BlockchainCommandHandler
    /// - Parameters:
    ///   - success: Indicates whether the signature generation is completed successfully
    ///   - response: APDU response of GenerateSignature command without SW
    ///   - session: NFCTagReaderSession handle for invalidating the session
    func OnSignCommandCompleted(success: Bool, response: Data?, error: String?, session: NFCTagReaderSession) -> Void {
        
        var result: Bool = false
        var error_msg: String = ""
        if(error != nil) {
            error_msg = error!
        }
        
        if(success && (response != nil)){
            print(TAG + ": Signature response from card: " + (response?.hexEncodedString() ?? ""))
            
            // Response format: 4 bytes global counter + 4 bytes key counter + DER signature
            if response!.count >= 8 {
                let globalCounter = response!.subdata(in: 0..<4)
                let keyCounter = response!.subdata(in: 4..<8)
                let derSignature = response!.subdata(in: 8..<response!.count)
                
                let globalCounterHex = globalCounter.hexEncodedString()
                let keyCounterHex = keyCounter.hexEncodedString()
                let derSignatureHex = derSignature.hexEncodedString()
                
                print(TAG + ": ========== SIGNATURE GENERATION RESULT ==========")
                print(TAG + ": Global counter (hex): \(globalCounterHex)")
                print(TAG + ": Key counter (hex): \(keyCounterHex)")
                print(TAG + ": DER signature (hex): \(derSignatureHex)")
                print(TAG + ": DER signature length: \(derSignature.count) bytes")
                print(TAG + ": Full response (hex): \(response!.hexEncodedString())")
                print(TAG + ": ================================================")
                
                result = true
                // Display the result
                DispatchQueue.main.async {
                    self.publicKeyLabel.text = "Signature Generated:\n\nGlobal Counter: \(globalCounterHex)\nKey Counter: \(keyCounterHex)\nDER Signature: \(derSignatureHex)"
                }
                print(TAG + ": Success: Signature displayed")
            } else {
                error_msg = "Invalid response length: \(response!.count) bytes (expected at least 8)"
                print(TAG + ": Invalid response length: \(response!.count)")
            }
        }

        if(result)
        {
            // Success
            session.alertMessage = "Signature generated successfully"
            session.invalidate()
        } else {
            DispatchQueue.main.async {
                self.publicKeyLabel.text = "✗ Failed to generate signature"
                self.publicKeyLabel.textColor = .systemRed
            }
            session.invalidate(errorMessage: "Failed to generate signature. ")
        }
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
    
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}
