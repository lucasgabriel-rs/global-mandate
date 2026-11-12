class_name Names
extends RefCounted
## Female and male first names and surnames by language, for the player and the politicians of each country.
## Surnames with their own feminine form (Russian, Polish, Czech, Greek, Lithuanian) come as "masculine|feminine".

const GROUPS := {
	"pt": {
		"f": ["Helena", "Sofia", "Beatriz", "Lúcia", "Clara", "Marina", "Ana", "Juliana", "Fernanda", "Luísa", "Mariana", "Carolina", "Isabela", "Gabriela"],
		"m": ["Marcos", "Rafael", "Tiago", "André", "Otávio", "Vicente", "João", "Pedro", "Lucas", "Gustavo", "Eduardo", "Felipe", "Henrique", "Rodrigo"],
		"last": ["Almeida", "Duarte", "Moreira", "Vargas", "Teixeira", "Nunes", "Campos", "Rezende", "Prado", "Salles", "Silva", "Souza", "Oliveira", "Pereira", "Costa", "Carvalho", "Ribeiro", "Fonseca"],
	},
	"es": {
		"f": ["María", "Lucía", "Camila", "Valentina", "Isabel", "Carmen", "Daniela", "Paula", "Sofía", "Ximena", "Gabriela", "Elena"],
		"m": ["José", "Carlos", "Diego", "Andrés", "Javier", "Alejandro", "Miguel", "Santiago", "Mateo", "Luis", "Fernando", "Pablo"],
		"last": ["García", "Rodríguez", "Martínez", "López", "Gómez", "Rojas", "Díaz", "Torres", "Vega", "Ramírez", "Flores", "Herrera", "Morales", "Castillo"],
	},
	"en": {
		"f": ["Mary", "Linda", "Susan", "Emily", "Sarah", "Jennifer", "Emma", "Olivia", "Grace", "Charlotte", "Hannah", "Margaret"],
		"m": ["John", "Robert", "James", "David", "Paul", "Michael", "William", "Thomas", "Richard", "George", "Daniel", "Andrew"],
		"last": ["Smith", "Johnson", "Brown", "Miller", "Wilson", "Clark", "Lewis", "Walker", "Young", "Hall", "Taylor", "Wright", "Scott", "Hughes", "Campbell"],
	},
	"fr": {
		"f": ["Marie", "Camille", "Claire", "Sophie", "Isabelle", "Juliette", "Chloé", "Léa", "Margaux", "Élise", "Nathalie", "Céline"],
		"m": ["Pierre", "Jean", "Louis", "Nicolas", "François", "Antoine", "Julien", "Mathieu", "Olivier", "Laurent", "Philippe", "Hugo"],
		"last": ["Martin", "Bernard", "Dubois", "Durand", "Lefebvre", "Moreau", "Laurent", "Simon", "Michel", "Garnier", "Rousseau", "Fontaine", "Mercier"],
	},
	"af_fr": {
		"f": ["Aminata", "Fatoumata", "Awa", "Mariam", "Aïssatou", "Clarisse", "Odile", "Bintou", "Rokia", "Adjoa", "Ramatou", "Nadège"],
		"m": ["Moussa", "Ibrahim", "Mamadou", "Ousmane", "Abdoulaye", "Joseph", "Serge", "Didier", "Boubacar", "Koffi", "Issa", "Patrice"],
		"last": ["Diallo", "Traoré", "Coulibaly", "Konaté", "Ouédraogo", "Sow", "Camara", "Keïta", "Kaboré", "Ndiaye", "Mbeki", "Touré", "Kouassi", "Sylla"],
	},
	"af_en": {
		"f": ["Amara", "Nia", "Thandi", "Aisha", "Abena", "Chiamaka", "Wanjiru", "Nomvula", "Grace", "Zanele", "Adaeze", "Esi"],
		"m": ["Kwame", "Tunde", "Kofi", "Sipho", "Chinedu", "Juma", "Thabo", "Emeka", "Kwabena", "Baraka", "Tendai", "Femi"],
		"last": ["Okafor", "Mensah", "Dlamini", "Moyo", "Banda", "Ndlovu", "Kamau", "Okonkwo", "Adeyemi", "Otieno", "Mwangi", "Boateng", "Phiri", "Nkosi"],
	},
	"af_horn": {
		"f": ["Meron", "Hiwot", "Selam", "Tigist", "Hodan", "Faduma", "Saba", "Almaz", "Ayaan", "Muna"],
		"m": ["Abebe", "Dawit", "Tesfaye", "Yonas", "Abdi", "Mohamed", "Haile", "Bereket", "Ahmed", "Yared"],
		"last": ["Abebe", "Tadesse", "Girma", "Bekele", "Haile", "Warsame", "Hassan", "Mengistu", "Tesfaye", "Farah", "Kebede", "Ali"],
	},
	"de": {
		"f": ["Anna", "Katharina", "Julia", "Sabine", "Monika", "Lena", "Hannah", "Laura", "Ursula", "Petra", "Johanna", "Greta"],
		"m": ["Jan", "Thomas", "Michael", "Stefan", "Andreas", "Markus", "Lukas", "Felix", "Jürgen", "Klaus", "Matthias", "Florian"],
		"last": ["Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker", "Hoffmann", "Schulz", "Koch", "Richter", "Huber", "Graf"],
	},
	"it": {
		"f": ["Giulia", "Francesca", "Chiara", "Sara", "Elena", "Valentina", "Alessandra", "Federica", "Martina", "Giorgia", "Silvia", "Paola"],
		"m": ["Luca", "Marco", "Giuseppe", "Alessandro", "Matteo", "Giovanni", "Andrea", "Francesco", "Lorenzo", "Paolo", "Stefano", "Davide"],
		"last": ["Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno", "Gallo", "Conti", "Costa"],
	},
	"nl": {
		"f": ["Emma", "Sanne", "Anouk", "Lotte", "Fleur", "Marieke", "Femke", "Eva", "Ingrid", "Noor"],
		"m": ["Jan", "Pieter", "Daan", "Sander", "Bram", "Joost", "Willem", "Maarten", "Ruben", "Koen"],
		"last": ["de Jong", "Jansen", "de Vries", "van Dijk", "Bakker", "Visser", "Smit", "Meijer", "de Boer", "Mulder", "Peeters", "Janssens"],
	},
	"nordic": {
		"f": ["Ingrid", "Astrid", "Sigrid", "Freja", "Karin", "Maja", "Elin", "Linnea", "Sanna", "Helga", "Aino", "Liv"],
		"m": ["Henrik", "Lars", "Erik", "Anders", "Magnus", "Nils", "Olav", "Jonas", "Mikael", "Gunnar", "Sven", "Bjørn"],
		"last": ["Larsen", "Hansen", "Johansson", "Andersson", "Nielsen", "Berg", "Lindqvist", "Virtanen", "Korhonen", "Jónsson", "Dahl", "Holm", "Eriksson"],
	},
	"ru": {
		"f": ["Anna", "Olga", "Natalia", "Elena", "Irina", "Tatiana", "Svetlana", "Yulia", "Daria", "Ekaterina", "Oksana", "Marina"],
		"m": ["Ivan", "Sergei", "Dmitri", "Alexei", "Mikhail", "Andrei", "Nikolai", "Pavel", "Viktor", "Oleg", "Yuri", "Taras"],
		"last": ["Ivanov|Ivanova", "Petrov|Petrova", "Smirnov|Smirnova", "Volkov|Volkova", "Sokolov|Sokolova", "Popov|Popova", "Morozov|Morozova", "Kuznetsov|Kuznetsova", "Lebedev|Lebedeva", "Kovalenko", "Shevchenko", "Bondarenko"],
	},
	"pl": {
		"f": ["Anna", "Katarzyna", "Agnieszka", "Magdalena", "Ewa", "Zuzana", "Barbora", "Joanna", "Petra", "Monika", "Lucie", "Alicja"],
		"m": ["Marek", "Piotr", "Tomasz", "Krzysztof", "Paweł", "Jakub", "Jan", "Martin", "Petr", "Michal", "Lukáš", "Wojciech"],
		"last": ["Kowalski|Kowalska", "Nowak", "Wiśniewski|Wiśniewska", "Lewandowski|Lewandowska", "Kamiński|Kamińska", "Novák|Nováková", "Svoboda|Svobodová", "Dvořák|Dvořáková", "Horváth|Horváthová", "Zieliński|Zielińska", "Černý|Černá"],
	},
	"balkan": {
		"f": ["Ana", "Milica", "Jelena", "Ivana", "Marija", "Maja", "Elena", "Tamara", "Nina", "Vesna", "Desislava", "Mirela"],
		"m": ["Marko", "Nikola", "Stefan", "Luka", "Ivan", "Milan", "Dragan", "Goran", "Petar", "Damir", "Georgi", "Emir"],
		"last": ["Horvat", "Novak", "Jovanović", "Petrović", "Nikolić", "Kovačević", "Marković", "Popović", "Begić", "Hodžić", "Ivanovski", "Dimitrov"],
	},
	"sq": {
		"f": ["Arta", "Elira", "Besa", "Drita", "Teuta", "Liridona", "Blerta", "Valbona", "Mimoza", "Jehona"],
		"m": ["Arben", "Besnik", "Ilir", "Gentian", "Agron", "Driton", "Fatmir", "Edon", "Kujtim", "Ardit"],
		"last": ["Hoxha", "Krasniqi", "Berisha", "Shala", "Gashi", "Leka", "Dervishi", "Kelmendi", "Morina", "Bytyqi"],
	},
	"ro": {
		"f": ["Ioana", "Andreea", "Elena", "Maria", "Cristina", "Mihaela", "Alexandra", "Raluca", "Gabriela", "Irina"],
		"m": ["Andrei", "Mihai", "Alexandru", "Ion", "Ștefan", "Gabriel", "Adrian", "Vlad", "Cristian", "Florin"],
		"last": ["Popescu", "Ionescu", "Popa", "Dumitru", "Stan", "Stoica", "Gheorghe", "Rusu", "Munteanu", "Ciobanu", "Constantin", "Lungu"],
	},
	"hu": {
		"f": ["Zsófia", "Katalin", "Eszter", "Anna", "Réka", "Judit", "Ildikó", "Krisztina", "Dóra", "Orsolya"],
		"m": ["László", "István", "Gábor", "Zoltán", "Péter", "Attila", "Balázs", "Tamás", "Ferenc", "Bence"],
		"last": ["Nagy", "Kovács", "Tóth", "Szabó", "Horváth", "Varga", "Kiss", "Molnár", "Németh", "Farkas", "Balogh", "Papp"],
	},
	"gr": {
		"f": ["Maria", "Eleni", "Katerina", "Sofia", "Dimitra", "Georgia", "Ioanna", "Anastasia", "Despina", "Christina"],
		"m": ["Giorgos", "Dimitris", "Nikos", "Kostas", "Yannis", "Christos", "Panagiotis", "Andreas", "Stavros", "Alexandros"],
		"last": ["Papadopoulos|Papadopoulou", "Georgiou", "Nikolaidis|Nikolaidou", "Christodoulou", "Pappas|Pappa", "Konstantinou", "Ioannidis|Ioannidou", "Antoniou", "Karagiannis|Karagianni", "Vlachos|Vlachou"],
	},
	"baltic": {
		"f": ["Rūta", "Laura", "Ieva", "Kristīne", "Liisa", "Kadri", "Agnė", "Inese", "Triin", "Eglė"],
		"m": ["Jonas", "Mindaugas", "Andris", "Jānis", "Tõnu", "Mart", "Tomas", "Kārlis", "Rasmus", "Darius"],
		"last": ["Kazlauskas|Kazlauskienė", "Petrauskas|Petrauskienė", "Bērziņš|Bērziņa", "Kalniņš|Kalniņa", "Ozols|Ozola", "Tamm", "Saar", "Kask", "Sepp", "Jankauskas|Jankauskienė"],
	},
	"tr": {
		"f": ["Ayşe", "Elif", "Zeynep", "Fatma", "Emine", "Merve", "Selin", "Defne", "Esra", "Leyla"],
		"m": ["Mehmet", "Mustafa", "Ahmet", "Emre", "Murat", "Burak", "Kemal", "Can", "Hakan", "Yusuf"],
		"last": ["Yılmaz", "Kaya", "Demir", "Şahin", "Çelik", "Yıldız", "Aydın", "Öztürk", "Arslan", "Doğan", "Kılıç", "Aslan"],
	},
	"ca": {
		"f": ["Aigerim", "Dilnoza", "Gulnara", "Madina", "Aida", "Leyla", "Zarina", "Nigora", "Aynur", "Saule"],
		"m": ["Nursultan", "Timur", "Rustam", "Bakhtiyar", "Azamat", "Ilham", "Farhod", "Serik", "Elchin", "Daniyar"],
		"last": ["Nazarbayev|Nazarbayeva", "Aliyev|Aliyeva", "Karimov|Karimova", "Tokayev|Tokayeva", "Rakhimov|Rakhimova", "Mammadov|Mammadova", "Yusupov|Yusupova", "Abdullayev|Abdullayeva", "Sultanov|Sultanova", "Atayev|Atayeva"],
	},
	"cauc": {
		"f": ["Nino", "Tamar", "Ani", "Mariam", "Lusine", "Ketevan", "Anahit", "Nana", "Gayane", "Salome"],
		"m": ["Giorgi", "Levan", "Davit", "Aram", "Tigran", "Irakli", "Armen", "Zurab", "Vahe", "Lasha"],
		"last": ["Beridze", "Kapanadze", "Gelashvili", "Maisuradze", "Hovhannisyan", "Grigoryan", "Sargsyan", "Harutyunyan", "Lomidze", "Petrosyan"],
	},
	"ar": {
		"f": ["Fatima", "Layla", "Nadia", "Amira", "Samira", "Yasmin", "Mariam", "Huda", "Rania", "Salma", "Noor", "Aisha"],
		"m": ["Omar", "Hassan", "Karim", "Yusuf", "Tariq", "Ahmed", "Khalid", "Mahmoud", "Ali", "Ibrahim", "Faisal", "Said"],
		"last": ["Haddad", "Rahman", "Khalil", "Nasser", "Aziz", "Mansour", "Saleh", "Farah", "Hamid", "Al-Sayed", "Bakr", "Qureshi", "Benali", "El-Amin"],
	},
	"fa": {
		"f": ["Shirin", "Maryam", "Parisa", "Leila", "Nasrin", "Zahra", "Farah", "Roya", "Mina", "Soraya"],
		"m": ["Reza", "Ali", "Hossein", "Mehdi", "Dariush", "Farid", "Kamran", "Navid", "Ahmad", "Rostam"],
		"last": ["Karimi", "Hosseini", "Mohammadi", "Rezaei", "Ahmadi", "Jafari", "Rahimi", "Sadeghi", "Ghani", "Rahmon", "Moradi", "Tehrani"],
	},
	"he": {
		"f": ["Noa", "Tamar", "Yael", "Shira", "Efrat", "Rivka", "Maya", "Avigail", "Talia", "Hadas"],
		"m": ["David", "Yosef", "Avi", "Moshe", "Itai", "Noam", "Eitan", "Yonatan", "Ariel", "Daniel"],
		"last": ["Cohen", "Levi", "Mizrahi", "Peretz", "Biton", "Friedman", "Shapiro", "Avraham", "Katz", "Golan"],
	},
	"in": {
		"f": ["Priya", "Ananya", "Lakshmi", "Kavya", "Sunita", "Meera", "Deepa", "Pooja", "Anjali", "Shreya", "Nisha", "Sita"],
		"m": ["Arjun", "Ravi", "Rahul", "Vikram", "Amit", "Sanjay", "Rajesh", "Karan", "Anil", "Suresh", "Prakash", "Rohan"],
		"last": ["Sharma", "Singh", "Patel", "Gupta", "Kumar", "Reddy", "Iyer", "Nair", "Rao", "Joshi", "Thapa", "Perera", "Fernando", "Dorji"],
	},
	"sa_m": {
		"f": ["Ayesha", "Fatima", "Sadia", "Nusrat", "Farzana", "Mahnoor", "Rubina", "Sabina", "Nadia", "Shabnam"],
		"m": ["Imran", "Asif", "Bilal", "Hamza", "Rashid", "Tanvir", "Shakib", "Faisal", "Kamal", "Zubair"],
		"last": ["Khan", "Hussain", "Ahmed", "Chowdhury", "Rahman", "Malik", "Islam", "Hossain", "Sheikh", "Butt", "Siddiqui", "Bhuiyan"],
	},
	"zh": {
		"f": ["Mei", "Lan", "Xiu", "Ying", "Hui", "Jing", "Li", "Fang", "Yan", "Ling", "Xiaoyu", "Qing"],
		"m": ["Wei", "Jun", "Hao", "Ming", "Lei", "Qiang", "Jian", "Tao", "Bo", "Yong", "Zhiwei", "Feng"],
		"last": ["Wang", "Li", "Zhang", "Liu", "Chen", "Yang", "Huang", "Zhao", "Wu", "Zhou", "Lin", "Tan", "Lim", "Ng"],
	},
	"ja": {
		"f": ["Yuki", "Hana", "Sakura", "Aiko", "Yui", "Haruka", "Mei", "Naomi", "Emi", "Keiko", "Rina", "Ayaka"],
		"m": ["Kenji", "Hiroshi", "Takashi", "Haruto", "Daiki", "Kazuo", "Satoshi", "Yuto", "Shinji", "Ren", "Akira", "Taro"],
		"last": ["Sato", "Suzuki", "Takahashi", "Tanaka", "Watanabe", "Ito", "Yamamoto", "Nakamura", "Kobayashi", "Kato", "Yoshida", "Yamada"],
	},
	"ko": {
		"f": ["Min-ji", "Ji-woo", "Seo-yeon", "Ha-eun", "Soo-jin", "Ji-hye", "Eun-ji", "Hye-jin", "Yu-na", "Da-eun"],
		"m": ["Min-jun", "Ji-ho", "Seo-jun", "Hyun-woo", "Dong-hyun", "Sung-min", "Jae-won", "Tae-yang", "Young-ho", "Jin-woo"],
		"last": ["Kim", "Lee", "Park", "Choi", "Jung", "Kang", "Cho", "Yoon", "Jang", "Lim", "Han", "Shin"],
	},
	"vi": {
		"f": ["Lan", "Hoa", "Mai", "Linh", "Thu", "Hương", "Ngọc", "Trang", "Phương", "Hạnh"],
		"m": ["Minh", "Hùng", "Tuấn", "Dũng", "Quang", "Hải", "Long", "Nam", "Đức", "Phong"],
		"last": ["Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Phan", "Vũ", "Đặng", "Bùi", "Đỗ", "Ngô", "Dương"],
	},
	"th": {
		"f": ["Siriporn", "Malee", "Nittaya", "Pim", "Kanya", "Sopheap", "Chanthy", "Ratana", "Dara", "Achara"],
		"m": ["Somsak", "Anan", "Prayut", "Kittisak", "Sombath", "Sokha", "Vichai", "Chai", "Thongchai", "Bounmy"],
		"last": ["Saetang", "Wongsa", "Srisuk", "Chanthavong", "Sok", "Chea", "Keo", "Rattanakorn", "Phommachanh", "Boonmee", "Suksai", "Meng"],
	},
	"ms": {
		"f": ["Siti", "Nur", "Dewi", "Putri", "Aisyah", "Rina", "Ayu", "Sri", "Intan", "Farah"],
		"m": ["Budi", "Ahmad", "Rizky", "Agus", "Hafiz", "Joko", "Arif", "Hendra", "Imran", "Bayu"],
		"last": ["Santoso", "Wijaya", "Hidayat", "Rahman", "Abdullah", "Ismail", "Saputra", "Kusuma", "Hamzah", "Setiawan", "Ibrahim", "Halim"],
	},
	"ph": {
		"f": ["Maria", "Angelica", "Kristine", "Jasmine", "Rosario", "Liza", "Camille", "Joy", "Patricia", "Bea"],
		"m": ["Jose", "Juan", "Mark", "Paolo", "Ramon", "Miguel", "Carlo", "Rodrigo", "Emilio", "Antonio"],
		"last": ["Santos", "Reyes", "Cruz", "Bautista", "Ocampo", "Garcia", "Mendoza", "Aquino", "Dela Cruz", "Villanueva", "Ramos", "Castro"],
	},
	"mn": {
		"f": ["Oyuun", "Sarnai", "Altantsetseg", "Enkhjargal", "Bolormaa", "Narantuya", "Tuya", "Khulan"],
		"m": ["Bat", "Ganbaatar", "Temuujin", "Bold", "Enkhbayar", "Sukhbaatar", "Erdene", "Baatar"],
		"last": ["Batbayar", "Ganbold", "Erdenebat", "Tsogt", "Dorj", "Purev", "Altankhuyag", "Bayar"],
	},
	"my": {
		"f": ["Thida", "Thandar", "Nilar", "Khin", "Su", "Hnin", "Ei", "May"],
		"m": ["Min", "Kyaw", "Thant", "Zaw", "Htun", "Win", "Soe", "Thein"],
		"last": ["Aung", "Myint", "Oo", "Naing", "Lwin", "Hlaing", "Tun", "Maung", "Kyi", "Thu"],
	},
	"oce": {
		"f": ["Grace", "Ruby", "Ella", "Mia", "Aroha", "Losana", "Mere", "Ana", "Kalesi", "Charlotte"],
		"m": ["Jack", "Liam", "Noah", "Tui", "Sione", "Ben", "Tevita", "Wiremu", "Peni", "Josaia"],
		"last": ["Taylor", "Ngata", "Wright", "Tamati", "Reid", "King", "Fraser", "Ward", "Bainimarama", "Waqa", "Kila", "Namaliu"],
	},
}

