# Mario RL — Super Mario 64 com Reinforcement Learning na Godot

Projeto que coloca o Mario do **Super Mario 64** (via emulação da engine original
dentro da Godot) para aprender tarefas com **Reinforcement Learning**: parkour até
um alvo, perseguição/fuga e batalhas multi-agente em times. Inclui três ambientes
de treino, scripts de treinamento com **Stable-Baselines3 (PPO)** e **RLlib
(MAPPO com crítico centralizado)**, exportação de políticas em **ONNX** e
inferência dentro do próprio editor.

> **Créditos ao projeto original:** a base deste repositório — o addon
> `libsm64_godot`, a GDExtension, as cenas demo e o manual — é o trabalho
> **[libsm64-godot](https://github.com/Brawmario/libsm64-godot)** de
> **Brawmario**, que por sua vez usa a **[libsm64](https://github.com/libsm64/libsm64)**
> (engine do SM64 como biblioteca). A camada de RL (`rl_parkour`, `rl_chase`,
> `rl_brawl`, `rl_common`, integração com Godot RL Agents / SB3 / RLlib) foi
> desenvolvida sobre essa base neste repositório. Todo o mérito pela integração
> SM64 ↔ Godot pertence aos autores originais; veja a seção [Créditos](#créditos).

---

## Índice

1. [Requisitos](#1-requisitos)
2. [Estrutura do projeto](#2-estrutura-do-projeto)
3. [Começando (Godot)](#3-começando-godot)
4. [O addon libsm64_godot (resumo)](#4-o-addon-libsm64_godot-resumo)
5. [Ambientes de RL](#5-ambientes-de-rl)
6. [Treinamento com Stable-Baselines3 (single-agent)](#6-treinamento-com-stable-baselines3-single-agent)
7. [Treinamento multi-agente com RLlib / MAPPO (brawl)](#7-treinamento-multi-agente-com-rllib--mappo-brawl)
8. [Inferência (usar um modelo treinado)](#8-inferência-usar-um-modelo-treinado)
9. [Export, Docker e CI](#9-export-docker-e-ci)
10. [Notas técnicas de arquitetura](#10-notas-técnicas-de-arquitetura)
11. [Solução de problemas](#11-solução-de-problemas)
12. [Créditos](#créditos)

---

## 1. Requisitos

| Componente | Versão / detalhe |
|---|---|
| Godot Engine | **4.5.2** (projeto usa `config/features=4.5`) |
| GDExtension compilada | incluída em `addons/libsm64_godot/extension/bin` (ou compile, ver §9) |
| Python (treino) | **3.11** (venv local `.venv311/`, já com as dependências) |
| ROM Super Mario 64 (USA) | SHA-256 `17ce0773…bb21d91` (ver abaixo; **não acompanha o repo**) |
| GPU | opcional (PyTorch usa CUDA se disponível; CPU funciona) |

### ROM do Super Mario 64 (USA)

Por motivos legais, a ROM **não** é distribuída aqui (o arquivo `baserom.us.z64`
é ignorado pelo git). Para rodar qualquer cena você precisa de uma ROM USA do
SM64 cujo SHA-256 seja exatamente:

```
17ce077343c6133f8c9f2d6d6d9a4ab62c8cd2aa57c40aea1f490b4c8bb21d91
```

Coloque o arquivo como `baserom.us.z64` na **raiz do projeto** — as três cenas
de treino procuram primeiro `res://baserom.us.z64` e depois `baserom.us.z64`
(ver `rl_parkour/main.gd`, `rl_chase/chase_main.gd`, `rl_brawl/brawl_main.gd`).
A verificação do hash é feita por `LibSM64Global.load_rom_file()`.

### Dependências Python

O ambiente principal está em `requirements.txt`:

```
stable-baselines3==2.9.0
gymnasium==1.3.0
shimmy>=2.0.0
godot-rl==0.8.2
tensorboard==2.16.2
numpy>=1.26
ray[rllib]
pettingzoo
pyyaml
```

> Detalhe histórico: o venv antigo (`.venv311`) usava `SB3==2.4.1` +
> `gymnasium==1.0.0`, combinação que quebrava o `VecVideoRecorder` e exigia um
> patch manual. Isso está documentado em `SB3_COMPATIBILITY_FIX.md` (mantido
> apenas como registro) e **não é mais necessário** com os pins atuais.
> Para recriar o ambiente do zero: `python -m venv .venv && pip install -r requirements.txt`.

Existe ainda o `requirements.mappo.txt`, um ambiente **legado e isolado**
(Ray 1.8 + MARLlib + `gym==0.20`) — **não instale junto** com o
`requirements.txt` (conflito `gym` 0.20 × `gymnasium` 1.x). O treino MAPPO
atual (`train_rllib_mappo.py`) usa o `ray[rllib]` do ambiente principal.

---

## 2. Estrutura do projeto

```
.
├── addons/
│   ├── libsm64_godot/        # addon SM64 (projeto original Brawmario)
│   │   ├── static/           # LibSM64Global (ROM, init/terminate)
│   │   ├── libsm64_mario/    # LibSM64Mario (Node3D do Mario)
│   │   ├── handlers/         # superfícies estáticas e objetos móveis
│   │   ├── components/       # propriedades físicas das superfícies
│   │   └── extension/        # .gdextension + binários por plataforma
│   └── godot_rl_agents/      # addon de RL (controllers, sensores, sync, ONNX)
├── extension/                # fontes C++ da GDExtension (SConstruct, src/, doc_classes/)
├── libsm64_godot_demo/       # cenas demo do addon original
├── rl_parkour/               # ambiente 1: correr até o alvo
├── rl_chase/                 # ambiente 2: perseguição (chaser × runner)
├── rl_brawl/                 # ambiente 3: batalha multi-agente em times
├── rl_common/                # script SB3 compartilhado (train_sb3.py)
├── docs/                     # manual do addon (manual.md + imagens)
├── export_presets.cfg        # presets Win/Linux/macOS/Web
├── Dockerfile                # export headless via godot-ci:4.5.2
├── .github/                  # CI: compila a GDExtension e exporta a demo
├── requirements*.txt         # dependências Python
├── logs/                     # TensorBoard/checkpoints (local, ignorado no git)
└── models/checkpoints/       # checkpoints de modelos (local, ignorado no git)
```

Cena principal do projeto (Godot): `res://libsm64_godot_demo/main.tscn`.

---

## 3. Começando (Godot)

1. Abra a Godot **4.5.2** e importe a pasta do projeto.
2. Ative o plugin `LibSM64 Godot` em **Projeto → Configurações → Plugins** (se
   aparecer erro de extensão, recarregue o projeto).
3. Coloque a ROM como `baserom.us.z64` na raiz do projeto.
4. Rode a cena demo (`libsm64_godot_demo/main.tscn`) ou uma das cenas de treino:
   - `rl_parkour/main.tscn`
   - `rl_chase/chase_main.tscn`
   - `rl_brawl/brawl_main.tscn`

Sem a ROM, as cenas exibem erro (`ROM not found`) e não inicializam o mundo.

---

## 4. O addon libsm64_godot (resumo)

Documentação completa do addon no original e em [`docs/manual.md`](docs/manual.md).
Resumo dos blocos usados pelos ambientes de RL:

- **`LibSM64Global`** — carrega a ROM (`load_rom_file()` com checagem SHA-256),
  inicializa/encerra o mundo (`init()` / `terminate()`).
- **`LibSM64Mario`** (`extends Node3D`) — o Mario; múltiplas instâncias por cena.
  Os agentes de RL estendem essa classe via `RLMario` (ver §10).
- **`LibSM64StaticSurfacesHandler`** — carrega os meshes do grupo
  `libsm64_static_surfaces` como colisão estática (`load_static_surfaces()`).
- **`LibSM64SurfaceObjectsHandler`** — objetos móveis de colisão.
- **`LibSM64AudioStreamPlayer`** — áudio gerado pela engine do SM64.
- A física do Mario roda a **30 ticks/s** (`LibSM64.tick_delta_time`); use meshes
  **simples e low-poly** para colisão.

---

## 5. Ambientes de RL

Todos os ambientes seguem o protocolo do addon **Godot RL Agents**
(`addons/godot_rl_agents`): cada agente estende `AIController3D` e implementa
`get_obs()`, `get_reward()`, `get_action_space()`, `set_action()`, `is_done()` e
`reset()`. A comunicação com o Python é feita pelo nó `sync` (porta padrão
**11008**). As cenas `main` instanciam **`num_envs` (padrão 4)** cópias do
ambiente lado a lado (`env_spacing`) e aceitam `time_scale` para acelerar a
física.

Espaço de ação (igual nos três ambientes — 5 canais contínuos):

| Canal | Efeito |
|---|---|
| `stick_x`, `stick_y` | analógico do Mario (−1…1) |
| `button_a` | pulo (> 0 = pressionado) |
| `button_b` | soco/ataque (> 0 = pressionado) |
| `button_z` | agachar/ground-pound (> 0 = pressionado) |

Implementação em `rl_parkour/mario_agent.gd` (`set_action()` → `RLMario.rl_*`).

### 5.1 `rl_parkour` — correr até o alvo

- **Cena:** `rl_parkour/main.tscn` (ambiente `parkour_env.tscn`).
- **Agente:** `MarioAgent` (`mario_agent.gd`) + `RLMario` (`rl_mario.gd`).
- **Observação (41 valores):** posição relativa do alvo (3) + velocidade (3) +
  ângulo de face (1) + `action`/100 e `flags`/100 internos do SM64 (2) + sensor
  RayCast 8×4 com alcance 10 m (32).
- **Recompensa:** `-0.01 × distância` por passo; **+10** ao chegar (< 2 m);
  **−10** ao cair (`y < −10`).
- **Fim de episódio:** chegou, caiu ou 1000 passos.

### 5.2 `rl_chase` — perseguição

- **Cena:** `rl_chase/chase_main.tscn` (ambiente `chase_env.tscn`).
- **Agente:** `ChaseAgent` (`chase_agent.gd`, estende `MarioAgent`), com
  `is_chaser` (papel) e referência ao `enemy`.
- **Observação (42 valores):** igual ao parkour, com posição relativa do
  inimigo e **flag de papel** (1 = perseguidor, 0 = fugitivo).
- **Recompensa:** perseguidor `-0.01 × distância` e **+10** ao encostar (< 2 m
  com B/Z); fugitivo `+0.01 × distância` e **−10** ao ser pego; **−10** ao cair.
- **Fim de episódio:** captura ou 900 passos (~15 s a 60 fps).

### 5.3 `rl_brawl` — batalha em times (multi-agente)

- **Cenas:** `rl_brawl/brawl_main.tscn` (ambiente `brawl_env.tscn`).
- **Times:** configuráveis no editor via array de `TeamConfig`
  (`team_name`, `team_color`, `team_texture`, `team_size`) — ver
  [`rl_brawl/README.md`](rl_brawl/README.md).
- **Agente:** `BrawlAgent` (estende `MarioAgent`); Mario com
  `apply_team_appearance()` (overlay da cor do time).
- **Observação local (64 valores):** velocidade (3) + face (1) + action/flags
  (2) + vida/8 (1) + id do time (1) + até 4 inimigos (posição relativa + vida,
  16) + até 2 aliados (8) + RayCast (32). Slots vazios = zero.
- **Estado global (9 por agente, p/ o crítico centralizado):** posição (3) +
  velocidade (3) + vida normalizada + flag vivo + id do time.
- **Recompensa:** `+1 × dano causado`, `+5 × abates`, `−1 × dano sofrido`,
  `−5 × mortes` (pesos ajustáveis: `damage_reward`, `kill_reward`,
  `damage_taken_penalty`, `death_penalty`, `survival_reward`).
- **Combate** (`brawl_env.gd`): ataque com B/Z dentro de `attack_range` (2.0 m)
  e `attack_cooldown` (0.5 s); `damage_wedges` por golpe; episódio até
  `max_episode_steps` (900) ou restar ≤ 1 time vivo.
- **Políticas:** uma por time (`team_0`, `team_1`, …) — ver §7 e
  [`rl_brawl/README.rllib.md`](rl_brawl/README.rllib.md).

---

## 6. Treinamento com Stable-Baselines3 (single-agent)

Um único script compartilhado atende os três ambientes:

```
rl_common/train_sb3.py            # implementação
rl_parkour/train.py               # wrappers finos (compatibilidade)
rl_chase/train.py
rl_brawl/train.py                 # (single-agent; p/ multi-agente ver §7)
```

Uso (também vale `python -m rl_common.train_sb3 ...`):

```bash
# Treino no editor (Godot aberto na cena de treino)
python rl_parkour/train.py --timesteps 1000000 --experiment_dir logs/parkour --experiment_name run1

# Treino com binário exportado, 4 envs em paralelo, física 8x
python rl_parkour/train.py --env_path export/linux64/libsm64-godot-demo.x86_64 \
  --n_parallel 4 --speedup 8 --timesteps 1000000 \
  --experiment_dir logs/parkour --experiment_name run1 \
  --save_model_path models/parkour_run1 --onnx_export_path models/parkour_run1.onnx
```

Principais flags: `--env_path` (binário; omita p/ treinar no editor), `--viz`
(mostra a simulação), `--n_parallel`, `--speedup`, `--seed`,
`--resume_model_path` (continuar/inferir), `--save_model_path`,
`--save_checkpoint_frequency`, `--onnx_export_path`, `--inference`,
`--linear_lr_schedule`, `--timesteps`.

Hiperparâmetros padrão (PPO, `MultiInputPolicy`): `lr=0.0003`, `n_steps=32`,
`ent_coef=0.0001`, logs TensorBoard no `--experiment_dir`:

```bash
tensorboard --logdir logs
```

> **SB3 × Ray:** se o pacote `ray` estiver instalado no mesmo venv, o script
> avisa que SB3 e `ray[rllib]` são incompatíveis entre si (são stacks
> alternativas: §6 **ou** §7).

---

## 7. Treinamento multi-agente com RLlib / MAPPO (brawl)

Arquivos: `rl_brawl/train_rllib_mappo.py`, `rl_brawl/rllib_config.yaml`,
`rl_brawl/rllib_models.py` (detalhes em
[`rl_brawl/README.rllib.md`](rl_brawl/README.rllib.md)).

```bash
# 1. Abra a Godot e dê PLAY na cena rl_brawl/brawl_main.tscn
# 2. No terminal:
python rl_brawl/train_rllib_mappo.py --config_file rl_brawl/rllib_config.yaml --experiment_dir logs/rllib
```

Como funciona:

- Cada time vira uma política RLlib (`team_0`, `team_1`, …); o mapeamento
  agente→política segue a ordem de spawn (`_spawn_teams()`), replicada por
  ambiente — os argumentos `--num_teams`, `--team_size` e `--num_envs`
  **precisam coincidir com a cena**.
- O algoritmo é **MAPPO**: o ator usa a observação local e um **crítico
  centralizado** (`CentralCriticModel`) consome o estado global do ambiente.
- Config padrão (`rllib_config.yaml`): PPO/Torch, rede `[256, 256]` ReLU,
  `lr=0.0003`, `train_batch_size=4000`, `sgd_minibatch_size=128`,
  `num_sgd_iter=10`, `clip_param=0.2`, filtro `MeanStdFilter`, 1M timesteps.
- Com `num_env_runners=0`, o worker local conecta na porta **11008** (Godot
  aberto no editor). Ao final, as políticas são exportadas em **ONNX** para a
  pasta do experimento; hiperparâmetros e recompensas vão para o **MLflow**.

---

## 8. Inferência (usar um modelo treinado)

- **SB3:** `python rl_parkour/train.py --resume_model_path <modelo.zip> --inference --timesteps <n>`
  (exige a cena/binário rodando da mesma forma que no treino).
- **ONNX na Godot:** exporte com `--onnx_export_path` (SB3) ou use o ONNX
  gerado pelo treino RLlib; o addon `godot_rl_agents` inclui o wrapper
  (`addons/godot_rl_agents/onnx/`) para rodar a política dentro do jogo sem
  Python.

---

## 9. Export, Docker e CI

Presets (`export_presets.cfg`): **Windows Desktop** (`export/win64/*.exe`),
**Linux/X11** (`export/linux64/*.x86_64`), **macOS** (`export/macos/*.zip`) e
**Web**. O treino com binário usa o export Linux.

```bash
# Export headless via Docker (imagem Godot 4.5.2)
docker build -t libsm64-godot .
docker run -it libsm64-godot
```

O **CI** (`.github/`) compila a GDExtension (Windows/Linux/macOS/Web, via
`compile_gdextension`), exporta a demo e publica os artefatos. Para compilar a
extensão manualmente, veja a seção original de build — mantida aqui por
conveniência:

1. Compile a [libsm64](https://github.com/libsm64/libsm64) e copie (sem mover)
   a biblioteca de `extension/libsm64/dist/` para
   `addons/libsm64_godot/extension/bin`.
2. Na pasta `extension`, rode `scons target=template_debug use_mingw=yes`
   (debug) ou `scons target=template_release use_mingw=yes` (release).

---

## 10. Notas técnicas de arquitetura

- **Reset do Mario:** teleportar o Mario no libsm64 pode corromper a máquina de
  estados do C++ (congelamento/OOB). Por isso `MarioAgent.reset()` **destrói e
  recria** o Mario (`delete()` → reposiciona → `create()`), exceto no primeir
...[truncated 1791 chars]