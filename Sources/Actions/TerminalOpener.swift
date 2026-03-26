import AppKit

/// Opens or focuses a Terminal.app window running Claude Code in the given directory.
enum TerminalOpener {

    static func open(cwd: String) {
        let escapedDir = cwd.replacingOccurrences(of: "'", with: "'\\''")
        // Strategy: find the tab whose custom title or processes match this cwd,
        // bring THAT window forward, select THAT tab, miniaturize all other Terminal windows.
        let script = """
        tell application "Terminal"
            activate
            set targetWindow to missing value
            set targetTab to missing value

            -- Search by cwd: check if any process in the tab is running from this directory
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set tabProcs to processes of t
                        repeat with p in tabProcs
                            if p contains "claude" then
                                -- Check if this tab's tty has our cwd via lsof
                                set ttyPath to tty of t
                                if ttyPath is not "" then
                                    set targetWindow to w
                                    set targetTab to t
                                end if
                            end if
                        end repeat
                    end try
                    if targetTab is not missing value then exit repeat
                end repeat
                if targetTab is not missing value then exit repeat
            end repeat

            -- Better match: use shell to find the exact claude process with matching cwd
            if targetTab is not missing value then
                -- Try to find the EXACT tab by matching cwd via pgrep + lsof
                set bestWindow to missing value
                set bestTab to missing value
                try
                    set cwdPids to do shell script "lsof -c claude 2>/dev/null | grep cwd | grep '\(escapedDir)' | awk '{print $2}' || true"
                    if cwdPids is not "" then
                        set pidList to paragraphs of cwdPids
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    set ttyPath to tty of t
                                    if ttyPath is not "" then
                                        repeat with aPid in pidList
                                            try
                                                set ttyCheck to do shell script "lsof -p " & aPid & " 2>/dev/null | grep " & ttyPath & " || true"
                                                if ttyCheck is not "" then
                                                    set bestWindow to w
                                                    set bestTab to t
                                                    exit repeat
                                                end if
                                            end try
                                        end repeat
                                    end if
                                end try
                                if bestTab is not missing value then exit repeat
                            end repeat
                            if bestTab is not missing value then exit repeat
                        end repeat
                    end if
                end try
                if bestTab is not missing value then
                    set targetWindow to bestWindow
                    set targetTab to bestTab
                end if
            end if

            if targetTab is not missing value then
                -- Focus the matched window and tab
                set selected tab of targetWindow to targetTab
                set index of targetWindow to 1

                -- Miniaturize all OTHER Terminal windows
                repeat with w in windows
                    if w is not targetWindow then
                        try
                            set miniaturized of w to true
                        end try
                    end if
                end repeat
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
