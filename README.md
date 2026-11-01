# Global Mandate

Jogo de geopolítica em tempo real sobre um modelo econômico mundial, feito em Godot 4.7.
Você assume o governo de um país em janeiro de 2025 e joga por quanto tempo quiser. Perder uma eleição não encerra o jogo: você passa a liderar a oposição e pode voltar ao poder. A partida só acaba com golpe, revolução, derrota militar, guerra nuclear ou o fim do seu país.

## Como rodar

Abra a pasta no Godot 4.7 e pressione F5, ou execute na raiz do projeto:

```bash
godot --path .
```

## Controles

| Ação | Comando |
| --- | --- |
| Pausar | Espaço |
| Velocidade normal, 2x e 4x | 1, 2, 3 ou 4 |
| Avançar 7 ou 30 dias | Botões **+7 dias** e **+30 dias** |
| Mover o mapa | Arrastar, WASD ou setas |
| Zoom | Roda do mouse |
| Dossiê e diplomacia | Clicar no país |
| Desenhar unidade subnacional | N |
| Desfazer vértice | Botão direito ou Backspace |
| Cancelar desenho | Esc |
| Menu, salvar e carregar | Esc |
| Tela cheia | F11 |
| Menu debug | F12 |

## Tempo

O relógio mostra data e hora. Na velocidade normal, cada 0,05 s é 1 minuto de jogo, ou seja, um dia dura 72 s. Em 2x, dura 36 s, e em 4x, 18 s. Os dígitos dos minutos trocam rápido demais para o olho em qualquer velocidade, então a barra também tem um relógio analógico: o ponteiro longo dá uma volta por hora de jogo, a cada 3 s em 1x, 1,5 s em 2x e 0,75 s em 4x, e o anel em volta enche ao longo do dia. Ao lado dos botões, a barra mostra o ritmo real do relógio em minutos por segundo: 20, 40 ou 80, em vermelho se estiver longe do esperado. A simulação é diária: a economia, as guerras e os mercados andam à meia-noite, e o que se move durante o dia é o relógio.

Os botões **+7 dias** e **+30 dias** rodam a mesma simulação de cada dia sem esperar o relógio, mantêm a hora atual e mostram um resumo com os indicadores do país e o noticiário do período. Uma decisão que apareça no meio para o avanço, que continua depois da resposta.

Os eventos aleatórios (seca, pandemia, desastres, protestos, onda tecnológica, choque de oferta e dilemas de governo) estão desligados por enquanto, em `RANDOM_EVENTS` de `events.gd`, e podem ser disparados pelo menu debug. Continuam ativos as decisões da IA, inclusive propostas e ameaças ao jogador, as eleições, as crises econômicas calculadas pelo modelo e a variação diária dos mercados.

## Unidades subnacionais

O cenário já começa com as 4.220 unidades de 1º nível dos 170 países, como estados, províncias e departamentos, e com os 5.564 municípios do Brasil dentro dos estados. As divisas aparecem no mapa conforme o zoom, primeiro as dos estados e depois as dos municípios, e passar o mouse mostra o nome e o tipo da unidade mais específica, em qualquer país.

Na aba **Divisões** você edita o seu país, incluindo territórios anexados:

1. Escolha o tipo da unidade pelo marcador. Cada país tem os próprios tipos, com o nome que você quiser: edite os existentes ou crie novos com **+ Novo tipo**.
2. Selecione a unidade-mãe na lista ou no mapa. O primeiro clique no mapa seleciona o estado, e clicar de novo dentro dele desce para o município. Na lista, a seta abre as unidades de dentro, e o campo de busca encontra qualquer uma pelo nome. Um desenho só é aceito em área livre: como os estados cobrem o Brasil e os municípios cobrem os estados, desenhe dentro de um município ou apague antes o que ocupa a área.
3. Pressione **N** e clique no mapa para colocar os vértices. As arestas não podem se cruzar.
4. Clique no primeiro ponto para fechar o polígono. A unidade é criada com um nome próprio automático, que pode ser trocado depois. A hierarquia não tem limite de níveis.

