import Foundation
import AVFoundation


// https://fortinetweb.s3.amazonaws.com/fortiguard/research/techreport.pdf
// https://github.com/travisgoodspeed/goodtag/wiki/RF430TAL152H
// https://github.com/travisgoodspeed/GoodV/blob/master/app/src/main/java/com/kk4vcz/goodv/NfcRF430TAL.java
// https://github.com/cryptax/misc-code/blob/master/glucose-tools/readdump.py
// https://github.com/travisgoodspeed/goodtag/blob/master/firmware/gcmpatch.c
// https://github.com/captainbeeheart/openfreestyle/blob/master/docs/reverse.md


struct NFCCommand {
    let code: Int
    var parameters: Data = Data()
    var description: String = ""
}

enum NFCError: LocalizedError {
    case commandNotSupported
    case customCommandError
    case read
    case readBlocks
    case write

    var errorDescription: String? {
        switch self {
        case .commandNotSupported: return "command not supported"
        case .customCommandError:  return "custom command error"
        case .read:                return "read error"
        case .readBlocks:          return "reading blocks error"
        case .write:               return "write error"
        }
    }
}


extension Sensor {

    var backdoor: Data {
        switch self.type {
        case .libre1:    return Data([0xc2, 0xad, 0x75, 0x21])
        case .libreProH: return Data([0xc2, 0xad, 0x00, 0x90])
        default:         return Data([0xde, 0xad, 0xbe, 0xef])
        }
    }

    var activationCommand: NFCCommand {
        switch self.type {
        case .libre1:
            return NFCCommand(code: 0xA0, parameters: backdoor, description: "activate")
        case .libreProH:
            return NFCCommand(code: 0xA0, parameters: backdoor + "4A454D573136382D5430323638365F23".bytes, description: "activate")
        case .libre2:
            return nfcCommand(.activate)
        default:
            return NFCCommand(code: 0x00)
        }
    }

    var universalCommand: NFCCommand    { NFCCommand(code: 0xA1, description: "A1 universal prefix") }
    var getPatchInfoCommand: NFCCommand { NFCCommand(code: 0xA1, description: "get patch info") }

    // Libre 1
    var lockCommand: NFCCommand         { NFCCommand(code: 0xA2, parameters: backdoor, description: "lock") }
    var readRawCommand: NFCCommand      { NFCCommand(code: 0xA3, parameters: backdoor, description: "read raw") }
    var unlockCommand: NFCCommand       { NFCCommand(code: 0xA4, parameters: backdoor, description: "unlock") }

    // Libre 2 / Pro
    // SEE: custom commands C0-C4 in TI RF430FRL15xH Firmware User's Guide
    var readBlockCommand: NFCCommand    { NFCCommand(code: 0xB0, description: "B0 read block") }
    var readBlocksCommand: NFCCommand   { NFCCommand(code: 0xB3, description: "B3 read blocks") }

    /// replies with error 0x12 (.contentCannotBeChanged)
    var writeBlockCommand: NFCCommand   { NFCCommand(code: 0xB1, description: "B1 write block") }

    /// replies with errors 0x12 (.contentCannotBeChanged) or 0x0f (.unknown)
    /// writing three blocks is not supported because it exceeds the 32-byte input buffer
    var writeBlocksCommand: NFCCommand  { NFCCommand(code: 0xB4, description: "B4 write blocks") }

    /// Usual 1252 blocks limit:
    /// block 04e3 => error 0x11 (.blockAlreadyLocked)
    /// block 04e4 => error 0x10 (.blockNotAvailable)
    var lockBlockCommand: NFCCommand   { NFCCommand(code: 0xB2, description: "B2 lock block") }


    enum Subcommand: UInt8, CustomStringConvertible {
        case unlock          = 0x1a    // lets read FRAM in clear and dump further blocks with B0/B3
        case activate        = 0x1b
        case enableStreaming = 0x1e
        case getSessionInfo  = 0x1f    // GEN_SECURITY_CMD_GET_SESSION_INFO
        case unknown0x10     = 0x10    // returns the number of parameters + 3
        case unknown0x1c     = 0x1c
        case unknown0x1d     = 0x1d    // disables Bluetooth
        // Gen2
        case readChallenge   = 0x20    // returns 25 bytes
        case readBlocks      = 0x21
        case readAttribute   = 0x22    // returns 6 bytes ([0]: sensor state)

