# Global Mandate

A real-time geopolitical game built on a world economic model, made with Godot 4.7.
You take over the government of a country in January 2025 and play for as long as you like. Losing an election does not end the game: you become the leader of the opposition and can come back to power. The game only ends with a coup, a revolution, a military defeat, a nuclear war or the end of your country.

The game is available in Portuguese, English and Spanish. Pick the language on the start screen or in the pause menu (Esc).

## Running

Open the folder in Godot 4.7 and press F5, or run from the project root:

```bash
godot --path .
```

## Controls

| Action | Input |
| --- | --- |
| Pause | Space |
| Normal speed, 2x and 4x | 1, 2, 3 or 4 |
| Skip 7 or 30 days | **+7 dias** and **+30 dias** buttons |
| Pan the map | Drag, WASD or arrow keys |
| Zoom | Mouse wheel |
| Dossier and diplomacy | Click a country |
| Open or close a government window | Click its icon in the dock |
| Legislative center | L, or the document icon in the dock |
| Draw a subnational unit | N |
| Undo vertex | Right click or Backspace |
| Cancel drawing | Esc |
| Menu, save and load | Esc |
| Fullscreen | F11 |
| Debug menu | F12 |

## Interface: floating windows and the dock

The government panels are floating windows, like the windows of a desktop app. A dock at the bottom of the screen, in the style of the macOS Dock, holds one icon per window, grouped by theme:

- **Government:** Panel, Politics, Ministers and Legislation.
- **Economy:** Fiscal, Currency, Trade and Economy.
- **Security:** Military and Divisions.
- **World:** World.

Clicking an icon opens the window in the center of the screen. Clicking it again brings the window to the front, and clicking it once more while it is in front minimizes it. A dot under the icon marks open windows, and the icons grow under the mouse.

Each window is dragged by its title bar and resized by its bottom-right corner. The red button closes it, the yellow one minimizes it and the green one stretches it to the full height of the screen; double-clicking the title bar does the same. Clicking anywhere on a window brings it to the front. With no window open, the map is free. The legislative center is also a window of the dock and does not block the rest of the screen.

The top bar shows the date, the speed buttons, the main indicators and the party fund. The news feed sits in the bottom-left corner and the map modes in the top-left corner.

## Time

At normal speed (1x) one game day passes per real second; at 2x, two days, and at 4x, four. The game has no hours: the top bar shows only the date. Next to the buttons, the bar shows the actual rate in days per second, in red if it is far from the expected value. The economy is calculated once a month, on the 1st, for every country at the same time, together with commodity prices and global risk; wars, parliament and the AI's decisions move day by day.

The **+7 dias** and **+30 dias** buttons run the same daily simulation without waiting for the clock and show a summary with the country's indicators and the news of the period. A decision that comes up midway pauses the skip, which resumes after you answer.

Random events (drought, pandemic, disasters, protests, technology boom, supply shock and government dilemmas) are turned off for now, in `RANDOM_EVENTS` in `events.gd`, and can be triggered from the debug menu. AI decisions (including proposals and threats to the player), elections, economic crises computed by the model and daily market moves are still active.

## Economy

### Sectors

GDP is split into ten sectors: agriculture, mining and energy, industry, construction, trade, transport and logistics, financial services, technology and communication, tourism and public services. The starting mix comes from income per capita and commodity production, with calibrated values for the largest economies. Each sector reacts to the cycle in its own way: construction feels interest rates, mining feels ore prices, and tourism feels war and instability. The **Economy** window (Sectors tab) shows each sector's output, share of GDP and growth over 12 months.

### Ports and airports

Each country has its real main ports and airports, with capacity in TEU, tonnes or passengers. Port demand follows foreign trade and airport demand follows GDP and tourism. Cargo goes to its usual facility first and spills over to those with spare capacity. The country's saturation (demand divided by capacity) sets its logistics: congested ports and airports hold back part of foreign trade and slow the transport and tourism sectors. The effect is measured against the starting saturation, which is already built into the starting GDP.

In the **Infrastructure** tab you can expand a facility (a construction project that takes time and money), grant it as a concession to private operators (the state collects a share of the replacement cost and a concession runs a little more efficiently) or see who operates it. War damages facilities and occupation closes them. Ports and airports appear as markers on the map. Landlocked countries have no seaport.

### Companies and stock exchange

