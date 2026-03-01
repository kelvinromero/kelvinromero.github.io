E se você pudesse ter latência por endpoint, taxa de erro por rota, e throughput em dashboards do Grafana — sem instrumentar uma única métrica no código?

Tenho experimentado derivar métricas de engenharia diretamente dos canonical logs usando LogQL e Loki. Não como substituto do Prometheus, mas como algo que você pode ter hoje, com o que já existe.

O artigo mostra as queries, a configuração dos painéis, e as regras de alerta. Incluindo onde essa abordagem NÃO funciona bem.

Artigo: https://kelvinromero.github.io/2026/02/15/log-based-engineering-metrics-grafana/

---

What if you could have per-endpoint latency, error rates by route, and throughput dashboards in Grafana — without instrumenting a single metric in code?

I've been experimenting with deriving engineering metrics directly from canonical logs using LogQL and Loki. Not as a Prometheus replacement, but as something you can have today, with what's already in place.

The article covers the queries, panel configs, and alert rules. Including where this approach falls short.

Full article: https://kelvinromero.github.io/2026/02/15/log-based-engineering-metrics-grafana/

#observability #grafana #loki #logql #metrics #softwareengineering