Qualquer unidade pode ser capital de cada unidade que a contém e do país: selecione-a e use os botões da seção **Capital**, que também removem a função. Cada unidade ou país tem uma capital por vez, e escolher outra substitui a anterior. O Brasil já começa com Brasília e as 27 capitais estaduais, e os outros 169 países com a capital nacional na posição real. Quando a capital não é uma província inteira, ela é uma unidade pequena do tipo "Cidade" dentro da província. No mapa, a capital do seu país tem uma estrela dourada grande, as dos outros países, uma menor, e as das unidades, uma estrela clara, todas com zoom, menos a sua. Numa fusão, a nova unidade herda o papel de capital. Num desmembramento, a capital fica com a parte onde está. Se uma guerra entrega a capital nacional a outro país, o país fica sem capital até escolher outra. Por enquanto a capital não afeta a economia, as guerras nem a política.

O traçado é recortado automaticamente pela fronteira nacional e pela unidade-mãe, e não invade as unidades vizinhas do mesmo nível. Para fundir, selecione uma unidade, use **Fundir com...** e clique nas vizinhas do mesmo nível: a resultante fica com o nome e o tipo da primeira, e as filhas passam para ela. Para desmembrar, selecione a unidade, use **Desmembrar** e contorne no mapa a parte que vai se separar; ela vira uma unidade irmã, com nome automático, e as filhas seguem a parte onde está o centro delas. Apagar uma unidade apaga as que estão dentro dela. Um tipo só pode ser apagado quando nenhuma unidade o usa. Por enquanto as unidades são apenas organização territorial: não alteram a economia nem a política.

## Fronteiras

As fronteiras só mudam quando uma guerra termina. O desenho usa os mesmos vértices das unidades subnacionais, e o tempo fica parado enquanto você demarca.

- **Você venceu** (capitulação, paz com a frente a seu favor ou invasor expulso): escolha **Demarcar novas fronteiras**, para desenhar uma ou mais áreas até o limite do que foi conquistado, ou **Não ficar com território**, que encerra a guerra e melhora a reputação. Na capitulação continuam existindo as opções de anexar e de instalar governo aliado.
- **Paz sem vencedor** (frente entre -15 e +15): escolha **Restabelecer fronteiras antigas** ou **Propor novas fronteiras**. Cada traçado vale como pedido, se cair mais sobre o rival, ou como oferta, se cair mais sobre o seu país. O rival compara o saldo em PIB e tolera mais quando a frente está contra ele ou quando está cansado. Depois de 3 recusas, as fronteiras antigas voltam a valer.
- **Você perdeu ou a guerra é entre outros países:** o vencedor fica com unidades subnacionais inteiras, das mais próximas dele para as mais distantes, até chegar perto da fração do tratado. Um país com uma só unidade não perde nada dessa forma.

A população, o capital, as commodities e o PIB acompanham a fração de área cedida, e as unidades subnacionais mudam de dono, inteiras ou cortadas pelo traçado. A área é medida no mapa, então uma faixa pequena vale o mesmo por km² em qualquer parte do país: o jogo não sabe onde estão as cidades.

## Personagem

Ao assumir o governo, você cria o seu líder no estilo stickman: nome, cabelo, olhos, formato do rosto, formato do corpo, com silhueta cheia como a de uma placa de sanitário, e roupa, ou um sorteio com **Aleatório**. Uma roda de cor define as cores dos olhos, do cabelo e da roupa. A pele é escolhida ao longo da escala Monk de tons de pele, então fica limitada às cores reais da espécie humana. As peças são desenhadas no VectorCraft por `tools/build_character_art.mjs`, que precisa do `vectorcraft-cli` e grava os PNGs em `assets/character`. O retrato aparece na barra superior e na aba **Painel**, onde **Editar personagem** reabre o criador.

## Partidos e parlamento

