# ÚVOD

Tato semestrální práce se zaměřuje na **sběr a ukládání sledovanosti (rozkoukanosti) videoobsahu napříč všemi typy zařízení** pro dva základní typy diváků – **přihlášené a anonymní**. Cílem je navrhnout a popsat databázové řešení, které umožní jednotným a škálovatelným způsobem zaznamenávat průběh sledování videí bez ohledu na to, zda je uživatel přihlášen ke svému účtu, nebo sleduje obsah anonymně.
Anonymní diváci jsou v systému identifikováni pomocí deviceId, zatímco přihlášení diváci pomocí userId.

V práci se čtenář seznámí s:

- problematikou **sběru dat o sledovanosti videí** v moderních distribuovaných systémech,

- návrhem **datového modelu** pro ukládání rozkoukanosti, včetně validace dat na databázové úrovni,

- rozdíly v přístupu ke zpracování dat pro **anonymní a přihlášené uživatele**,

- využitím **NoSQL databáze MongoDB** pro tento typ úloh,

- základními principy **škálování a vysoké dostupnosti** databáze (např. shardovaný cluster, replikační sady),

- praktickými ukázkami inicializačních skriptů, validačních schémat a práce s časovými údaji (např. createdAt, updatedAt).

Součástí práce je databázový návrh a technický popis řešení. **Není součástí semestrálního projektu** samotná implementace klientských aplikací (web, mobil, smart TV), detailní analýza uživatelského chování, ani pokročilé analytické a reportingové nástroje nad nasbíranými daty. Tyto oblasti by však vzhledem k tématu mohly být přirozeným rozšířením práce – například integrace s analytickými platformami, strojové učení nad daty sledovanosti nebo personalizace obsahu.

# 1. ARCHITEKTURA

## 1.1 Schéma a popis architektury

![Architecture](./doc/architecture.svg)

                Vytvořte schéma architektury a vložte jako obrázek např. pomocí draw.io.
                Podrobně architekturu popište, je nutné minimálně odpověď na tyto otázky:
                    Jak vypadá architektura Vašeho řešení a proč?
                    Jak se případně liší od doporučeného používání a proč?
            1.2.Specifika konfigurace
            Podrobně popište specifikaci Vaší konfigurace. Tato kapitola musí obsahovat následující podkapitoly:

## 1.2.1 CAP teorém

Navržené řešení splňuje garance Availability (A) a Partition Tolerance (P) Brewerova CAP teorému, tedy jedná se o AP systém.

Partition tolerance je v distribuovaném databázovém systému považována za nezbytnou vlastnost, protože výpadky sítě nebo dočasná nedostupnost jednotlivých uzlů nelze v reálném provozu vyloučit. Systém je proto navržen tak, aby i při těchto stavech nadále přijímal zápisy a poskytoval odpovědi klientům.

Dostupnost je v rámci tohoto řešení klíčová. Data o rozkoukanosti musí být přijata a uložena i v případě částečné nedostupnosti clusteru, aby nedocházelo ke ztrátě informací o sledování videí. Vzhledem k charakteru dat je akceptovatelná dočasná nekonzistence, například situace, kdy je uživateli na různých zařízeních vrácena hodnota rozkoukanosti s odchylkou do 10 sekund. Tato odchylka odpovídá intervalu, ve kterém zařízení periodicky odesílá informace o sledování.

Silná konzistence (Consistency) tedy není pro daný use-case nezbytná, protože systém pracuje s eventual consistency a drobná časová nepřesnost nemá negativní dopad na uživatelský zážitek ani funkčnost aplikace.

### 1.2.2. Cluster

V produkčním nasazení je použit **jeden MongoDB sharded cluster**, který je z důvodu vysoké dostupnosti a odolnosti proti výpadkům **rozprostřen přes dvě geograficky oddělená datacentra (Datacentrum A a Datacentrum B)**.

Cluster je tvořen:

- jedním **config server replica setem**,

- několika **shard replica sety**,

- instancemi služby **mongos**, které zprostředkovávají přístup aplikací ke clusteru.

V každém datacentru běží **jedna instance služby mongos**, která slouží jako vstupní bod pro aplikační vrstvu. Aplikace se ke clusteru připojují prostřednictvím služby mongos, která na základě metadat uložených v konfiguračních serverech směruje jednotlivé požadavky na odpovídající shardy.