## Language of each country. Those not here use the most common language of the region.
const COUNTRY_GROUP := {
	"BRA": "pt", "PRT": "pt", "AGO": "pt", "MOZ": "pt", "GNB": "pt", "TLS": "pt",
	"ESP": "es", "MEX": "es", "ARG": "es", "COL": "es", "CHL": "es", "PER": "es", "VEN": "es", "ECU": "es", "GTM": "es",
	"CUB": "es", "BOL": "es", "DOM": "es", "HND": "es", "PRY": "es", "SLV": "es", "NIC": "es", "CRI": "es", "PAN": "es",
	"URY": "es", "GNQ": "es",
	"USA": "en", "GBR": "en", "CAN": "en", "AUS": "en", "NZL": "en", "IRL": "en", "JAM": "en", "TTO": "en", "BHS": "en",
	"BLZ": "en", "GUY": "en",
	"FRA": "fr", "BEL": "fr", "LUX": "fr", "HTI": "fr",
	"CIV": "af_fr", "SEN": "af_fr", "MLI": "af_fr", "BFA": "af_fr", "NER": "af_fr", "GIN": "af_fr", "TCD": "af_fr", "CMR": "af_fr",
	"TGO": "af_fr", "BEN": "af_fr", "GAB": "af_fr", "COG": "af_fr", "COD": "af_fr", "CAF": "af_fr", "MDG": "af_fr", "DJI": "af_fr",
	"BDI": "af_fr", "RWA": "af_fr", "MUS": "af_fr",
	"ETH": "af_horn", "ERI": "af_horn", "SOM": "af_horn",
	"DEU": "de", "AUT": "de", "CHE": "de", "ITA": "it", "NLD": "nl", "SUR": "nl",
	"SWE": "nordic", "NOR": "nordic", "DNK": "nordic", "ISL": "nordic", "FIN": "nordic",
	"RUS": "ru", "UKR": "ru", "BLR": "ru",
	"POL": "pl", "CZE": "pl", "SVK": "pl",
	"SRB": "balkan", "HRV": "balkan", "BIH": "balkan", "SVN": "balkan", "MNE": "balkan", "MKD": "balkan", "BGR": "balkan",
	"ALB": "sq", "XKX": "sq", "ROU": "ro", "MDA": "ro", "HUN": "hu", "GRC": "gr", "CYP": "gr",
	"LTU": "baltic", "LVA": "baltic", "EST": "baltic", "TUR": "tr",
	"KAZ": "ca", "UZB": "ca", "TKM": "ca", "KGZ": "ca", "AZE": "ca", "GEO": "cauc", "ARM": "cauc",
	"IRN": "fa", "AFG": "fa", "TJK": "fa", "ISR": "he",
	"IND": "in", "NPL": "in", "BTN": "in", "LKA": "in", "PAK": "sa_m", "BGD": "sa_m",
	"CHN": "zh", "TWN": "zh", "HKG": "zh", "SGP": "zh", "JPN": "ja", "KOR": "ko", "PRK": "ko", "VNM": "vi",
	"THA": "th", "LAO": "th", "KHM": "th", "IDN": "ms", "MYS": "ms", "BRN": "ms", "PHL": "ph", "MNG": "mn", "MMR": "my",
	"PNG": "oce", "FJI": "oce",
}
const REGION_GROUP := {"LAM": "es", "NAM": "en", "EUR": "de", "MEA": "ar", "AFR": "af_en", "ASI": "zh", "OCE": "oce"}
const DEFAULT_GROUP := "pt"