Each country has companies, real for the large economies and generated for the rest. Each one bills a share of its sector's output. Margins feel the cycle, interest rates and the exchange rate, and the value is profit times a P/E that falls when rates and risk go up. Companies are either **publicly traded** (open capital, listed on the exchange) or **privately held** (closed capital), and the state may own all or part of them. The rest of the listed market enters as "other companies", which follows nominal GDP. The country's stock index comes from all of this. The **Companies** and **Stock exchange** tabs show the companies, their owners and the index history.

Companies change hands by law: the **Privatize** and **Nationalize** blocks in the law editor sell or buy the state's stake. A strong national champion lifts the productivity of its whole sector.

### Population

Population is no longer a fixed growth rate. Each country has three age groups (young people 0-14, working age 15-64 and elderly 65+) with its own birth and death rates. The largest countries start from rounded UN estimates for 2024, and the rest are estimated from income per capita and population growth. Births fall slowly as income rises and drop during war and instability; death rates of the elderly fall over time and with health spending; war kills working-age adults. Countries with few young people age faster, because larger generations reach 65 than reach 15.

Ageing hits the economy in two places: a smaller share of working-age people reduces the labor supply, and more elderly people than at the start raise pension spending in the public accounts. People also migrate between countries, mostly working-age adults: countries well above the world average in income, peace and stability attract migrants, those well below lose them, and war and occupation create refugees. Migration never changes the world population, and annexed territory brings its own age structure. The **Population** tab of the **Economy** window shows the age structure, birth, death and migration rates and the extra pension cost.

### Public accounts

The first day of the game already has budget figures, a credit rating and reserves. The central bank works with a target rate, and the news feed reports major macro moves (growth, inflation, rating changes, crises).

### Exchange rate, reserves and sovereign fund

The **Currency** window shows the exchange rate, reserves (in US$ and in months of imports), the central bank's net intervention, the exchange rate policy, capital controls, capital flight, dollarization and the depreciation implied by uncovered interest parity (i = i* + expected depreciation + risk premium), plus a section for the sovereign wealth fund with charts of reserves and of the fund.

- **Intervention:** a floating central bank sells dollars when its currency is under pressure and buys them when it weakens too much. It leans against moves beyond what inflation already explains, sells only what its reserves allow (below three months of imports it holds back) and slowly rebuilds its starting buffer. Under a dollar peg it buys and sells whatever the fixed rate requires.
- **Capital flight and controls:** money leaves when risk or inflation rises, pushing the currency down and draining reserves. Capital controls cut the flight but scare off investment and add a little risk.
- **Dollarization:** rises quickly with high inflation, falls slowly, and weakens the interest rate's grip on the exchange rate.
- **Sovereign wealth fund:** receives a share of the state's commodity revenue (`rent_take`) and of budget surpluses, invests abroad (60% equities following the US stock market, 40% bonds) without strengthening the currency, and pays a yearly withdrawal into the budget, capped by law (Norway's 3% rule). When commodity revenue falls below its average, the fund covers part of the drop. A large fund lowers the risk premium; withdrawing more than about 4% a year shrinks it and costs approval. Norway, Saudi Arabia, the United Arab Emirates, Kuwait, Qatar, China and Singapore start with balances close to the real ones (`swf` column of `data/countries.csv`); any other country can create one through the Exchange and Sovereign Fund Law in the legislative center.

## Legislation

The **legislative center** (L key or the document icon in the dock) lists the country's legal codes at the top, then the bills in progress, the norms in force and, last, the option to write a standalone law. Laws are built with visual blocks, as in Scratch: each stack that starts with an event is an article. The editor has a block library, a programming area, block properties, validation and a simulator. Its screens are in `scenes/ui/legislation/`.

### Legal codes

The country starts with seven codes in force. Six are **complementary laws** (they need an absolute majority to change); the Exchange and Sovereign Fund Law is an ordinary law:

