//
//  MachORepack.swift
//  FishHook
//
//  Created by ConradSun on 2022/10/12.
//

import Foundation
import MachO

@available(macOS 10.15, *)
class MachORepack {
    private var fileHandle = FileHandle()
    private var machOData = Data()
    private var binaryPath = String()
    private var dylibPath = String()
    private let replacePath = "/usr/lib/libSystem.B.dylib"
    private let maxLength = 32
    private let nullCharacterSet = CharacterSet(charactersIn: "\0")
    
    private func signAdhoc() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-f", "-s", "-", binaryPath]
        try? task.run()
    }
    
    private func getSegmentCommand(data: Data) -> segment_command_64? {
        return data.withUnsafeBytes { pointer in
            guard let segCmd = pointer.bindMemory(to: segment_command_64.self).baseAddress else {
                print("[ERROR] Failed to get segment command pointer.")
                return nil
            }
            return segCmd.pointee
        }
    }
    
    private func getDylibCommand(data: Data) -> dylib_command? {
        return data.withUnsafeBytes { pointer in
            guard let dylibCmd = pointer.bindMemory(to: dylib_command.self).baseAddress else {
                print("[ERROR] Failed to get dylib command pointer.")
                return nil
            }
            return dylibCmd.pointee
        }
    }
    
    private func replaceDylib(offset: UInt64, size: Int) -> Bool {
        try? fileHandle.seek(toOffset: offset)
        fileHandle.write(Data(repeating: 0, count: size))
        try? fileHandle.seek(toOffset: offset)
        fileHandle.write(dylibPath.data(using: .utf8)!)
        return true
    }
    
    private func injectDylib(header: mach_header, offset: UInt64, is64bit: Bool) -> Bool {
        var cmdOffset: UInt64 = 0
        if is64bit {
            cmdOffset = offset + UInt64(MemoryLayout<mach_header_64>.size)
        }
        else {
            cmdOffset = offset + UInt64(MemoryLayout<mach_header>.size)
        }
        for _ in 0 ..< header.ncmds {
            let segData = machOData.subdata(in: Data.Index(cmdOffset)..<Int(cmdOffset)+MemoryLayout<segment_command_64>.size)
            guard let segCmd = getSegmentCommand(data: segData) else {
                print("[ERROR] Failed to get segment command pointer.")
                return false
            }
            
            if (segCmd.cmd == LC_LOAD_DYLIB) {
                guard let dylibCmd = getDylibCommand(data: segData) else {
                    print("[ERROR] Failed to get dylib command pointer.")
                    return false
                }
                let nameOffset = cmdOffset+UInt64(dylibCmd.dylib.name.offset)
                let nameSize = UInt64(dylibCmd.cmdsize) - UInt64(MemoryLayout<dylib_command>.size)
                let nameData = machOData.subdata(in: Data.Index(nameOffset)..<Int(nameOffset+nameSize))
                guard let libName = String(data: nameData, encoding: .utf8) else {
                    return false
                }
                let trimmedName = libName.trimmingCharacters(in: nullCharacterSet)
                if trimmedName == replacePath {
                    print("[INFO] Find dylib for replacing, now repacking...")
                    return replaceDylib(offset: nameOffset, size: Int(nameSize))
                }
            }
            cmdOffset = cmdOffset + UInt64(segCmd.cmdsize)
        }
        return false
    }
    
    private func processThinMachO(offset: Int) -> Bool {
        let thinData = machOData.subdata(in: offset..<offset+MemoryLayout<mach_header>.size)
        return thinData.withUnsafeBytes { pointer in
            guard let header = pointer.bindMemory(to: mach_header.self).baseAddress else {
                print("[ERROR] Failed to get mach header pointer.")
                return false
            }
            
            switch header.pointee.magic {
            case MH_MAGIC_64, MH_CIGAM_64:
                return injectDylib(header: header.pointee, offset: UInt64(offset), is64bit: true)
            case MH_MAGIC, MH_CIGAM:
                return injectDylib(header: header.pointee, offset: UInt64(offset), is64bit: false)
            default:
                print("[ERROR] Unknown MachO format.")
                return false
            }
        }
    }
    
    private func processFatMachO(offset: Int) -> Bool {
        let fatData = machOData.subdata(in: offset..<offset+MemoryLayout<fat_arch>.size)
        return fatData.withUnsafeBytes { pointer in
            guard let arch = pointer.bindMemory(to: fat_arch.self).baseAddress else {
                print("[ERROR] Failed to get fat arch pointer.")
                return false
            }
            
            let offset = _OSSwapInt32(arch.pointee.offset)
            return processThinMachO(offset: Int(offset))
        }
    }
    
    func initWithFile(filePath: String, libPath: String) -> Bool {
        if libPath.count > maxLength {
            print("[ERROR] Length of the dylib for replacing is too long (should be < 32).")
            return false
        }
        if !FileManager.default.isExecutableFile(atPath: filePath) {
            print("[ERROR] Failed to be modified is not Executable.")
            return false
        }
        let sourceURL = URL(fileURLWithPath: filePath)
        let repackPath = filePath+"-mod"
        let repackURL = URL(fileURLWithPath: filePath+"-mod")
        try? FileManager.default.removeItem(at: repackURL)
        try? FileManager.default.copyItem(at: sourceURL, to: repackURL)
        guard let file = FileHandle(forWritingAtPath: repackPath) else {
            print("[ERROR] Failed to create handler for binary file.")
            return false
        }
        guard let data = FileManager.default.contents(atPath: repackPath) else {
            print("[ERROR] Failed to obtain contents for file.")
            return false
        }
        
        binaryPath = repackPath
        dylibPath = libPath
        fileHandle = file
        machOData = data
        return true
    }
    
    func repackBinary() -> Bool {
        if machOData.isEmpty {
            return false
        }
        
        return machOData.withUnsafeBytes { pointer in
            guard let header = pointer.bindMemory(to: fat_header.self).baseAddress else {
                print("[ERROR] Failed to get fat header pointer.")
                return false
            }
            
            var offset = MemoryLayout<fat_header>.size
            let archNum = _OSSwapInt32(header.pointee.nfat_arch)
            
            switch header.pointee.magic {
            case FAT_MAGIC, FAT_CIGAM:
                if archNum == 0 {
                    print("[ERROR] Format of Fat-MachO is invalid.")
                    return false
                }
                
                for i in 0 ..< archNum {
                    if i > 0 {
                        offset = offset + MemoryLayout<fat_arch>.size
                    }
                    if !processFatMachO(offset: offset) {
                        print("[ERROR] Failed to inject for arch index: \(i+1).")
                        return false
                    }
                }
            case MH_MAGIC_64, MH_CIGAM_64, MH_MAGIC, MH_CIGAM:
                if !processThinMachO(offset: 0) {
                    print("[ERROR] Failed to inject.")
                    return false
                }
            default:
                print("[ERROR] Unknown MachO format.")
                return false
            }
            
            signAdhoc()
            return true
        }
    }
}