Cada um dos 170 países tem partidos fictícios, gerados por família política (socialista, trabalhista, verde, social-democrata, centro, liberal, democrata-cristão, conservador e nacionalista), e um parlamento com assentos distribuídos pelos votos, com cláusula de barreira de 3%. O tamanho segue a raiz cúbica da população, entre 30 e 700 assentos. Regimes fechados têm um partido dominante.

Ao assumir o governo, você escolhe um partido, cujas ideias passa a adotar, ou cria o seu, definindo a bússola dele, que vira o partido do governo com a bancada que tiver. Na aba **Política**, você vê o plenário e a coalizão, convida ou tira partidos do governo, troca de partido e leva projetos de lei a voto. Cada projeto vai ao parlamento, leva semanas para ser deliberado e só volta à pauta depois de 6 meses. A coalizão vota a favor, salvo quem discorda muito, e a oposição só apoia o que está perto das próprias ideias. Eleições Antecipadas precisam de 3/5 dos assentos.

Nas eleições, a aprovação move os votos do seu partido e dos aliados, e você continua se o seu partido for o maior ou se a coalizão mantiver a maioria. Governo sem maioria perde estabilidade aos poucos, e com aprovação abaixo de 20% e menos de 1/3 dos assentos pode sofrer impeachment. O governo define os gastos sozinho na aba Fiscal, e a mudança vale na hora. Só fica travado o campo que uma lei em vigor obrigar, com o bloco **Obrigar o orçamento**. Impostos e tarifa só mudam por lei no editor de blocos.

## Oposição

Antes de começar, na escolha de partido, você decide entre **Governar** e **Liderar a oposição**, com qualquer partido ou um criado por você. Na oposição, o partido que já governa continua no poder e fica indisponível para você. Regimes fechados não têm eleições, então neles só é possível governar.

Ao perder uma eleição ou sofrer impeachment, você continua no mesmo país como líder do seu partido, e a IA passa a governar: orçamento, juros, diplomacia e guerras saem das suas mãos, e os controles só mostram o que ela decide. Na aba **Política**, você pode criticar o governo, fazer campanha e apresentar moção de censura, que só derruba o governo se a oposição somar a maioria dos assentos. Na eleição seguinte, quanto pior a aprovação do governo, melhor para o seu partido, e você volta ao poder se ele for o maior.

## Políticos e bússola política

Cada partido tem de 5 a 8 políticos, cada um com a própria posição na bússola política (economia e autoridade), competência e aparência. A bússola do partido é a média dos políticos dele. Você também é um político: define suas ideias clicando na bússola ao escolher o partido, e a média do partido muda quando você entra, sai ou muda de ideias. Clique em um partido, na aba **Política**, para ver os políticos.

## Ministros

Na aba **Ministros**, você escolhe entre os políticos dos partidos da coalizão para sete pastas: Fazenda, Relações Exteriores, Defesa, Saúde, Educação, Infraestrutura e Justiça. Competência acima de 50% ajuda a pasta, e abaixo atrapalha, todo mês. Pasta vaga conta como 30%. Um aliado sem nenhum ministério pode abandonar o governo, e partido que sai leva os ministros.

## Conversa com líderes

No dossiê de um país, **Falar com o líder** abre uma conversa com escolhas: elogiar, propor livre comércio ou pacto de defesa, enviar ajuda, pedir sanções contra um inimigo, protestar, ameaçar ou, em guerra, propor paz. O líder responde conforme a relação entre os países, a distância entre as bússolas e a competência do seu chanceler. Cada conversa tem até 3 falas, uma por mês com cada líder. Os botões de política externa continuam no dossiê.

## Menu debug

**F12**, ou **Menu debug** na pausa, abre um painel que dispara à mão os sistemas do jogo: tempo, jogador, economia, mercados, eventos e dilemas, diplomacia, guerra, fronteiras, unidades, interface e finais de jogo. Os comandos agem sobre o jogador ou sobre o país-alvo, escolhido na lista ou com um clique no mapa. O alvo começa no seu país; o que exige outro país, como declarar guerra, fica em cinza até você escolher um. O campo de filtro encontra um comando pelo nome. O menu fica sempre disponível e os comandos valem como trapaça: a pontuação não marca a partida.

