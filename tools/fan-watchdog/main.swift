import Foundation
import Darwin

guard CommandLine.arguments.count == 4,
      let parentPID = Int32(CommandLine.arguments[1]),
      let fanCount = Int(CommandLine.arguments[2]) else { exit(2) }

let helper = CommandLine.arguments[3]
while kill(parentPID, 0) == 0 { sleep(3) }

for index in 0..<fanCount {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    task.arguments = ["-n", helper, "auto", "\(index)"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
}