        var description: String {
            switch self {
            case .unlock:          return "unlock"
            case .activate:        return "activate"
            case .enableStreaming: return "enable BLE streaming"
            case .getSessionInfo:  return "get session info"
            case .readChallenge:   return "read security challenge"
            case .readBlocks:      return "read FRAM blocks"
            case .readAttribute:   return "read patch attribute"
            default:               return "[unknown: 0x\(rawValue.hex)]"
            }
        }
    }


    /// The customRequestParameters for 0xA1 are built by appending
    /// code + params (b) + usefulFunction(uid, code, secret (y))
    func nfcCommand(_ code: Subcommand, parameters: Data = Data()) -> NFCCommand {

        var parameters = Data([code.rawValue]) + parameters

        var b: [UInt8] = []
        var y: UInt16 = 0x1b6a

        if code == .enableStreaming {

            // Enables Bluetooth on Libre 2. Returns peripheral MAC address to connect to.
            // streamingUnlockCode could be any 32 bit value. The streamingUnlockCode and
            // sensor Uid / patchInfo will have also to be provided to the login function
            // when connecting to peripheral.

            b = [
                UInt8(streamingUnlockCode & 0xFF),
                UInt8((streamingUnlockCode >> 8) & 0xFF),
                UInt8((streamingUnlockCode >> 16) & 0xFF),
                UInt8((streamingUnlockCode >> 24) & 0xFF)
            ]
            y = UInt16(patchInfo[4...5]) ^ UInt16(b[1], b[0])
        }

        if b.count > 0 {
            parameters += b
        }

        if code.rawValue < 0x20 {
            let d = Libre2.usefulFunction(id: uid, x: UInt16(code.rawValue), y: y)
            parameters += d
        }

        return NFCCommand(code: 0xA1, parameters: parameters, description: code.description)
    }
}


#if !os(watchOS)

import CoreNFC


enum IS015693Error: Int, CustomStringConvertible {
    case none                   = 0x00
    case commandNotSupported    = 0x01
    case commandNotRecognized   = 0x02
    case optionNotSupported     = 0x03
    case unknown                = 0x0f
    case blockNotAvailable      = 0x10
    case blockAlreadyLocked     = 0x11
    case contentCannotBeChanged = 0x12

    var description: String {
        switch self {
        case .none:                   return "none"
        case .commandNotSupported:    return "command not supported"
        case .commandNotRecognized:   return "command not recognized (e.g. format error)"
        case .optionNotSupported:     return "option not supported"
        case .unknown:                return "unknown"
        case .blockNotAvailable:      return "block not available (out of range, doesn???t exist)"
        case .blockAlreadyLocked:     return "block already locked -- can???t be locked again"
        case .contentCannotBeChanged: return "block locked -- content cannot be changed"
        }
    }
}


extension Error {
    var iso15693Code: Int {
        if let code = (self as NSError).userInfo[NFCISO15693TagResponseErrorKey] as? Int {
            return code
        } else {
            return 0
        }
    }
    var iso15693Description: String { IS015693Error(rawValue: self.iso15693Code)?.description ?? "[code: 0x\(self.iso15693Code.hex)]" }
}


enum TaskRequest {
    case activate
    case enableStreaming
    case readFRAM
    case unlock
    case reset
    case prolong
    case dump
}


class NFC: NSObject, NFCTagReaderSessionDelegate, Logging {

    var session: NFCTagReaderSession?
    var connectedTag: NFCISO15693Tag?
#if !targetEnvironment(macCatalyst)
    var systemInfo: NFCISO15693SystemInfo!
#endif
    var sensor: Sensor!

    // Gen2
    var securityChallenge: Data = Data()
    var authContext: Int = 0
    var sessionInfo: Data = Data()

    var taskRequest: TaskRequest? {
        didSet {
            guard taskRequest != nil else { return }
            startSession()
        }
    }

    var main: MainDelegate!

