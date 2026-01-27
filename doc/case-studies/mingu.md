# Extrémní výkon pro 900 milionů uživatelů v Číně

## Kontext a výzvy

Migu Video, dceřiná společnost China Mobile, je gigantem na čínském trhu s videoobsahem. S více než 900 miliony diváků čelí datovým objemům, které jsou pro běžné databáze nepředstavitelné. Jejich knihovna obsahuje přes 90 milionů záznamů a během akcí jako zimní olympiáda v Pekingu zažívají brutální nápor dotazů. Staré relační systémy trpěly úzkými hrdly v propustnosti a nebyly schopny efektivně provádět složité agregační dotazy nad nestrukturovanými daty z interaktivních služeb (např. „bullet comments“ – komentáře běžící přímo přes video).

## Řešení s MongoDB Enterprise Advanced

Migu Video začalo v roce 2018 postupně nahrazovat tradiční databáze a dnes tvoří MongoDB více než polovinu jejich datové infrastruktury (přes 450 instancí). Využívají **MongoDB Enterprise Advanced** společně s nástrojem **Ops Manager** pro automatizaci správy. Klíčovým prvkem je **Zone Sharding**, který umožňuje segmentovat data uživatelů podle geografických oblastí. To přibližuje data k uživatelům (edge computing) a zvyšuje odolnost systému – výpadek v jedné zóně neovlivní zbytek země.

## Výsledky a přínosy

Po migraci na MongoDB se **výkon klíčových systémů zvýšil 35násobně**. Během špiček zimní olympiády systém bez jediného zaváhání odbavil **200 000 dotazů za sekundu (QPS)**. Flexibilní schéma MongoDB umožnilo rychlé nasazení interaktivních prvků (metaverse, interaktivní hraní). Přestože počet databázových instancí vzrostl trojnásobně, díky automatizaci přes Ops Manager nebylo nutné úměrně navyšovat počet administrátorů, což vedlo k obrovskému zvýšení efektivity provozu.