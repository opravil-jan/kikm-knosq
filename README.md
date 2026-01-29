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

## 1. ARCHITEKTURA

### 1.1 Schéma a popis architektury

![Architecture](./doc/architecture.svg)

#### Jak vypadá architektura Vašeho řešení a proč?

Řešení je navrženo jako **MongoDB Sharded Cluster**, jehož cílem je zajistit **horizontální škálování**, **rovnoměrné rozložení zátěže a vysokou dostupnost dat**. V rámci této semestrální práce je architektura realizována se **třemi shardy**, které slouží jako **ukázková konfigurace**. V produkčním nasazení by byl počet shardů vyšší a přizpůsobený očekávanému objemu dat a zátěže.

Cluster je tvořen několika shardy, přičemž každý **shard** je implementován jako **ReplicaSet**. Toto řešení umožňuje automatickou volbu primárního uzlu při výpadku a zvyšuje celkovou odolnost systému. Aplikační vrstva komunikuje výhradně přes **mongos router**, který zajišťuje transparentní směrování dotazů a zápisů na správné shardy. Metadata o shardech, chunkech a shard klíčích jsou uložena na **config servers**, které umožňují činnost MongoDB balanceru a správné vyvažování clusteru.

Na architektonickém obrázku je naznačeno **rozložení clusteru do dvou datacenter**, které reflektuje typický produkční scénář. Toto rozdělení zvyšuje dostupnost řešení a jeho odolnost vůči výpadku celé lokality. V rámci semestrální práce slouží toto schéma především jako **koncepční ukázka produkčního nasazení**.

Datový model je rozdělen do dvou hlavních kolekcí:

- **viewers** – data vázaná na uživatele (pole **userId**)

- **devices** – data vázaná na zařízení (pole **deviceId**)

Sharding je povolen na databázi **video_watch_time** a obě kolekce jsou shardované pomocí **hashed shard key**, aby se dosáhlo rovnoměrné distribuce dat i zápisů napříč shardy:

```javascript
sh.enableSharding("video_watch_time")

db.devices.createIndex({ deviceId: "hashed" })
sh.shardCollection("video_watch_time.devices", { deviceId: "hashed" })

db.viewers.createIndex({ userId: "hashed" })
sh.shardCollection("video_watch_time.viewers", { userId: "hashed" })
```

Kolekce **viewers** je shardovaná podle pole **userId**, které je uloženo jako BinData (**subtype 04 – UUID**). Tento formát je úspornější než stringová reprezentace, umožňuje menší indexy a efektivnější shardování. UUID jsou převáděna do binární podoby již při exportu/importu dat, aby nedocházelo k dodatečným změnám shard key, které MongoDB nepovoluje.

Kolekce **devices** je shardovaná podle pole **deviceId**, které je definováno jako pevně dlouhý string (16 znaků) a slouží jako přirozený identifikátor zařízení. Použití hashed shard key zajišťuje rovnoměrnou distribuci dat i v případě vysokého počtu aktivních zařízení.

Inicializace clusteru i dat probíhá řízeně pomocí skriptů. Sharding a indexy jsou nastaveny **před samotným importem dat**, aby se data od počátku rovnoměrně rozprostřela mezi shardy a MongoDB balancer mohl efektivně udržovat vyvážený stav clusteru.

#### Jak se případně liší od doporučeného používání a proč?

Namísto často doporučovaného **range shard key** je v řešení použit **hashed shard key** (pro **userId** i **deviceId**). Důvodem je skutečnost, že prioritou řešení je **rovnoměrná distribuce zápisů a stabilní výkon při vysoké zátěži**, nikoliv optimalizace range dotazů. Tento přístup zároveň minimalizuje riziko vzniku hotspotů a je vhodný pro write-heavy workload.

Další odchylkou od běžného přístupu je **striktní dodržení neměnnosti shard key**. Veškeré transformace dat (např. převod UUID do **BinData**) probíhají ještě před importem do MongoDB, čímž se předchází nepovoleným hromadným aktualizacím shard key. Řízená inicializace shardovaných kolekcí před importem dat se liší od plně automatického chování MongoDB, ale zajišťuje předvídatelné chování clusteru a rovnoměrné zatížení shardů již od začátku provozu.

MongoDB ve své dokumentaci standardně doporučuje **geograficky distribuovanou architekturu se třemi datacentry**, která umožňuje dosažení quorum i při výpadku celé jedné lokality (tzv. majority write concern). V rámci této semestrální práce a případného produkčního nasazení architektura počítá jen se **dvěmi datacentry**, což odpovídá demonstračnímu a produkčnímu charakteru řešení a omezenému rozsahu implementace a prostředků. Toto rozložení je na architektonickém obrázku uvedeno jako model možného produkčního nasazení, přičemž v ideálním produkčním prostředí by bylo vhodné rozšíření na tři a více datacenter v souladu s oficičními doporučeními MongoDB.

### 1.2.Specifika konfigurace

#### 1.2.1 CAP teorém

Navržené řešení splňuje garance Availability (A) a Partition Tolerance (P) Brewerova CAP teorému, tedy jedná se o AP systém.

Partition tolerance je v distribuovaném databázovém systému považována za nezbytnou vlastnost, protože výpadky sítě nebo dočasná nedostupnost jednotlivých uzlů nelze v reálném provozu vyloučit. Systém je proto navržen tak, aby i při těchto stavech nadále přijímal zápisy a poskytoval odpovědi klientům.

