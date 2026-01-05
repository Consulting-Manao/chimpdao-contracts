/**
 * Centralized Logging Utility
 * Uses OSLog for production-ready logging with proper categories and privacy protection
 */

import Foundation
import os.log

/// Logging categories for different subsystems
enum LogCategory: String {
    case nfc = "NFC"
    case blockchain = "Blockchain"
    case crypto = "Crypto"
    case ui = "UI"
    case network = "Network"
}

/// Centralized logger using OSLog
final class Logger {
    private static let subsystem = "com.stellarmerchshop.chimp"
    
    /// Get logger for a specific category
    /// - Parameter category: Log category
    /// - Returns: OSLog instance for the category
    private static func logger(for category: LogCategory) -> OSLog {
        return OSLog(subsystem: subsystem, category: category.rawValue)
    }
    
    /// Log an informational message
    /// - Parameters:
    ///   - message: Message to log
    ///   - category: Log category
    static func logInfo(_ message: String, category: LogCategory) {
        os_log("%{public}@", log: logger(for: category), type: .info, message)
    }
    
    /// Log an error message
    /// - Parameters:
    ///   - message: Message to log
    ///   - category: Log category
    static func logError(_ message: String, category: LogCategory) {
        os_log("%{public}@", log: logger(for: category), type: .error, message)
    }
    
    /// Log a debug message (only in debug builds)
    /// - Parameters:
    ///   - message: Message to log
    ///   - category: Log category
    static func logDebug(_ message: String, category: LogCategory) {
        #if DEBUG
        os_log("%{public}@", log: logger(for: category), type: .debug, message)
        #endif
    }
    
    /// Log a warning message
    /// - Parameters:
    ///   - message: Message to log
    ///   - category: Log category
    static func logWarning(_ message: String, category: LogCategory) {
        os_log("%{public}@", log: logger(for: category), type: .default, message)
    }
    
    /// Log an error with additional details
    /// - Parameters:
    ///   - message: Message to log
    ///   - error: Error object
    ///   - category: Log category
    static func logError(_ message: String, error: Error, category: LogCategory) {
        let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        os_log("%{public}@: %{public}@", log: logger(for: category), type: .error, message, errorDescription)
    }
}