| Code | What it covers |
| --- | --- |
| **Tax Code** | Personal income tax by brackets, social security, VAT and reduced rates, selective tax, corporate income tax, simplified regime for small firms, IOF, property and inheritance taxes, wealth tax and tax enforcement. |
| **Labor Code** | Minimum wage, working hours, overtime, vacation, 13th salary, severance and FGTS, unemployment insurance, parental leave, unions, strikes, outsourcing, gig work, minimum working age, retirement age and benefit cap. |
| **Penal Code** | Crimes and penalties, age of criminal responsibility, drugs, guns, death penalty and life imprisonment, sentence progression, alternative penalties, prisons and policing. |
| **Civil Code** | Marriage age, same-sex marriage, divorce, property regime, property rights and expropriation, adverse possession, inheritance, contracts and usury, business registration, bankruptcy and statute of limitations. |
| **Electoral Code** | Compulsory voting, voting age, electoral system, threshold, campaign finance, reelection limits, gender quotas, electronic voting and free airtime. |
| **Rights and duties** | Fundamental rights from a closed list with their scope, duties such as military service and compulsory schooling, press and internet censorship and state of emergency. |
| **Exchange and Sovereign Fund Law** | Central bank intervention in the exchange rate (free, mild or strong), capital controls (none, outflow tax or quotas), the sovereign wealth fund's share of commodity revenue and surpluses, and its yearly withdrawal cap. |

Each code has its own concrete blocks, with choices and numbers instead of typed names. The starting text depends on the country (democracy level, income per capita and, where it exists, the political data of the country), and the starting text is neutral: only what the player changes has an effect. Each code feeds the economy and politics every month through approval, stability, investment, unemployment, inequality, labor supply, productivity and tax evasion, and keeps its own indicators, such as crime rate, legal certainty, pension coverage and deficit, labor rigidity, turnout and civil liberties.

The Constitution prevails: the Electoral Code cannot change the electoral system, the minimum threshold or the length of the mandate that the Constitution sets, and a code block that tries to do so leaves a note in the history explaining why it had no effect.

### Editing a code

On a code's card, **Alterar** opens the editor with the text in force. The block library shows only that code's blocks and the events; the generic blocks stay folded under **Avançado** and open with one click. Fields that refer to something that already exists (a tax, a right, an institution, a license, a ministry) are lists, and free text is only used to create something new.

Before sending a bill, the **expected effects** panel shows the expected change in approval, the effect on the budget (for the Tax Code, the extra or lost revenue per year), how each social group sees it and how each party is likely to vote.

The blocks look like puzzle pieces: statements have a notch on top and a tab underneath and snap into the stack, events have a rounded top, control blocks ("If", "Repeat") have a C-shaped mouth, values are round pieces and conditions are hexagonal. Each piece is as wide as its own text. The programming area grows to fit the longest stack, scrolls to the end and can be dragged by its empty background with the left or middle mouse button.

### Taxes, parliament and the Constitution

**Taxes only change by law.** The Fiscal and Trade windows open the editor with the Tax Code in force. The sliders are kept for spending, mobilization, money printing and interest rates.

**Parliament deliberates.** Ready bills go through debate and vote, about a month per chamber. Bills now show their path as a step tracker (committee, floor, other chamber, sanction, publication, entry into force), with the current step highlighted, the days left and the estimated chance of passing. Countries with two chambers have one tab for the Chamber and another for the Senate in the Politics window, each with its own seats, and the bill must pass both.

**The Constitution changes by amendment.** An amendment alters, replaces, adds or removes provisions. New articles can be text only or programmed with blocks, and programmed ones run like any norm. Removing the article of a power, such as the veto, ends that power. Entrenched clauses cannot change, and every previous version is kept.

The game has no individual citizens: each event runs over an aggregate group, and a condition is worth the share of the group for which it is true. The simulator runs the same program with a fictional person. Only the player's country has norms. In opposition, the government AI adjusts taxes without going through the editor.

## Subnational units

The scenario starts with the 4,220 first-level units of the 170 countries, such as states, provinces and departments, and with Brazil's 5,564 municipalities inside the states. Borders appear on the map with zoom, first those of the states and then those of the municipalities, and hovering shows the name and type of the most specific unit, in any country.

In the **Divisions** window you edit your country, including annexed territories:

1. Choose the unit type with the marker. Each country has its own types, with any name you want: edit the existing ones or create new ones with **+ Novo tipo**.
2. Select the parent unit in the list or on the map. The first click on the map selects the state, and clicking again inside it goes down to the municipality. In the list, the arrow opens the units inside, and the search field finds any unit by name. A drawing is only accepted in free area: since states cover Brazil and municipalities cover the states, draw inside a municipality or first delete what occupies the area.
3. Press **N** and click on the map to place the vertices. Edges cannot cross.
4. Click the first point to close the polygon. The unit is created with an automatic name, which can be changed later. The hierarchy has no depth limit.