Dostupnost je v rámci tohoto řešení klíčová. Data o rozkoukanosti musí být přijata a uložena i v případě částečné nedostupnosti clusteru, aby nedocházelo ke ztrátě informací o sledování videí. Vzhledem k charakteru dat je akceptovatelná dočasná nekonzistence, například situace, kdy je uživateli na různých zařízeních vrácena hodnota rozkoukanosti s odchylkou do 10 sekund. Tato odchylka odpovídá intervalu, ve kterém zařízení periodicky odesílá informace o sledování.

Silná konzistence (Consistency) tedy není pro daný use-case nezbytná, protože systém pracuje s eventual consistency a drobná časová nepřesnost nemá negativní dopad na uživatelský zážitek ani funkčnost aplikace.

#### 1.2.2. Cluster

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

#### 1.2.4 Sharding/Partitioning

V rámci této semestrální práce je databázový systém **MongoDB** provozován v **sharded clusteru** složeném z **minimálně tří shardů**. Každý shard je realizován jako **Replica Set**, což zajišťuje vysokou dostupnost dat a odolnost vůči výpadkům jednotlivých uzlů.

Použití tří shardů je v kontextu semestrální práce považováno za **dostačující**, protože umožňuje demonstrovat princip horizontálního škálování, distribuci dat a směrování dotazů (query routing) v MongoDB. Zároveň odpovídá omezeným hardwarovým prostředkům dostupným pro akademické nasazení.

V **reálném produkčním prostředí** by však byl počet shardů **výrazně vyšší**, a to zejména z důvodu nutnosti efektivně rozložit **zátěž zapisovacích operací**. Cílové produkční řešení je navrženo tak, aby zvládalo až **70 000 požadavků za sekundu**, přičemž převážná většina těchto požadavků představuje **write operace**. Tyto zápisy vznikají například při pravidelném odesílání informací o sledovanosti obsahu z koncových zařízení, typicky v intervalu několika sekund.

##### Sharding strategie

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

#### 1.2.5 Replikace

Každý shard je implementován jako replica set se třemi replikami. Tento počet replik je považován za dostačující vzhledem k charakteru dat a poměru operací.

Systém je výrazně zápisově orientovaný, přičemž poměr operací je přibližně 100 zápisů ku 1 čtení. Tři repliky poskytují:

- dostatečnou ochranu proti ztrátě dat,

- vysokou dostupnost zápisů,

- možnost čtení ze sekundárních uzlů v případě potřeby.

Vyšší počet replik by znamenal vyšší latenci zápisů a zvýšené nároky na infrastrukturu, aniž by přinesl významný přínos pro daný use-case.

#### 1.2.6 Perzistence dat

Perzistence dat v semestrální práci je řešena pomocí databázového systému **MongoDB**, který slouží jako hlavní úložiště dat získaných z externího zdroje a následně analyzovaných. Databáze uchovává data o zařízeních a divácích v kolekcích devices a viewers, nad kterými jsou prováděny analytické dotazy. Data jsou ukládána trvale na disk a zůstávají zachována i po restartu databázového systému nebo celé aplikace.

Databáze je provozována v kontejnerizovaném prostředí pomocí Dockeru. Datový adresář MongoDB je mapován na perzistentní úložiště hostitelského systému, čímž je zajištěno, že uložená data nejsou závislá na životním cyklu kontejneru. Tento přístup umožňuje opakované spouštění databáze bez ztráty již importovaných nebo zpracovaných dat.

MongoDB pracuje s kombinací **primární paměti (RAM)** a **sekundární paměti (disk)**. Operační paměť je využívána především pro cachování často používaných dat a indexů, které jsou následně využívány při agregačních dotazech. Disk slouží jako dlouhodobé úložiště kompletní datové sady. Přesun dat mezi pamětí a diskem je řízen databázovým systémem automaticky a nevyžaduje zásah aplikační vrstvy.

Ukládání dat do databáze probíhá zejména formou **hromadného importu dat ze souborů JSON** při inicializaci databáze. Tato data představují vstupní dataset pro další zpracování. V průběhu práce s databází jsou využívány operace update a upsert, které umožňují aktualizaci existujících záznamů a zabraňují vzniku duplicit, například při opakovaném zpracování stejných dat.

Načítání dat je realizováno pomocí dotazů find a především pomocí agregačních pipeline, které jsou klíčovou součástí semestrální práce. Agregace jsou používány pro výpočty statistik, jako jsou počty zařízení, počty záznamů sledování nebo identifikace zařízení, na kterých nebylo zaznamenáno sledování videa. Zpracování probíhá přímo v databázi, což snižuje množství přenášených dat a zvyšuje efektivitu celého řešení.

#### 1.2.7

Distribuce dat v navrženém řešení je realizována kombinací shardingové a replikační architektury. Data jsou nejprve směrována přes komponentu mongos, která na základě shard klíče rozhodne, do kterého shardu bude daný záznam uložen.

Každý shard ukládá pouze část celkového datasetu a data jsou v rámci shardu replikována mezi tři uzly. Zápisová operace je primárně prováděna na primární repliku shardu, odkud jsou změny asynchronně propagovány na sekundární repliky.

Čtecí operace mohou být směrovány buď na primární, nebo sekundární uzly, v závislosti na požadované konzistenci. Celková distribuce dat je tak navržena tak, aby maximalizovala dostupnost, zvládala vysoký počet zápisů a umožňovala horizontální škálování systému.

##### collection Devices

###### Dotaz pro zjištění rozložení dat mezi jednotlivými shardy

```javascript
db.devices.getShardDistribution()
```

###### Výsledek dotazu

