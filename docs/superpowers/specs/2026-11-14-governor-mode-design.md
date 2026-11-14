# Modo Governador — design

Status: aprovado pelo autor em 2026-11-14. Nenhum código de produto foi escrito.

## Intenção

O jogador governa uma unidade subnacional (estado, província, região) em vez de um país. O cargo muda com o tipo da unidade (governador, prefeito, ...). A experiência é a do jogo atual (orçamento, leis, eleições, aprovação), em escala menor e **sem soberania**: sem política externa, sem moeda, sem forças armadas, e só com as leis que a Constituição deixa a cargo do estado. O motivo declarado pelo autor é que seria divertido; o critério de sucesso é ser jogável e divertido, não ser uma simulação fiel.

## Objetivos

- Escolher uma unidade de 1º nível na tela inicial e jogá-la com a mesma interface de janelas.
- Orçamento estadual (receitas, despesas, dívida), aprovação e eleição para o cargo executivo da unidade.
- Nome do cargo por **tipo de unidade** (ver Cargo por tipo de unidade).
- Relação com a União: repasses, e leis federais que limitam o estado.
- Tabela de **competências** por país: o que é do estado e o que é da União.
- O país-mãe segue funcionando sozinho, pela IA.

## Não objetivos

- Assembleia estadual e leis estaduais no editor de leis (v2).
- Carreira política até a presidência (v3).
- Municípios como unidades jogáveis na v1 (o nome do cargo já é por tipo de unidade, então a estrutura os comporta depois).
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

### Oposição: presidente do partido na unidade

Ao perder o cargo, o jogador não vira líder da oposição nacional: ele passa a ser o **presidente do diretório do partido naquela unidade** e disputa a eleição seguinte, com a IA governando a unidade nesse período. Ele usa as ferramentas de oposição que já existem em `politics.gd` (fundo do partido, pesquisa, campanha, crítica ao governo), apontadas para a aprovação e a eleição da unidade.

O diretório é **subordinado à presidência nacional do partido**. Chamada minha para o formato: o diretório recebe só uma parte do fundo do partido, a direção nacional pode vetar candidaturas e pode intervir se o diretório destoar da linha nacional do partido, e a relação do jogador com ela pesa na campanha. O construtor define os números. Quando o partido é o do governo federal, a subordinação rende repasses melhores; quando é de oposição nacional, rende atrito.

A **moção de censura** depende de uma assembleia estadual e fica desligada até a v2. O construtor verifica quais ações de `politics.gd` assumem o parlamento nacional e adapta só o que for preciso.

### Quem é o jogador

Qualquer escolha aqui mexe nos ~246 usos de `world.player` e nos 74 de `in_office`, então a regra é reaproveitar o que já existe: o caminho da **oposição**, que já deixa o jogador ligado a um país que a IA governa (`in_office = false`, `NationAI.step_month` roda para o país dele, `governed()` devolve `null`).

Chamada minha: no modo governador, `world.player` é o **país-mãe**, `in_office` é `false`, e um campo novo `world.governor` (um `StateGov`, ou `null` no modo país) diz qual unidade o jogador comanda. A interface do país vira leitura, e as janelas estaduais usam `world.governor`. Falta ao construtor verificar quais telas assumem "player não governa" como "player é oposição" e precisam de um terceiro papel (`governor`) em `Legislation.role()`.

### Cargo por tipo de unidade

O nome do cargo executivo é uma propriedade do **tipo** da unidade (`Subdivisions.types`), não do jogo: governador para estados, prefeito para municípios e cidades, e assim por diante, com a regra de cada país. Isso vale também para tipos criados pelo jogador (o criador de unidades pede o nome do cargo, com padrão "Governador" quando nada for dado). Todo texto, janela e notícia que diga "governador" usa o nome do cargo do tipo da unidade jogada, no masculino ou no feminino conforme o cargo. Os msgid ficam em português (o nome do cargo entra como dado, não como texto fixo). Padrões de partida: Brasil, Estado e Distrito Federal: Governador; Município e Cidade: Prefeito. Outros países: o padrão genérico, que o construtor completa a partir dos tipos do cenário.

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

## Decidido pelo autor

- Perder a eleição para governador **não** encerra a partida: o jogador segue na oposição e disputa a eleição seguinte, com a IA governando o estado nesse período.
- Na oposição o jogador é o presidente do partido **na unidade**, subordinado à presidência nacional do partido (ver Oposição). Não vira líder de oposição do país.
- O nome do cargo (governador, prefeito, ...) depende do tipo da unidade. No Brasil município tem prefeito, não governador.
- Só unidades de **1º nível** são jogáveis na v1; municípios ficam para depois.
- A unidade pode ser escolhida em **qualquer país**. A tabela de competências faz de países unitários um desafio maior, sem proibição.
- Se a unidade for dividida, o jogador fica com a parte que contém a capital. A partida só acaba se a unidade deixar de existir.
- Se a unidade passar a outro país, a nova União decide se mantém o jogador no cargo **pela bússola política**: compara a posição do jogador (`leader.econ`, `leader.social`, a de antes da troca) com a do partido no poder da nova União, com `Politics.distance`. Dentro do limite, ele é mantido; fora, é retirado. O construtor escolhe o limite, partindo de `COALITION_MAX_DISTANCE`. O que vem depois depende do regime da nova União (democrático quando `dem >= 4.0`, como no resto do código):
  - **Democracia:** o jogador escolhe a qual partido da nova União se filia, no seletor de partidos que já existe. Se foi mantido, segue como governador (e adota as ideias do partido, como em `join_party`). Chamada minha: se foi retirado, ele também escolhe o partido, perde o cargo e segue como presidente do diretório da unidade (ver Oposição), disputando a eleição seguinte.
  - **Ditadura:** se foi retirado, **perde a partida**. Se foi mantido, filia-se automaticamente ao partido no poder da nova União, sem escolha.

## Perguntas para o autor

Nenhuma em aberto. Aguardando aprovação do documento.
