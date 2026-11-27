import Foundation
import UfuqCore

// Claude Code hook: stdin JSON -> state file. Silent, always exit 0.
let input = FileHandle.standardInput.readDataToEndOfFile()
let environment = ProcessInfo.processInfo.environment
AgentStateStore(environment: environment).apply(stdin: input, now: Date(), environment: environment)
exit(0)