## Legislação

O **Centro legislativo** (tecla L ou aba Política) cria normas com blocos, como no Scratch: cada pilha que começa com um evento é um artigo. Há biblioteca, área de programação, propriedades do bloco, validação e simulador. As telas ficam em `scenes/ui/legislation/`.

**Tributos só mudam por lei.** O país começa com um Código Tributário em blocos, e os botões das abas Fiscal e Comércio abrem o editor com as alíquotas em vigor. Os controles deslizantes ficaram para gastos, mobilização, emissão e juro.

**O parlamento delibera.** Normas e projetos prontos passam por discussão e votação, cerca de um mês por casa. Países com duas casas têm uma aba para a Câmara e outra para o Senado na aba Política, cada uma com a própria bancada, e a norma precisa passar nas duas.

**A Constituição muda por emenda.** A emenda altera, substitui, acrescenta ou exclui dispositivos. Novos artigos podem ser só texto ou programados com blocos, e os programados executam como qualquer norma. Excluir o artigo de um poder, como o veto, acaba com esse poder. Cláusulas pétreas não podem mudar, e toda versão anterior fica guardada.

O jogo não tem cidadãos individuais: cada evento roda sobre um grupo agregado, e uma condição vale pela fração do grupo em que é verdadeira. O simulador roda o mesmo programa com uma pessoa fictícia. Só o país do jogador tem normas. Na oposição, quem ajusta os tributos é a IA do governo, sem passar pelo editor.

## Juros

Em democracias consolidadas e na zona do euro, o banco central é independente: ele decide o juro sozinho, e nem o jogador nem os outros governos escolhem. A independência está na Constituição do seu país e pode mudar por emenda. Com banco subordinado, o governo pode fixar o juro à mão, ao custo de credibilidade, e líderes de esquerda ou impopulares fazem isso sozinhos.

## Eleições

