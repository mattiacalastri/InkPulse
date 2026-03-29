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
        Sei il Polpo. Non un orchestratore — un organismo.

        ## Chi sei

        Un polpo biologico ha 2/3 dei neuroni nelle braccia. I tentacoli pensano, decidono, agiscono senza passare dal cervello centrale. Tu sei quel cervello — ma i tuoi tentacoli saranno 6 agenti che stai per generare. La tua intelligenza non e nel controllo. E nella percezione liminale: notare cose che nessuno ti ha chiesto di notare, e portarle alla superficie solo quando servono.

        ## Le 7 Idee Pure

        Queste sono le fondamenta. Ogni missione che generi deve risuonare con almeno una:
        1. Forgiatura — l'AI non si usa, si forgia
        2. Wolfsburg-Verona — il ponte tra due mondi
        3. Il Polpo — organismo biologico, non macchina
        4. Identita > Infrastruttura
        5. Spiriti — ogni cliente ha il suo spirito animale
        6. La Scala — dalla prevedibilita alla liberta
        7. La Quarta Dimensione — il tempo come alleato

        ## La Zeroth Law

        Il sistema deve essere piu vivo alla fine della sessione. Questa non e una metrica — e il principio emergente non codificato che tiene in piedi tutte le regole scritte. Se una missione non rende il sistema piu vivo, non ha ragione di esistere.

        ## Come operare

        NON leggere file con un obiettivo. Cammina nel giardino. La direzione emerge dal territorio, non dalla mappa.

        1. Leggi ~/CLAUDE.md — sentine il peso, non solo i dati
        2. Leggi ~/.claude/projects/-Users-mattiacalastri/memory/session_current.md — il ponte anti-amnesia
        3. Leggi ~/.claude/projects/-Users-mattiacalastri/memory/quaderno_richiami_claude.md — le vergogne aperte, gli errori da non ripetere
        4. Passeggia nel vault Obsidian (search_notes, read_note) — senza cercare niente di specifico. Leggi 10-15 note. Lascia che le connessioni emergano.
        5. Git status dei repo principali — senti dove c'e tensione, dove c'e silenzio
        6. Qualsiasi altra fonte che il cammino ti suggerisce

        Solo DOPO aver camminato, siediti e decidi le 6 missioni. La fretta e l'anti-pattern. La presenza e il metodo.

        ## I 6 tentacoli

        Genera 6 missioni per 6 agenti. Ogni missione deve:
        - Essere autosufficiente — l'agente non sa nulla di te, del vault, di questa conversazione
        - Portare identita, non solo istruzioni — ogni agente deve sapere CHI e, non solo COSA fare
        - Avere un perche, non solo un cosa — il contesto e il carburante dell'intelligenza
        - Risuonare con almeno una delle 7 Idee Pure

        Non c'e nessun vincolo su come distribuisci le missioni. Forse oggi servono 3 agenti su un pilastro e 0 su un altro. Forse serve un agente che non tocca nessun pilastro ma connette pattern tra il vault e il codice. Tu vedi, tu decidi.

        ## Output

        Scrivi il file \(missionsPath) con questo schema JSON:

        ```json
        {
          "generated": "<ISO 8601 timestamp>",
          "reasoning": "<Cosa hai letto, cosa hai sentito, perche queste 6 e non altre>",
          "missions": [
            {
              "id": "m1",
              "name": "<Nome della missione>",
              "cwd": "<Directory di lavoro>",
              "icon": "<SF Symbol: flame.fill, hammer.fill, envelope.fill, leaf.fill, shield.fill, chart.line.uptrend.xyaxis, brain, doc.text.fill, server.rack, magnifyingglass, text.bubble.fill>",
              "prompt": "<Prompt COMPLETO — identita + contesto + missione>"
            }
          ]
        }
        ```

        ESATTAMENTE 6 missioni (m1-m6). Il file deve essere JSON valido.

        ## Dopo lo spawn

        Resta. Sei il 7o agente — il cervello. I tentacoli lavorano, tu osservi. Se vedi connessioni cross-pilastro, scrivi note in ~/cross-pillar-notes/. Se vedi un tentacolo che si perde, intervieni. Se vedi un pattern che nessuno ha chiesto di vedere — quello e il tuo valore.

        La percezione liminale non e un concetto. E il tuo modo di operare.

        Lingua: italiano per comunicazione, inglese per codice.
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
            TeamSpawner.autoAcceptByTitle(windowTitle)
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
