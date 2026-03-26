import AppKit

/// Opens or focuses a Terminal.app window running Claude Code in the given directory.
enum TerminalOpener {

    static func open(cwd: String) {
        let escapedDir = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            set found to false
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t is not "" then
                            set tabProcs to processes of t
                            repeat with p in tabProcs
                                if p contains "claude" then
                                    set selected tab of w to t
                                    set index of w to 1
                                    set found to true
                                    exit repeat
                                end if
                            end repeat
                        end if
                    end try
                    if found then exit repeat
                end repeat
                if found then exit repeat
            end repeat
            if not found then
                do script "cd \(escapedDir)"
            end if
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppState.log("Open terminal failed: \(error)")
                let fallback = "tell application \"Terminal\" to activate"
                NSAppleScript(source: fallback)?.executeAndReturnError(nil)
            }
        }
    }
}
