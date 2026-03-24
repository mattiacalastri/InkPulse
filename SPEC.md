# InkPulse v1.1 — Feature Batch Spec
> Intervista: sess.460, 24 Mar 2026
> Stato: SPEC PRONTA — implementare in sessione separata

---

## Obiettivo

Aggiungere 5 feature a InkPulse per trasformarlo da monitor passivo a cockpit operativo.
Ogni feature è indipendente e può essere implementata in isolamento.

---

## Feature 1: Context Window %

### Cosa
Mostrare la percentuale di context window utilizzata per ogni sessione, sia nella SessionRowView che nell'header aggregato.

### Calcolo
```
contextUsed = inputTokens + cacheReadInputTokens + cacheCreationInputTokens
contextPercent = contextUsed / contextLimit * 100
```
Dove `contextUsed` viene dall'ultimo `assistant` event (campo `usage` nel JSONL).

### Context Limits — Configurabili
Aggiungere a `InkPulseConfig` / `config.json`:
```json
{
  "context_limits": {
    "claude-opus-4": 200000,
    "claude-opus-4-6[1m]": 1000000,
    "claude-sonnet-4": 200000,
    "claude-haiku-3.5": 200000
  }
}
```
Default hardcoded in `Constants.swift`. L'utente può override da Config panel.

Logica matching: se il model string dell'evento contiene una key della tabella, usa quel limite. Fallback: 200000.

### Dove appare
1. **Header stats grid** — nuova colonna `ctx` dopo `cost`, mostra media aggregata
2. **SessionRowView** — progress bar piccola (50px) accanto all'health bar, con % numerica

### Stato in SessionMetrics
Nuovo campo:
```swift
private(set) var lastContextTokens: Int = 0  // aggiornato ad ogni assistant event
```

