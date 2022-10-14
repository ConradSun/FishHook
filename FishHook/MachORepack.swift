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
    private func injectDylib(is64bit: Bool) -> Bool {
        guard let fileHandle = FileHandle(forWritingAtPath: binaryPath) else {
            print("File to create handler for binary file.")
            return false
        }
        
        let pathSize = (dylibPath.count & ~(pathPadding - 1)) + pathPadding
        let cmdSize = MemoryLayout<dylib_command>.size + pathSize
        var cmdOffset = 0
        var dylibCmd = dylib_command()
        
        if is64bit {
            cmdOffset = MemoryLayout<mach_header_64>.size
        }
        else {
            cmdOffset = MemoryLayout<mach_header>.size
        }
        
        dylibCmd.cmd = UInt32(LC_LOAD_DYLIB)
        dylibCmd.cmdsize = UInt32(cmdSize)
        dylibCmd.dylib.name = lc_str(offset: UInt32(MemoryLayout<dylib_command>.size))
        
        let result = machOData.withUnsafeBytes { pointer -> Bool in
            guard let header = pointer.bindMemory(to: mach_header.self).baseAddress else {
                print("File to get mach header pointer.")
                return false
            }
            
            print("ncmds: \(header.pointee.ncmds), sizeofcmds: \(header.pointee.sizeofcmds).")
            
            try? fileHandle.seek(toOffset: UInt64(cmdOffset) + UInt64(header.pointee.sizeofcmds))
            fileHandle.write(Data(bytes: &dylibCmd, count: MemoryLayout<dylib_command>.size))
            fileHandle.write(dylibPath.data(using: .utf8)!)
            
            var newHeader = header.pointee
            newHeader.ncmds = newHeader.ncmds + 1
            newHeader.sizeofcmds = newHeader.sizeofcmds + UInt32(cmdSize)
            try? fileHandle.seek(toOffset: 0)
            fileHandle.write(Data(bytes: &newHeader, count: MemoryLayout<mach_header>.size))
            return true
        }
        
        try? fileHandle.close()
        signAdhoc()
        return result
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
                print("File to get fat header pointer.")
                return false
            }
            
            switch header.pointee.magic {
            case FAT_MAGIC, FAT_CIGAM:
                print("Unsupport mutiple platform.")
                return false
            case MH_MAGIC_64, MH_CIGAM_64:
                return injectDylib(is64bit: true)
            case MH_MAGIC, MH_CIGAM:
                return injectDylib(is64bit: false)
            default:
                return false
            }
        }
    }
}
