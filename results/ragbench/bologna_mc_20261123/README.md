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
- vector_remote (un gateway, su cluster1): differenza ~30 ms. È la rete tra il
  portatile e cluster1. Con arrivi costanti e un solo gateway non si forma coda
  (D/D/1: 475 ms di servizio ogni 500 ms).
- Campagna su un cluster (k6 vicino al nodo): baseline 2 ms; con più gateway e
  bilanciamento casuale la differenza cresce con l'utilizzo per gateway, per
  esempio gateway_3 a 2/3/4/5 RPS dà 2/53/171/632 ms e gateway_4_llm_2 a
  3/4/5/6 RPS dà 31/100/200/429 ms.
- Nelle run multi-cluster la differenza cresce con ρ per gateway (0.43, 0.45,
  0.57) e la distribuzione ha una coda lunga (mediana molto sotto la media).

KubeTwin sottostima la latenza del client del 18–30% sulla media (39–48% al
p99), di più per le allocazioni più distribuite. Nessuna correzione per il
percorso dal portatile: i ~30 ms di vector_remote sono un'osservazione, non una
misura separata. Analisi completa e figure: repo ragbench,
`results/multicluster_20261123/`. Ipotesi da verificare
scomponendo la simulazione (tempo nel gateway vs attesa in coda):
1. Il gateway su un edge resta occupato anche per gli RTT verso i servizi su
   cluster1 (e per edge↔edge via cluster1): il modello potrebbe contare quelle
   latenze nel TTR ma non nell'occupazione del gateway.
2. RTT o jitter reali più alti di quelli in `ragbench_3c.conf` (30/50 ms).
3. Il bilanciamento di Liqo/kube-proxy non è uniforme come `sample` di KubeTwin.
4. L'ingresso via NodePort di cluster1 verso un gateway edge aggiunge un RTT
   per richiesta, che il modello non conta.
