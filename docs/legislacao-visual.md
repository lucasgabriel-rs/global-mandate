# Sistema de Legislação Visual — Documento de Design

Status: descreve o que existe na branch `claude/emenda-sem-texto-e-busca-de-blocos`, que parte de `claude/centro-legislativo-atualiza` (base `main` em c1363fa) e acrescenta emendas sem texto livre e a busca na biblioteca de blocos. Itens marcados **[aberto]** são decisões ou lacunas ainda não resolvidas, não funcionalidades prontas.

## 1. Visão

O jogador governa um país e **escreve as leis como blocos encaixáveis**, no estilo Scratch, em vez de escolher efeitos num menu. Uma lei é um programa visual: eventos disparam artigos, artigos têm condições e ações. O mesmo programa:

1. vira **texto jurídico** legível (“Art. 1º … a) … b) …”);
2. é **verificado e compilado** para instruções simples;
3. **tramita** num processo legislativo com votos, sanção/veto e controle de constitucionalidade;
4. quando em vigor, **executa no mundo simulado** (impostos, direitos, orçamento, empresas, cidadãos), reagindo a eventos do jogo.

Objetivo de design: dar ao jogador expressividade real (regras próprias, condicionais, exceções) sem permitir código arbitrário e sem que a interface precise de texto livre.

### Princípios

- **Dados, não código.** Um programa é um dicionário serializável (salvo, versionado, exportável). Nenhum bloco executa nada por si.
- **A interface nunca roda os blocos.** Só o compilador lê a estrutura; só o motor executa o resultado.
- **Lista fechada.** O compilador só aceita tipos do catálogo; o motor só conhece as ações listadas, tem limite de passos e só lê um “retrato” (`view`) do mundo.
- **Escolha em vez de digitação.** Campos preferem listas (`choice`, `ref`, `unit`, `ministry`) a texto livre; texto livre só nomeia algo novo.
- **Hierarquia e consequências.** Quem pode propor o quê depende do papel do jogador e do tipo de norma; o resultado depende da política do país.

## 2. Mapa de arquivos

| Camada | Arquivo | Papel |
|---|---|---|
| Dados | `scripts/sim/law_program.gd` | Formato do programa e operações de edição (encaixar, retirar, clonar, texto legal) |
| Catálogo | `scripts/sim/law_catalog.gd` | Blocos avançados, categorias, listas de escolha |
| Códigos | `scripts/sim/codes/*.gd`, `law_codes.gd` | Blocos concretos de cada código legal e seus efeitos |
| Compilador | `scripts/sim/law_compiler.gd` | Leitura → verificação → forma intermediária → código plano |
| Motor | `scripts/sim/law_engine.gd` | Executa o código e devolve efeitos |
| Modelos | `scripts/sim/law_templates.gd` | Leis prontas (editor e projetos da IA) |
| Regras | `scripts/sim/legislation.gd` | Normas, tramitação, votos, versões, execução, auditoria |
| Editor | `scripts/ui/law_editor.gd` + `law_block_view`, `law_canvas`, `law_slot`, `law_socket`, `law_trash` | Biblioteca, área de programação, propriedades, validação |
| Apoio | `law_simulator.gd`, `law_review.gd`, `norm_page.gd`, `amendment_editor.gd`, `process_track.gd` | Simulação, efeitos esperados, leitura, emendas, trilha do processo |
| Hub | `scripts/ui/legislation_center.gd` | Janela “Centro legislativo” (ver §9) |

Toda a interface fica em cenas `.tscn` (`scenes/ui/legislation/…`); os scripts só preenchem e ligam.

## 3. Modelo de dados

### 3.1 Programa

```
programa = {"next_id": n, "stacks": [pilha...]}
pilha    = {"pos": [x, y], "repealed": bool, "blocks": [bloco...]}
bloco    = {"id": n, "type": "ec_charge",
            "fields": {campo: valor},
            "plugs":  {campo: bloco},        # valores/condições encaixados
            "slots":  {nome: [bloco...]}}    # corpo de blocos de controle
```

- **Cada pilha cujo primeiro bloco é um evento é um artigo** da norma. A ordem de criação dá a numeração.
- `plugs` guardam expressões (um bloco `value` ou `bool` dentro de um campo); `slots` guardam blocos dentro de `Se`, `Enquanto`, `Repetir`, `Para cada`.
- `repealed` marca artigo revogado por versão posterior sem apagá-lo.
- Copiar um modelo para outro programa renumera os ids (`LawProgram.clone`).