Z hlediska návrhu vysoké dostupnosti by ideálním řešením bylo umístění jednotlivých uzlů replica setu do **tří nezávislých lokalit**, kde by každý uzel byl umístěn v samostatném datacentru. Taková topologie by umožnila, aby při výpadku kteréhokoliv datacentra došlo k **automatické volbě nového primárního uzlu (primary)** na základě většinového hlasování, bez nutnosti manuálního zásahu.

Tato architektura však **není v daném prostředí realizovatelná**, protože **není k dispozici třetí datacentrová lokalita**, ve které by bylo možné umístit třetí uzel replica setu. Z tohoto důvodu bylo zvoleno řešení se **dvěma datacentry** a následujícím rozložením uzlů:

- **Datacentrum A** obsahuje vždy **dva uzly každého replica setu**, přičemž jeden z nich je preferovaný a standardně zvolen jako primary.

- **Datacentrum B** obsahuje vždy **jeden uzel každého replica setu**, který slouží jako sekundární replika.

Toto rozložení zajišťuje, že při výpadku jednoho uzlu v Datacentru A může replica set stále disponovat většinou hlasů a je schopen **automaticky zvolit nový primární uzel**, aniž by došlo k omezení zápisových operací.

V případě **úplného výpadku Datacentra A** však Datacentrum B samo o sobě nedisponuje dostatečným počtem hlasů pro automatickou volbu primárního uzlu. V takové situaci je **manuálně nasazen další uzel do jednotlivých replica setů v Datacentru B**, čímž je obnovena většina hlasů. Po tomto zásahu je cluster opět schopen **plně přijímat zápisové (write) požadavky**.

Zároveň je toto řešení **odolné vůči tzv. split-brain scénáři**, tedy stavu, kdy dojde k výpadku komunikace mezi Datacentrem A a Datacentrem B. Díky tomu, že většina hlasů v replica setech je standardně umístěna v Datacentru A, nemůže v Datacentru B při ztrátě konektivity dojít k automatické volbě primárního uzlu. Tím je zabráněno vzniku dvou současně aktivních primárních uzlů a zajištěna **konzistence dat**. V případě ztráty komunikace zůstává cluster dostupný pouze v části infrastruktury, která disponuje většinou hlasů.

Zvolená architektura tak představuje vědomý kompromis mezi:

- vysokou dostupností systému,

- konzistencí dat a ochranou proti split-brain,

- omezeními infrastruktury (absence třetí datacentrové lokality),

- a efektivním využitím hardwarových a provozních prostředků.

                1.2.3. Uzly
                    Minimálně 3.
                    Uveďte kolik nodů používáte a proč?
                    Uveďte řádný popis.

### 1.2.4 Sharding/Partitioning
V rámci této semestrální práce je databázový systém **MongoDB** provozován v **sharded clusteru** složeném z **minimálně tří shardů**. Každý shard je realizován jako **Replica Set**, což zajišťuje vysokou dostupnost dat a odolnost vůči výpadkům jednotlivých uzlů.

Použití tří shardů je v kontextu semestrální práce považováno za **dostačující**, protože umožňuje demonstrovat princip horizontálního škálování, distribuci dat a směrování dotazů (query routing) v MongoDB. Zároveň odpovídá omezeným hardwarovým prostředkům dostupným pro akademické nasazení.

V **reálném produkčním prostředí** by však byl počet shardů **výrazně vyšší**, a to zejména z důvodu nutnosti efektivně rozložit **zátěž zapisovacích operací**. Cílové produkční řešení je navrženo tak, aby zvládalo až **70 000 požadavků za sekundu**, přičemž převážná většina těchto požadavků představuje **write operace**. Tyto zápisy vznikají například při pravidelném odesílání informací o sledovanosti obsahu z koncových zařízení, typicky v intervalu několika sekund.

#### Sharding strategie

Zvolená **sharding strategie** je založena na **Shard Key Indexes**, které určují způsob distribuce dokumentů mezi jednotlivé shardy:

- pro kolekci devices je jako **shard key** použit atribut deviceId,

- pro kolekci viewers je jako **shard key** použit atribut userId.

Tato volba shard key zajišťuje, že **veškerá data vztahující se ke konkrétnímu zařízení nebo konkrétnímu divákovi jsou uložena vždy na jednom konkrétním shardu**. Díky tomu nedochází k rozptylování dotazů (scatter-gather queries) napříč celým clusterem a každý dotaz i zápis zatěžuje pouze jeden shard.

