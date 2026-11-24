# ragbench multi-cluster a Bologna: prima campagna (23 novembre 2026)

Dati di Elisa: `ragbench_multicluster.zip`, estratto in
`~/code/ragbench/data_bologna_mc_20261123/ragbench_multicluster/data` (non
committato). Liqo su k3s, cluster1 + cluster2edge + cluster3edge, allocazioni
`allocations/kubetwin_3c_4rps.json`, `--request-fraction 0.5`, 4 RPS, 300 s.
k6 lanciato dal portatile di Elisa (WSL). Elisa ha modificato lo script per
aggirare `kubectl exec` su k3s+Liqo; i contatori CPU sono comunque presenti.
Tabella completa: `comparison.csv`.

## Esito delle run

| scenario | esito |
|---|---|
| vector_remote 1, 2 RPS | ok: 0 errori, 100% tracce |
| solution_46 (B) | ok: 0 errori, 100% tracce |
| solution_8 (C) | ok: 0 errori, 100% tracce |
| solution_48 (D) | 326 errori su 1201 (27%) |
| solution_39 (A), solution_1 (E) | non partite: `llm-generate-cluster1` non va Ready |

- **39 e 1** sono le due candidate con 15 pod su cluster1 (7.5 core di request
  con il guardrail). `llm-generate` è l'ultimo Deployment applicato e resta
  Pending: su cluster1 i core liberi sono tra 6.5 (46 ci sta) e 7.5. Manca
  l'output di `kubectl describe node` per conferma.
- **48**: tutti gli errori hanno status 0 e latenza 0 (k6 non apre o perde la
  connessione), sparsi per tutta la run. Non raggiungono nessun gateway: i 5
  gateway hanno la stessa CPU per richiesta e la CPU totale dei gateway è il
  73% di quella della 8, pari alla quota di richieste riuscite. 48 è l'unica
  candidata con un gateway su cluster3edge. Da indagare con `--keep-k6-csv`
  (colonne `error`, `error_code`) e `kubectl get endpoints gateway`.
- Throttling trascurabile (al massimo 20 periodi su circa 1400, su llm-generate).

## Confronto con KubeTwin (mean, ms)

| | KubeTwin (10 seed) | client k6 | Δ vs client | tracce (span radice) | Δ vs tracce | client − tracce | ρ per gateway |
|---|---|---|---|---|---|---|---|
| 46 | 573 ± 8 | 696 | −17.7% | 537 | +6.8% | 159 | 0.43 |
| 8 | 648 ± 8 | 888 | −27.0% | 668 | −3.0% | 220 | 0.45 |
| 48 | 730 ± 13 | 1040 | −29.8% | 714 | +2.2% | 326 | 0.57 |

**Il confronto giusto è con il client, non con le tracce.** Ogni pod gateway
ha un solo worker sincrono (`WORKERS = 1`) occupato per tutta la richiesta,
chiamate a valle comprese. Le richieste in coda aspettano nel backlog del
socket **prima** che lo span radice cominci, quindi le tracce non vedono
l'attesa al gateway. KubeTwin invece la modella (il container resta occupato
durante le chiamate annidate), e su un cluster è stato validato contro la
latenza del client (`kubetwin_bologna_mdn.md`). L'accordo con le tracce è
quindi in parte una coincidenza: il totale di KubeTwin, attesa compresa, si
avvicina a un valore misurato che l'attesa non la contiene.

Prove che la differenza client − tracce è l'attesa al gateway:
- vector_remote (un gateway, su cluster1): differenza ~30 ms, cioè il percorso
  da k6 sul portatile al gateway più la gestione della richiesta fuori dallo
  span. Con arrivi costanti e un solo gateway non si forma coda (D/D/1: 475 ms
  di servizio ogni 500 ms).
- Campagna su un cluster (k6 vicino al nodo): baseline 2 ms; con più gateway e
  bilanciamento casuale la differenza cresce con l'utilizzo per gateway, per
  esempio gateway_3 a 2/3/4/5 RPS dà 2/53/171/632 ms e gateway_4_llm_2 a
  3/4/5/6 RPS dà 31/100/200/429 ms.
- Nelle run multi-cluster la differenza cresce con ρ per gateway (0.43, 0.45,
  0.57) e la distribuzione ha una coda lunga (mediana molto sotto la media).