    var isAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }

    func startSession() {
        // execute in the .main queue because of publishing changes to main's observables
        session = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main)
        session?.alertMessage = "Hold the top of your iPhone near the Libre sensor until the second longer vibration"
        session?.begin()
    }

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        log("NFC: session did become active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code != .readerSessionInvalidationErrorUserCanceled {
                session.invalidate(errorMessage: "Connection failure: \(readerError.localizedDescription)")
                log("NFC: \(readerError.localizedDescription)")
            }
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        log("NFC: did detect tags")

        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }

        session.alertMessage = "Scan Complete"

        if  main.app.sensor != nil {
            sensor = main.app.sensor
        } else {
            sensor = Sensor(main: main)
            main.app.sensor = sensor
        }

#if !targetEnvironment(macCatalyst)    // the async methods and Result handlers don't compile in Catalyst

        Task {

            do {
                try await session.connect(to: firstTag)
                connectedTag = tag
            } catch {
                log("NFC: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(error.localizedDescription)")
                return
            }

            let retries = 5
            var requestedRetry = 0
            var failedToScan = false
            repeat {
                failedToScan = false
                if requestedRetry > 0 {
                    AudioServicesPlaySystemSound(1520)    // "pop" vibration
                    log("NFC: retry # \(requestedRetry)...")
                    // await Task.sleep(250_000_000) not needed: too long
                }

                // Libre 3 workaround: calling A1 before tag.sytemInfo makes them work
                // The first reading prepends further 7 0xA5 dummy bytes

                do {
                    sensor.patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
                } catch {
                    failedToScan = true
                }

                do {
                    systemInfo = try await tag.systemInfo(requestFlags: .highDataRate)
                    AudioServicesPlaySystemSound(1520)    // initial "pop" vibration
                } catch {
                    log("NFC: error while getting system info: \(error.localizedDescription)")
                    if requestedRetry > retries {
                        session.invalidate(errorMessage: "Error while getting system info: \(error.localizedDescription)")
                        return
                    }
                    failedToScan = true
                    requestedRetry += 1
                }

                do {
                    sensor.patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
                } catch {
                    log("NFC: error while getting patch info: \(error.localizedDescription)")
                    if requestedRetry > retries && systemInfo != nil {
                        requestedRetry = 0 // break repeat
                    } else {
                        if !failedToScan {
                            failedToScan = true
                            requestedRetry += 1
                        }
                    }
                }

            } while failedToScan && requestedRetry > 0


            // https://www.st.com/en/embedded-software/stsw-st25ios001.html#get-software

            let uid = tag.identifier.hex
            log("NFC: IC identifier: \(uid)")

            var manufacturer = tag.icManufacturerCode.hex
            if manufacturer == "07" {
                manufacturer.append(" (Texas Instruments)")
            } else if manufacturer == "7a" {
                manufacturer.append(" (Abbott Diabetes Care)")
                sensor.type = .libre3
                sensor.securityGeneration = 3 // TODO: test
            }
            log("NFC: IC manufacturer code: 0x\(manufacturer)")
            log("NFC: IC serial number: \(tag.icSerialNumber.hex)")

            var firmware = "RF430"
            switch tag.identifier[2] {
            case 0xA0: firmware += "TAL152H Libre 1 A0 "
            case 0xA4: firmware += "TAL160H Libre 2 A4 "
            case 0x00: firmware = "unknown Libre 3 "
            default:   firmware += " unknown "
            }
            log("NFC: \(firmware)firmware")

            log(String(format: "NFC: IC reference: 0x%X", systemInfo.icReference))
            if systemInfo.applicationFamilyIdentifier != -1 {
                log(String(format: "NFC: application family id (AFI): %d", systemInfo.applicationFamilyIdentifier))
            }
            if systemInfo.dataStorageFormatIdentifier != -1 {
                log(String(format: "NFC: data storage format id: %d", systemInfo.dataStorageFormatIdentifier))
            }

            log(String(format: "NFC: memory size: %d blocks", systemInfo.totalBlocks))
            log(String(format: "NFC: block size: %d", systemInfo.blockSize))

            sensor.uid = Data(tag.identifier.reversed())
            log("NFC: sensor uid: \(sensor.uid.hex)")

            if sensor.patchInfo.count > 0 {
                log("NFC: patch info: \(sensor.patchInfo.hex)")
                log("NFC: sensor type: \(sensor.type.rawValue)\(sensor.patchInfo.hex.hasPrefix("a2") ? " (new 'A2' kind)" : "")")

                DispatchQueue.main.async {
                    self.main.settings.patchUid = self.sensor.uid
                    self.main.settings.patchInfo = self.sensor.patchInfo
                }
            }

            log("NFC: sensor serial number: \(sensor.serial)")

            if taskRequest != .none {

                /// Libre 1 memory layout:
                /// config: 0x1A00, 64    (sensor UID and calibration info)
                /// sram:   0x1C00, 512
                /// rom:    0x4400 - 0x5FFF
                /// fram lock table: 0xF840, 32
                /// fram:   0xF860, 1952

                if taskRequest == .dump {

                    do {
                        var (address, data) = try await readRaw(0x1A00, 64)
                        log(data.hexDump(header: "Config RAM (patch UID at 0x1A08):", address: address))
                        (address, data) = try await readRaw(0x1C00, 512)
                        log(data.hexDump(header: "SRAM:", address: address))
                        (address, data) = try await readRaw(0xFFAC, 36)
                        log(data.hexDump(header: "Patch table for A0-A4 E0-E2 commands:", address: address))
                        (address, data) = try await readRaw(0xF860, 43 * 8)
                        log(data.hexDump(header: "FRAM:", address: address))
                    } catch {}

                    do {
                        let (start, data) = try await read(fromBlock: 0, count: 43)
                        log(data.hexDump(header: "ISO 15693 FRAM blocks:", startingBlock: start))
                        sensor.fram = Data(data)
                        if sensor.encryptedFram.count > 0 && sensor.fram.count >= 344 {
                            log("\(sensor.fram.hexDump(header: "Decrypted FRAM:", startingBlock: 0))")
                        }
                    } catch {
                    }

                    /// count is limited to 89 with an encrypted sensor (header as first 3 blocks);
                    /// after sending the A1 1A subcommand the FRAM is decrypted in-place
                    /// and mirrored in the last 43 blocks of 89 but the max count becomes 1252
                    var count = sensor.encryptedFram.count > 0 ? 89 : 1252
                    if sensor.securityGeneration > 1 { count = 43 }

                    let command = sensor.securityGeneration > 1 ? "A1 21" : "B0/B3"

                    do {
                        defer {
                            taskRequest = .none
                            session.invalidate()
                        }

                        let (start, data) = try await readBlocks(from: 0, count: count)

                        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

                        let blocks = data.count / 8

                        log(data.hexDump(header: "\'\(command)' command output (\(blocks) blocks):", startingBlock: start))

                        // await main actor
                        if await main.settings.debugLevel > 0 {
                            let bytes = min(89 * 8 + 34 + 10, data.count)
                            var offset = 0
                            var i = offset + 2
                            while offset < bytes - 3 && i < bytes - 1 {
                                if UInt16(data[offset ... offset + 1]) == data[offset + 2 ... i + 1].crc16 {
                                    log("CRC matches for \(i - offset + 2) bytes at #\((offset / 8).hex) [\(offset + 2)...\(i + 1)] \(data[offset ... offset + 1].hex) = \(data[offset + 2 ... i + 1].crc16.hex)\n\(data[offset ... i + 1].hexDump(header: "\(libre2DumpMap[offset]?.1 ?? "[???]"):", address: 0))")
                                    offset = i + 2
                                    i = offset
                                }
                                i += 2
                            }
                        }

                    } catch {
                        log("NFC: 'read blocks \(command)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                    }
                    return
                }

                if sensor.securityGeneration > 1 {
                    var commands: [NFCCommand] = [sensor.nfcCommand(.readAttribute),
                                                  sensor.nfcCommand(.readChallenge)
                    ]

                    // await main actor
                    if await main.settings.debugLevel > 0 {

                        for c in 0xA0 ... 0xDF {
                            commands.append(NFCCommand(code: c, description: c.hex))
                        }

                        // Gen2 supported commands: A1, B1, B2, B4

                        // Libre 3:
                        // getting 28 bytes from A1: a5 00 01 00 01 00 00 00 c0 4e 1e 0f 00 01 04 0c 01 30 34 34 5a 41 38 43 4c 36 79 38
                        // getting 0xC1 error from A0, A1 20-22, A8, A9, C8, C9
                        // getting 64 0xA5 bytes from A2-A7, AB-C7, CA-DF
                        // getting 22 bytes from AA: 44 4f 43 34 32 37 31 35 2d 31 30 31 11 26 20 12 09 00 80 67 73 e0
                        // getting zeros from standard read command 0x23
                    }
                    for cmd in commands {
                        log("NFC: sending \(sensor.type) '\(cmd.description)' command: code: 0x\(cmd.code.hex), parameters: 0x\(cmd.parameters.hex)")
                        do {
                            let output = try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)
                            log("NFC: '\(cmd.description)' command output (\(output.count) bytes): 0x\(output.hex)")
                            if output.count == 6 { // .readAttribute
                                let state = SensorState(rawValue: output[0]) ?? .unknown
                                sensor.state = state
                                log("\(sensor.type) state: \(state.description.lowercased()) (0x\(state.rawValue.hex))")
                            }
                        } catch {
                            log("NFC: '\(cmd.description)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                        }
                    }

                }

            libre2:
                if sensor.type == .libre2 {
                    let subCmd: Sensor.Subcommand = (taskRequest == .enableStreaming) ?
                        .enableStreaming : .unknown0x1c

                    // TODO
                    if subCmd == .unknown0x1c { break libre2 }    // :)

                    let currentUnlockCode = sensor.streamingUnlockCode
                    sensor.streamingUnlockCode = UInt32(await main.settings.activeSensorStreamingUnlockCode)

                    let cmd = sensor.nfcCommand(subCmd)
                    log("NFC: sending \(sensor.type) command to \(cmd.description): code: 0x\(cmd.code.hex), parameters: 0x\(cmd.parameters.hex)")


                    do {
                        defer {
                            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                            taskRequest = .none
                            // session.invalidate()
                        }

                        let output = try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)

                        log("NFC: '\(cmd.description)' command output (\(output.count) bytes): 0x\(output.hex)")

                        if subCmd == .enableStreaming && output.count == 6 {
                            log("NFC: enabled BLE streaming on \(sensor.type) \(sensor.serial) (unlock code: \(sensor.streamingUnlockCode), MAC address: \(Data(output.reversed()).hexAddress))")
                            await main.settings.activeSensorSerial = sensor.serial
                            await main.settings.activeSensorAddress = Data(output.reversed())
                            sensor.initialPatchInfo = sensor.patchInfo
                            await main.settings.activeSensorInitialPatchInfo = sensor.patchInfo
                            sensor.streamingUnlockCount = 0
                            await main.settings.activeSensorStreamingUnlockCount = 0

                            // TODO: cancel connections also before enabling streaming?
                            await main.rescan()

                        }

                    } catch {
                        log("NFC: '\(cmd.description)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                        sensor.streamingUnlockCode = currentUnlockCode
                    }

                }

                if taskRequest == .reset ||
                    taskRequest == .prolong ||
                    taskRequest == .unlock ||
                    taskRequest == .activate {

                    do {
                        try await execute(taskRequest!)
                    } catch {
                        // TODO
                    }

                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

                    sensor.detailFRAM()
                    taskRequest = .none
                    session.invalidate()
                    return
                }

            }

            var blocks = 43
            if taskRequest == .readFRAM {
                if sensor.type == .libre1 {
                    blocks = 244
                }
            }

            do {

                if sensor.securityGeneration == 2 {

                    // TODO: use Gen2.communicateWithPatch(nfc: self)

                    // FIXME: OOP nfcAuth endpoint still offline

                    securityChallenge = try await send(sensor.nfcCommand(.readChallenge))
                    do {

                        // FIXME: "404 Not Found"
                        _ = try await main.post(OOPServer.gen2.nfcAuthEndpoint!, ["patchUid": sensor.uid.hex, "authData": securityChallenge.hex])

                        let oopResponse = try await main.post(OOPServer.gen2.nfcDataEndpoint!, ["patchUid": sensor.uid.hex, "authData": securityChallenge.hex]) as! OOPGen2Response
                        authContext = oopResponse.p1
                        let authenticatedCommand = Data(oopResponse.data.bytes)
                        log("OOP: context: \(authContext), authenticated `A1 1F get session info` command: \(authenticatedCommand.hex)")
                        var getSessionInfoCommand = sensor.nfcCommand(.getSessionInfo)
                        getSessionInfoCommand.parameters = authenticatedCommand.suffix(authenticatedCommand.count - 3)
                        sessionInfo = try! await send(getSessionInfoCommand)
                        // TODO: drop leading 0xA5s?
                        // sessionInfo = sessionInfo.suffix(sessionInfo.count - 8)
                        log("NFC: session info = \(sessionInfo.hex)")
                    } catch {
                        log("NFC: OOP error: \(error.localizedDescription)")
                    }
                }

                let (start, data) = try await sensor.securityGeneration < 2 ?
                read(fromBlock: 0, count: blocks) : readBlocks(from: 0, count: blocks)

                let lastReadingDate = Date()

                // "Publishing changes from background threads is not allowed"
                DispatchQueue.main.async {
                    self.main.app.lastReadingDate = lastReadingDate
                }
                sensor.lastReadingDate = lastReadingDate

                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                session.invalidate()

                log(data.hexDump(header: "NFC: did read \(data.count / 8) FRAM blocks:", startingBlock: start))

                // FIXME: doesn't accept encrypted content
                if sensor.securityGeneration == 2 {
                    do {
                        _ = try await main.post(OOPServer.gen2.nfcDataAlgorithmEndpoint!, ["p1": authContext, "authData": sessionInfo.hex, "content": data.hex, "patchUid": sensor.uid.hex, "patchInfo": sensor.patchInfo.hex])
                    } catch {
                        log("NFC: OOP error: \(error.localizedDescription)")
                    }
                }

                sensor.fram = Data(data)

            } catch {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                session.invalidate(errorMessage: "\(error.localizedDescription)")
            }

            if taskRequest == .readFRAM {
                sensor.detailFRAM()
                taskRequest = .none
                return
            }

            await main.parseSensorData(sensor)

            await main.status("\(sensor.type)  +  NFC")

        }

#endif    // !targetEnvironment(macCatalyst)

    }

#if !targetEnvironment(macCatalyst)    // the new Result handlers don't compile in Catalyst 14


    @discardableResult
    func send(_ cmd: NFCCommand) async throws -> Data {
        var data = Data()
        do {
            debugLog("NFC: sending \(sensor.type) '\(cmd.code.hex) \(cmd.parameters.hex)' custom command\(cmd.description == "" ? "" : " (\(cmd.description))")")
            let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)
            data = Data(output!)
        } catch {
            log("NFC: \(sensor.type) '\(cmd.description) \(cmd.code.hex) \(cmd.parameters.hex)' custom command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
            throw error
        }
        return data
    }


    func read(fromBlock start: Int, count blocks: Int, requesting: Int = 3, retries: Int = 5) async throws -> (Int, Data) {

        var buffer = Data()

        var remaining = blocks
        var requested = requesting
        var retry = 0

        while remaining > 0 && retry <= retries {

            let blockToRead = start + buffer.count / 8

            do {
                let dataArray = try await connectedTag?.readMultipleBlocks(requestFlags: .highDataRate, blockRange: NSRange(blockToRead ... blockToRead + requested - 1))

                for data in dataArray! {
                    buffer += data
                }

                remaining -= requested

                if remaining != 0 && remaining < requested {
                    requested = remaining
                }

            } catch {

                log("NFC: error while reading multiple blocks #\(blockToRead.hex) - #\((blockToRead + requested - 1).hex) (\(blockToRead)-\(blockToRead + requested - 1)): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")

                retry += 1
                if retry <= retries {
                    AudioServicesPlaySystemSound(1520)    // "pop" vibration
                    log("NFC: retry # \(retry)...")
                    await Task.sleep(250_000_000)

                } else {
                    if sensor.securityGeneration < 2 || taskRequest == .none {
                        session?.invalidate(errorMessage: "Error while reading multiple blocks: \(error.localizedDescription.localizedLowercase)")
                    }
                    throw NFCError.read
                }
            }
        }

        return (start, buffer)
    }


    func readBlocks(from start: Int, count blocks: Int, requesting: Int = 3) async throws -> (Int, Data) {

        if sensor.securityGeneration < 1 {
            debugLog("readBlocks() B3 command not supported by \(sensor.type)")
            throw NFCError.commandNotSupported
        }

        var buffer = Data()

        var remaining = blocks
        var requested = requesting

        while remaining > 0 {

            let blockToRead = start + buffer.count / 8

            var readCommand = NFCCommand(code: 0xB3, parameters: Data([UInt8(blockToRead & 0xFF), UInt8(blockToRead >> 8), UInt8(requested - 1)]))
            if requested == 1 {
                readCommand = NFCCommand(code: 0xB0, parameters: Data([UInt8(blockToRead & 0xFF), UInt8(blockToRead >> 8)]))
            }

            // FIXME: the Libre 3 replies to 'A1 21' with the error code C1

            if sensor.securityGeneration > 1 {
                if blockToRead <= 255 {
                    readCommand = sensor.nfcCommand(.readBlocks, parameters: Data([UInt8(blockToRead), UInt8(requested - 1)]))
                }
            }

            if buffer.count == 0 { debugLog("NFC: sending '\(readCommand.code.hex) \(readCommand.parameters.hex)' custom command (\(sensor.type) read blocks)") }

            do {
                let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: readCommand.code, customRequestParameters: readCommand.parameters)
                let data = Data(output!)

                if sensor.securityGeneration < 2 {
                    buffer += data
                } else {
                    debugLog("'\(readCommand.code.hex) \(readCommand.parameters.hex) \(readCommand.description)' command output (\(data.count) bytes): 0x\(data.hex)")
                    buffer += data.suffix(data.count - 8)    // skip leading 0xA5 dummy bytes
                }
                remaining -= requested

                if remaining != 0 && remaining < requested {
                    requested = remaining
                }

            } catch {

                log(buffer.hexDump(header: "\(sensor.securityGeneration > 1 ? "`A1 21`" : "B0/B3") command output (\(buffer.count/8) blocks):", startingBlock: start))

                if requested == 1 {
                    log("NFC: error while reading block #\(blockToRead.hex): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                } else {
                    log("NFC: error while reading multiple blocks #\(blockToRead.hex) - #\((blockToRead + requested - 1).hex) (\(blockToRead)-\(blockToRead + requested - 1)): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                }
                throw NFCError.readBlocks
            }
        }

        return (start, buffer)
    }


    // Libre 1 only

    func readRaw(_ address: Int, _ bytes: Int) async throws -> (Int, Data) {

        if sensor.type != .libre1 {
            debugLog("readRaw() A3 command not supported by \(sensor.type)")
            throw NFCError.commandNotSupported
        }

        var buffer = Data()
        var remainingBytes = bytes

        while remainingBytes > 0 {

            let addressToRead = address + buffer.count
            let bytesToRead = min(remainingBytes, 24)

            var remainingWords = remainingBytes / 2
            if remainingBytes % 2 == 1 || ( remainingBytes % 2 == 0 && addressToRead % 2 == 1 ) { remainingWords += 1 }
            let wordsToRead = min(remainingWords, 12)   // real limit is 15

            let readRawCommand = NFCCommand(code: 0xA3, parameters: sensor.backdoor + [UInt8(addressToRead & 0xFF), UInt8(addressToRead >> 8), UInt8(wordsToRead)])

            if buffer.count == 0 { debugLog("NFC: sending '\(readRawCommand.code.hex) \(readRawCommand.parameters.hex)' custom command (\(sensor.type) read raw)") }

            do {
                let output = try await connectedTag?.customCommand(requestFlags: .highDataRate, customCommandCode: readRawCommand.code, customRequestParameters: readRawCommand.parameters)
                var data = Data(output!)

                if addressToRead % 2 == 1 { data = data.subdata(in: 1 ..< data.count) }
                if data.count - bytesToRead == 1 { data = data.subdata(in: 0 ..< data.count - 1) }

                buffer += data
                remainingBytes -= data.count

            } catch {
                debugLog("NFC: error while reading \(wordsToRead) words at raw memory 0x\(addressToRead.hex): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                throw NFCError.customCommandError
            }
        }

        return (address, buffer)

    }


    // Libre 1 only: overwrite mirrored FRAM blocks

    func writeRaw(_ address: Int, _ data: Data) async throws {

        if sensor.type != .libre1 {
            debugLog("FRAM overwriting not supported by \(sensor.type)")
            throw NFCError.commandNotSupported
        }

        do {

            try await send(sensor.unlockCommand)

            let addressToRead = (address / 8) * 8
            let startOffset = address % 8
            let endAddressToRead = ((address + data.count - 1) / 8) * 8 + 7
            let blocksToRead = (endAddressToRead - addressToRead) / 8 + 1

            let (readAddress, readData) = try await readRaw(addressToRead, blocksToRead * 8)
            var msg = readData.hexDump(header: "NFC: blocks to overwrite:", address: readAddress)
            var bytesToWrite = readData
            bytesToWrite.replaceSubrange(startOffset ..< startOffset + data.count, with: data)
            msg += "\(bytesToWrite.hexDump(header: "\nwith blocks:", address: addressToRead))"
            debugLog(msg)

            let startBlock = addressToRead / 8
            let blocks = bytesToWrite.count / 8

            if address >= 0xF860 {    // write to FRAM blocks

                let requestBlocks = 2    // 3 doesn't work

                let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
                let remainder = blocks % requestBlocks
                var blocksToWrite = [Data](repeating: Data(), count: blocks)

                for i in 0 ..< blocks {
                    blocksToWrite[i] = Data(bytesToWrite[i * 8 ... i * 8 + 7])
                }

                for i in 0 ..< requests {

                    let startIndex = startBlock - 0xF860 / 8 + i * requestBlocks
                    let endIndex = startIndex + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)
                    let blockRange = NSRange(startIndex ... endIndex)

                    var dataBlocks = [Data]()
                    for j in startIndex ... endIndex { dataBlocks.append(blocksToWrite[j - startIndex]) }

                    do {
                        try await connectedTag?.writeMultipleBlocks(requestFlags: .highDataRate, blockRange: blockRange, dataBlocks: dataBlocks)
                        debugLog("NFC: wrote blocks 0x\(startIndex.hex) - 0x\(endIndex.hex) \(dataBlocks.reduce("", { $0 + $1.hex })) at 0x\(((startBlock + i * requestBlocks) * 8).hex)")
                    } catch {
                        log("NFC: error while writing multiple blocks 0x\(startIndex.hex)-0x\(endIndex.hex) \(dataBlocks.reduce("", { $0 + $1.hex })) at 0x\(((startBlock + i * requestBlocks) * 8).hex): \(error.localizedDescription)")
                        throw NFCError.write
                    }
                }
            }

            try await send(sensor.lockCommand)

        } catch {

            // TODO: manage errors

            debugLog(error.localizedDescription)
        }

    }


    // TODO: write any Data size, not just a block

    func write(fromBlock startBlock: Int, _ data: Data) async throws {

        let startIndex = startBlock
        let endIndex = startIndex
        let blockRange = NSRange(startIndex ... endIndex)
        let dataBlocks = [data]
        
        do {
            try await connectedTag?.writeMultipleBlocks(requestFlags: .highDataRate, blockRange: blockRange, dataBlocks: dataBlocks)
            debugLog("NFC: wrote blocks 0x\(startIndex.hex) - 0x\(endIndex.hex) \(dataBlocks.reduce("", { $0 + $1.hex }))")
        } catch {
            log("NFC: error while writing multiple blocks 0x\(startIndex.hex)-0x\(endIndex.hex) \(dataBlocks.reduce("", { $0 + $1.hex }))")
            throw NFCError.write
        }

    }

#endif    // !targetEnvironment(macCatalyst)

}

#endif    // !os(watchOS)
