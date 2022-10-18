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
    private let pathPadding = 8
    private var machOData = Data()
    private var binaryPath = String()
    private var dylibPath = String()
    
    private func signAdhoc() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-f", "-s", "-", binaryPath]
        try? task.run()
    }
    
    private func injectDylib(header: mach_header, offset: UInt64, is64bit: Bool) -> Bool {
        guard let fileHandle = FileHandle(forWritingAtPath: binaryPath) else {
            print("Failed to create handler for binary file.")
            return false
        }
        
        let pathSize = (dylibPath.count & ~(pathPadding - 1)) + pathPadding
        let cmdSize = MemoryLayout<dylib_command>.size + pathSize
        var cmdOffset: UInt64 = 0
        var dylibCmd = dylib_command()
        
        if is64bit {
            cmdOffset = offset + UInt64(MemoryLayout<mach_header_64>.size)
        }
        else {
            cmdOffset = offset + UInt64(MemoryLayout<mach_header>.size)
        }
        
        dylibCmd.cmd = UInt32(LC_LOAD_DYLIB)
        dylibCmd.cmdsize = UInt32(cmdSize)
        dylibCmd.dylib.name = lc_str(offset: UInt32(MemoryLayout<dylib_command>.size))
        
        try? fileHandle.seek(toOffset: cmdOffset + UInt64(header.sizeofcmds))
        fileHandle.write(Data(bytes: &dylibCmd, count: MemoryLayout<dylib_command>.size))
        fileHandle.write(dylibPath.data(using: .utf8)!)
        
        var newHeader = header
        newHeader.ncmds = newHeader.ncmds + 1
        newHeader.sizeofcmds = newHeader.sizeofcmds + UInt32(cmdSize)
        try? fileHandle.seek(toOffset: offset)
        fileHandle.write(Data(bytes: &newHeader, count: MemoryLayout<mach_header>.size))
        
        try? fileHandle.close()
        return true
    }
    
    private func processThinMachO(offset: Int) -> Bool {
        let thinData = machOData.advanced(by: offset)
        return thinData.withUnsafeBytes { pointer in
            guard let header = pointer.bindMemory(to: mach_header.self).baseAddress else {
                print("Failed to get mach header pointer.")
                return false
            }
            
            switch header.pointee.magic {
            case MH_MAGIC_64, MH_CIGAM_64:
                return injectDylib(header: header.pointee, offset: UInt64(offset), is64bit: true)
            case MH_MAGIC, MH_CIGAM:
                return injectDylib(header: header.pointee, offset: UInt64(offset), is64bit: false)
            default:
                print("Unknown MachO format.")
                return false
            }
        }
    }
    
    private func processFatMachO(offset: Int) -> Bool {
        let fatData = machOData.advanced(by: offset)
        return fatData.withUnsafeBytes { pointer in
            guard let arch = pointer.bindMemory(to: fat_arch.self).baseAddress else {
                print("Failed to get fat arch pointer.")
                return false
            }
            
            let offset = _OSSwapInt32(arch.pointee.offset)
            return processThinMachO(offset: Int(offset))
        }
    }
    
    func initWithFile(filePath: String, libPath: String) -> Bool {
        if !FileManager.default.isExecutableFile(atPath: filePath) {
            print("File to be modified is not Executable.")
            return false
        }
        guard let data = FileManager.default.contents(atPath: filePath) else {
            print("Failed to obtain contents for file.")
            return false
        }
        
        binaryPath = filePath
        dylibPath = libPath
        machOData = data
        return true
    }
    
    func repackBinary() -> Bool {
        if machOData.isEmpty {
            return false
        }
        
        return machOData.withUnsafeBytes { pointer in
            guard let header = pointer.bindMemory(to: fat_header.self).baseAddress else {
                print("Failed to get fat header pointer.")
                return false
            }
            
            var result = false
            var offset = MemoryLayout<fat_header>.size
            let archNum = _OSSwapInt32(header.pointee.nfat_arch)
            
            switch header.pointee.magic {
            case FAT_MAGIC, FAT_CIGAM:
                if archNum == 0 {
                    print("Format of Fat-MachO is invalid.")
                    return false
                }
                
                for i in 0 ..< archNum {
                    if i > 0 {
                        offset = offset + MemoryLayout<fat_arch>.size
                    }
                    result = processFatMachO(offset: offset)
                    if !result {
                        return false
                    }
                }
            case MH_MAGIC_64, MH_CIGAM_64, MH_MAGIC, MH_CIGAM:
                result = processThinMachO(offset: 0)
            default:
                print("Unknown MachO format.")
                return false
            }
            
            signAdhoc()
            return result
        }
    }
}