### Colori
- Verde (#00d4aa): < 60%
- Arancione (#FFA500): 60-85%
- Rosso (#FF4444): > 85%

---

## Feature 2: Ultimo Tool + Task Name

### Cosa
Mostrare nella SessionRowView l'ultimo tool usato e (se disponibile) il nome del task attivo.

### Dati dal JSONL
- **Ultimo tool**: già tracciato in `toolNameEvents` di SessionMetrics. Serve solo esporre l'ultimo.
- **Task name**: estrarre da eventi `progress` dove `data` contiene `TaskCreate` o `TaskUpdate` con un subject. Parsing best-effort con string scan (come già fatto per `cwd`).

### Stato in SessionMetrics
Nuovi campi:
```swift
private(set) var lastToolName: String?      // es. "Edit", "Bash", "Read"
private(set) var lastToolTarget: String?    // es. "LiveTab.swift" (dal tool_use content, se disponibile)
private(set) var activeTaskName: String?    // es. "Add context window %" (da TaskCreate/TaskUpdate)
```

Per `lastToolTarget`: dal content block `tool_use`, estrarre il primo argomento (file_path, command, pattern). Troncarlo a 30 char. Best-effort, non critico.

### UI
Terza riga nella SessionRowView, sotto `status · uptime`:
```
Edit: LiveTab.swift · Task: Add context %
```
Font: `.system(size: 9, design: .monospaced)`, colore `.white.opacity(0.3)`.
Se non c'è task, mostra solo il tool. Se non c'è nemmeno il tool, nascondi la riga.

### Vincolo
**MAI mostrare contenuto dei messaggi user/assistant.** Solo nome tool + primo argomento (path/command).

---

## Feature 3: Kill Session

### Cosa
Bottone per terminare una sessione Claude stalled.

### Workflow
1. Utente clicca icona ☠️ (o `xmark.circle`) sulla SessionRowView
2. Alert di conferma: "Terminare sessione [nome]? (PID [pid])"
3. Se conferma: SIGTERM al processo
4. Se dopo 5s il processo è ancora vivo: SIGKILL
5. UI aggiorna automaticamente (il session timeout la rimuoverà)

### Trovare il PID
Nuovo file `Sources/Actions/ProcessResolver.swift`:
```swift
// Esegue: ps -eo pid,tty,lstart,command | grep "claude$"
// Matcha per sessionId → cwd → TTY
// Restituisce Optional<pid_t>
```
Approccio:
1. `Process()` esegue `ps -eo pid,tty,command`
2. Filtra righe che finiscono con `claude`
3. Per ogni PID, controlla cwd via `lsof -p PID | grep cwd`
4. Matcha con `sessionCwds[sessionId]`

Se non riesce a trovare il PID → disabilita il bottone con tooltip "PID not found".

### Kill
```swift
kill(pid, SIGTERM)
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    // check if still alive
    if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
}
```

### Vincolo
**MAI killare senza conferma.** Il bottone è sempre dietro un `.alert()`.

### UI
- Icona `xmark.circle.fill` rossa, visibile solo nel pannello espanso della SessionRowView
- Disabilitata se PID non trovato

---

## Feature 4: Daily Cost Budget

### Cosa
Budget giornaliero configurabile con progress bar e notifica.

### Config
Aggiungere a `InkPulseConfig`:
```json
{
  "daily_budget_eur": 0,
  "budget_alert_thresholds": [0.8, 1.0]
}
```
Default `0` = disabilitato. Configurabile dal Config panel.

### Calcolo
Somma `costEUR` di tutte le sessioni attive + costi da heartbeat records di oggi.

### UI — Header
Se budget > 0, mostra progress bar sotto la stats grid:
```
DAILY BUDGET                     €3.20 / €10.00
██████████████░░░░░░░░░░░░░░░░░░  32%
```
Colori: verde < 60%, arancione 60-80%, rosso > 80%.

### Notifiche
- Al superamento di ogni threshold (80%, 100%): notifica macOS via `NotificationManager`
- Cooldown: 1 notifica per threshold per giorno (usa un `Set<Double>` in memoria)

### Vincolo
**Budget alert = solo notifica, MAI killare sessioni automaticamente.**

### Nessun persistent state extra
Il budget speso si calcola live dai heartbeat files di oggi. Non serve salvare nulla di nuovo.

---

## Feature 5: Sound on Anomaly

### Cosa
Suono di sistema quando scatta un'anomaly critica.

### Implementazione
In `AnomalyWatcher.swift`, dopo `notificationManager.send(...)`:
```swift
NSSound(named: "Funk")?.play()  // system sound, zero file esterni
```

### Config
Aggiungere a `InkPulseConfig`:
```json
{
  "sound_on_anomaly": true
}
```

### Upgrade futuro
Sostituire `NSSound` con un suono custom cyberpunk `.aiff` quando avremo tempo di crearlo. Per ora system sound.

---

## File da modificare

| File | Modifiche |
|------|-----------|
| `Config/Constants.swift` | Aggiungere `defaultContextLimits`, `defaultDailyBudget` |
| `Config/ConfigLoader.swift` | Nuovi campi `InkPulseConfig`: `context_limits`, `daily_budget_eur`, `budget_alert_thresholds`, `sound_on_anomaly` |
| `Parser/ClaudeEvent.swift` | Nessuna modifica |
| `Parser/JSONLParser.swift` | Estrarre tool target (file_path/command) dal content block tool_use |
| `Metrics/SessionMetrics.swift` | Nuovi campi: `lastContextTokens`, `lastToolName`, `lastToolTarget`, `activeTaskName` |
| `Metrics/MetricsEngine.swift` | Esporre `lastContextTokens`, `lastToolName`, `lastToolTarget`, `activeTaskName` nel `MetricsSnapshot` |
| `Notifications/AnomalyWatcher.swift` | Aggiungere `NSSound` dopo notifica |
| `UI/SessionRowView.swift` | Terza riga (tool+task), context bar, kill button |
| `UI/LiveTab.swift` | Colonna `ctx` nel header, daily budget bar |
| `UI/ConfigView.swift` | Campi per budget, context limits, sound toggle |
| **NUOVO** `Actions/ProcessResolver.swift` | PID lookup via ps + lsof |
| **NUOVO** `Actions/SessionKiller.swift` | SIGTERM/SIGKILL con conferma |

## File da NON modificare

- `Watcher/` — il data flow funziona già
- `Persistence/` — nessun nuovo file di stato
- `Tests/` — aggiungere test per ProcessResolver e context % calc

---

## Vincoli inviolabili

1. **MAI killare senza conferma** — sempre `.alert()` prima
2. **MAI mostrare contenuto messaggi** — solo tool name + primo argomento
3. **Budget alert = solo notifica** — nessun kill automatico
4. **No persistent state extra** — solo config.json esistente + memoria in-app
5. **System sound per ora** — custom audio è upgrade futuro

---

## Ordine di implementazione suggerito

1. **Context Window %** — più dati sono già lì, solo UI + un campo
2. **Ultimo Tool + Task Name** — parsing aggiuntivo + terza riga UI
3. **Daily Cost Budget** — config + UI + notifica
4. **Sound on Anomaly** — 3 righe di codice
5. **Kill Session** — il più complesso (ProcessResolver + UI + conferma)

---

## Test plan

- [ ] Context % mostra valore corretto confrontato con JSONL raw
- [ ] Context % colore cambia a 60% e 85%
- [ ] Tool name si aggiorna in real-time nella SessionRowView
- [ ] Kill button mostra conferma, non killa senza click
- [ ] Kill button disabilitato se PID non trovato
- [ ] SIGTERM → SIGKILL fallback funziona
- [ ] Budget bar appare solo se budget > 0 in config
- [ ] Notifica budget scatta a 80% e 100%, una sola volta
- [ ] Suono anomaly si sente su hemorrhage/loop/explosion
- [ ] Sound disabilitabile da config
- [ ] Config panel mostra e salva tutti i nuovi campi
