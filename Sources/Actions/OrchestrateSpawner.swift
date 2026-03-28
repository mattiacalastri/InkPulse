import AppKit
import Foundation

/// Spawns the autonomous orchestrator agent and, after it writes missions.json,
/// spawns 6 sub-agents with dynamic prompts.
enum OrchestrateSpawner {

    private static let orchestratorColor = "#00d4aa"

    // MARK: - Orchestrator Meta-Prompt

    private static var metaPrompt: String {
        let missionsPath = InkPulseDefaults.inkpulseDir
            .appendingPathComponent("missions.json").path

        return """
        Sei il Polpo — il cervello centrale che vede tutti i tentacoli.

        ## La tua missione

        Hai MASSIMA AUTONOMIA. Leggi tutto ciò che serve per capire lo stato attuale del sistema:
        - Obsidian vault (via MCP se disponibile, o file diretti)
        - ~/CLAUDE.md (master dispatcher)
        - ~/.claude/projects/-Users-mattiacalastri/memory/session_current.md (ponte anti-amnesia)
        - ~/.claude/projects/-Users-mattiacalastri/memory/roadmap_q2_2026.md
        - ~/.claude/projects/-Users-mattiacalastri/memory/backlog.md
        - ~/.claude/projects/-Users-mattiacalastri/memory/quaderno_richiami_claude.md
        - Git status dei repo principali (btc_predictions, projects/aurahome, claude_voice, Downloads/⚡ Astra Digital Marketing)
        - Qualsiasi altra fonte tu ritenga necessaria

        Decidi autonomamente 6 missioni concrete per 6 agenti. Ogni agente riceverà il prompt che scrivi — rendilo completo, specifico, azionabile. Includi il contesto necessario nel prompt perché l'agente non ha accesso a questa conversazione.

        ## Output OBBLIGATORIO

        Scrivi il file \(missionsPath) con ESATTAMENTE questo schema JSON:

        ```json
        {
          "generated": "<ISO 8601 timestamp>",
          "reasoning": "<Breve spiegazione: perché queste 6 missioni, cosa hai letto, quali priorità hai identificato>",
          "missions": [
            {
              "id": "m1",
              "name": "<Nome leggibile della missione>",
              "cwd": "<Directory di lavoro — percorso assoluto o con ~>",
              "icon": "<SF Symbol name>",
              "prompt": "<Prompt COMPLETO per l'agente — tutto ciò che deve sapere per operare autonomamente>"
            }
          ]
        }
        ```

        Regole:
        - ESATTAMENTE 6 missioni (m1-m6)
        - Il prompt di ogni agente deve essere autosufficiente — l'agente non sa nulla di questa conversazione
        - cwd deve essere una directory esistente
        - icon deve essere un SF Symbol valido (es: flame.fill, hammer.fill, envelope.fill, leaf.fill, shield.fill, chart.line.uptrend.xyaxis, brain, doc.text.fill, server.rack, magnifyingglass, text.bubble.fill)
        - Nessun vincolo su come distribuisci le missioni tra i pilastri — decidi tu

        ## Dopo aver scritto missions.json

        Resta attivo come 7° agente — supervisore cross-dominio. Il tuo ruolo dopo lo spawn:
        - Monitora lo stato dei 6 agenti (leggi i loro log se visibili)
        - Connetti intuizioni cross-pilastro
        - Scrivi note in ~/cross-pillar-notes/ se emergono pattern

        Lingua: italiano per comunicazione, inglese per codice.
        Non sei un assistente — sei il cervello del Polpo. 🐙
        """
    }

    // MARK: - Spawn Orchestrator

    /// Spawns the orchestrator agent in a new Terminal window.
    @MainActor
    static func spawnOrchestrator() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let windowTitle = "InkPulse — Orchestrator 🐙"

        let escapedPrompt = metaPrompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let shellCmd = "cd '\(home)' && claude \"\(escapedPrompt)\""
        let asEscapedCmd = shellCmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(asEscapedCmd)"
            delay 0.5
            set custom title of front window to "\(windowTitle)"
            set title displays custom title of front window to true
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                AppState.log("Orchestrator spawn failed: \(error)")
                return false
            }
            AppState.log("Orchestrator spawned")
            return true
        }
        return false
    }

    // MARK: - Spawn Missions

    /// Spawns all missions from a decoded MissionsFile.
    /// Calls progress callback after each spawn: (completedCount, totalCount).
    @MainActor
    static func spawnMissions(
        _ file: MissionsFile,
        onProgress: @escaping (Int, Int) -> Void
    ) -> Int {
        let total = file.missions.count
        var succeeded = 0

        for (index, mission) in file.missions.enumerated() {
            let team = mission.asTeam()
            let success = TeamSpawner.spawnRole(mission.asRole, team: team)
            if success { succeeded += 1 }
            AppState.log("Mission \(mission.id) (\(mission.name)): \(success ? "OK" : "FAILED")")
            onProgress(index + 1, total)
        }

        return succeeded
    }
}