```javascript

Shard replicaSet-shard-02 at replicaSet-shard-02/shard-02-a.femoz.net:27018,shard-02-b.femoz.net:27018,shard-02-c.femoz.net:27018
{
  data: '43.94MiB',
  docs: 334497,
  chunks: 1,
  'estimated data per chunk': '43.94MiB',
  'estimated docs per chunk': 334497
}

Shard replicaSet-shard-03 at replicaSet-shard-03/shard-03-a.femoz.net:27018,shard-03-b.femoz.net:27018,shard-03-c.femoz.net:27018
{
  data: '43.72MiB',
  docs: 332820,
  chunks: 1,
  'estimated data per chunk': '43.72MiB',
  'estimated docs per chunk': 332820
}

Shard replicaSet-shard-01 at replicaSet-shard-01/shard-01-a.femoz.net:27018,shard-01-b.femoz.net:27018,shard-01-c.femoz.net:27018
{
  data: '43.7MiB',
  docs: 332683,
  chunks: 1,
  'estimated data per chunk': '43.7MiB',
  'estimated docs per chunk': 332683
}

Totals
{
  data: '131.37MiB',
  docs: 1000000,
  chunks: 3,
  'Shard replicaSet-shard-02': [
    '33.45 % data',
    '33.44 % docs in cluster',
    '137B avg obj size on shard'
  ],
  'Shard replicaSet-shard-03': [
    '33.28 % data',
    '33.28 % docs in cluster',
    '137B avg obj size on shard'
  ],
  'Shard replicaSet-shard-01': [
    '33.26 % data',
    '33.26 % docs in cluster',
    '137B avg obj size on shard'
  ]
}
```

##### collection viewers

###### Dotaz pro zjištění rozložení dat mezi jednotlivými shardy

```javascript
db.viewers.getShardDistribution()
```

###### Výsledek dotazu

```javascript

Shard replicaSet-shard-03 at replicaSet-shard-03/shard-03-a.femoz.net:27018,shard-03-b.femoz.net:27018,shard-03-c.femoz.net:27018
{
  data: '56.65MiB',
  docs: 330943,
  chunks: 1,
  'estimated data per chunk': '56.65MiB',
  'estimated docs per chunk': 330943
}
Shard replicaSet-shard-02 at replicaSet-shard-02/shard-02-a.femoz.net:27018,shard-02-b.femoz.net:27018,shard-02-c.femoz.net:27018
{
  data: '57.17MiB',
  docs: 334128,
  chunks: 1,
  'estimated data per chunk': '57.17MiB',
  'estimated docs per chunk': 334128
}

Shard replicaSet-shard-01 at replicaSet-shard-01/shard-01-a.femoz.net:27018,shard-01-b.femoz.net:27018,shard-01-c.femoz.net:27018
{
  data: '57.32MiB',
  docs: 334929,
  chunks: 1,
  'estimated data per chunk': '57.32MiB',
  'estimated docs per chunk': 334929
}

Totals
{
  data: '171.15MiB',
  docs: 1000000,
  chunks: 3,
  'Shard replicaSet-shard-03': [
    '33.1 % data',
    '33.09 % docs in cluster',
    '179B avg obj size on shard'
  ],
  'Shard replicaSet-shard-02': [
    '33.4 % data',
    '33.41 % docs in cluster',
    '179B avg obj size on shard'
  ],
  'Shard replicaSet-shard-01': [
    '33.49 % data',
    '33.49 % docs in cluster',
    '179B avg obj size on shard'
  ]
}
```

#### 1.2.8. Zapezpečení

Zabezpečení databáze MongoDB je v rámci této semestrální práce řešeno pomocí **autentizace** a **autorizace uživatelů** a **zabezpečení interní komunikace mezi databázovými uzly**. Toto řešení odpovídá doporučenému postupu MongoDB pro provoz v clusterovém prostředí.

Autentizace je realizována pomocí vestavěného uživatelského systému MongoDB. V databázi admin je vytvořen administrátorský uživatel cluster-admin s rolí root, který slouží výhradně pro správu databázového clusteru. Pro aplikační část je v databázi video_watch_time vytvořen samostatný uživatel pcm s rolí readWrite, který má přístup pouze k datům potřebným pro běh aplikace. Tím je zajištěna **autorizace** na základě rolí a dodržen princip minimálních oprávnění, kdy aplikace nemá administrátorská práva nad celým systémem.

Vzhledem k tomu, že databáze běží v distribuovaném prostředí, je zabezpečena také **vzájemná komunikace mezi jednotlivými instancemi MongoDB**. K tomuto účelu je použit **keyfile**, který MongoDB využívá pro interní autentizaci uzlů v replica setu nebo shardovaném clusteru. Keyfile obsahuje sdílený tajný klíč, díky kterému si jednotlivé uzly ověřují svou důvěryhodnost a brání se neoprávněnému připojení cizí instance.

## 2. FUNKČNÍ ŘEŠENÍ

### 2.1. Struktura

Projekt je navržen jako distribuovaný **MongoDB sharded cluster**, který se skládá z následujících hlavních komponent:

- **Config servery** (Replica Set) – uchovávají metadata o clusteru
- **Shardy** (Replica Sets) – samotná datová vrstva
- **Mongos routery** – směrování dotazů do shardů
- **HAProxy** – jednotný vstupní bod do clusteru
- **Inicializační kontejner** (cluster-init) – automatická konfigurace clusteru po startu

