# Škálování pro FIFA World Cup v Latinské Americe

## Kontext a výzvy

Mediastream je přední „mediatech“ firma v Latinské Americe, která zajišťuje technologické zázemí pro více než 150 společností. Jejich platforma obslouží 150 milionů přehrání videí denně a spravuje přihlašovací údaje pro 30 milionů uživatelů. Největší výzvou byl **přechod na globální sportovní akce**, jako je Mistrovství světa ve fotbale (FIFA World Cup). Bylo nutné zajistit, aby platforma zvládla nárůst návštěvnosti z běžných statisíců na miliony souběžně sledujících diváků, a to při zachování bleskového přístupu k metadatům (názvy videí, náhledy, popisy).

## Řešení s MongoDB Atlas

Společnost migrovala na MongoDB Atlas již v roce 2018. Hlavním důvodem byla **multi-cloudová agilita** a schopnost automatického škálování. Před velkými turnaji tým provádí rozsáhlé zátěžové testy na MongoDB, které simulují extrémní nápor požadavků. Architektura využívá schopnost Atlasu přidávat uzly do clusteru bez přerušení provozu, což Mediastreamu umožňuje reagovat na neočekávané zprávy nebo důležité zápasy, které vyvolávají desetinásobné špičky oproti běžnému provozu.

## Výsledky a přínosy

Platforma nyní dosahuje dostupnosti **99,995%** a dokáže zpracovat přes **10 milionů požadavků za minutu**. Schopnost obsloužit milion souběžných diváků v reálném čase zajistila hladký průběh vysílání Mistrovství světa v zemích jako Chile, Mexiko nebo Kolumbie. MongoDB také výrazně zrychlilo práci vývojářů, kteří mohou snadněji upravovat datové modely pro nové segmenty trhu, jako je e-commerce a online vzdělávání, kam Mediastream expanduje.