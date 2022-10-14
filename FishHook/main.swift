//
//  main.swift
//  DylibInject
//
//  Created by ConradSun on 2022/10/12.
//

import Foundation

func main() {
    guard CommandLine.argc > 1, #available(macOS 10.15, *) else {
        return
    }
    let filePath = CommandLine.arguments[1]
    let libPath = "/usr/local/lib/libinject.dylib"
    
    let repack = MachORepack()
    if repack.initWithFile(filePath: filePath, libPath: libPath) {
        _ = repack.repackBinary()
    }
}

main()