Výsledkem tohoto přístupu je:

- **nižší latence** při čtení i zápisu dat,

- **lepší škálovatelnost** zapisovacích operací,

- **efektivní využití clusterových prostředků**,

- a předvídatelné chování systému při vysoké zátěži.

Zvolený způsob sharding/partitioningu je proto vhodný jak z hlediska výkonu, tak i z pohledu budoucího horizontálního škálování systému.
            
### 1.2.5 Replikace

Každý shard je implementován jako replica set se třemi replikami. Tento počet replik je považován za dostačující vzhledem k charakteru dat a poměru operací.

Systém je výrazně zápisově orientovaný, přičemž poměr operací je přibližně 100 zápisů ku 1 čtení. Tři repliky poskytují:

- dostatečnou ochranu proti ztrátě dat,

- vysokou dostupnost zápisů,

- možnost čtení ze sekundárních uzlů v případě potřeby.

Vyšší počet replik by znamenal vyšší latenci zápisů a zvýšené nároky na infrastrukturu, aniž by přinesl významný přínos pro daný use-case.


                1.2.6. Perzistence dat
                    Minimálně 3.
                    Uveďte, jakým způsobem řeší Vaše databáze perzistenci dat?
                    Uveďte, jak pracujte s primární i sekundární pamětí.
                    Uveďte, jak načítáte a ukládáte data.
                    Uveďte řádný popis.
### 1.2.7
Distribuce dat v navrženém řešení je realizována kombinací shardingové a replikační architektury. Data jsou nejprve směrována přes komponentu mongos, která na základě shard klíče rozhodne, do kterého shardu bude daný záznam uložen.

Každý shard ukládá pouze část celkového datasetu a data jsou v rámci shardu replikována mezi tři uzly. Zápisová operace je primárně prováděna na primární repliku shardu, odkud jsou změny asynchronně propagovány na sekundární repliky.

Čtecí operace mohou být směrovány buď na primární, nebo sekundární uzly, v závislosti na požadované konzistenci. Celková distribuce dat je tak navržena tak, aby maximalizovala dostupnost, zvládala vysoký počet zápisů a umožňovala horizontální škálování systému.

                1.2.7. Distribuce dat
                    Z předešlých kapitol vše shrňte a uveďte, jak se data rozdělují pomocí shardů, jak je replikujte, jak konkrétně u Vašeho řešení probíhá celková distribuce dat pro zápis/čtení.
                    Uveďte řádný popis - textový popis + screeny + popis uvádějící například skript, který provádí automatické rozdělení dat, počty záznamů na jendotlivých uzlech (count),...
                1.2.8. Zapezpečení
                    Uveďte, jakým způsobem jste vyřešili zabezpečení databáze a proč?
                    Minimálně je požadována autentizace a autorizace.
                    Upozornění: V případě MongoDB je nutné mít keyfile.
# FUNKČNÍ ŘEŠENÍ
            Tato kapitola obsahuje popis návod na zprovoznění funkčního řešení a popis jeho struktury. 
            2.1. Struktura
                Popište adresářovou strukturu Vašeho řešení a jednotlivé soubory, docker-compose.yml popište důkladně samostatně v kapitole 2.1.1.
                2.1.1. docker-compose.yml
                    Uveďte řádný popis vytvořeného docker-compose.yml.
            2.2. Instalace
                Podrobně popište, jak zprovoznit Vaše řešení.
                Řešení je nutné vytvořit tak, aby využívalo docker a spuštění probíhalo maximálně automatizovaně pomocí docker-compose.yml, tzn. že docker-compose.yml odkazuje na veškeré skripty, se kterými pracuje a pro zprovoznění není nutné provádět manuální spuštění pomocných skriptů.
                V rámci docker-compose.yml využijte automatické spuštění skriptů poté co se vám spustí kontejnery viz například https://www.baeldung.com/ops/docker-compose-run-script-on-start
# PŘÍPADY UŽITÍ A PŘÍPADOVÉ STUDIE
            Popište pro jaké účely (případy užití) ja daná NoSQL databáze vhodná. 
            Uveďte, pro jaký účel (případ užití) jste si danou databázi zvolili a proč? K čemu Vaše řešení slouží? O jaký případ užití se jedná?
            Uveďte, proč jste nezvolili jinou NoSQL databázi vzhledem k účelu?
            Vyhledejte a popište 3 případové studie spojené s vybranou NoSQL databázi.
            Rozsah každé případové studie musí být alespoň 1/2 A4.