### 3.2 Tipos de bloco (`kind`)

| kind | Função | Exemplo |
|---|---|---|
| `event` | Abre um artigo; define *quando* roda | “Todo mês”, “Quando um cidadão ingressar”, “Em {data}”, “Quando esta norma entrar em vigor” |
| `statement` | Instrução com efeito | Criar tributo, conceder direito |
| `cblock` | Instrução com blocos dentro | `Se`, `Se/Senão`, `Enquanto`, `Repetir`, `Para cada` |
| `value` | Número ou texto (campo `out`) | idade do cidadão, dinheiro, operações aritméticas |
| `bool` | Condição | “cidadão trabalha em {profissão}”, `E`/`OU`/`NÃO`, comparações |

Cada bloco declara `rank`: a **menor hierarquia de norma** que pode usá-lo (ex.: um decreto não acessa blocos de lei). Campos têm tipo (`num`, `money`, `pct`, `days`, `bool`, `text`, `date`, `any`, `var`, `choice`, `unit`, `ministry`, `company`, `ref`) e valor inicial `d`.

### 3.3 Norma

Uma norma envolve o programa com metadados: tipo, número, título, ementa, estado, autor, `program` (rascunho), `versions[]` (congeladas na publicação), `current_v`, `process` (log, etapa, espera pelo jogador), `amends`/`revokes` quando altera ou revoga outra. Cada versão guarda `program`, `text`, `code` compilado, `position` (posição ideológica), data, resumo da mudança e hash.

### 3.4 Estados

`Em elaboração → Em tramitação → Aprovada → Aguardando publicação → Publicada → Em vigor`, com saídas `Rejeitada`, `Declarada inválida`, `Suspensa`, `Revogada`, `Expirada`.

## 4. Biblioteca de blocos

Duas fontes, unificadas por `LawCatalog.get_def()` / `categories()`:

1. **Códigos legais** (`LawCode`): Tributário, Trabalhista, Penal, Civil, Eleitoral, Direitos e deveres, Cambial. Cada código traz seus blocos, uma cor de categoria, um `norm_type` (lei complementar, salvo a Constituição), o texto/programa inicial do país (`seed_program`) e o efeito de cada bloco no jogo (`apply`). Adicionar um código = um arquivo em `scripts/sim/codes/` + registro em `LawCodes.SCRIPTS`.
2. **Avançados** (`LawCatalog.BLOCKS`, ~99 blocos): eventos, condições, operadores lógicos, consultas, variáveis, ações administrativas, economia/tributação, direitos/obrigações e controle de fluxo. Servem a quem quer regras próprias.

Dois modos de edição:
- **Lei avulsa:** paleta com os blocos de todos os códigos e, num grupo aberto, os avançados.
- **Norma de código** (alterar o Código X): só a categoria do código e os eventos; o resto fica recolhido a um clique.

## 5. Compilador

`LawCompiler.compile(program, context)` → `{ok, errors, warnings, ir, code, position, text}`.

Etapas: **leitura** (pilhas → artigos), **verificação**, **forma intermediária** (`ir`), **código plano** (`code`) por artigo.

- `context` informa hierarquia da norma, normas existentes, unidades territoriais e instituições, para validar referências e `rank`.
- **Erros** bloqueiam o envio (`ok=false`; nada de `code`). **Avisos** não bloqueiam: “o evento não dispara nenhuma ação”, “bloco nunca executado (há um encerramento antes)”.
- Limite de `MAX_BLOCKS = 400` por programa.
- Variáveis são declaradas por artigo; laços (`Enquanto`, `Repetir`, `Para cada`) são reconhecidos na verificação.
- O texto jurídico sai do mesmo programa (`LawProgram.legal_text`): cada pilha é um artigo, blocos internos viram alíneas.
- O compilador também calcula a **posição ideológica** da norma, usada na votação e na opinião dos eleitores.

## 6. Motor de execução

`LawEngine.run(code, state)` executa um artigo **sem alterar o jogo**: devolve uma lista de efeitos, aplicada depois só se a execução terminar bem.

