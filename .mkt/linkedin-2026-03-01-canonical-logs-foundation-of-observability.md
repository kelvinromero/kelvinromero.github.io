Você já abriu os logs de produção e encontrou 47 linhas espalhadas por 6 arquivos pra uma única requisição? Sem user ID, sem contexto, metade dizendo "processing request".

Eu passei por isso várias vezes. Então resolvi escrever sobre uma abordagem que mudou como eu penso sobre logging: canonical log lines — um único evento estruturado por requisição, emitido no final do ciclo, com tudo que você precisa pra debugar.

Não é ideia minha — a Stripe popularizou isso. Mas implementar em Go com slog, definir responsabilidades por camada, e entender onde NÃO logar, foi onde a coisa ficou interessante.

Escrevi sobre isso aqui: https://kelvinromero.github.io/2026/03/01/canonical-logs-foundation-of-observability/

---

Ever opened production logs and found 47 scattered lines across 6 files for a single request? No user ID, no context, half of them saying "processing request".

I've been there more times than I'd like to admit. So I wrote about canonical log lines — one structured event per request, emitted at the end of the lifecycle, containing everything you need to debug.

The idea comes from Stripe. But implementing it in Go with slog, defining layer responsibilities, and figuring out where NOT to log — that's where it got interesting.

Full article: https://kelvinromero.github.io/2026/03/01/canonical-logs-foundation-of-observability/

#observability #logging #softwarearchitecture #golang #softwareengineering