Con `ragbench_3c.conf` KubeTwin sottostima la latenza del client del 18–30%
sulla media (39–48% al p99), di più per le allocazioni più distribuite.

## Causa: ogni chiamata tra cluster costa due RTT

Dalle tracce, per ogni chiamata, durata dello span client meno durata dello
span server del figlio (mediana):

| collegamento | RTT iniettato | modello (`ragbench_3c.conf`) | misurato per chiamata |
|---|---|---|---|
| stesso cluster | | 2 × 2.17 ms | 3.5–5 ms |
| cluster1 ↔ cluster2edge | 30 ms | 30 ms | 66 ms |
| cluster1 ↔ cluster3edge | 50 ms | 50 ms | 104 ms |
| cluster2edge ↔ cluster3edge | via cluster1 | 80 ms | 165 ms |

Le distribuzioni sono a picchi netti (~4, ~66, ~104, ~165 ms), quindi i
ritardi configurati a Bologna sono quelli previsti. Il costo è 2 × RTT più
~5 ms perché le celle muBench girano con worker sync di gunicorn, che non
tengono viva la connessione: ogni chiamata apre una connessione TCP nuova (un
RTT per il handshake, uno per richiesta e risposta), anche se il client usa una
`requests.Session`. KubeTwin contava un solo RTT per chiamata. Dentro il
cluster il valore del modello (per tratta) era già giusto.

`examples/ragbench_3c_measured.conf` usa il costo misurato per chiamata
(66 e 104 ms; edge↔edge via cluster1 = 170 ms); tutto il resto è invariato.
La configurazione di rete del testbed non cambia: cambia il parametro di
KubeTwin, che ora rappresenta il costo effettivo di una chiamata
dell'applicazione e non l'RTT fisico.

## Confronto con le latenze misurate (client k6, 10 seed)

`kubetwin_measured_latencies_10seeds.csv`; generato con
`opt3c_rps4/reeval/kt_percentiles.rb examples/ragbench_3c_measured.conf`.

| | | media | p50 | p90 | p95 | p99 |
|---|---|---|---|---|---|---|
| 46 (B) | reale | 696 | 621 | 997 | 1152 | 1925 |
| | KubeTwin | 706 ± 18 | 629 | 1060 | 1255 | 1737 |
| | Δ | **+1.4%** | +1.4% | +6.3% | +9.0% | −9.8% |
| 8 (C) | reale | 888 | 770 | 1307 | 1533 | 2570 |
| | KubeTwin | 914 ± 28 | 789 | 1407 | 1682 | 2340 |
| | Δ | **+3.0%** | +2.4% | +7.7% | +9.7% | −9.0% |
| 48 (D) | reale | 1040 | 888 | 1610 | 1980 | 3062 |
| | KubeTwin | 1161 ± 30 | 959 | 1955 | 2396 | 3414 |
| | Δ | +11.6% | +8.0% | +21.5% | +21.0% | +11.5% |

B e C tornano all'accuratezza della campagna su un cluster. La D è
sovrastimata perché il 27% delle richieste è fallito prima dei gateway: i
gateway reali hanno servito ~2.9 RPS, KubeTwin ne simula 4. Va ripetuta senza
errori prima di giudicarla. Il p99 viene da una run di 300 s per candidata.

**Attenzione**: le latenze sono stimate dalle stesse run su cui si valuta. Per
il paper vanno misurate in modo indipendente (ping tra i cluster e una chiamata
da un pod di cluster1 a un servizio su ogni edge).

## Conseguenze e prossimi passi

1. Il fronte di `opt3c_rps4` e le 5 candidate sono calcolati con RTT dimezzati:
   rilanciare ottimizzazione e rivalutazione con `ragbench_3c_measured.conf`
   (con RTT doppi lo spreading costa di più) e con i core davvero liberi su
   cluster1 (39 e 1 non ci stavano).
2. Da Bologna: ping tra i cluster, `kubectl describe node` di cluster1, una run
   della 48 senza errori (`--keep-k6-csv` per gli errori), k6 vicino a cluster1.
3. Nel modello, meglio separare RTT fisico e numero di RTT per chiamata
   (parametro di KubeTwin) invece di usare un valore effettivo.

Analisi con figure (entrambi i modelli, più il costo per chiamata): repo ragbench,
`results/multicluster_20261123/`.