# VÝHODY A NEVÝHODY
            Popište, jaké výhody a nevýhody má daná NoSQL databáze.
            Uveďte, jaké výhody a nevýhody má Vaše řešení a proč?
# DALŠÍ SPECIFIKA
            Popis specifických vlastností řešení, pokud nejsou použity žádná specifika, pak uveďte, že vaše řešení je použito jak je doporučeno a nemá vlastní specifika (nic mu nechybí a ani mu nic nepřebývá).
# DATA
            Použijte libovolné 3 datové soubory, kdy jeden soubor obsahuje alespoň 5 tis. záznamů.
            Popis dat bude ve velké míře zpracován pomocí knihoven jazyka Python a dále bude doplněn dovysvětlujícími texty.
            S jakými typy dat Vaše databáze pracuje, jakého jsou formátu a jak s nimi databáze nakládá?
            Proč jste nezvolili další možné datové struktury pro Vaši databázi?
            S kolika daty Vaše databáze bude pracovat? Jakého rozsahu jsou ukázková data?
            Kolik obsahují prázdných hodnot?
            Jaké úpravy jste s daty prováděli a proč?
            Jaký je zdroj dat? Uveďte URL adresu.
            Pomocí skriptů v Python s využitím knihoven Pandas, Numpy, apod. data popište a proveďte základní analýzu dat (základní statistiky - počty, prázdná pole, suma, průměr, grafické zobrazení, apod.
# DOTAZY
            Uveďte a popište 30 NETRIVIÁLNÍCH různých navazujících příkladů včetně řešení (všechny tři datasety popisují jedno téma) a podrobného vysvětlení jednotlivých příkazů.
                NETRIVIVÁLNÍ DOTAZ je například dotaz využívající v MongoDB aggregate a zároveň unwind a zároveň group a zároveň sort nebo například aggregate a zároveň lookup a zároveň match a zároveň project nebo aggregate a zároveň unset a zároveň ......
                Příkazy řádně okomentujete tzn., že každý příkaz zkopírujete z konzole a u každého příkazu uvedete, jaké je jeho obecné chování a jak konkrétně pracuje s daty ve vašem případě a řeší konkrétní úlohu.
                Předpoklad je takový, že budete mít příkazy z různých kategorií např.
                    "práce s daty" - insert, update, delete, merge
                    "agregační funkce",
                    "konfigurace",
                    "nested (embedded) dokumenty"
                    "indexy"
                    takových kategorií je požadováno alespoň 5, kdy u každé "kategorie" uvedete alespoň 6 příkazů.
            Každý dotaz musí vracet nějaká data.
            Každý dotaz musí vracet různá data. Nelze, aby stejná data vracelo více dotazů.
            Dle zvoleného typu databáze využijte i možnost práce s clusterem, replikačním faktorem a shardingem.
            Pokuste se například (mimo jiné) nasimulovat výpadek některého z uzlů a popište možnosti řešení.
            Upozornění: V případě MongoDB je nutné mít validační schéma.
# ZÁVĚR
            V závěru pochvalně i kriticky zhodnoťte Vaši semestrální práci, popište hloubku zpracování. Shrňte k jakým závěrům jste došli, co je možné s Vaším řešením vykonávat, apod.
# ZDROJE
            Uveďte řádně všechny zdroje, se kterými jste pracovali, abecedně seřazené, a to včetně použitých nástrojů.
# PŘÍLOHY DOKUMENTACE
            Data
            složka pojmenovaná Data, která obsahuje:
                obsahuje minimálně 3 datasety
                obsahuje Python skript (JupyterLab)
            Dotazy
            složka pojmenovaná Dotazy, která obsahuje:
                1 soubor se všemi dotazy, kdy každý dotaz obsahuje zadání v přirozeném jazyce a řešení v příslušeném jazyce vybrané NoSQL databáze
            Funkční řešení
            Složka pojmenovaná Funkční řešení, která obsahuje:
                docker-compose.yml
                skripty nutné pro zprovoznění
                případně další složky a soubory nutné pro zprovoznění řešení