Any unit can be the capital of each unit that contains it and of the country: select it and use the buttons in the **Capital** section, which also remove the role. Each unit or country has one capital at a time, and choosing another replaces the previous one. Brazil starts with Brasília and the 27 state capitals, and the other 169 countries with the national capital at its real position. When the capital is not a whole province, it is a small "City" unit inside the province. On the map, your country's capital has a large golden star, other countries' capitals a smaller one, and unit capitals a light star, all scaling with zoom except yours. In a merge, the new unit inherits the capital role. In a split, the capital stays with the part where it lies. If a war hands the national capital to another country, the country has no capital until it picks another. For now the capital does not affect the economy, wars or politics.

The outline is clipped automatically by the national border and by the parent unit, and does not overlap neighboring units of the same level. To merge, select a unit, use **Fundir com...** and click the neighbors of the same level: the result keeps the name and type of the first one, and the children move to it. To split, select the unit, use **Desmembrar** and outline on the map the part that will separate; it becomes a sibling unit with an automatic name, and the children follow the part where their center lies. Deleting a unit deletes the units inside it. A type can only be deleted when no unit uses it. For now units are only territorial organization: they do not change the economy or politics.

## Borders

Borders only change when a war ends. The drawing uses the same vertices as the subnational units, and time stays paused while you draw.

- **You won** (capitulation, peace with the front in your favor or invader expelled): choose **Demarcar novas fronteiras**, to draw one or more areas up to the limit of what was conquered, or **Não ficar com território**, which ends the war and improves your reputation. On capitulation, the options to annex and to install an allied government are still there.
- **Peace without a winner** (front between -15 and +15): choose **Restabelecer fronteiras antigas** or **Propor novas fronteiras**. Each outline counts as a demand, if it falls more on the rival, or as an offer, if it falls more on your country. The rival compares the balance in GDP and tolerates more when the front is against it or when it is tired. After 3 refusals, the old borders apply again.
- **You lost, or the war is between other countries:** the winner takes whole subnational units, from the closest to the farthest, until it gets close to the treaty share. A country with a single unit loses nothing this way.

Population, capital, commodities and GDP follow the share of area ceded, and subnational units change owner, whole or cut by the outline. Area is measured on the map, so a small strip is worth the same per km² anywhere in the country: the game does not know where the cities are.

## Character

When you take over the government, you create your leader as a **countryball**: a ball wearing your country's flag, with white countryball eyes and no mouth. Female characters wear a pink bow on top of the ball. The creator has separate **first name** and **last name** fields and a gender choice. **Aleatório** draws a first name and last name that match the gender, from name lists by region and language of the country; switching gender while the name is still random swaps the first name for one of the new gender, while a name you typed stays as it is. The portrait appears in the top bar and in the **Panel** window, where **Editar personagem** reopens the creator. Older saves that only have the full name still load: it is split at the first space.

The flags come from `data/flags.json`; a country without a flag there gets stripes with colors derived from its ISO code. The old stickman art in `assets/character/` is no longer used.

## Parties and parliament

Each of the 170 countries has fictional parties, generated by political family (socialist, labor, green, social democrat, center, liberal, Christian democrat, conservative and nationalist), and a parliament with seats distributed by votes, with a 3% threshold by default. Its size follows the cube root of the population, between 30 and 700 seats. Closed regimes have a dominant party.

When you take over the government, you choose a party, whose ideas you adopt, or create your own, setting its compass, and it becomes the governing party with whatever seats it has. In the **Politics** window you see the chamber and the coalition, invite parties into the government or remove them, change parties and put bills to a vote. Each bill goes to parliament, takes weeks to be debated and can only return to the agenda after 6 months. The coalition votes in favor, except members who strongly disagree, and the opposition only supports what is close to its own ideas. Early elections need 3/5 of the seats.

In elections, approval moves the votes of your party and its allies, and you stay in power if your party is the largest or the coalition keeps the majority. A government without a majority slowly loses stability, and with approval below 20% and less than 1/3 of the seats it can be impeached. The government sets spending on its own in the Fiscal window, and the change applies immediately. Only the field that a law in force locks with the **Obrigar o orçamento** block stays fixed. Taxes and tariffs only change by law in the block editor.

## Opposition

Before starting, when choosing a party, you decide between **Governar** and **Liderar a oposição**, with any party or one you create. In opposition, the party already in government stays in power and is unavailable to you. Closed regimes have no elections, so there you can only govern.

When you lose an election or are impeached, you stay in the same country as the leader of your party, and the AI governs: budget, interest rates, diplomacy and wars leave your hands, and the controls only show what it decides. In the **Politics** window you can criticize the government, campaign and file a motion of no confidence, which only brings down the government if the opposition holds the majority of seats. In the next election, the worse the government's approval, the better for your party, and you return to power if it is the largest.

