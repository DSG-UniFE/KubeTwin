# ragbench in KubeTwin: stato del lavoro (14 novembre 2026)

Documento di passaggio per riprendere il lavoro da un altro computer o con
un'altra sessione di Claude Code. Le memorie di Claude e la cronologia
completa delle sessioni sono nel repo privato `fpoltronieri/claude-memory-kubetwin`.

## Repository e branch

| repo | branch | stato |
|---|---|---|
| KubeTwin (`DSG-UniFE/KubeTwin`) | `ragbench` | pushato. Parte dal vecchio master locale (2c2b3a668), **non** da `origin/master` |
| ragbench (`fpoltronieri/ragbench`, privato) | `main` | pushato (ultimo commit 6fcc7d7) |
| tracesim (`fpoltronieri/tracesim`, privato) | | risultati Bologna non ancora salvati lì |
| OPTIMUUM-estensioni | `trace-driven-sim` | `ragbench_bologna/train_ragbench_mdn.py` **non committato** (il branch ha modifiche locali non tue) |

Regole: nessun `Co-Authored-By` né attribuzione a Claude nei commit di
KubeTwin e ragbench. Non toccare `master` di KubeTwin.

`origin/master` di KubeTwin ha circa 25 commit di refactoring (Zeitwerk,
`RequestForwarder`, `WorkflowSequence`, linting) che il branch `ragbench`
non ha. Per portare le correzioni nel main conviene applicarle una alla
volta sul nuovo master, perché `ksimulation.rb` darà molti conflitti.

## Correzioni presenti sul branch `ragbench`

- `MDN#elu` corretta, campionamento MDN in scala logaritmica (`MDNSampler`), modello a due stadi (hurdle) per TeaStore.
- Nessun doppio rilascio del container dopo chiamate annidate (41c63cda4, ora riscritto).
- Topologia Bookinfo di nuovo **sequenziale** (`calls:`); la versione parallela era sbagliata. MDN: errore medio 6.85%, p99 9.84%.
- Latenze di federazione configurabili (`intra_cluster_latency`, `inter_cluster_jitter_sd`, `min_latency`); il valore della federazione è l'RTT.
- Terzo obiettivo dell'ottimizzatore: repliche totali (`bin/optimizer_optimuum`).
- Seeding: `seeds random_choices:` / `random_seed:` fissano la scelta del pod e il campionamento MDN. Opzioni `--generations`, `--population`, `--runs`, `--seed`.

## Configurazioni ragbench in `examples/`

- `ragbench_bologna.conf`: un cluster, gaussiane stimate dalla campagna di Bologna (`--request-fraction 0.5`, nodo da 8 core).
- `ragbench_bologna_mdn.conf`: come sopra ma con MDN (`mdn_models/ragbench_bologna_*_weights.json`); è la più accurata. Risultati in `results/ragbench/kubetwin_bologna_{gaussian,mdn}.md`.
- `ragbench_3c.conf`: 3 cluster federati (cluster1 + cluster2edge a 30 ms RTT + cluster3edge a 50 ms RTT; traffico edge↔edge via cluster1). 7 core per cluster, 500m di request per pod, MDN, guardrail non modellato. `RAGBENCH_RPS` (default 4), `RAGBENCH_SEED`.

Per eseguire KubeTwin fuori dalla root del repo:
`RBENV_VERSION=3.3.9 BUNDLE_GEMFILE=~/code/KubeTwin/Gemfile bundle exec ruby -I ~/code/KubeTwin/lib ...`,
da una cartella con il symlink `mdn_models`. Ogni valutazione scrive
`final_allocation.json`/`.txt` nella cartella corrente.

## Ottimizzazione a 3 cluster (`opt3c_rps4/`)

```
RAGBENCH_RPS=4 ruby bin/optimizer_optimuum examples/ragbench_3c.conf --generations 30 --population 60
```

Ci vogliono circa 8 minuti. Il fronte ha 60 soluzioni (46 distinte). La ricerca di NSGA-II **non è
riproducibile**: la libreria `mhl` crea la popolazione iniziale con
`SecureRandom`. Il seed fissa solo la valutazione.

`reeval/reeval.rb` rivaluta ogni soluzione con 10 seed (1000–1009) diversi
da quello dell'ottimizzazione. Risultati in `reeval/reeval_10seeds.csv` e
`pareto_front_rps4_reeval.csv`. Il grafico del fronte è un artifact privato su claude.ai,
intitolato "ragbench 3-cluster Pareto front".

