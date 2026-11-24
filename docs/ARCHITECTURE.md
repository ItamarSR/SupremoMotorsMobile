# Arquitetura

Camadas: **dados** (`data/*.json`, `content/*.json`) → **estado** (autoloads) → **sistemas**
(nós independentes) → **UI** (só exibe e emite sinais). Sistemas conversam pelo barramento
`Bus` (sinais) e por `Callable`s injetados no `main.gd` (raiz de composição); nenhum sistema
referencia outro diretamente, exceto via interfaces explícitas (`player_getter`, `world`).

```
main.gd (composição)
 ├─ WorldBuilder      mapa, POIs, zonas (rua/lote/limite/região)
 ├─ WeatherSystem     dia/noite + clima → Game.grip_env
 ├─ TrafficSystem     semáforos + NPCs (IA de rota)
 ├─ PoliceSystem      infrações → suspeita → abordagem/perseguição/bloqueio/apreensão
 ├─ ParkingSystem     estado de estacionamento, multa, guincho, furto, recuperação
 ├─ EconomySystem     banco, empréstimo, seguro, compra/venda, tuning, despesas
 ├─ MissionSystem     missões data-driven, escolhas, flags
 ├─ GameUI + Menus    HUD, controles, minimapa, painéis
 └─ SupremoCar        veículo (física + dados + áudio), IA opcional
Autoloads: Bus (eventos) · Data (JSON + pacotes) · Game (estado + save versionado)
```

## Mapa para os módulos do Prompt Mestre
| Módulo do prompt | Aqui |
|---|---|
| VehicleCore | `Data` + `VehicleStats` + `Game.make_vehicle` |
| VehiclePhysics / EngineSimulation | `vehicle/car.gd` |
| VehicleAudio | `vehicle/engine_audio.gd` |
| TuningSystem | `data/tuning.json` + `EconomySystem.install_part` |
| TrafficAI | `systems/traffic_system.gd` |
| PoliceSystem | `systems/police_system.gd` |
| MissionSystem | `systems/mission_system.gd` |
| EconomySystem / BankingSystem | `systems/economy_system.gd` |
| JobSystem | ⏳ só entregas via missões |
| GarageSystem | `ui/menus.gd` + `main.gd` (troca de veículo) |
| ParkingSystem / TheftSystem | `systems/parking_system.gd` |
| EventSystem | ⏳ não implementado |
| WeatherSystem | `systems/weather_system.gd` |
| SaveSystem | `core/game_state.gd` |
| MultiplayerCore | ⏳ não implementado (veja abaixo) |

## Expansão
- **Novo veículo:** soltar um `.json` no formato de `data/vehicles.json` em `content/` (ou `user://content`).
- **Nova peça de tuning / missão / regra de polícia / preço:** editar o JSON correspondente.
- **Dados versionados:** `Game.SAVE_VERSION`; `from_dict` recusa versões futuras e remove modelos desconhecidos.
- **IDs únicos:** `uid` de veículo, `id` de multa, `id` de missão/POI.

## Preparação para multiplayer (ainda não implementado)
Lógica de dinheiro/estado já está separada da UI e passa por `Game`/`EconomySystem`/`ParkingSystem`,
o que permite mover essas chamadas para um **servidor autoritativo** (validação de transações,
persistência de personagem, replicação de veículos). Passos: (1) extrair `Game` para um serviço
com API, (2) transformar ações da UI em comandos assinados, (3) usar o `Server/` (Node) como base
de salas/matchmaking, (4) replicação por snapshots + reconciliação de física.

## Convenções
Indentação de 2 espaços; tipos explícitos quando o valor vem de `Dictionary` (evita inferência `Variant`).