## Politicians and political compass

Each party has 5 to 8 politicians, each with their own position on the political compass (economy and authority), competence and appearance. The party's compass is the average of its politicians. You are also a politician: you set your ideas by clicking the compass when choosing the party, and the party's average changes when you join, leave or change your mind. Click a party in the **Politics** window to see its politicians.

## Ministers

In the **Ministers** window you choose among the politicians of the coalition parties for seven portfolios: Finance, Foreign Affairs, Defense, Health, Education, Infrastructure and Justice. Competence above 50% helps the portfolio every month, and below 50% hurts it. A vacant portfolio counts as 30%. An ally without any ministry may leave the government, and a party that leaves takes its ministers with it.

## Ministries

The **Criar**, **Fundir** and **Extinguir ministério** blocks in the law editor change the cabinet. An extra ministry costs money and one fewer saves money, but the area without its own minister is poorly run, and a minister who accumulates areas performs worse in each. When the law is revoked, the ministries go back to what they were.

## Elections

Each country votes by districts, in the subnational units, with seats shared by population. The system can be proportional (D'Hondt), first-past-the-post, two-round single-member or mixed, with a threshold. In presidential systems the head of government is elected directly in two rounds, and parliament can turn out against them; in parliamentary systems, whoever forms a majority governs. The senate elects the same number of senators per unit. Your country's Constitution defines all of this and can change by amendment, and the Electoral Code sets the rest: compulsory voting, voting age, free airtime and electronic voting change turnout, campaign finance sets how much each party's fund weighs on the vote, a higher threshold keeps small parties out, and the reelection limit is enforced on the player. The Politics window shows the result of the last election.

Units have population. The states of Brazil and the United States use rounded census figures. The rest of the world is estimated by area, and municipalities share their state's population the same way.

## Plebiscite

A norm of the **Plebiscito** type goes through parliament and then to the polls: it only applies if the majority of the electorate approves. The result depends on the popularity of the proposal, which the paid poll estimates. In democratic countries, creating or splitting a subnational unit follows the same procedure, and the unit is only born at the end of it.

## Interest rates

In consolidated democracies and in the euro zone the central bank is independent: it sets the rate on its own, and neither the player nor the other governments choose it. Independence is in your country's Constitution and can change by amendment. With a subordinate bank, the government can set the rate by hand, at a cost in credibility, and left-wing or unpopular leaders do so on their own.

## Leader conversations and treaties

In a country's dossier, **Falar com o líder** opens a conversation with choices: praise, propose free trade or a defense pact, send aid, ask for sanctions against an enemy, protest, threaten or, at war, propose peace. The leader answers based on the relationship between the countries, the distance between your party's compass and theirs, what they think of each subject (a right-wing leader opens markets more easily, an authoritarian only backs down in the face of much greater force) and the competence of your foreign minister. Each conversation has up to 3 lines, one per month with each leader. Leaders also take the initiative: they meet each other, and sometimes ask to talk to you. The foreign policy buttons are still in the dossier.

Treaties follow the real-life process: negotiation, signature, ratification by parliaments, a term in force and withdrawal with six months' notice. There are free trade, customs union, mutual defense, non-aggression, arms control, climate, extradition and investment treaties. The world already starts with treaties such as the North Atlantic one. Propose one from the other country's dossier and follow it in the **Tratados** tab of the legislative center.

## Life and end of career

All politicians have an age, including you, fall ill and die, with risk rising with age. When a party leader dies, the most competent member takes over. Every January parties get new names.

The game only ends for your character with impeachment, a coup, resignation, assassination or death. Then you choose between a new game and taking over another character in the same game. Losing an election or a war leads to opposition; in a closed regime, with no elections to contest, losing the war brings down the leader. If your country ceases to exist, the new character starts in the country that annexed it.

## The world acts on its own

Every month the governments of the other countries act according to their leader's compass. On the left they spend and tax more; on the right they cut and open trade. Authoritarians arm the country, fight more and govern by decree; libertarians invest in education and prefer agreements. They sign trade deals and pacts, exchange missions, criticize, impose tariffs and sanctions (including on you) and go to war. Similar ideas bring countries closer, and opposite ideas push them apart. The news feed shows what involves you or the large economies.

In every country with a free parliament, parties propose bills according to their own ideas, and the benches vote weeks later. The dossier shows what is being debated and the latest votes. Authoritarian regimes have no proposals from parliament. In your country, parties also file bills, which appear among the bills in progress.

## Vote trading

On a bill in progress, **Negociar votos** asks each bench for its vote, for or against, including on bills from other parties. The price follows the size of the bench and comes out of your party's fund; the generous offer costs double and has a better chance. The further from the party's ideas, the harder it is to turn the vote. A refusal costs nothing, but ends the conversation about that bill. In government you can also offer a place in the coalition. Your own bench follows the party line for free.

## Party funds

Each party has a cash fund that it receives every month according to its vote share. Your party's fund appears at the top of the screen and pays, each at its own price, for: popularity poll (the most expensive), campaign, motion of no confidence, parliamentary support poll, criticism of the government and inviting a party. Prices follow the size of the economy.

There is no free vote forecast. The **support poll** shows how each bench is likely to vote, by chamber, with a margin of error. The **popularity poll** shows how many voters approve the proposal. Popularity counts for real: when the norm enters into force, an unpopular one takes approval away from the government and a popular one adds to it.

Foreign actions have no cost: the same action with the same country can only be repeated after 30 days.

## Debug menu

**F12**, or **Menu debug** in the pause menu, opens a panel that triggers the game systems by hand: time, player, economy, markets, events and dilemmas, diplomacy, war, borders, units, interface and game endings. Commands act on the player or on the target country, chosen in the list or with a click on the map. The target starts on your country; commands that need another country, such as declaring war, stay grayed out until you pick one. The filter field finds a command by name. The menu is always available and its commands count as cheating: the game is not scored.

## Languages

The game is written in Brazilian Portuguese, and English and Spanish come from gettext catalogs. The language is chosen in the **Idioma** / **Language** list on the start screen or in the pause menu (Esc), applies immediately and is saved in `user://settings.cfg`. On first launch the game uses the system language if it is English or Spanish, and Portuguese otherwise. When run from the editor it starts in Portuguese (`locale/test`). To force a language at launch:

```bash
godot --path . -- --lang=en
```

The Portuguese text is the msgid. English and Spanish live in `locale/en.po` and `locale/es.po`, registered in `project.godot` with `pt_BR` as fallback, so any missing entry shows in Portuguese. In English, numbers use a decimal point and comma thousands separators. Proper names of people, companies and cities are not translated; country names, sectors and law blocks are.

After changing any player-facing text, update the catalogs:

```bash
godot --headless --path . --script tools/extract_pot.gd -- --merge
```

This rewrites `locale/messages.pot` from the scenes (texts, tooltips, placeholders, titles, dock labels and tab names), from `tr()`, `TranslationServer.translate()` and `Lang.tr_if()` calls, from constants marked `# i18n`, `# i18n-all` or `# i18n-begin` / `# i18n-end`, and from the law block catalog, sectors and country names. With `--merge` it runs `msgmerge --update` on each `.po` (requires gettext) and prints how many entries are missing or fuzzy. Translate the empty `msgstr` entries, keeping `%s`, `%d`, `{field}` and `\n`, and check a catalog with `msgfmt --check -o /dev/null locale/en.po`.

## Editing the interface

All menus are scenes in `scenes/ui/`, opened and edited in Godot:

- `start_screen.tscn`: start screen.
- `hud.tscn`: top bar, the window desk with all government windows, the dossier, map modes, news feed, notices and the dock.
- `float_window.tscn`, `dock.tscn` and `dock_item.tscn`: the floating window frame (title bar, traffic-light buttons and resize grip), the dock and its icons. The dock icons are in `assets/ui/dock/`.
- `panels/`: the content of each window (Divisions, Politics, Ministers, Economy with Sectors, Infrastructure, Companies and Stock exchange tabs), the border panel and the debug menu.
- `legislation/`: legislative center, law editor, blocks, amendments, expected effects and the step tracker.
- `modals/`: pause, help, confirmation, decision, character creator, party choice, party, minister, conversation and game over.
- `rows/`: rows repeated in lists, such as news, party, minister, unit and sector.
- `theme.tres`: general theme. The slider images are in `assets/ui/`.

Texts, sizes, colors and positions can be changed freely in the editor. Scripts find nodes by unique name (`%`), so renaming a node marked with `%` requires changing the name in the script. Nodes with a prefix, such as `top_gdp`, `slider_tax_income`, `dossier_pop` or `action_war`, receive values by name and can be moved anywhere in the same scene. The parts of the dossier that only appear for another country are in the `foreign_only` group, and the parts of the party choice that only appear at the start are in `at_start_only`. Windows are children of the desk in `hud.tscn`, and their order there is their index in the dock.

Some texts change during the game: what the script writes into a label, such as values and country names, replaces the scene text. Charts, portraits, compasses and countryballs are drawn by script and appear empty in the editor. The debug menu commands are generated from the list in `debug_menu.gd`.

## Exporting

Export presets for Windows and Linux (x86_64 and arm64) are in `export_presets.cfg`, with `tools/*`, `tests/*` and `assets/character/*` excluded. Builds go to `bin/`, which Git and Godot ignore.

`data/countries.csv` must stay imported as **Keep File** (`importer="keep"` in `countries.csv.import`). Godot imports CSV files as translations by default, and then the export only carries the generated `.translation` files: without the CSV the exported game cannot load the countries.

## The model

There are 170 countries with their own GDP, population, debt, inflation, interest rates, exports, armed forces and commodity production. Each one runs the same economy every month:

- **Supply:** Solow production function with capital, labor, human capital and productivity, with income convergence, split into ten sectors.
- **Demography:** three age groups with births, deaths, ageing and migration between countries; the working-age share sets the labor supply and the elderly share weighs on pensions.
- **Demand:** output gap driven by the real interest rate, fiscal impulse, partner demand, real exchange rate, terms of trade, credit and confidence, plus the logistics of ports and airports.
- **Prices:** Phillips curve with expectations anchored by central bank credibility, exchange rate pass-through and energy and food shocks.
- **Monetary policy:** Taylor rule, the euro zone with a common ECB, dollar pegs that can break.
- **Exchange rate:** purchasing power parity, real interest rate differential, current account, uncovered interest parity and risk premium, with central bank intervention, capital flight, capital controls and dollarization.
- **Sovereign wealth funds:** commodity revenue and surpluses saved abroad, a withdrawal rule and a cushion against commodity price falls.
- **Public finances:** taxes with a Laffer curve and tax evasion, automatic stabilizers, debt in local currency and in dollars, endogenous risk premium, credit rating, IMF and default.
- **Trade:** gravity-based bilateral matrix, changed by tariffs, agreements, sanctions and wars.
- **Commodities:** oil, gas, grains, metals and chips with supply by country, stocks and OPEC+.
- **Financial crises:** credit cycle that produces banking crises and global contagion.
- **Companies:** company profits and valuations and a stock index per country.
- **Laws:** the legal codes feed investment, unemployment, inequality, labor supply, productivity and tax evasion.

On top of this runs geopolitics: bilateral relations, alliances, sanctions, wars with a front line and attrition, nuclear deterrence, elections, coups and nations with their own AI.

## Data

- Borders: Natural Earth (public domain), via the `world-atlas` package. `tools/build_map.mjs` generates `data/map.json`.
The raw files live in `tools/raw/`, outside the repository. You only need to download them to regenerate `data/`; the game runs without them.
- Subnational units: Natural Earth admin-1 10m (public domain). `tools/build_admin1.mjs` generates `data/admin1.json` from `tools/raw/ne_10m_admin_1.geojson`, which the game does not use directly. Names follow the source, untranslated, and the assignment of disputed territories follows the de facto control the source adopts. Municipalities and other levels below the first are not included.
- Municipalities of Brazil: IBGE mesh published by the `tbrugz/geodata-br` project (CC0). `tools/build_municipios.mjs` generates `data/municipios.json` from `tools/raw/geojs-100-mun.json`. The mesh has 5,564 municipalities, fewer than the current 5,570: those created after it appear inside their original municipality.
- Limits: `tools/clip_units.gd` clips the states by the country outline and the municipalities by the state, with areas and lines. Units entirely outside the outline, such as islands the map does not have, become a small marker on the nearest edge. To generate everything from scratch, run `build_map.mjs`, `build_admin1.mjs`, `build_municipios.mjs` and that script, in this order.
- National capitals: Natural Earth populated places 10m (public domain). `tools/build_capitais.mjs` generates `data/capitais.json`, with Portuguese names from its own table, typed from memory, and corrections where the source marks several capitals or the largest city. For disputed capitals, such as Jerusalem, the game follows the source. Run this script before `clip_units.gd`.
- Ports and airports: `data/infra.json`, main facilities of each country with approximate capacity. Companies: `data/companies.json`, large real companies of the main economies with approximate figures. Flags: `data/flags.json`.
- Economy and armed forces: `data/countries.csv`, approximate 2024 values typed from memory for game purposes.

The values in `countries.csv`, `infra.json` and `companies.json` were not checked against their sources and must not be used as factual reference. Microstates and small islands appear on the map as neutral territories.

## Performance

Each day's simulation, saving, loading and starting the game run on other threads, and the screen keeps drawing. Only the main thread creates nodes and talks to the interface. The world has one owner at a time: while a thread works on it, `world.busy` is on and the interface neither reads nor changes anything; a click or key press waits for it to finish, and simulation signals are queued until then. Simulation code must never touch nodes or emit signals directly: use `_send`, in `world.gd`, or `world.emit_news` for news. Opening the map triangulates each country in parallel, on the available cores.

`--ui-profile` measures the time of each heavy operation, and `--ui-threads` tests the turn of the month, clicks in the middle of the simulation, decisions during day skips and saving.

## Tests

Headless tests run as scripts and print `RESULTADO: N falhas` (`falhas: N` for `policy.gd`). Interface tests run the game with a flag and save screenshots to the folder given in `--shots`.

```bash
godot --headless --path . -s tests/legislation.gd
```

```bash
godot --path . -- --ui-legislation --shots=/tmp/shots
```

| Headless (`-s tests/X.gd`) | What it covers |
| --- | --- |
| `scenes.gd` | Opens every scene and rejects repeated names under the same parent. |
| `policy.gd` | Checks the effect of each player lever against a control. |
| `calibrate.gd` | Prints world indicators and populations by age group year by year (`-- 15 42`), with optional `taiwan` and `hormuz` scenarios. |
| `economy_health.gd` | Long runs of the world economy within sane bounds. |
| `demography.gd` | Starting age structures, ageing, labor supply, pensions, migration and old saves. |
| `sectors.gd`, `infra.gd`, `corporate.gd` | Sectors, ports and airports, companies and the stock exchange. |
| `legislation.gd` | Laws, legislative process, party fund, polls, amendments and block dragging. |
| `code_tributario.gd`, `code_penal_civil.gd`, `code_trabalho_eleicoes.gd`, `direitos.gd` | Each legal code: starting text, changes by bill, revocation and monthly effects. |
| `fx_swf.gd` | Central bank intervention, capital flight and controls, dollarization, interest parity, sovereign funds (starting balances, returns, withdrawal rule, commodity cushion, risk and approval) and the Exchange Law. |
| `politics.gd` | Parties, parliament, votes, elections and the character creator. |
| `statecraft.gd` | Opposition, politicians, compass, ministers and conversations. |
| `society.gd` | Age and death, elections, plebiscite, units with formal procedure, ministries, end of career, conversations and treaties. |
| `world_ai.gd` | Lets the world run on its own and prints what happened. |
| `clock.gd`, `capitals.gd`, `borders.gd`, `subdivisions.gd` | Clock and day skips, capitals, borders and wars, subnational units. |

| Interface (`-- --ui-X --shots=DIR`) | What it covers |
| --- | --- |
| `--ui-desk` | Dock and floating windows: open, bring to front, drag, resize, minimize, centered opening and small screens. |
| `--ui-legislation`, `--ui-society` | Legislative center, code cards, filtered library, expected effects, step tracker, amendments and society systems. |
| `--ui-economy`, `--ui-infra`, `--ui-corporate`, `--ui-econ-audit` | Economy windows (including Currency with reserves and the sovereign fund), population, infrastructure, companies and stock exchange. |
| `--ui-creator` | Countryball creator, with male and female portraits and names, and a gallery of every country's countryball (`galeria_bandeiras.png`). |
| `--ui-locale` | Switches to English and Spanish and takes screenshots of the start screen, HUD, legislative center and block editor. |
| `--ui-politics`, `--ui-statecraft` | Politics and statecraft through the interface. |
| `--ui-clock`, `--ui-capitals`, `--ui-divisions`, `--ui-borders` | Clock, capitals, drawing units and borders with clicks on the map. |
| `--ui-debug` | Presses every debug menu command, one at a time. |
| `--ui-threads`, `--ui-profile` | Threading and timing. |
| `--ui-layout` | Records the position and style of each control on every screen in `layout.txt`, with a screenshot of each. Running it before and after changing a scene shows what moved. |
| `--ui-test` | Plays on its own through the interface and saves screenshots. |