### Le 5 candidate per Bologna (`allocations_bologna_rps4.json`)

Allocazione per servizio scritta come cluster1/cluster2edge/cluster3edge.

| | sol. | TTR (10 seed) | Gini | repl. | gateway | embedder | vector-search | reranker | llm-generate |
|---|---|---|---|---|---|---|---|---|---|
| A, la più veloce | 39 | 535 ± 6 ms | 0.77 | 18 | 5/1/0 | 3/0/0 | 2/1/0 | 2/1/0 | 2/1/0 |
| B, 17 repliche | 46 | 573 ± 8 | 0.70 | 17 | 3/2/0 | 3/0/0 | 2/1/0 | 2/1/0 | 2/1/0 |
| C, a metà | 8 | 648 ± 8 | 0.23 | 18 | 3/3/0 | 1/2/0 | 1/1/1 | 1/1/1 | 1/1/1 |
| D, spreading perfetto | 48 | 730 ± 13 | 0.00 | 18 | 2/2/1 | 1/1/1 | 2/1/1 | 1/1/1 | 1/1/1 |
| E, quasi tutto su cluster1 | 1 | 628 ± 18 | 0.93 | 15 | 3/0/0 | 3/0/0 | 2/1/0 | 3/0/0 | 3/0/0 |

A, C e D hanno lo stesso numero di repliche e isolano l'effetto dello
spreading. A ed E richiedono 7.5 core di request su cluster1 (guardrail
compreso).

### Come le lancia Bologna (ragbench, tracce dai log)

Il file e le istruzioni complete per Bologna sono nel repo ragbench (commit
0d67ed7): `allocations/kubetwin_3c_4rps.json` e la sezione del README
"Multi-cluster runs: optimizer allocations" (setup Liqo, controlli,
run). In sintesi:

```
cp clusters.example.json clusters.json      # cluster-id Liqo veri
python -m ragbench.calibrate                # + --cluster cluster2edge/3edge --out ...
export RAGBENCH_TARGET=http://<nodo cluster1>:30090/api/v1
python -m ragbench.run vector_remote 1,2 --request-fraction 0.5
for s in 39 46 8 48 1; do
  python -m ragbench.run solution_$s 4 --allocation kubetwin_3c_4rps.json --request-fraction 0.5
done
```

Da controllare a Bologna:
- namespace `ragbench` offloaded verso entrambi gli edge;
- `kubectl logs` ed `exec` funzionanti sui pod remoti da cluster1 (se `exec` fallisce, `cpu_stat` resta vuoto senza fermare la run);
- NTP su tutti i nodi e sulla macchina di k6.

Prova consigliata prima della campagna: la candidata C per 60 s (`--duration 60`).
OpenTelemetry e YAML scritti a mano sono stati scartati: si tengono ragbench e i log.

## Punti aperti

1. **Parametri da confermare con Bologna**: core per cluster, RTT tra cluster, ingresso del carico da cluster1. Se cambiano, si aggiorna `ragbench_3c.conf` e si rilancia l'ottimizzazione con la rivalutazione.
2. **Minimo di repliche per servizio**: oggi è `n_clusters` = 3 (scelta di Mattia, c71bcaa5c). Se torna a 1, il Gini va portato alla definizione di tracesim (G/Gmax).
3. **Seeding da migliorare** (non ancora fatto):
   - le latenze di federazione usano `seeds[:communication_latencies]` e non `random_seed`;
   - latenza intra-cluster e rumore inter-cluster partono dallo stesso seed;
   - scelta del pod e tempi MDN condividono il `rand` globale, quindi i numeri casuali comuni tra allocazioni si disallineano. Servono generatori separati.
4. `--request-fraction 0.5`: nei dati di Bologna il throttling è sotto l'1% dei periodi e l'uso medio di CPU arriva al massimo a 2.5 core su 8, quindi le misure non sono alterate. KubeTwin modella solo il vincolo di scheduling (500m), non la contesa di CPU sullo stesso nodo.
5. tracesim: salvare i risultati di Bologna nel suo repo e rendere `NODE_CORES` un parametro (ora è fisso a 28).
6. Discrepanza da indagare: gateway_2 a 3–4 RPS (tracesim sovrastima le attese al gateway). In KubeTwin, gateway_3 a 5 RPS esce circa il 12% troppo basso.
