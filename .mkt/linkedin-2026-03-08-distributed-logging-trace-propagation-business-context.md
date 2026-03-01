Canonical logs resolvem o problema dentro de um serviço. Mas quando uma ação do usuário vira 5 chamadas HTTP e 3 mensagens Kafka, como você reconstrói o que aconteceu?

Tenho explorado como propagar trace_id entre serviços (HTTP e Kafka) e enriquecer cada log com dimensões de negócio: bounded_context, feature, e session_feature_id — que é a sequência de requisições que o usuário faz pra completar uma jornada.

Com isso, uma query LogQL reconstrói o fluxo inteiro de um checkout distribuído. Sem precisar de um sistema de tracing completo.

Artigo completo: https://kelvinromero.github.io/2026/03/08/distributed-logging-trace-propagation-business-context/

---

Canonical logs solve the single-service problem. But when a user action fans out across 5 HTTP calls and 3 Kafka messages, how do you reconstruct what happened?

I've been exploring how to propagate trace_id across services (HTTP and Kafka) and enrich every log with business dimensions: bounded_context, feature, and session_feature_id — the sequence of requests a user makes to complete a journey.

With that in place, a single LogQL query reconstructs an entire distributed checkout flow. No full tracing system required.

Full article: https://kelvinromero.github.io/2026/03/08/distributed-logging-trace-propagation-business-context/

#observability #distributedsystems #logging #golang #softwareengineering