- Limites: `MAX_STEPS = 4000`, `MAX_REPEAT = 200`. Estourar interrompe a norma com mensagem.
- Só lê o `view` (retrato: sujeito, grupos, preços, tetos, isenções). Não há acesso arbitrário ao mundo.
- **Modo agregado** (jogo): o sujeito é um grupo de `count` milhões de pessoas com valores médios. Uma condição sobre o cidadão vale pela **fração** do grupo em que é verdadeira; cada ramo roda com o peso dessa fração. Isso evita simular cidadão a cidadão.
- **Modo individual** (simulador): o sujeito é uma pessoa; toda condição vale 0 ou 1; pode gerar `trace`.
- `Aguardar N dias` suspende o artigo e devolve uma continuação (`pc`, pesos, quadros, laços), retomada depois.
- Tributos respeitam **tetos e isenções** vigentes antes de virar efeito.

### 6.1 Disparo e aplicação (`Legislation`)

- `fire(world, evento)` reúne os artigos de todas as normas **em vigor** cujo evento coincide e os executa em ordem de **prioridade crescente** (o de maior prioridade roda por último e prevalece).
- Prioridade = hierarquia da norma × 1e7 + especialidade (nº de condições do artigo) × 1e5 + dia de vigência. Ou seja: hierarquia, depois especialidade, depois a mais recente.
- Um artigo não roda duas vezes no mesmo dia pelo mesmo motivo.
- `_commit` converte efeitos em mudanças no mundo; efeitos persistentes são guardados com `stand(...)` enquanto a norma vale e removidos ao revogar/suspender (`_purge_norm`).
- **Falhas:** cada falha de execução é registrada; após `MAX_FAILURES = 3` a norma é **suspensa automaticamente** e há notícia de crise.

## 7. Ciclo de vida de uma norma

### 7.1 Tipos e hierarquia (`NORM_TYPES`)

| Tipo | Hierarquia | Órgão | Votação | Sanção |
|---|---|---|---|---|
| Constituição | 100 | Assembleia Constituinte | qualificada | não |
| Emenda constitucional | 90 | Parlamento | quórum de emenda | não |
| Lei complementar | 70 | Parlamento | absoluta | sim |
| Lei ordinária / Plebiscito | 60 | Parlamento | simples | sim / não |
| Decreto autônomo | 45 | Chefe de governo | — | não |
| Decreto | 40 | Chefe de governo | — | não |
| Resolução | 35 | Parlamento | simples | não |
| Regulamento | 30 | Ministério | — | não |
| Portaria | 20 | Ministério | — | não |

### 7.2 Papéis e permissões

Papéis: **Chefe de governo**, **Líder da oposição**, **Parlamento**, **Corte constitucional**. `ROLE_ACTIONS` define o que cada um pode fazer (criar, editar, apresentar, analisar, votar, aprovar, vetar, promulgar, publicar, revogar, administrar). `can(world, ação, tipo)` combina papel e tipo (`needs`). A interface desabilita ou oculta o que o papel não permite.

### 7.3 Tramitação

Etapas (com dias em `STEP_DAYS`): apresentação → admissibilidade → análise constitucional → discussão → votação (→ segunda casa / segunda votação / intervalo, se bicameral ou emenda) → verificação de quórum → [plebiscito] → sanção (→ veto em análise) → promulgação → publicação → vigência. As etapas variam por tipo (`_steps_for`).

- **Votação:** cada partido vota segundo afinidade com a posição da norma; `roll_call` calcula o resultado; o quórum exigido depende do tipo (`_required_share`).
- **Sanção:** se o jogador é chefe de governo, o processo pode **esperar a decisão dele** (`waiting_player`); sem resposta, há sanção tácita após `TACIT_SANCTION_DAYS = 15`. Veto pode ser derrubado.
- **Controle de constitucionalidade:** a corte pode declarar inválida norma que remove direito protegido, cria tributo confiscatório (> 35%) ou revoga norma de hierarquia superior. Quanto mais democrático o país, mais a corte age de fato.
- **Plebiscito** quando exigido.

### 7.4 Negociação e informação (antes e durante o voto)

