---
layout: post
title: "SABER IFPB — Building a Research Competency Search Engine"
description: "How I built a full-text search platform for researchers, projects, and competencies at IFPB using Django, Elasticsearch, and Django REST Framework — and got it registered as intellectual property in Brazil."
date: 2018-12-03
tags: [elasticsearch, django, search, python]
---

During my internship at PRPIPG (the Research and Graduate Studies office) at IFPB — Instituto Federal de Educação, Ciência e Tecnologia da Paraíba — I worked on a project called **SABER IFPB**: a search engine for researchers, research groups, projects, competencies, bibliographic publications, and later patents and trademark registrations.

The tool was designed for PRPIPG managers to find researcher profiles based on their competencies. Need an expert in machine learning for a new grant proposal? Search by competency and find every researcher, their publications, and their active projects in seconds.

## The problem

IFPB is a large institution with hundreds of researchers across multiple campuses. Before SABER, finding who worked on what required personal knowledge, spreadsheets, or manual searches through the Lattes platform (Brazil's national researcher database). There was no centralized, searchable index of the institution's research capacity.

## The solution

We built a web application that aggregates researcher data from multiple sources and indexes it for fast full-text search. The core architecture:

- **Django** as the web framework, handling data models, admin interface, and server-side rendering
- **Elasticsearch** for indexing and searching hundreds of thousands of entries with sub-second response times
- **Django REST Framework** for API endpoints, enabling integration with other institutional systems (like SUAP)
- **jQuery** for the interactive search frontend

The search covers researchers, research groups, projects, competencies, publications, patents, and trademark registrations. Results are ranked by relevance and can be filtered by campus, department, or knowledge area.

## What I learned

This was my first experience building a system that needed to handle real-world data at scale. Key lessons:

1. **Full-text search is not SQL LIKE** — Elasticsearch's inverted index and BM25 scoring were transformative compared to naive database queries
2. **Data quality matters more than algorithms** — We spent more time cleaning and normalizing data from Lattes than building search features
3. **Search UX is its own discipline** — Autocomplete, faceted filtering, and result highlighting made the difference between a tool people used and one they ignored

## Intellectual property

In September 2020, SABER IFPB was officially registered as intellectual property with INPI (Brazil's National Institute of Industrial Property) under process **BR 51 2020 001729-0**.

> **Title:** Banco de Competências do IFPB - SABER IFPB
> **Holder:** Instituto Federal de Educação, Ciência e Tecnologia da Paraíba
> **Creators:** Carlos Danilo Miranda Regis, Fausto Véras Maranhão Ayres, Kelvin Romero Meira de Oliveira Cordeiro, Maxwell Anderson Ielpo do Amaral, Pedro Vinícius Silva de Paiva
> **Languages:** CSS, HTML, JavaScript, PostgreSQL, Python
> **Created:** September 20, 2018

The full INPI registration document is available below.

## The tool

SABER IFPB is still available and in use at IFPB: [suap.ifpb.edu.br/bi/](https://suap.ifpb.edu.br/bi/)

![SABER IFPB](/assets/img/projects/saber.png)

---

## INPI Registration Document

<div style="width:100%; max-width:800px; margin: 2rem auto;">
  <embed src="/assets/files/saber-ifpb-intellectual-property.pdf" type="application/pdf" width="100%" height="800px" style="border: 1px solid #333; border-radius: 4px;" />
  <p style="margin-top: 0.5rem; font-size: 0.875rem; color: #999;">
    Can't see the PDF? <a href="/assets/files/saber-ifpb-intellectual-property.pdf" target="_blank">Download it here</a>.
  </p>
</div>
