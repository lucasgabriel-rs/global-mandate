# Modo Governador — design

Status: rascunho para aprovação. Nenhum código de produto foi escrito.

## Intenção

O jogador governa uma unidade subnacional (estado, província, região) em vez de um país. A experiência é a do jogo atual (orçamento, leis, eleições, aprovação), em escala menor e **sem soberania**: sem política externa, sem moeda, sem forças armadas, e só com as leis que a Constituição deixa a cargo do estado. O motivo declarado pelo autor é que seria divertido; o critério de sucesso é ser jogável e divertido, não ser uma simulação fiel.

## Objetivos

- Escolher uma unidade de 1º nível na tela inicial e jogá-la com a mesma interface de janelas.
- Orçamento estadual (receitas, despesas, dívida), aprovação e eleição para governador.
- Relação com a União: repasses, e leis federais que limitam o estado.
- Tabela de **competências** por país: o que é do estado e o que é da União.
- O país-mãe segue funcionando sozinho, pela IA.

## Não objetivos

- Assembleia estadual e leis estaduais no editor de leis (v2).
- Carreira política até a presidência (v3).
- Municípios como unidades jogáveis.
- Qualquer efeito do gasto estadual sobre as contas nacionais (ver Restrições).

## Antiobjetivos (falha mesmo que "funcione")

- Mexer no núcleo do jogo de país a ponto de arriscar quebrá-lo.
- Contar o mesmo PIB, receita ou gasto duas vezes.
- Um governador que é só o presidente com menos botões.

## Abordagens consideradas

- **A. Unidade vira um `Country` falso.** Reaproveita todas as janelas, mas obriga a dividir o PIB sem dupla contagem e a fazer ~246 usos de `world.player` aceitarem um jogador não soberano. Descartada: risco alto no núcleo.
- **B. Camada nova `StateGov`.** Escolhida pelo autor. Objeto próprio por unidade, ligado à economia nacional, mais tabela de competências.
- **C. Jogador continua sendo o país com "poderes delegados".** Descartada: não é governar uma unidade não soberana.

## Design (v1)

### Quem é o jogador

Qualquer escolha aqui mexe nos ~246 usos de `world.player` e nos 74 de `in_office`, então a regra é reaproveitar o que já existe: o caminho da **oposição**, que já deixa o jogador ligado a um país que a IA governa (`in_office = false`, `NationAI.step_month` roda para o país dele, `governed()` devolve `null`).

Chamada minha: no modo governador, `world.player` é o **país-mãe**, `in_office` é `false`, e um campo novo `world.governor` (um `StateGov`, ou `null` no modo país) diz qual unidade o jogador comanda. A interface do país vira leitura, e as janelas estaduais usam `world.governor`. Falta ao construtor verificar quais telas assumem "player não governa" como "player é oposição" e precisam de um terceiro papel (`governor`) em `Legislation.role()`.

### `StateGov`

`RefCounted` em `scripts/sim/`, dono: `GameWorld` (nunca autoload: simulação e testes `-s` não enxergam autoloads). Um por unidade de 1º nível do país, criado sob demanda para a unidade jogada (as outras só existem se a IA estadual entrar na v2).

Campos de partida (o construtor refina): `unit_id`, `owner_iso`, `gdp_share`, `pop_share` (de `Subdivisions.pop_share`), `revenue`, `spending` por área, `debt`, `approval`, `next_election`, `party_id`, `transfers_in`.

Regra de fluxo, **em uma só direção**: PIB, população e preços estaduais derivam dos nacionais (fatia × renda relativa); o estado nunca escreve de volta nas contas do país. Receita estadual = alíquotas que a competência permite × base estadual + repasses federais. A despesa estadual é gasto só do estado.

### Competências

Tabela por país em `data/` (arquivo novo, p.ex. `competences.json`), com áreas (saúde, educação, segurança pública, infraestrutura, tributos, ...) e quem decide cada uma: `state`, `union` ou `shared`. Vem pronta para Brasil e EUA; os demais usam um padrão genérico e há uma marca "estado unitário" para países em que a região quase não decide (decisão minha; hoje não existe classificação federal/unitária em `data/` nem em `game_data.gd`, então ela é nova).

As competências são o ponto de encaixe nas janelas e, na v2, no editor de leis (`Legislation.can()` e `permission_table()` já centralizam quem pode o quê).

### Interface

Toda janela ou aba estadual é um `.tscn` editável, nunca montada em código. Dock filtrado: Painel, Política, Fiscal, Economia e uma janela de Relações com a União. Janelas de Militar, Moeda e Mundo ficam escondidas. Tela inicial ganha a escolha "país ou unidade". Saves: seção própria e versionada para o estado de governador; save antigo carrega em modo país.

### Repasses e União

Repasses mensais definidos pela tabela e pela relação política: afinidade partidária entre governador e governo federal e o peso da unidade. O jogador pode pedir verba extra, com chance e custo, no formato do pedido de votos já existente em `party_talk.gd`. Leis federais que valem para o estado vêm do país-mãe; o governador não as revoga.

## Restrições

- Código novo, comentários e changelog em inglês; msgid do jogo em português.
- Uma branch por mudança (`claude/governador`), em worktree a partir de `main`; não levar `project.godot` e `export_presets.cfg` locais.
- v1 não alimenta de volta as contas nacionais.
- Mudança de dono, fusão ou anexação de unidade eleva `Subdivisions.revision`; o `StateGov` precisa reagir.

## Fases

- **v1:** o acima.
- **v2:** assembleia estadual, partidos estaduais, leis estaduais no editor, respeitando competências.
- **v3:** carreira: disputar a presidência, e outros estados com IA.

## Fica para o construtor

Fórmulas de PIB e receita estadual, valores iniciais da tabela de competências, textos, balanceamento, escolha exata do formato da tabela e do save.

## Perguntas para o autor

1. Perder a eleição para governador encerra a partida, ou o jogador segue como oposição, como no modo país?
2. Dá para escolher unidade em qualquer país, ou só em federações?
3. Se a unidade for anexada ou dividida, a partida acaba ou o governador acompanha o território?
