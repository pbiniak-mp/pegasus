# Salesforce CI/CD

## Przepływ zmian

1. Pull request do `uat` uruchamia `.github/workflows/validate-uat.yml`.
2. Workflow sprawdza formatowanie i lint tylko dla zmienionych plików, buduje delta package względem SHA bazowego PR-a i wykonuje dry-run na UAT.
3. Merge do `uat` uruchamia `.github/workflows/deploy-uat.yml` i wdraża dokładnie różnicę wprowadzoną przez merge/push.
4. Pull request do `master` uruchamia analogiczną walidację na Production.
5. Merge do `master` uruchamia właściwy deployment na Production.

Wszystkie cztery workflowy korzystają z Metadata API `67.0`. Wersje Salesforce CLI i `sfdx-git-delta` są przypięte, aby aktualizacja zależności nie zmieniała zachowania procesu bez zmiany w repozytorium.

`sourceApiVersion` projektu również wynosi `67.0`. Wersje zapisane w metadanych poszczególnych klas, triggerów, flow i komponentów nie są podnoszone automatycznie: wpływają na semantykę ich wykonania i powinny być migrowane osobno, z testami regresji danego komponentu. Nie blokuje to wysyłania i odbierania metadanych przez API 67.

## Serializacja deploymentów

Walidacja i deployment kierowane do tego samego orga mają wspólną grupę `concurrency`. UAT i Production mają osobne kolejki. GitHub uruchamia maksymalnie jedną operację Metadata API dla danego orga, a pozostałe czekają w kolejności zamiast wykonywać się równolegle lub zastępować poprzednie oczekujące uruchomienie.

Nie jest to ręczna akceptacja deploymentu. To zabezpieczenie przed konfliktami i niestabilnymi wynikami, gdy dwie walidacje lub deploymenty próbują jednocześnie zmieniać ten sam org.

## Ochrona gałęzi i status checks

Repozytorium ma aktywne rulesety `UAT Protection` i `PROD Protection`. Wymuszają one zmianę przez pull request, blokują usuwanie i force-push oraz nie mają wyjątku pozwalającego właścicielowi ominąć reguły. Liczba wymaganych approvali wynosi 0, dlatego pojedynczy maintainer może sam scalić PR.

Przed scaleniem GitHub wymaga zakończonego sukcesem checka:

- `Validation on UAT` dla `uat`;
- `Validation on PROD` dla `master`.

Środowiska GitHub `UAT` i `Production` przechowują sekrety używane przez Actions, ale nie odpowiadają za zakaz bezpośredniego pushowania. Ten zakaz realizują rulesety gałęzi.

## Wybór testów Apex

`config/unitTestMap.json` jest wersjonowaną mapą komponent -> minimalny zestaw klas testowych. Nie jest generowany przy każdym PR ani deploymentcie. Workflow odczytuje mapę i:

- dla zmienionej klasy lub triggera z bezpiecznym mapowaniem używa `RunSpecifiedTests`;
- zmienioną klasę `@IsTest` dodaje bezpośrednio do zestawu testów;
- przy braku mapowania, pokryciu komponentu poniżej 75%, usunięciu/zmianie nazwy Apex albo nieprawidłowym wpisie przełącza się na `RunLocalTests`;
- dla zmian wyłącznie w metadanych również zachowuje `RunLocalTests`.

Fallback oznacza, że nieaktualna mapa może jedynie spowolnić walidację. Nie powinna obniżyć poziomu bezpieczeństwa.

### Dlaczego nie `RunRelevantTests`

`RunRelevantTests` pozostaje funkcją Beta, w której Salesforce sam ustala zależności na podstawie payloadu. Dotychczasowe walidacje UAT w tym repozytorium kończyły się sukcesem z zerową liczbą uruchomionych testów także wtedy, gdy delta zawierała Apex. Dlatego workflow używa jawnej, audytowalnej mapy i zachowawczego fallbacku. `RunRelevantTests` można ponownie ocenić po ustabilizowaniu funkcji i porównaniu wyników na kilku rzeczywistych deltach.

## Odświeżenie mapy

Odświeżenie mapy nie jest wymagane do poprawnego wdrożenia nowej klasy. Nowa klasa bez wpisu automatycznie uruchomi `RunLocalTests` i pozostanie na tej bezpiecznej, wolniejszej ścieżce aż do kolejnego odświeżenia. Mapę warto odświeżać zbiorczo po wdrożeniu nowych klas i testów, po większej zmianie zależności/pokrycia albo okresowo, jeśli chcemy przyspieszyć ich późniejsze zmiany.

Polecenie najpierw uruchamia pełne `RunLocalTests`; plik jest nadpisywany tylko wtedy, gdy cały zestaw przejdzie:

```bash
npm run test-map:refresh -- UAT-pegasus
```

Po odświeżeniu należy przejrzeć i commitować zmianę `config/unitTestMap.json` razem z kodem. Skrypt niskiego poziomu `.github/scripts/generate-unit-test-map.js` tylko odczytuje istniejące rekordy `ApexCodeCoverage`; normalnie należy używać powyższego polecenia, żeby mapa nie powstała ze starych lub częściowych danych.

## Kontrole jakości

Walidacje PR wykonują Prettier dla zmienionych plików YAML, JavaScript, JSON, CSS i HTML oraz ESLint dla zmienionego JavaScriptu Aura/LWC. Apex i XML nie są automatycznie przeformatowywane, żeby podstawowa kontrola jakości nie powodowała dużych zmian stylu w istniejących plikach. Kontrola jest ograniczona do diffu, ponieważ repozytorium ma istniejący dług formatowania i lintowania niezwiązany z nowymi PR-ami.