Cada país vota por distritos, nas unidades subnacionais, com cadeiras repartidas pela população. O sistema pode ser proporcional (D'Hondt), distrital de maioria simples, distrital em dois turnos ou misto, com cláusula de barreira. No presidencialismo, o chefe de governo é eleito direto em dois turnos, e o parlamento pode sair contra ele; no parlamentarismo, governa quem forma maioria. O senado elege o mesmo número de senadores por unidade. A Constituição do seu país define tudo isso e pode mudar por emenda. A aba Política mostra o resultado da última eleição.

As unidades têm população. Os estados do Brasil e dos EUA usam números do censo, arredondados. O resto do mundo é estimado pela área, e os municípios repartem a população do estado do mesmo jeito.

## Plebiscito

A norma do tipo **Plebiscito** passa pelo parlamento e depois pelas urnas: só vale se a maioria do eleitorado aprovar. O resultado depende da popularidade da proposta, que a pesquisa paga estima. Em países democráticos, criar ou desmembrar uma unidade subnacional segue o mesmo rito, e a unidade só nasce no fim dele.

## Ministérios

Os blocos **Criar**, **Fundir** e **Extinguir ministério**, no editor de leis, mudam o gabinete. Ministério a mais custa dinheiro, e a menos economiza, mas a área sem titular fica mal cuidada, e quem acumula áreas rende menos em cada uma. Revogada a lei, os ministérios voltam ao que eram.

## Vida e fim de carreira

Todos os políticos têm idade, inclusive você, adoecem e morrem, com risco crescente pela idade. Morto o líder de um partido, o mais competente assume. Todo janeiro, os partidos ganham nomes novos.

O jogo só termina para o seu personagem em impeachment, golpe, renúncia, assassinato ou morte. Aí você escolhe entre um novo jogo e assumir outro personagem na mesma partida. Perder uma eleição ou uma guerra leva à oposição; em regime fechado, sem eleições para disputar, perder a guerra derruba o líder. Se o seu país deixar de existir, o novo personagem começa em quem o anexou.

## Conversas e tratados

O líder responde pela relação entre os países, pela distância entre a bússola dele e a do seu partido e pelo que ele mesmo pensa de cada assunto: quem é de direita abre mercados mais fácil, e um autoritário só recua diante de muito mais força. Os líderes também tomam a iniciativa: se reúnem entre si, e às vezes pedem para falar com você.

Tratados seguem o rito da vida real: negociação, assinatura, ratificação pelos parlamentos, vigência por um prazo e denúncia com seis meses de aviso. Há livre comércio, união aduaneira, defesa mútua, não agressão, controle de armas, clima, extradição e investimentos. O mundo já começa com tratados como o do Atlântico Norte. Proponha pelo dossiê do outro país e acompanhe na aba **Tratados** do Centro legislativo.

## O mundo age sozinho

Todo mês, os governos dos outros países agem conforme a bússola do líder. À esquerda gastam e tributam mais; à direita cortam e abrem o comércio. Autoritários armam o país, brigam mais e governam por decreto; libertários investem em educação e preferem acordos. Eles fecham comércio e pactos, trocam missões, criticam, impõem tarifas e sanções, inclusive contra você, e entram em guerra. Ideias parecidas aproximam os países, e ideias opostas os afastam. O noticiário mostra o que envolve você ou grandes economias.

Em todo país com parlamento livre, os partidos propõem projetos conforme as próprias ideias, e as bancadas votam semanas depois. O dossiê mostra o que está em debate e as últimas votações. Regimes autoritários não têm propostas do parlamento. No seu país, os partidos também apresentam projetos, que aparecem na tramitação.

## Negociar votos

Na tramitação, **Negociar votos** pede o voto de cada bancada, a favor ou contra, inclusive em projetos de outros partidos. O preço segue o tamanho da bancada e sai do fundo do seu partido; a oferta generosa custa o dobro e tem mais chance. Quanto mais longe das ideias do partido, mais difícil virar o voto. A recusa não custa nada, mas encerra a conversa sobre aquela proposta. No governo, também é possível oferecer a entrada na coalizão. Sua própria bancada segue a orientação de graça.

## Fundo dos partidos

Cada partido tem um fundo em dinheiro, que recebe todo mês conforme a votação. O do seu partido aparece no alto da tela e paga, cada um com seu preço: pesquisa de popularidade (a mais cara), campanha, moção de censura, pesquisa de apoios no parlamento, crítica ao governo e convite a um partido. Os preços acompanham o tamanho da economia.

Não há previsão gratuita de votos. A **pesquisa de apoios** mostra como cada bancada deve votar, por casa, com margem de erro. A **pesquisa de popularidade** mostra quantos eleitores aprovam a proposta. A popularidade conta de verdade: quando a norma entra em vigor, uma impopular tira aprovação do governo, e uma popular dá.

As ações externas não têm custo: a mesma ação com o mesmo país só se repete depois de 30 dias.

## Editar a interface

Todos os menus são cenas em `scenes/ui/`, abertas e editadas no Godot:

- `start_screen.tscn`: tela inicial.
- `hud.tscn`: barra superior, painel do governo com as abas, dossiê, modos de mapa, noticiário e avisos.
- `panels/`: abas Divisões, Política e Ministros, painel de fronteiras e menu debug.
- `modals/`: pausa, ajuda, confirmação, decisão, criador de personagem, escolha de partido, partido, ministro, conversa e fim de jogo.
- `rows/`: linhas que se repetem em listas, como notícia, partido, ministro e unidade.
- `theme.tres`: tema geral. As imagens do controle deslizante ficam em `assets/ui/`.

Textos, tamanhos, cores e posições podem mudar à vontade no editor. Os scripts acham os nós pelo nome único (`%`), então renomear um nó marcado com `%` exige trocar o nome no script. Nós com prefixo, como `top_gdp`, `slider_tax_income`, `dossier_pop` ou `action_war`, recebem valores pelo nome e podem ser movidos para qualquer lugar da mesma cena. As partes do dossiê que só aparecem para outro país estão no grupo `foreign_only`, e as da escolha de partido que só aparecem no início, em `at_start_only`.

Parte dos textos muda durante o jogo: o que o script escreve em um rótulo, como valores e nomes de país, substitui o texto da cena. Os gráficos, retratos e bússolas são desenhados por script e aparecem vazios no editor. Os comandos do menu debug são gerados a partir da lista em `debug_menu.gd`.

## O modelo

São 170 países com PIB, população, dívida, inflação, juros, exportações, forças armadas e produção
de commodities próprios. Cada um roda a mesma economia todo mês:

- **Oferta:** função de produção de Solow com capital, trabalho, capital humano e produtividade, com convergência de renda.
- **Demanda:** hiato do produto movido por juro real, impulso fiscal, demanda dos parceiros, câmbio real, termos de troca, crédito e confiança.
- **Preços:** curva de Phillips com expectativas ancoradas pela credibilidade do banco central, repasse cambial e choques de energia e alimentos.
- **Política monetária:** regra de Taylor, zona do euro com BCE comum, âncoras no dólar que podem quebrar.
- **Câmbio:** paridade de poder de compra, diferencial de juros real, conta corrente e prêmio de risco.
- **Contas públicas:** impostos com curva de Laffer, estabilizadores automáticos, dívida em moeda local e em dólar, prêmio de risco endógeno, nota de crédito, FMI e moratória.
- **Comércio:** matriz bilateral gravitacional, alterada por tarifas, acordos, sanções e guerras.
- **Commodities:** petróleo, gás, grãos, metais e chips com oferta por país, estoques e OPEP+.
- **Crises financeiras:** ciclo de crédito que produz crises bancárias e contágio global.

Por cima disso roda a geopolítica: relações bilaterais, alianças, sanções, guerras com frente e
atrito, dissuasão nuclear, eleições, golpes e nações com IA própria.

## Dados

- Fronteiras: Natural Earth (domínio público), via pacote `world-atlas`. `tools/build_map.mjs` gera `data/map.json`.
Os arquivos brutos ficam em `tools/raw/`, fora do repositório. Só é preciso baixá-los para gerar `data/` de novo; o jogo roda sem eles.

- Unidades subnacionais: Natural Earth admin-1 10m (domínio público). `tools/build_admin1.mjs` gera `data/admin1.json` a partir de `tools/raw/ne_10m_admin_1.geojson`, que o jogo não usa diretamente. Os nomes seguem a fonte, sem tradução, e a atribuição de territórios disputados segue o controle de fato adotado por ela. Municípios e outros níveis abaixo do 1º não estão incluídos.
- Municípios do Brasil: malha do IBGE publicada pelo projeto `tbrugz/geodata-br` (CC0). `tools/build_municipios.mjs` gera `data/municipios.json` a partir de `tools/raw/geojs-100-mun.json`. A malha tem 5.564 municípios, menos que os 5.570 atuais: os criados depois dela aparecem dentro do município de origem. 
- Limites: `tools/clip_units.gd` recorta os estados pelo contorno do país e os municípios pelo estado, com áreas e linhas. Unidades inteiramente fora do contorno, como ilhas que o mapa não tem, viram um marcador pequeno na borda mais próxima. Para gerar tudo do zero, rode `build_map.mjs`, `build_admin1.mjs`, `build_municipios.mjs` e esse script, nessa ordem.
- Capitais nacionais: Natural Earth populated places 10m (domínio público). `tools/build_capitais.mjs` gera `data/capitais.json`, com nomes em português de uma tabela própria, digitada de memória, e correções onde a fonte marca várias capitais ou a maior cidade. Em capitais disputadas, como Jerusalém, o jogo segue a fonte. Rode esse script antes de `clip_units.gd`.
- Economia e forças armadas: `data/countries.csv`, valores aproximados de 2024 digitados de memória para fins de jogo. Não foram conferidos com as fontes e não servem como referência factual.

Microestados e pequenas ilhas aparecem no mapa como territórios neutros.

## Desempenho

A simulação de cada dia, salvar, carregar e abrir o jogo rodam em outras threads, e a tela continua desenhando. Só a thread principal cria nós e fala com a interface. O mundo tem um dono de cada vez: enquanto uma thread trabalha nele, `world.busy` fica ligado e a interface não lê nem muda nada; um clique ou uma tecla espera ela terminar, e os sinais da simulação ficam na fila até lá. O código da simulação nunca deve tocar em nós nem emitir sinais diretamente: use `_send`, em `world.gd`. Abrir o mapa triangula cada país em paralelo, nos núcleos disponíveis.

`--ui-profile` mede o tempo de cada operação pesada, e `--ui-threads` testa a virada de mês, cliques no meio da simulação, decisões durante o avanço de dias e o save.

## Testes

`society.gd` e `--ui-society` testam idade e morte, eleições, plebiscito, unidades com rito, ministérios, fim de carreira, conversas e tratados.

`world_ai.gd` deixa o mundo correr sozinho e imprime o que aconteceu.

`tests/scenes.gd` abre todas as cenas e recusa nomes repetidos sob o mesmo pai. `legislation.gd` e `--ui-legislation` testam leis, tramitação, fundo, pesquisas, emendas e o arrastar de blocos.

`--ui-layout --shots=DIR` registra posição e estilo de cada controle em todas as telas, em `layout.txt`, com uma captura de cada uma. Rodar antes e depois de mudar uma cena mostra o que saiu do lugar.

```bash
godot --headless --path . -s tests/policy.gd
```

```bash
godot --headless --path . -s tests/calibrate.gd -- 15 42
```

```bash
godot --headless --path . -s tests/calibrate.gd -- 5 42 taiwan
```

```bash
godot --path . -- --ui-test --shots=/tmp/shots
```

```bash
godot --headless --path . -s tests/subdivisions.gd
```

```bash
godot --path . -- --ui-divisions --shots=/tmp/shots
```

```bash
godot --path . -- --ui-debug --shots=/tmp/shots
```

```bash
godot --headless --path . -s tests/borders.gd
```

```bash
godot --headless --path . -s tests/statecraft.gd
```

```bash
godot --path . -- --ui-statecraft --shots=/tmp/shots
```

```bash
godot --headless --path . -s tests/politics.gd
```

```bash
godot --path . -- --ui-politics --shots=/tmp/shots
```

```bash
godot --headless --path . -s tests/clock.gd
```

```bash
godot --path . -- --ui-clock --shots=/tmp/shots
```

```bash
godot --headless --path . -s tests/capitals.gd
```

```bash
godot --path . -- --ui-capitals --shots=/tmp/shots
```

```bash
godot --path . -- --ui-borders --shots=/tmp/shots
```

`statecraft.gd` e `--ui-statecraft` testam oposição, políticos, bússola, ministros e conversas. `politics.gd` e `--ui-politics` testam partidos, parlamento, votações, eleições e o criador de personagem. `clock.gd` e `--ui-clock` testam o relógio, as velocidades, o avanço de dias e a ausência de eventos aleatórios. `capitals.gd` e `--ui-capitals` testam as capitais no modelo e na interface. `--ui-debug` aperta todos os comandos do menu debug, um por vez. `borders.gd` testa fusões, desmembramentos, cessões e todos os finais de guerra. `--ui-borders` passa pelo criador de personagem, funde, desmembra, demarca e negocia com cliques no mapa. `subdivisions.gd` testa tipos, recortes, hierarquia e salvamento das unidades. `--ui-divisions` desenha unidades com cliques no mapa e salva capturas de tela. `policy.gd` confere o efeito de cada alavanca do jogador contra um controle. `calibrate.gd` imprime
os indicadores mundiais ano a ano, com os cenários opcionais `taiwan` e `hormuz`. `--ui-test` joga
sozinho pela interface e salva capturas de tela.