Veškerá persistentní data jsou ukládána mimo kontejnery do adresáře **storage/**, aby byla zajištěna jejich trvalost i po restartu.

#### 2.1.1. Adresářová struktura projektu

Adresářová struktura projektu je následující:

```console

├── data -> storage/net/femoz/cluster-init/docker-entrypoint-initdb.d/data
├── doc
├── storage
│   └── net
│       └── femoz
│           ├── cluster-init
│           │   ├── docker-entrypoint-initdb.d
│           │   │   └── data
│           │   └── scripts
│           ├── config-server-01
│           │   └── data/configdb
│           ├── config-server-02
│           │   └── data/configdb
│           ├── config-server-03
│           │   └── data/configdb
│           ├── haproxy
│           │   └── usr/local/etc/haproxy
│           ├── mongos-01
│           │   └── data/db
│           ├── mongos-02
│           │   └── data/db
│           ├── shard-01-a
│           ├── shard-01-b
│           ├── shard-01-c
│           ├── shard-02-a
│           ├── shard-02-b
│           ├── shard-02-c
│           ├── shard-03-a
│           ├── shard-03-b
│           └── shard-03-c

```

##### Popis klíčových částí

- storage/net/femoz/

    Hlavní adresář pro persistentní data jednotlivých MongoDB uzlů.

- cluster-init/

    Obsahuje skripty a inicializační data, která jsou spuštěna automaticky po startu clusteru:
  - scripts/init-cluster.sh – skript pro inicializaci replica setů, shardů a jejich připojení
  - docker-entrypoint-initdb.d/data – ukázková data pro naplnění databáze

- config-server-*

    Datové adresáře konfiguračních serverů MongoDB (metadata clusteru).

- shard-*-*

    Datové adresáře jednotlivých shardů, každý shard je tvořen replica setem o třech uzlech.

- mongos-*

    Datové adresáře routerů mongos, které přijímají klientské dotazy.

- haproxy/

    Obsahuje konfiguraci HAProxy, která zajišťuje jednotný přístupový bod do clusteru.

#### 2.1.2 docker-compose.yml

Soubor docker-compose.yml definuje kompletní topologii MongoDB clusteru. Je rozdělen do několika logických částí:

##### Config servery

Tři kontejnery (config-server-01, 02, 03) tvoří **replica set konfiguračních serverů**, který je nezbytný pro provoz shardovaného clusteru.

- Použitý image: mongo

- Port: 27019

- Parametry:
  - --configsvr
  - --replSet replicaSet-config

##### Shardy

Řešení obsahuje tři shardy, každý ve formě replica setu o třech uzlech:

- replicaSet-shard-01
- replicaSet-shard-02
- replicaSet-shard-03

Každý shard používá:

- Port 27018
- Parametr --shardsvr

Tato konfigurace umožňuje horizontální škálování a vysokou dostupnost dat.

##### Mongos routery

Dva kontejnery (mongos-01, mongos-02) slouží jako routery, které přijímají dotazy klientů a směrují je do správných shardů.

- Port 27017
- Připojení na config replica set

##### HAProxy

HAProxy slouží jako externí vstupní bod pro klienty:

- Mapuje port 27017 na hostiteli
- Směruje provoz na mongos uzly
- Umožňuje jednoduché přepínání a rozšíření clusteru

##### Inicializační kontejner (cluster-init)

Speciální kontejner cluster-init:

- Spouští skript init-cluster.sh automaticky po startu ostatních služeb

- Inicializuje:
  - replica sety
  - přidání shardů do clusteru
  - vytvoření databází a kolekcí
- Řídí se proměnnými z .env souboru

Tento přístup odpovídá doporučenému postupu automatického spouštění skriptů po startu kontejnerů.

### 2.2. Instalace

#### Požadavky

- Docker
- Docker Compose
- Linux / macOS (řešení je testováno primárně na Linuxu)

#### Postup instalace

##### 1. Naklonování repozitáře

```console
git clone https://github.com/opravil-jan/kikm-knosq.git
cd kikm-knosq
```

##### 2. Nastavení proměnných prostředí

V souboru .env lze řídit chování inicializace clusteru, např.:

```console
CLUSTER_INIT_ENABLED=1
```

##### 3. Spuštění projektu

Projekt se spouští výhradně pomocí skriptu start.sh:

```console
./start.sh

```

#### Funkce skriptu start.sh

Skript provádí následující kroky:

1. Načte proměnné prostředí ze souboru .env

2. Zastaví běžící kontejnery (docker compose down)

3. Pokud je povolena inicializace (CLUSTER_INIT_ENABLED=1):
    - vytvoří docker network pokud neexistuje
    - smaže stará data shardů a config serverů
    - vytvoří čisté adresáře pro nový cluster

4. Spustí celý cluster pomocí:

    ```code
    docker compose up -d
    ```

Díky tomuto přístupu je možné:

- cluster kompletně znovu inicializovat
- nebo jej spustit bez zásahu do existujících dat

#### Shrnutí

Navržené řešení splňuje všechny požadavky zadání:

- je plně kontejnerizované,
- využívá docker-compose.yml jako hlavní řídicí prvek,
- nevyžaduje manuální spouštění pomocných skriptů,
- umožňuje automatickou inicializaci MongoDB shardovaného clusteru,
- je snadno rozšiřitelné a opakovatelné.

Celý projekt je uložen ve veřejném Git repozitáři, kde je k dispozici i kompletní zdrojový kód a doplňující dokumentace.

## 3. PŘÍPADY UŽITÍ A PŘÍPADOVÉ STUDIE

### 3.1 Vhodnost NoSQL databáze MongoDB pro různé případy užití

NoSQL databáze jsou obecně vhodné pro scénáře, kde je kladen důraz na vysokou škálovatelnost, flexibilní datový model a schopnost pracovat s velkými objemy dat. MongoDB patří mezi dokumentově orientované NoSQL databáze a ukládá data ve formátu BSON (binární JSON), což umožňuje přirozené mapování objektů aplikace na databázovou strukturu.

MongoDB je vhodná zejména pro následující případy užití:

- aplikace s rychle se měnícím datovým schématem,
- systémy pracující s velkým objemem nestrukturovaných nebo polostrukturovaných dat,
- analytické a logovací systémy,
- real-time aplikace s vysokým počtem zápisů,
- distribuované systémy vyžadující horizontální škálování (sharding),
- aplikace s požadavkem na vysokou dostupnost a odolnost vůči výpadkům.

Díky podpoře **replika setů a shardovaného clusteru** je MongoDB schopna efektivně škálovat jak výkonově, tak kapacitně, což je klíčové pro moderní datově náročné aplikace.

### 3.2 Zdůvodnění volby databáze MongoDB pro navržené řešení

Pro navržené řešení byla zvolena databáze MongoDB především z důvodu potřeby:

- horizontálního škálování dat,
- vysoké dostupnosti,
- ukládání časových a uživatelských dat ve velkém objemu,
- flexibilního datového modelu.

Navržený systém slouží jako **datová vrstva pro ukládání a analýzu uživatelského chování**, konkrétně např. sledování aktivity uživatelů, zařízení nebo interakcí s obsahem. Jedná se o typický **event-driven a analytický případ užití**, kde dochází k vysokému počtu zápisů a kde se objem dat v čase výrazně zvětšuje.

MongoDB byla zvolena zejména proto, že:

- podporuje sharding na úrovni kolekcí, což umožňuje rozložení dat mezi více uzlů,
- umožňuje snadnou změnu struktury dokumentů bez nutnosti migrací schématu,
- nabízí vysoký výkon při zápisu i čtení,
- má bohatý ekosystém nástrojů a velmi dobrou dokumentaci.

### 3.3 Proč nebyla zvolena jiná NoSQL databáze

Alternativní NoSQL databáze byly zvažovány, avšak nebyly zvoleny z následujících důvodů:

- **Cassandra**

    Je optimalizovaná především pro extrémně vysoký počet zápisů a jednoduché dotazy nad klíči. Nevhodná je však pro složitější dotazy a flexibilní práci s dokumenty, kterou MongoDB umožňuje.

- **Redis**

    Je primárně in-memory databáze, vhodná spíše jako cache nebo pro krátkodobá data. Pro dlouhodobé ukládání velkého objemu dat by byla nákladná a méně vhodná.

- **CouchDB**
    Nabízí dokumentový model podobný MongoDB, ale má slabší podporu shardování a nižší výkon při vysokém zatížení.

MongoDB tedy představuje optimální kompromis mezi flexibilitou, výkonem a možnostmi distribuce dat.


### 3.4 Případové studie

- [FZ Sports](./doc/case-studies/fz-sports.md)
- [Mediastream](./doc/case-studies/mediastream.md)
- [Migu Video](./doc/case-studies/mingu.md)

## 4. VÝHODY A NEVÝHODY

### MongoDB (obecně) – výhody a nevýhody

#### Výhody

MongoDB je dokumentová NoSQL databáze, která umožňuje ukládat data ve flexibilním JSON/BSON formátu bez nutnosti striktního relačního schématu. To urychluje vývoj, protože se model snadno přizpůsobuje změnám požadavků. Dobře se hodí pro práci s velkým množstvím dat a vysokou zátěží, nabízí výkonné indexování a nativně podporuje replikaci a horizontální škálování (sharding).

#### Nevýhody

Flexibilita schématu může vést k nekonzistentním datům, pokud se nepoužije validace. Ve srovnání s relačními DB bývá složitější udržet datovou integritu napříč více kolekcemi (např. vztahy a složité joiny), a některé analytické dotazy mohou být náročnější na návrh i výkon. U špatně navržených indexů nebo dotazů může rychle růst spotřeba paměti a diskového prostoru.

### Navrhované řešení (sharding + replikace) – výhody a nevýhody a proč

#### Výhody (proč)

- Škálovatelnost: Díky shardingu lze data rozdělit mezi více uzlů a zvyšovat výkon i kapacitu přidáváním dalších serverů. To je vhodné pro růst objemu záznamů i počtu dotazů.

- Dostupnost: Replikační sety zajišťují odolnost vůči výpadku uzlu – při selhání primárního uzlu proběhne volba nového a systém pokračuje bez zásadního dopadu.

- Lepší rozložení zátěže: Rozdělení kolekcí (např. podle různých shard klíčů) pomáhá oddělit hotspoty a umožní optimalizovat výkon pro různé typy přístupů (např. podle userId vs. deviceId).

#### Nevýhody (proč)

- Vysoké hardwarové nároky pro produkční provoz: Produkční sharded cluster typicky vyžaduje více uzlů (shardy, config servery, routery mongos, replikace), což znamená vyšší náklady na CPU/RAM/disky a síť.

- Vyšší provozní složitost: S rostoucím počtem uzlů roste náročnost správy (monitoring, zálohování, aktualizace, ladění shard klíčů, balancování chunků).

- Citlivost na volbu shard klíče: Špatně zvolený shard key může způsobovat nerovnoměrné rozložení dat/zátěže (hotspoty) a výkonové problémy, které se pak řeší obtížně.

- Komplexnější dotazy napříč shardy: Některé dotazy mohou být „scatter-gather“ (dotaz na více shardů), což zvyšuje latenci a zatížení clusteru.

## 5. DALŠÍ SPECIFIKA

Navrhované řešení nemá žádná specifika a odpovídá standardím řešením dle dokumentace

## 6. DATA

V aktuální verzi práce máš 2 kolekce každá obsahuje 1 000 000 dokumentů a tedy typicky i 2 datové soubory pro seed/import:

- devices.json → anonymní diváci (podle zařízení)
- viewers.json → přihlášení diváci (podle userId)

### S jakými typy dat vaše databáze pracuje, jakého jsou formátu a jak s nimi databáze nakládá?

**Databáze**: MongoDB
**Kolekce**: devices (anonymní), viewers (přihlášení)
**Import formát**: JSON (prakticky NDJSON pro mongoimport)

#### devices – pole a typy (jen dle schématu)

- deviceId – string (délka 16; required)
- sidp – long (10000 až 20000000000)
- idec – string (3–20; required)
- progress – int (>= 0; required) – poslední čas sledování (sekundy)
- finished – bool
- createdAt – date
- updatedAt – date

#### viewers – pole a typy (jen dle schématu)

- userId – binData (required) – identifikátor přihlášeného diváka
- deviceId – string (délka 16)
- sidp – long (10000 až 20000000000)
- idec – string (3–20; required)
- progress – int (>= 0; required)
- finished – bool
- createdAt – date
- updatedAt – date

### Jak s daty DB nakládá

- MongoDB ukládá dokumenty jako BSON (typy jako date, binData, long jsou nativní).

- Má zapnutou schema validation přes $jsonSchema, takže do kolekcí neprojde nevalidní dokument (typ, required pole, rozsahy).

- Nevyužíváš vnořená data: dokumenty jsou “ploché”, což zrychluje čtení i indexaci a zjednodušuje dotazy.

### Proč jste nezvolili další možné datové struktury pro Vaši databázi?

Řešení míří na poměr výkon / složitost / provozní náklady.

#### Proč dokumentová DB (MongoDB) v tomto scénáři dává smysl

- Data jsou logicky “záznamy posledního stavu sledování” (device/user + idec + progress).

- Potřebuješ jednoduchý rychlý zápis a rychlé čtení pro agregace (např. top idec podle počtu).

- Plochý model bez vnoření = rychlost + jednoduchost.

#### Proč ne relační DB

- Pro tak velké objemy event-like dat a časté agregace by SQL řešení typicky vedlo k vysokým nárokům (indexy, joiny, údržba, scaling), případně ke komplikované architektuře.
- Navíc rigidní schéma je méně flexibilní pro importy a validaci při různých variantách záznamů.
- Dalším významným omezením relačních databází je nízká rychlost zápisu při vysoké zátěži.

#### Proč ne Cassandra (a podobná řešení)

Cassandra by šla použít, ale je extrémně složitá na návrh (modelování podle dotazů, kompakce, tuning) a produkční nasazení.

### S kolika daty bude databáze pracovat? Jakého rozsahu jsou ukázková data?

Ukázková data jsou ve stovkách MB:

- viewers.json ~236 MB
- devices.json ~165 MB

Počet záznamů v každé kolekci je 1 000 000.

V reálném provozu počítáme s ročním přírůstkem:

- viewers 10 000 000
- devices 7 000 000

### Kolik obsahují prázdných hodnot?

V rámci schématu platí:

- povinná pole (required) nesmí být prázdná (deviceId/userId, idec, progress)
- ostatní pole (sidp, deviceId u viewers, finished, createdAt, updatedAt) mohou chybět / být null podle toho, co export dodá

Prázdné hodnoty tedy typicky uvidíš hlavně u:

- finished
- createdAt, updatedAt
- sidp
- deviceId (jen u viewers)

Data byla analyzována pomocí vlastního Python skriptu empty-values.py, který zpracovává zdrojová JSON data a zjišťuje výskyt prázdných hodnot u jednotlivých polí definovaných ve schématu databáze. Výsledky této analýzy jsou uvedeny níže.

#### devices.json

- createdAt:  1000000
- sidp:       33963
- deviceId:   0
- idec:       0
- progress:   0
- finished:   0
- updatedAt:  0

#### viewers.json

- createdAt:  1000000
- sidp:       7157
- userId:     0
- deviceId:   0
- idec:       0
- progress:   0
- finished:   0
- updatedAt:  0

### Jaké úpravy jste s daty prováděli a proč?

- Převod dat do formátu vhodného pro import (mongoimport)
- Validace a čištění podle $jsonSchema
- typy:
  - progress int - chyby v datech kdy progress je menší než 0
  - sidp long - správně zavést datový typ
  
    ```json
    {"sidp":{"$numberLong":"14288838217"}}
    ```
  
  - updatedAt date - správně označit string, že je typu date
  
    ```json
    {"updatedAt":{"$date":"2025-07-18T17:16:16.555Z"}}
    ```

  - userId binData - určit subtyp binárních dat

    ```json
    {"userId":{"$uuid":"7318ff1f-ad73-4740-8177-9e47318dec2a"}}
    ```

  - Omezení extrémních hodnot progress - odebrání maximální délky videa ve schématu

### Jaký je zdroj dat? Uveďte URL adresu.

Zdroj dat je Elasticsearch, kde jsou data aktuálně ukládána z důvodu nižších hardwarových požadavků a protože je potřeba zvládat velký objem dat. V interním systému zaměstnavatele

## 7. DOTAZY

### 7.1 Práce s daty

#### Insert: Ulož novou rozkoukanost

```javascript
db = db.getSiblingDB("video_watch_time");

db.viewers.insertOne({
  userId: UUID("d3ae5057-13bd-44c7-8231-8ab937b9b601"),
  deviceId: "6783052292090994",
  sidp: "12059685760",
  idec: "219562220460017",
  progress: 10,
  finished: false,
  createdAt: new Date(),
  updatedAt: new Date(),
})
```

#### Update: Aktualizuj rozkoukanost

```javascript
db = db.getSiblingDB("video_watch_time")

db.viewers.findOneAndUpdate(
  {
    userId: UUID("d3ae5057-13bd-44c7-8231-8ab937b9b601"),
    idec: "219562220460017",
  },
  {
    $set: {
      deviceId: "6783052292090994",
      progress: 20,
      finished: false,
      updatedAt: new Date()
    }
  }
)
```

#### Insert on conflict update: Založ novou rozkoukanost a nebo aktualizuj existující

```javascript
db = db.getSiblingDB("video_watch_time");

db.viewers.updateOne(
  {
    userId: UUID("d3ae5057-13bd-44c7-8231-8ab937b9b601"),
    idec: "219562220460017"
  },
  {
    $set: {
      deviceId: "6783052292090994",
      progress: 20,
      finished: false,
      updatedAt: new Date()
    },
    $setOnInsert: {
      userId: UUID("d3ae5057-13bd-44c7-8231-8ab937b9b601"),
      idec: "219562220460017",
      createdAt: new Date()
    },
  },
  {
    upsert: true
  }
)
```

#### Delete: Smaž všechna rozkoukaná videa diváka

```javascript
db = db.getSiblingDB("video_watch_time");

db.viewers.deleteMany({ userId: UUID("8ba16964-bda3-4a4e-9ae4-07e4c25ecf04") })
```

#### Merge: převeď všechny rozkoukané videa anonymního diváka pod účet diváka přihlášeného diváka

```javascript
db = db.getSiblingDB("video_watch_time");

db.devices.aggregate([
  {
    $match: {
      deviceId: "7900991453332736"
    }
  },
  {
    $addFields: {
      userId: UUID("808fc319-c8af-460b-a27d-0ec2b6f145fd"),
      createdAt: new Date(),
      updatedAt: new Date()
    }
  },
  {
    $merge: {
      into: "viewers",
      whenMatched: "fail",     // nebo "keepExisting"
      whenNotMatched: "insert"
    }
  }
]).toArray()
```

### 7.2 Agregační funkce

#### Seznam deseti nejsledovanejsich videi anonymních diváků

```javascript
db = db.getSiblingDB("video_watch_time");

db.devices.aggregate([
  {
    $match: {
      idec: { $exists: true, $ne: null }
    }
  },

  {
    $group: {
      _id: "$idec",
      recordsCount: { $sum: 1 }
    }
  },
  {
    $sort: {
      recordsCount: -1
    }
  },
 {
    $limit: 10
  },
  {
    $project: {
      _id: 0,
      idec: "$_id",
      recordsCount: 1
    }
  }
]).toArray()
```

#### Počet zařízení na kterých se diváci nepřihlašují

```javascript
db = db.getSiblingDB("video_watch_time");

db.devices.aggregate([
  {
    $lookup: {
      from: "viewers",
      localField: "deviceId",
      foreignField: "deviceId",
      as: "viewerRefs"
    }
  },
  {
    $match: {
      $expr: { $eq: [ { $size: "$viewerRefs" }, 0 ] }
    }
  },
  {
    $group: {
      _id: null,
      devicesNotUsedByViewers: { $sum: 1 }
    }
  },
  {
    $project: {
      _id: 0,
      devicesNotUsedByViewers: 1
    }
  }
]).toArray()

```

#### Počet zařízení na kterých se diváci přihlašují a zároveň na nich koukají jako anonymní

```javascript
db = db.getSiblingDB("video_watch_time");

db.devices.aggregate([
  {
    $lookup: {
      from: "viewers",
      localField: "deviceId",
      foreignField: "deviceId",
      as: "viewer"
    }
  },
  {
    $match: {
      viewer: { $ne: [] }
    }
  },
  {
    $group: {
      _id: "$deviceId"
    }
  },
  {
    $count: "uniqueDevicesInBoth"
  }
]).toArray()
```

#### Seznam 20 nejrozkoukanejsich serialu na ktere se divaji prihlaseni divaci

```javascript
db = db.getSiblingDB("video_watch_time");

db.viewers.aggregate([
  {
    $match: {
      finished: false
    }
  },
  {
    $group: {
      _id: "$sidp",
      idecCount: { $sum: 1 }
    }
  },
  {
    $sort: {
      idecCount: -1
    }
  },
  {
    $limit: 20
  },
  {
    $project: {
      _id: 0,
      sidp: "$_id",
      idecCount: 1
    }
  }
]).toArray()

```

#### Seznam uživatelů kteří nekoukali na žadné video za poslední rok

```javascript
db = db.getSiblingDB("video_watch_time");

const oneYearAgo = new Date();
oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);

db.viewers.aggregate([
  {
    $group: {
      _id: "$userId",
      lastUpdatedAt: { $max: "$updatedAt" }
    }
  },
  {
    $match: {
      $or: [
        { lastUpdatedAt: { $lt: oneYearAgo } },
        { lastUpdatedAt: { $exists: false } }
      ]
    }
  }
]).toArray();
```

#### Celkový počet videi které sledovaly anonymní diváci a nedokoukali je. To jest updatedAt je starší než jeden měsíc

```javascript
db = db.getSiblingDB("video_watch_time");

const oneMonthAgo = new Date();
oneMonthAgo.setMonth(oneMonthAgo.getMonth() - 1);

db.devices.aggregate([
  {
    $match: {
      finished: false,
      updatedAt: { $lt: oneMonthAgo }
    }
  },
  {
    $count: "totalUndoneVideos"
  }
]).toArray();
```

#### Kolik průměrně má přihlášený divák rozkoukaných videii za posledni 3 měsíce

```javascript
db = db.getSiblingDB("video_watch_time");

const threeMonthsAgo = new Date();
threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

db.viewers.aggregate([
  // jen poslední 3 měsíce + rozkoukaná videa
  {
    $match: {
      finished: false,
      updatedAt: { $gte: threeMonthsAgo }
    }
  },

  // počet rozkoukaných videí per user
  {
    $group: {
      _id: "$userId",
      rozkoukanaVidea: { $sum: 1 }
    }
  },

  // průměr přes všechny uživatele
  {
    $group: {
      _id: null,
      prumerRozkoukanychVideiNaUzivatele: {
        $avg: "$rozkoukanaVidea"
      },
      pocetUzivatelu: { $sum: 1 }
    }
  }
]).toArray();

```




### xxx

### 7.3 Konfigurace

#### Rozložení collection v shardech

```javascript
db = db.getSiblingDB("video_watch_time");

db.devices.getShardDistribution()

```

### 7.5 Indexy

#### Unique index pro zamezení duplicit rozkoukanosti

Index je použit už při inicializaci clusteru před tím než jsou do něj importována první data

```javascript
db = db.getSiblingDB("video_watch_time");

db.devices.createIndex({ deviceId: 1, idec: 1 }, { unique: true });
```

#### Query: Seznam deseti nejsledovanejsich videi anonymních diváků

```javascript
db.devices.createIndex(
  { idec: 1 }
);
```

#### Query: Počet zařízení na kterých se diváci nepřihlašují

```javascript
db = db.getSiblingDB("video_watch_time");

db.viewers.createIndex(
  { deviceId: 1 }
);
db.devices.createIndex(
  { deviceId: 1 }
);
```

#### Query: Seznam 20 nejrozkoukanejsich serialu na ktere se divaji prihlaseni divaci

```javascript
db = db.getSiblingDB("video_watch_time");

db.viewers.createIndex(
  { sidp: 1 },
  { partialFilterExpression: { finished: false } }
);
```

#### Query: Seznam uživatelů kteří nekoukali na žadné video za poslední rok

```javascript
db = db.getSiblingDB("video_watch_time");

db.viewers.createIndex(
  { userId: 1, updatedAt: -1 }
);
```

#### Query: Celkový počet videi které sledovaly anonymní diváci a nedokoukali je. To jest updatedAt je starší než jeden měsíc

```javascript
db = db.getSiblingDB("video_watch_time");

db.devices.createIndex(
  { updatedAt: 1 },
  { partialFilterExpression: { finished: false } }
);
```

#### Query: Kolik průměrně má přihlášený divák rozkoukaných videii za posledni 3 měsíce

```javascript
db = db.getSiblingDB("video_watch_time");

db.viewers.createIndex(
  { updatedAt: 1, userId: 1 },
  { partialFilterExpression: { finished: false } }
);

```

## 8. ZÁVĚR

Cílem této semestrální práce bylo navrhnout a ověřit řešení pro sběr, ukládání a vyhodnocování dat o sledovanosti videí s důrazem na škálovatelnost a práci s velkým objemem dat. Zvolené řešení bylo založeno na dokumentově orientované databázi MongoDB, distribuované architektuře a využití shardování pro horizontální škálování.

Na základě provedené analýzy, návrhu schémat, indexace a ukázkových dotazů lze konstatovat, že navržené řešení je funkční a vhodné pro daný typ problému. Umožňuje efektivně ukládat informace o zařízeních, uživatelích a jejich interakcích se sledovaným obsahem, a zároveň nad těmito daty provádět analytické dotazy, jako je zjišťování nejsledovanějších videí či identifikace neaktivních zařízení. Hloubka zpracování odpovídá požadavkům semestrální práce a zahrnuje nejen samotný návrh databáze, ale i úvahy nad shard klíči, indexací a distribucí dat.

Zásadním omezením navrženého řešení je však jeho **vysoká závislost na dostatečném množství hardwarových prostředků**. Aby bylo řešení skutečně robustní a schopné dlouhodobě ustát vysoký provoz a velký počet souběžných uživatelů, je nutné nasazení většího počtu shardů, replikačních uzlů a odpovídající síťové infrastruktury. Toto lze považovat za jediné, avšak klíčové omezení – bez adekvátního hardwaru by systém mohl narážet na výkonové limity.

Dalším aspektem, který lze hodnotit kriticky, je **komplikovanost dotazovacího jazyka MongoDB** oproti klasickému SQL. Především agregační pipeline může být pro vývojáře méně přehledná a hůře čitelná než ekvivalentní relační dotazy, zejména u složitějších analytických úloh. Na druhou stranu tento přístup nabízí vysokou flexibilitu a výkon při práci s rozsáhlými daty.

Je důležité zdůraznit, že tato semestrální práce představuje pouze simulaci reálného problému v omezeném akademickém kontextu. V produkčním nasazení, při dostatečném počtu hardwarových prostředků a správném nastavení architektury, je však navržené řešení schopné fungovat spolehlivě a robustně a zvládnout veškeré požadavky kladené na podobný systém v praxi.

## 9. ZDROJE

- https://chatgpt.com
- https://gemini.google.com
- https://www.mongodb.com/docs
- https://www.gnu.org/savannah-checkouts/gnu/bash/manual/bash.html
- https://www.youtube.com/watch?v=LBthwZDRR-c&list=PL34sAs7_26wPvZJqUJhjyNtm7UedWR8Ps&index=2