- **Efeitos esperados** (`expected_effects`): aprovação, orçamento, grupos sociais, reação dos partidos, caminho previsto. Mostrado em `LawReview` antes de enviar.
- **Chance de aprovação** (`pass_chance`), **pesquisas pagas** com o fundo do partido (`poll`: apoio no parlamento ou popularidade, com margem de erro).
- **Negociação de votos** (`negotiate`, `offer_post`): comprar apoio por preço dependente do partido; **conversa** com líder de partido (`chat_request`) com chance dependente de fatores explícitos.
- **Conflitos** (`find_conflicts`): avisa quando a norma disputa o mesmo parâmetro (alíquota, orçamento, salário mínimo, direito) com outra em vigor e qual prevalece; avisa também sobre direito garantido pela Constituição.

### 7.5 Versões, emendas, revogação

- Publicar congela uma **versão** (programa + texto + código compilado + hash). Versões publicadas abrem **somente para leitura**; mudar exige novo projeto (`start_change`).
- **Emendas** (Constituição): **não há texto livre**, porque o jogo não interpreta o que o jogador escrevesse. O editor de emendas só oferece o que o jogo entende: (1) mudar o **valor** de um artigo com parâmetro (número, sim/não, lista de direitos, sistema eleitoral/de governo); (2) **excluir** um artigo (botão em cada linha, menos cláusulas pétreas); (3) **“Novo artigo com blocos”**, que abre o editor de blocos e vira um artigo que a Constituição executa. Artigos que são só texto (ex.: Art. 1º e 2º) só podem ser excluídos. Há comparação com o texto em vigor (`preview_op`). A simulação ainda aceita operações antigas de texto (`add`/`replace` com `text`) para não quebrar saves e emendas já em tramitação, mas a interface não as cria mais e a IA não propõe emendas de texto.
- **Revogação** total ou por artigos (`start_revocation`); **suspensão** (`suspend`); **expiração** por prazo (`_check_expiry`).
- **Auditoria** (`audit`, até 1500 entradas): toda mudança de estado, execução, falha e suspensão com quem, o quê, antes/depois.

## 8. Editor visual

### 8.1 Estrutura da tela

Biblioteca (campo de busca + categorias que abrem e fecham) · área de programação (`LawCanvas`, pilhas posicionáveis) · propriedades do bloco selecionado · painel de validação (erros/avisos) · texto jurídico gerado · barra de ações (Simular, Apresentar).

### 8.2 Interação

- **Biblioteca:** cada categoria é um grupo que abre e fecha (▸/▾, com a contagem de blocos). Começam fechadas, menos *Eventos* e, ao alterar um código, a categoria desse código; “Avançado” e “Outros códigos” são grupos maiores que contêm categorias. O campo **Buscar bloco...** filtra pelo texto do bloco como o jogador o vê (sem diferenciar maiúsculas nem acentos: “acao” acha “ação”; casar com o nome de uma categoria mostra a categoria inteira), abre só os grupos com resultado, esconde o resto e mostra “Nenhum bloco encontrado.” se nada casa. Ao limpar a busca (ou com Esc no campo), volta ao que o jogador tinha aberto.
- Arrastar da biblioteca **cria uma cópia**; arrastar na área move; soltar na lixeira apaga.
- Alvos de soltura (`drop`, único ponto que altera o programa): `canvas`, `after`, `before`, `slot`, `plug`, `trash`. `can_move_to` e `can_plug` validam antes (um bloco não entra em si mesmo; `LawProgram.accepts` confere tipo do encaixe).
- Retirar um bloco leva **todos os de baixo** na pilha (como Scratch); “apagar um” mantém os de baixo no lugar.
- Os encaixes são desenhados com dente e chapéu (`LawBlockView`: `NOTCH_*`, `HAT`), cor da categoria e borda vermelha em erro, branca em seleção. A boca de `cblock` acompanha o layout da coluna.
- Campos: `ref` mostra lista do que existe (tributos, licenças, instituições, deveres) com “Outro nome” para criar algo novo; o painel de propriedades **não é refeito durante a edição**, para o campo não perder o foco.
- Compilação **contínua**: cada edição recompila e atualiza a validação.

### 8.3 Fluxo de envio

`Apresentar` → painel de **efeitos esperados** (`LawReview`) → botão **enviar** → norma entra em tramitação. O **Simulador** (`LawSimulator`) roda o programa com um cidadão fictício (evento, profissão, território) e mostra o cálculo; **não cobra nada nem muda a partida**.

### 8.4 Modelos

