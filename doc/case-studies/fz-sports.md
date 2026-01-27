
# FZ Sports: Budování „digitálního stadionu“ pro miliony fanoušků

## Kontext a výzvy

 FZ Sports je mateřskou společností platformy **Fanatiz**, jedné z nejrychleji rostoucích sportovních streamovacích služeb na světě. Spravuje práva pro 1190 Sports a technologii Nunchee, přičemž ročně odvysílá přes 10 000 zápasů. Hlavním problémem byla **extrémní nárazová zátěž** – v jeden okamžik může probíhat až 30 fotbalových utkání současně. Původní řešení postavené na relačních databázích naráželo na limity škálovatelnosti a flexibility. Tým ztrácel drahocenný čas manuální údržbou a migracemi schémat, což ohrožovalo stabilitu přenosů v kritických momentech, kdy fanoušci netolerují žádné výpadky.

## Řešení s MongoDB Atlas

Společnost se rozhodla pro přechod na non-relační model a zvolila **MongoDB Atlas** běžící na AWS. Využili tzv. **MERN stack** (MongoDB, Express, React, Node.js), který vývojářům umožnil pracovat s jednotnou metodologií napříč celou aplikací. Mezi klíčové nasazené funkce patří:

- **Atlas Search**: Pro bleskové vyhledávání v archivech i živých přenosech.
- **Online Archive**: Funkce, která automaticky odsouvá starší data (starší než 2 roky) do   levnějšího úložiště, čímž udržuje hlavní databázi rychlou a efektivní.
- **Atlas Device SDK**: Pro synchronizaci uživatelských profilů a preferencí napříč     zařízeními v reálném čase.

## Výsledky a přínosy

Díky reorganizaci autorizační databáze a využití indexů se **výkon zvýšil o 100%**. Nasazení Online Archive vedlo k **40% úspoře nákladů na úložiště**. Platforma nyní bez problémů zvládá obrovské špičky návštěvnosti bez nutnosti manuálního škálování. Vývojový tým se díky plně spravované službě (managed service) mohl přestat starat o údržbu serverů a plně se soustředit na inovace, jako je personalizovaný doporučovací systém pro fanoušky.