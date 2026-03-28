import AppKit

/// Opens or focuses a Terminal.app window running Claude Code.
/// Matches by window title (set during Spawn) or by cwd via process lookup.
enum TerminalOpener {

    /// Focus the Terminal window for the given cwd.
    /// Strategy:
    ///   1. Match window custom title containing the cwd's last path component
    ///   2. Match any tab running a claude process
    ///   3. Fallback: just activate Terminal
    static func open(cwd: String) {
        // Extract meaningful identifier from cwd for title matching
        // e.g. ~/my-project -> "my-project", ~/work/webapp -> "webapp"
        let cwdName = URL(fileURLWithPath: cwd).lastPathComponent

        let script = """
        tell application "Terminal"
            activate
            set matched to false

            -- Pass 1: match custom title containing the directory name
            repeat with w in windows
                try
                    if custom title of w contains "\(cwdName)" then
                        set index of w to 1
                        set matched to true
                        exit repeat
                    end if
                end try
            end repeat

            -- Pass 2: if no match, try matching by tab processes
            if not matched then
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            set tabProcs to processes of t
                            repeat with p in tabProcs
                                if p contains "claude" then
                                    -- Found a claude tab, focus it
                                    set selected tab of w to t
                                    set index of w to 1
                                    set matched to true
                                    exit repeat
                                end if
                            end repeat
                        end try
                        if matched then exit repeat
                    end repeat
                    if matched then exit repeat
                end repeat
            end if
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppState.log("Open terminal failed: \(error)")
                // Fallback: just activate Terminal
                NSAppleScript(source: "tell application \"Terminal\" to activate")?.executeAndReturnError(nil)
            }
        }
    }
}