`LawTemplates` traz leis prontas (imposto predial, salário mínimo, renda básica, socorro à indústria, direito de greve, isenção a pequenos negócios, pisos de educação/saúde, teto de defesa, ordem pública, liberdade de associação). Servem de ponto de partida do jogador e de **projetos que os partidos da IA apresentam** (até `MAX_AI_PENDING = 3` ao mesmo tempo).

## 9. Centro legislativo (hub)

Janela flutuante (índice 10 da mesa de janelas), reconstruída por `main.open_legislation(aba, mensagem)`. Primeira aba: **códigos** (cartões com artigos, alterações pendentes, ler/alterar), **projetos em tramitação** (negociar, conversar, sancionar/vetar, pesquisa), **normas** (filtro por estado) e criação de lei avulsa/modelo/emenda/importação. Demais abas: Constituição, instituições, auditoria, tratados.

**Atualização contínua.** O HUD chama `refresh()` do centro a cada ~0,25 s; o centro compara uma **assinatura** do estado (tamanho da auditoria e das normas, papel, fundo do partido, e para cada norma: estado, espera pelo jogador e tamanho do log; tratados) e só reconstrói as listas quando ela muda, para não destruir botões no meio de um clique. Coberto por `--ui-legislation`.

## 10. Persistência e interoperabilidade

- Normas, versões, auditoria, variáveis e pendências fazem parte do estado do mundo (`to_dict`) e do save.
- **Exportar/importar** normas em `user://legislacao/` (`EXPORT_FORMAT = 1`), para reaproveitar leis entre partidas.
- A simulação roda em outra thread; o registro de códigos é montado uma vez (`LawCodes.warm`) e depois é só leitura. Código de códigos não toca em nós nem sinais; notícias só por `world.emit_news`.

## 11. Testes

| Teste | Cobre |
|---|---|
| `--ui-legislation` | Fluxo completo com arrastar e soltar reais, simulador, apresentação, negociação, conversa, tramitação até a vigência, leitura de versão, emendas, e atualização do centro com a janela aberta |
| `--ui-desk` | Janelas flutuantes (inclui o centro) |
| `--ui-locale` | Centro legislativo e editor em inglês/espanhol |
| `tests/legislation.gd`, `code_tributario.gd`, `code_penal_civil.gd`, `code_trabalho_eleicoes.gd`, `direitos.gd` | Regras, códigos legais e direitos (simulação) |
| `--ui-threads` | Cliques durante a simulação (um limite de tempo de quadro é instável) |

## 12. Questões em aberto

- **[aberto]** Filtro da aba Auditoria só recebe tipos novos ao reabrir a janela; a lista atualiza.
- **[aberto]** O limite de quadro em `--ui-threads` (“carregar não trava a tela”) falha de forma intermitente.
- **[aberto]** Não há depuração passo a passo no jogo; o simulador mostra o cálculo de um cidadão, mas não rastreia uma norma em vigor ao longo do tempo.
- **[aberto]** Blocos novos em códigos exigem tradução manual dos `msgid` (o jogo mantém `locale/*.po`); não há verificação automática de cobertura por bloco.
- **[aberto]** Conflitos só são detectados para parâmetros listados em `_claims` (alíquotas, orçamento, parâmetros, salário mínimo, direitos); outros efeitos de blocos novos precisam ser registrados ali para aparecer.
- **[aberto]** Revisar o equilíbrio de preços de negociação (`DEAL_*`) e das chances de conversa (`CHAT_*`) com jogadores reais.

## 13. Como estender

1. **Novo bloco avançado:** adicionar ao `BLOCKS` do catálogo (id, `cat`, `kind`, `text` com `{campos}`, `fields`, `rank`), tratar no compilador (verificação/IR) e no motor (`_act`/`_eval`), e dar efeito em `Legislation._commit`.
2. **Novo código legal:** criar `scripts/sim/codes/code_x.gd` herdando `LawCode` (`id`, `title`, `category`, `norm_type`, `blocks()`, `seed_program()`, `apply()`), registrar em `LawCodes.SCRIPTS`, e cobrir com um teste de simulação.
3. **Novo tipo de norma:** entrada em `NORM_TYPES` (hierarquia, órgão, votação, sanção, `needs`), etapas em `_steps_for`, e permissões em `ROLE_ACTIONS`.
4. **Nova aba/lista no centro:** cena `.tscn` própria, preenchimento em `legislation_center.gd`, e incluir o que muda na `_signature()` para o refresh contínuo.