static func group_for(iso: String, region := "") -> String:
	if COUNTRY_GROUP.has(iso):
		return COUNTRY_GROUP[iso]
	return REGION_GROUP.get(region, DEFAULT_GROUP)


static func _list(group: String, key: String) -> Array:
	return GROUPS.get(group, GROUPS[DEFAULT_GROUP])[key]


static func first(group: String, gender: String, rng: RandomNumberGenerator) -> String:
	var options := _list(group, "f" if gender == "f" else "m")
	return options[rng.randi() % options.size()]


static func last(group: String, gender: String, rng: RandomNumberGenerator) -> String:
	var options := _list(group, "last")
	return _form(String(options[rng.randi() % options.size()]), gender)


static func _form(entry: String, gender: String) -> String:
	var parts := entry.split("|")
	return parts[1] if gender == "f" and parts.size() > 1 else parts[0]


## The same surname in the other gender's form (Ivanov and Ivanova); those without two forms stay the same.
static func regender_last(surname: String, gender: String) -> String:
	for g: String in GROUPS:
		for entry: String in GROUPS[g].last:
			if entry.contains("|") and surname in entry.split("|"):
				return _form(entry, gender)
	return surname


## Probable gender of a first name, for saves and politicians from before genders. When in doubt, the ending in "a".
static func guess_gender(first_name: String) -> String:
	for g: String in GROUPS:
		if first_name in GROUPS[g].f:
			return "f"
		if first_name in GROUPS[g].m:
			return "m"
	return "f" if first_name.ends_with("a") else "m"
