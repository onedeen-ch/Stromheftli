# Stromheftli

Private Offline-App für Android. Die Auswertung verwendet Europe/Zurich. Daten und PDFs bleiben im App-Speicher.

## APK aufs Handy

Unter **Actions → Android APK** einen erfolgreichen Lauf öffnen. Unter **Artifacts** das ZIP **Stromheftli-APK** herunterladen (bei GitHub anmelden), entpacken und **Stromheftli.apk** auf dem Android-Handy öffnen. Falls Android fragt, die Installation für die verwendete Dateien-App zulassen. Der Workflow läuft bei Push auf main und kann mit Run workflow gestartet werden. Die Debug-Signatur kann zwischen CI-Läufen wechseln. Eine Deinstallation löscht die lokalen Daten.

## Erste Messwerte

**Übersicht → Lastgang importieren**. Eine XLSX mit den Spalten Datum, Zeit, Wirkleistung [kW] auswählen. Intervallende oder -beginn kontrollieren und die Vorschau bestätigen. Excel-Zeitwerte, numerische Datumszellen und Text im Format TT.MM.JJJJ / HH:mm:ss werden gelesen. Negative Leistungen sind für diesen Bezugsimport ungültig. Gültige Zeilen können nach Prüfung der Fehlerliste übernommen werden. Bei erkennbar doppeldeutigen Herbstzeiten die vorgeschlagene Zuordnung prüfen.

Unter Verbrauch zwischen Tag, Woche und Monat wechseln. Auf einen Balken tippen für Details. Die Tagesgrafik ist horizontal scrollbar. Tarifzeiten werden in Viertelstunden und mit einem Gültigkeitsbeginn erfasst. Vor der ersten eigenen Regel gilt der Standard Mo–Fr 07:00–19:00. Im PDF-Archiv Dateien importieren oder im Android-Teilen-Dialog Stromheftli auswählen.

## Entwicklung

Flutter 3.32.8, JDK 17, Android SDK. Im Repository `bash tool/android.sh` ausführen, um das native Android-Gerüst aus dem gepinnten SDK zu ergänzen. Anschliessend `flutter pub get`, `flutter analyze`, `flutter test` und `flutter build apk --debug`. Das Gerüst verwendet die App-ID ch.stromheftli.app. Echte Messdaten und Rechnungen gehören nicht ins Repository.

## Monatsimport prüfen

XLSX und CSV verwenden dieselbe Zeit- und Tarifberechnung. CSV unterstützt Semikolon, Tabulator oder Komma und Dezimalpunkt bzw. Dezimalkomma. Der Spaltentitel bestimmt die Einheit: Wirkleistung [kW] ist ein Viertelstundenmittel, Energie [kWh] die Energie des Intervalls. Ein optionaler Kontrollwert in kWh muss auf drei Nachkommastellen zur Dateisumme passen, bevor gespeichert wird. Die Vorschau zeigt die komplette Datei mit HT/NT. Bei mehreren Tagen öffnet die App nach dem Speichern den letzten importierten Kalendermonat. Bei einem weiteren Import ersetzen bestätigte Korrekturen dieselben Viertelstunden.
