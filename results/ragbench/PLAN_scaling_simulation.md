# Piano: confronto tra strategie in sola simulazione (scenari grandi)

Riferimento nel paper: `Sections/results.tex`, § "At scale, in simulation"
(`sec:comparison_simulation`, branch `draft-new-sections`). Prerequisito: la
soglia d'errore di KubeTwin fissata sul testbed (§ "On the testbed").

Tre punti da chiudere prima di fissare gli scenari. Per ognuno: cosa sappiamo
già (verificato), cosa fare, criterio per dire che è chiuso.

## 1. Tempo di calcolo dell'ottimizzazione

**Verificato:**
- 3 cluster, 5 servizi, 4 RPS, 340 s simulati: 30 generazioni × 60 individui
  = 1800 valutazioni in circa 8 minuti, cioè ~0.27 s per valutazione
  (`opt3c_rps4`, HANDOFF).
- Una valutazione = una simulazione (`bin/optimizer_optimuum`, `runs: 1`).
- Cromosoma: `n_ms` geni per il numero di repliche (da `n_clusters` a
  `MAX_REPLICAS` = 10) più `n_ms × 10` geni per il cluster di ogni replica
  (`koptimizer_multiobjective.rb:106-107`). Con 50 servizi sono 550 geni.

**Da fare:**
1. Misurare il costo di una valutazione al variare di una dimensione alla
   volta: servizi (5, 10, 20, 50), cluster (3, 5, 10, 20), RPS (4, 8, 16).
   Bastano 20 valutazioni casuali per punto. Il costo dovrebbe crescere con
   il numero di eventi, cioè richieste × chiamate per richiesta.
2. Ridurre la durata simulata: verificare se 120 s invece di 340 s danno le
   stesse statistiche (media entro 1–2%) sulle 5 candidate attuali.
3. Stimare generazioni e popolazione necessarie per convergere: hypervolume
   in funzione della generazione su un caso medio (10 cluster, 20 servizi).
4. Se serve: valutazioni in parallelo (le simulazioni sono indipendenti; la
   libreria mhl va controllata).

**Chiuso quando:** per ogni scenario del paper c'è una stima del tempo
totale, e il più grande sta sotto un limite deciso (per esempio 12 ore).

## 2. Topologia di rete

**Verificato** (`lib/kube_twin/latency_manager.rb`):
- La latenza tra due cluster è quella della coppia elencata in
  `federation.latencies`, più un rumore gaussiano unico (`inter_cluster_jitter_sd`).
- Una coppia non elencata viene instradata via il cluster 0 (somma delle due
  latenze verso il cluster 0). È il modello di Liqo a stella usato finora.
- Se manca una latenza verso il cluster 0, il codice usa la latenza **interna**
  al cluster senza segnalarlo (`if loc1 == 0 || loc2 == 0`). Con molti cluster
  è facile dimenticarne una: meglio che sollevi un errore.
- Il valore va inteso come costo di una chiamata (2 RTT + ~5 ms con i worker
  sync di muBench; vedi `bologna_mc_20261123/README.md`).

**Da fare:**
1. Scegliere la topologia degli scenari grandi: stella (un cluster centrale e
   N edge, come Liqo) oppure matrice completa (cluster regionali). Proposta:
   stella per 5 e 10 cluster, matrice completa per 20.
2. Generare i valori da RTT plausibili (per esempio 5–20 ms tra cluster
   regionali, 30–80 ms verso gli edge), convertiti in costo per chiamata con
   la stessa regola misurata (2 RTT + 5 ms). Meglio ancora aggiungere a
   KubeTwin un parametro "RTT per chiamata" (vedi punto 5 del README dei
   risultati) così la conf contiene l'RTT fisico.
3. Correggere il fallback silenzioso del punto sopra (errore se manca una
   coppia) e aggiungere un test.
4. Jitter: oggi è un solo valore per tutti i collegamenti; valutare un jitter
   proporzionale alla latenza.

**Chiuso quando:** c'è un generatore di conf (cluster, core, matrice di
latenze) e la conf a 3 cluster attuale si ottiene come caso particolare.

## 3. Tempi di servizio per applicazioni diverse da ragbench

**Verificato:**
- Le MDN sono addestrate sui 5 servizi di ragbench (baseline 1 RPS della
  campagna su un cluster) e condizionate a RPS costante (`rps: 1`,
  `use_configured_rps: true`).
- muBench ha un generatore di grafi di servizi
  (`~/code/muBench/ServiceGraphGenerator`) e un generatore di workmodel.

**Da fare:**
1. Applicazioni grandi come composizione di ragbench: più istanze (o varianti
   con servizi duplicati) che riusano le MDN esistenti. È l'opzione più solida,
   perché ogni tempo di servizio resta validato.
2. Topologie sintetiche (20–50 servizi) da `ServiceGraphGenerator`: assegnare
   a ogni servizio una delle 5 MDN di ragbench come "classe" in base alla CPU
   richiesta (50, 60, 80, 150 ms), oppure una lognormale con media e varianza
   prese dalla classe più vicina.
3. Dichiarare nel paper che per le topologie sintetiche il tempo di servizio
   è estrapolato (minacce alla validità, già in bozza).
4. Facoltativo: una run sul testbed di una topologia sintetica piccola
   (10 servizi) per controllare che la regola di assegnazione delle classi
   regga.

**Chiuso quando:** per ogni scenario del paper è scritto da dove vengono i
tempi di servizio, e almeno uno scenario grande usa solo MDN validate.

## Ordine proposto

1. Punto 2.3 (fallback silenzioso) e parametro RTT per chiamata: piccoli, e
   servono anche per rifare l'ottimizzazione a 3 cluster con la conf misurata.
2. Punto 1.1–1.2 (misure di costo): decidono la dimensione massima.
3. Punti 2.1–2.2 e 3.1–3.2: generatore di scenari.
4. Strategie di confronto come regole in KubeTwin (Default, Spread,
   Co-location, casuale, solo TTR) e campagna di simulazione.
