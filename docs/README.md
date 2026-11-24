# Supremo Motors: Brasil Underground — Protótipo v0.3 (Godot 4.3+)

Jogo 3D de mundo aberto com cultura automotiva brasileira. Esta versão é o **protótipo
jogável** pedido na Estratégia de Desenvolvimento (item 14 do Prompt Mestre), feito em
**Godot 4** (GDScript, renderizador GL Compatibility) para rodar em **Windows e Android**.

> ⚠️ **Honestidade técnica:** o código foi escrito e revisado **estaticamente**. Ele **não foi
> executado** no Godot neste ambiente (não há Godot instalado aqui). Espere pequenos erros
> de parse/ajustes no primeiro "Executar". Rode os testes (abaixo) e me envie o log de erros.

## Instalar e rodar
1. Instale o **Godot 4.3 ou superior** (versão padrão, não .NET) — https://godotengine.org
2. Abra o Godot → **Import** → selecione `project.godot` desta pasta → **Executar (F5)**.
3. Testes automatizados:
   ```
   godot --headless --path . res://tests/test_runner.tscn
   ```
   (saída `TESTES: N ok, 0 falhas`; código de saída 0 = sucesso)
4. **Android:** instale os export templates, configure Java/Android SDK em *Editor Settings →
   Export → Android*, crie o preset Android e use o nome de pacote **`br.supremo.motors.game`**
   (é o que o launcher "JOGAR" procura). Orientação já está em paisagem.

## Controles
| Ação | Teclado | Toque |
|---|---|---|
| Acelerar / Frear (ré parado) | W,S ou ↑,↓ | ACELERAR / FREIO |
| Direção | A,D ou ←,→ | < > |
| Freio de mão | Espaço | FREIO MÃO |
| Interagir (perto do marcador colorido) | E | INTERAGIR |
| Celular (missões, multas, extrato, garagem, diagnóstico) | C | CELULAR |
| Estacionar / voltar a dirigir | P | ESTACIONAR |
| Trancar / destrancar (estacionado) | L | TRANCAR |
| Motor ligar/desligar (estacionado) | M | MOTOR |
| Farol | F | FAROL |
| Reposicionar (desvira) | R | REPOSICIONAR |

## O que está implementado (10 itens do protótipo)
| # | Item | Onde | Estado |
|---|---|---|---|
| 1 | Um bairro jogável | `world/world_builder.gd` | ✅ Vila Supremo: grade de ruas, quarteirões, POIs, morro com comunidade e estátua, rodovia, ponte estaiada, palmeiras, bandeira do Brasil. **Cenário 100% procedural (placeholders).** |
| 2 | Um carro e uma moto | `data/vehicles.json`, `vehicle_builder.gd` | ✅ Gol, Uno, Fusca, Opala SS, Skyline R34, **CG 160 (moto)**, viatura. Carrocerias são formas procedurais, **não modelos reais**. |
| 3 | Direção com física funcional | `vehicle/car.gd` | ✅ Suspensão por raycast, pneus com limite de aderência, curva de torque, câmbio automático, ré, consumo, dano por colisão. Moto usa estabilização *arcade*. **Não é simulação validada.** |
| 4 | Oficina de tuning | `economy_system.gd`, `ui/menus.gd`, `data/tuning.json` | ✅ ~35 peças (motor, transmissão, escape, suspensão/freios, exterior, interior, segurança) + pintura. Efeitos em potência, aderência, peso, consumo, confiabilidade e valor. Visual: pintura, aerofólio, rodas, neon e rebaixamento. |
| 5 | Áudio dinâmico básico | `vehicle/engine_audio.gd` | ✅ Síntese em tempo real por RPM/carga/cilindros/escape/turbo/estouros/corte de giro. **Não é MetaSounds** (isso é da Unreal). |
| 6 | Missão remunerada | `mission_system.gd`, `data/missions.json` | ✅ 4 missões do Cap. 1 (entrega, compra, autoescola sem multa, peça com **escolha e consequência persistente**), GPS no minimapa e baliza 3D. |
| 7 | Polícia (fiscalização + perseguição) | `police_system.gd`, `data/police.json` | ✅ Radar de velocidade, avanço de sinal, direção perigosa, veículo irregular, fuga; abordagem, perseguição, bloqueio e apreensão com pátio. |
| 8 | Estacionamento: tranca, multa, guincho | `parking_system.gd` | ✅ Estado persistente, multa por vaga irregular, guincho para o pátio, **furto** de carros destrancados, alarme, rastreador, seguro, garagem protegida. |
| 9 | Dinheiro e garagem | `game_state.gd`, `economy_system.gd`, `menus.gd` | ✅ Banco, extrato, empréstimo com juros, seguro, IPVA, multas, compra/venda, garagem com comparação de desempenho, troca de veículo. |
| 10 | Salvar e carregar | `game_state.gd` | ✅ JSON versionado (`user://save_v3.json`), migração do save v2, autosave a cada 60 s e ao fechar/pausar. |

Extras já presentes: dia/noite, clima (limpo/nublado/chuva com menos aderência), tráfego de NPCs
com semáforos, minimapa/GPS, HUD, pacotes de conteúdo (`content/*.json`).

## O que NÃO está implementado (não finja que está)
Multiplayer/PvP/servidor autoritativo · gerenciador de eventos (corrida, arrancada, drift…) ·
Capítulos 2 a 6 · profissões além da entrega por missão · transferências e financiamento ·
pedestres · interior dos veículos e personagem a pé · danos visuais (só mecânicos) ·
modo foto · volante com force feedback · modelos 3D reais · MetaSounds/áudio por amostras ·
regiões desbloqueáveis · oficinas administradas por jogadores · organizações/clubes.

## Modelos 3D
Carrocerias de Gol, Uno, Opala, Skyline, Strada e viatura usam modelos **CC0 do Kenney Car Kit** (`assets/models/`), escalados para as medidas de cada veiculo. Sao modelos genericos, **nao** replicas das marcas brasileiras. Fusca e CG 160 continuam procedurais. Se o carro aparecer de re, mude `MODEL_YAW_DEG` em `vehicle_builder.gd` para 0.0. Sem os arquivos importados, o jogo volta ao visual procedural.

## Critérios de conclusão do protótipo
- [ ] Abre no Godot 4.3 sem erros de parse e `test_runner.tscn` passa.
- [ ] Dirigir carro e moto pelo bairro; ré; farol; chuva e noite.
- [ ] Comprar peça na oficina e ouvir/ver a diferença (som, aerofólio, cor).
- [ ] Concluir "Primeiro bico" e receber o pagamento.
- [ ] Passar de 70 km/h na avenida: multa, abordagem, fuga e perseguição; ser apreendido e retirar no pátio.
- [ ] Estacionar na rua: multa e guincho; estacionar destrancado e ver o furto; recuperar.
- [ ] Salvar, fechar, abrir e continuar do mesmo ponto.

