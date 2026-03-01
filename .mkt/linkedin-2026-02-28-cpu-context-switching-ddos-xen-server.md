Quase 10 anos atrás, durante a graduação no IFPB, investigamos algo que me intrigava: quando uma VM sofre um ataque DDoS
num servidor compartilhado, as vizinhas também degradam. Por quê?

Montamos um lab com Xen Server, rodamos 60 rodadas de experimento, e descobrimos que durante o ataque, a CPU converte
14% mais interrupções em trocas de contexto. Escrevemos um artigo sobre isso.

Esse ano decidi revisitar (esse e outros trabalhos ao longo da minha carreira em tecnologia) o artigo e adicionei uma
visualização interativa pra ilustrar o que acontece. O problema
do "noisy neighbor" continua relevante em qualquer infra compartilhada.

Talvez toda essa revolução da inteligência artificial tenha me deixado relembrando os bons e velhos tempos, quando eu era um jovem
pesquisador curioso. Se você se interessa por virtualização, segurança cibernética, ou sistemas em geral, acho que vai
gostar de ler o artigo e brincar com a simulação.

Paper e simulação interativa: https://kelvinromero.github.io/2026/02/28/cpu-context-switching-ddos-xen-server/

---

Nearly 10 years ago, during undergrad at IFPB, I investigated something that intrigued
me: when a VM suffers a DDoS attack on a shared server, its neighbors degrade too. Why?

We set up a Xen Server lab, ran 60 experiment rounds, and discovered that during the attack, the CPU converts 14% more
interrupts into context switches. We wrote a paper about it.

This year I decided to revisit the paper (along with other works throughout my career in technology) and added an
interactive visualization to illustrate what happens. The "noisy neighbor" problem remains relevant in any shared
infrastructure.

Maybe all this artificial intelligence revolution has me reminiscing about the good old days, when I was a young curious
researcher. If you're interested in virtualization, cybersecurity, or systems in general, I think you'll enjoy reading
the article and playing with the simulation.

Paper and interactive simulation: https://kelvinromero.github.io/2026/02/28/cpu-context-switching-ddos-xen-server/

#virtualization #cybersecurity #research #systems #softwareengineering
