# Protocollo di Orchestrazione InkPulse v2.2.0
> Il cervello del Polpo. Un pulsante, 7 agenti autonomi.

---

## Architettura

```
                    MATTIA (Forgiatore)
                         |
                  [Orchestrate 🐙]
                         |
              InkPulse (control plane)
                         |
         ┌───────────────┼───────────────┐
         |                               |
    Orchestrator                   missions.json
    (7° agente)                    (6 missioni)
    Legge vault,                        |
    decide tutto              ┌────┬────┬────┬────┬────┐
         |                    m1   m2   m3   m4   m5   m6
         |                    (prompt dinamici generati
    Resta attivo               dall'orchestrator)
    come supervisore
```

## Flusso

1. Mattia clicca **Orchestrate** in InkPulse
2. InkPulse spawna 1 agente orchestrator in Terminal
3. L'orchestrator ha **massima autonomia**: legge vault Obsidian, session_current.md, roadmap, quaderno, git status — qualsiasi cosa serva
4. Scrive `~/.inkpulse/missions.json` con 6 missioni concrete
5. InkPulse rileva il file (FSEvents + poll 2s fallback)
6. InkPulse spawna 6 agenti con i prompt dinamici
7. L'orchestrator resta attivo come 7° agente (supervisore cross-dominio)

## missions.json

```json
{
  "generated": "2026-03-28T14:30:00Z",
  "reasoning": "Breve spiegazione del perché queste 6 missioni",
  "missions": [
    {
      "id": "m1",
      "name": "Nome leggibile",
      "cwd": "~/projects/aurahome",
      "icon": "flame.fill",
      "color": "#FFD700",
      "prompt": "Prompt COMPLETO e autosufficiente per l'agente"
    }
  ]
}
```

## Coesistenza con teams.json

Il sistema statico (`~/.inkpulse/teams.json`) resta disponibile per spawn chirurgici di singoli agenti/team. I due sistemi coesistono:

- **Orchestrate** = il Polpo decide tutto (massima autonomia)
- **Spawn Team** = spawn manuale con ruoli predefiniti (controllo diretto)

## Comunicazione Cross-Pilastro

L'orchestrator e gli agenti scrivono note in `~/cross-pillar-notes/` per coordinamento inter-pilastro. Formato: `{contesto}-{data}.md`.

## Componenti

| File | Ruolo |
|------|-------|
| `OrchestrateSpawner.swift` | Meta-prompt + spawn orchestrator + spawn missioni |
| `MissionsWatcher.swift` | FSEvents + poll su missions.json, decode, callback |
| `TeamConfig.swift` | MissionConfig, MissionsFile, OrchestratePhase |
| `AppState.swift` | orchestrate(), timeout 120s, onMissionsReady() |
| `LiveTab.swift` | Pulsante con 5 stati UI |
