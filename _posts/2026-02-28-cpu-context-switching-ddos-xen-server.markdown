---
layout: post
title: "CPU Context Switching and Performance Degradation Under DDoS in Xen Server"
description: "Research paper from CONNEPI 2016 analyzing how CPU context switches relate to performance degradation in paravirtualized environments during distributed denial-of-service attacks."
date: 2026-02-28
tags: [virtualization, security, research, systems]
image: /assets/img/posts/cpu-context-switching-ddos-xen-server.svg
---

*Originally published as a research paper at CONNEPI 2016. Revisited here with interactive visualizations and updated context.*

This article summarizes my research paper presented at **CONNEPI 2016** (XI Congresso Norte Nordeste de Pesquisa e Inovação), co-authored with André Henrique Sousa de Menezes, Prof. Leandro Cavalcanti de Almeida, and Prof. Paulo Ditarso Maciel Junior at IFPB.

The full paper is embedded at the bottom of this post.

## The question

Server virtualization lets multiple virtual machines share the same physical hardware. This is efficient — but what happens to the *neighbors* when one VM gets hit by a DDoS attack?

We already knew from prior experiments that neighboring VMs suffer performance degradation during an attack on a co-hosted VM. The question was *why*, and specifically: **what role does CPU context switching play?**

## Background

In a paravirtualized environment like Xen Server, the hypervisor mediates all system calls and hardware access from guest VMs. Every network packet, every I/O operation, every system call goes through the hypervisor. This creates overhead — and that overhead becomes critical under attack.

A **context switch** happens when the CPU transfers control from one process to another. They're triggered either when a process completes its time slice, or when a high-priority **interrupt** forces the OS to reclaim the CPU. Context switches are expensive: the CPU must save the current process state, load the new one, and flush relevant caches.

Previous work by [Shea and Liu (2012)](https://ieeexplore.ieee.org/document/6245983) showed that virtualized environments experience a non-linear increase in context switches under DDoS compared to bare-metal systems. They proposed kernel modifications to KVM to reduce context switching overhead.

We wanted to understand this relationship in Xen Server specifically.

## The experiment

We built a controlled lab environment:

- **Host:** Intel i7 quad-core, 32 GB RAM, 1 TB HDD, two Gigabit Ethernet interfaces (LACP bonded for 2 Gbps)
- **Hypervisor:** Citrix XenServer 7.2.1511
- **Two VMs:** Each with 1 vCPU, 1 GB RAM, 10 GB disk, Debian 8.2 running Apache 2
- **Attack infrastructure:** 10 slave machines for DDoS, plus a master controller and client machines
- **Network:** Cisco Catalyst 2960 switch, VMs on separate virtual networks

The experiment ran **60 rounds**: 30 without attack (baseline) and 30 with a DDoS attack targeting VM1. In both scenarios, both VMs ran synthetic workloads via Sysbench and Stress-ng to simulate realistic server load.

Each round followed four automated phases — **initialization**, **execution**, **collection**, and **cleanup** — orchestrated by shell scripts that coordinated all machines via SSH. On the VMs, **Sysbench** and **Stress-ng** generated a consistent synthetic workload to simulate realistic server load. We collected context switch and interrupt data directly from Dom0 (the privileged Xen management domain) using **`vmstat`**, a native Linux tool that reports kernel statistics including per-second interrupt and context switch counts.

## See it in action

Before diving into the numbers, here's an interactive simulation of what happens inside the CPU. Toggle the DDoS attack to see how interrupts flood the system and force context switches:

<div id="cpu-sim" style="max-width:750px; margin:2rem auto; font-family: system-ui, -apple-system, sans-serif;">

<!-- Controls -->
<div style="display:flex; align-items:center; gap:1rem; margin-bottom:1rem; flex-wrap:wrap;">
  <button id="ddos-toggle" onclick="toggleDDoS()" style="padding:0.5rem 1.25rem; border:none; border-radius:6px; font-weight:600; font-size:0.875rem; cursor:pointer; background:#22c55e; color:#fff; transition: background 0.3s;">
    ▶ Start DDoS Attack
  </button>
  <span id="ddos-status" style="font-size:0.8rem; color:#888;">Normal operation</span>
</div>

<!-- CPU Timeline -->
<div style="background:#0f172a; border:1px solid #1e293b; border-radius:8px; overflow:hidden; margin-bottom:1rem;">
  <div style="background:#1e293b; padding:0.4rem 0.75rem; display:flex; align-items:center; gap:0.5rem;">
    <span style="width:8px;height:8px;border-radius:50%;background:#ef4444;display:inline-block;"></span>
    <span style="width:8px;height:8px;border-radius:50%;background:#eab308;display:inline-block;"></span>
    <span style="width:8px;height:8px;border-radius:50%;background:#22c55e;display:inline-block;"></span>
    <span style="font-size:0.75rem;color:#94a3b8;margin-left:0.25rem;">CPU Timeline — Dom0 Hypervisor</span>
  </div>
  <div style="padding:1rem;">
    <!-- Process lanes -->
    <div style="display:flex; gap:0.5rem; align-items:center; margin-bottom:0.75rem;">
      <span style="font-size:0.7rem; color:#64748b; width:60px; flex-shrink:0;">VM1</span>
      <div id="lane-vm1" style="flex:1; height:24px; display:flex; gap:2px; overflow:hidden; border-radius:4px;"></div>
    </div>
    <div style="display:flex; gap:0.5rem; align-items:center; margin-bottom:0.75rem;">
      <span style="font-size:0.7rem; color:#64748b; width:60px; flex-shrink:0;">VM2</span>
      <div id="lane-vm2" style="flex:1; height:24px; display:flex; gap:2px; overflow:hidden; border-radius:4px;"></div>
    </div>
    <div style="display:flex; gap:0.5rem; align-items:center; margin-bottom:0.75rem;">
      <span style="font-size:0.7rem; color:#64748b; width:60px; flex-shrink:0;">Hypervisor</span>
      <div id="lane-hyp" style="flex:1; height:24px; display:flex; gap:2px; overflow:hidden; border-radius:4px;"></div>
    </div>
    <div style="display:flex; gap:0.5rem; align-items:center;">
      <span style="font-size:0.7rem; color:#64748b; width:60px; flex-shrink:0;">Interrupts</span>
      <div id="lane-int" style="flex:1; height:16px; display:flex; gap:1px; overflow:hidden; border-radius:4px;"></div>
    </div>
    <!-- Legend -->
    <div style="display:grid; grid-template-columns:1fr 1fr; gap:0.5rem 1.5rem; margin-top:1rem; padding:0.75rem; background:#1e293b; border-radius:6px;">
      <div style="display:flex; align-items:center; gap:0.5rem;">
        <span style="display:inline-block;width:12px;height:12px;background:#3b82f6;border-radius:2px;flex-shrink:0;"></span>
        <span style="font-size:0.75rem; color:#cbd5e1;"><strong style="color:#e2e8f0;">Running</strong> — VM executing its workload normally</span>
      </div>
      <div style="display:flex; align-items:center; gap:0.5rem;">
        <span style="display:inline-block;width:12px;height:12px;background:#f59e0b;border-radius:2px;flex-shrink:0;"></span>
        <span style="font-size:0.75rem; color:#cbd5e1;"><strong style="color:#e2e8f0;">Context Switch</strong> — CPU saves/loads process state (expensive)</span>
      </div>
      <div style="display:flex; align-items:center; gap:0.5rem;">
        <span style="display:inline-block;width:12px;height:12px;background:#8b5cf6;border-radius:2px;flex-shrink:0;"></span>
        <span style="font-size:0.75rem; color:#cbd5e1;"><strong style="color:#e2e8f0;">Hypervisor</strong> — Dom0 mediating system calls and I/O</span>
      </div>
      <div style="display:flex; align-items:center; gap:0.5rem;">
        <span style="display:inline-block;width:12px;height:12px;background:#ef4444;border-radius:2px;flex-shrink:0;"></span>
        <span style="font-size:0.75rem; color:#cbd5e1;"><strong style="color:#e2e8f0;">High-priority interrupt</strong> — forces CPU to context switch</span>
      </div>
      <div style="display:flex; align-items:center; gap:0.5rem;">
        <span style="display:inline-block;width:12px;height:12px;background:#6b7280;border-radius:2px;flex-shrink:0;"></span>
        <span style="font-size:0.75rem; color:#cbd5e1;"><strong style="color:#e2e8f0;">Low-priority interrupt</strong> — handled without context switch</span>
      </div>
    </div>
  </div>
</div>

<!-- Live counters -->
<div style="display:grid; grid-template-columns:repeat(3,1fr); gap:0.75rem; margin-bottom:1rem;">
  <div style="background:#0f172a; border:1px solid #1e293b; border-radius:8px; padding:0.75rem; text-align:center;">
    <div style="font-size:0.65rem; color:#64748b; text-transform:uppercase; letter-spacing:0.05em;">Interrupts/s</div>
    <div id="counter-int" style="font-size:1.5rem; font-weight:700; color:#ef4444; font-variant-numeric:tabular-nums;">0</div>
    <div style="font-size:0.6rem; color:#475569; margin-top:0.25rem;">Hardware signals requesting CPU attention</div>
  </div>
  <div style="background:#0f172a; border:1px solid #1e293b; border-radius:8px; padding:0.75rem; text-align:center;">
    <div style="font-size:0.65rem; color:#64748b; text-transform:uppercase; letter-spacing:0.05em;">Context Switches/s</div>
    <div id="counter-cs" style="font-size:1.5rem; font-weight:700; color:#f59e0b; font-variant-numeric:tabular-nums;">0</div>
    <div style="font-size:0.6rem; color:#475569; margin-top:0.25rem;">Times CPU saved/loaded process state</div>
  </div>
  <div style="background:#0f172a; border:1px solid #1e293b; border-radius:8px; padding:0.75rem; text-align:center;">
    <div style="font-size:0.65rem; color:#64748b; text-transform:uppercase; letter-spacing:0.05em;">Conversion Rate</div>
    <div id="counter-rate" style="font-size:1.5rem; font-weight:700; color:#a78bfa; font-variant-numeric:tabular-nums;">0%</div>
    <div style="font-size:0.6rem; color:#475569; margin-top:0.25rem;">% of interrupts that forced a context switch</div>
  </div>
</div>

<!-- Animated bar chart -->
<div style="background:#0f172a; border:1px solid #1e293b; border-radius:8px; overflow:hidden;">
  <div style="background:#1e293b; padding:0.4rem 0.75rem;">
    <span style="font-size:0.75rem;color:#94a3b8;">Experiment Data — Actual measurements from 60 rounds</span>
  </div>
  <div style="padding:1rem;">
    <div style="margin-bottom:1rem;">
      <div style="display:flex; justify-content:space-between; margin-bottom:0.25rem;">
        <span style="font-size:0.75rem; color:#94a3b8;">Interrupts</span>
        <span id="bar-int-val" style="font-size:0.75rem; color:#ef4444; font-variant-numeric:tabular-nums;">25,295</span>
      </div>
      <div style="background:#1e293b; border-radius:4px; height:20px; overflow:hidden;">
        <div id="bar-int" style="height:100%; background:linear-gradient(90deg,#ef4444,#f87171); border-radius:4px; transition:width 1s ease; width:17.9%;"></div>
      </div>
    </div>
    <div style="margin-bottom:1rem;">
      <div style="display:flex; justify-content:space-between; margin-bottom:0.25rem;">
        <span style="font-size:0.75rem; color:#94a3b8;">Context Switches</span>
        <span id="bar-cs-val" style="font-size:0.75rem; color:#f59e0b; font-variant-numeric:tabular-nums;">13,504</span>
      </div>
      <div style="background:#1e293b; border-radius:4px; height:20px; overflow:hidden;">
        <div id="bar-cs" style="height:100%; background:linear-gradient(90deg,#f59e0b,#fbbf24); border-radius:4px; transition:width 1s ease; width:14.1%;"></div>
      </div>
    </div>
    <div>
      <div style="display:flex; justify-content:space-between; margin-bottom:0.25rem;">
        <span style="font-size:0.75rem; color:#94a3b8;">Conversion Rate (Interrupts → Context Switches)</span>
        <span id="bar-rate-val" style="font-size:0.75rem; color:#a78bfa; font-variant-numeric:tabular-nums;">53.39%</span>
      </div>
      <div style="background:#1e293b; border-radius:4px; height:20px; overflow:hidden; position:relative;">
        <div id="bar-rate" style="height:100%; background:linear-gradient(90deg,#8b5cf6,#a78bfa); border-radius:4px; transition:width 1s ease; width:53.39%;"></div>
      </div>
    </div>
  </div>
</div>
</div>

<script>
(function(){
  var ddosActive = false;
  var simInterval = null;
  var SLOTS = 40;

  // Data from the actual experiment
  var DATA = {
    normal:  { interrupts: 25295, cs: 13504, rate: 53.39 },
    ddos:    { interrupts: 141157, cs: 95369, rate: 67.63 }
  };

  function makeSlots(lane, count, colorFn) {
    lane.innerHTML = '';
    for (var i = 0; i < count; i++) {
      var d = document.createElement('div');
      d.style.cssText = 'flex:1; height:100%; border-radius:2px; transition: background 0.15s;';
      d.style.background = colorFn(i);
      lane.appendChild(d);
    }
  }

  function normalColors() {
    // VM1: mostly running, occasional context switch
    makeSlots(document.getElementById('lane-vm1'), SLOTS, function(i) {
      return (i % 8 === 5) ? '#f59e0b' : '#3b82f6';
    });
    // VM2: mostly running, rare context switch
    makeSlots(document.getElementById('lane-vm2'), SLOTS, function(i) {
      return (i % 12 === 7) ? '#f59e0b' : '#3b82f6';
    });
    // Hypervisor: mostly idle, occasional handling
    makeSlots(document.getElementById('lane-hyp'), SLOTS, function(i) {
      return (i % 8 === 5 || i % 12 === 7) ? '#8b5cf6' : '#1e293b';
    });
    // Interrupts: sparse, mostly low-priority
    makeSlots(document.getElementById('lane-int'), SLOTS, function(i) {
      if (i % 8 === 4) return '#ef4444';
      if (i % 6 === 3) return '#6b7280';
      return '#0f172a';
    });
  }

  function ddosColors() {
    // VM1: heavily interrupted, lots of context switches
    makeSlots(document.getElementById('lane-vm1'), SLOTS, function(i) {
      if (i % 3 === 0) return '#f59e0b';
      if (i % 3 === 1) return '#f59e0b';
      return '#3b82f6';
    });
    // VM2: collateral damage — more context switches than normal
    makeSlots(document.getElementById('lane-vm2'), SLOTS, function(i) {
      return (i % 4 < 2) ? '#f59e0b' : '#3b82f6';
    });
    // Hypervisor: constantly busy
    makeSlots(document.getElementById('lane-hyp'), SLOTS, function(i) {
      return (i % 5 === 4) ? '#1e293b' : '#8b5cf6';
    });
    // Interrupts: flooded with high-priority
    makeSlots(document.getElementById('lane-int'), SLOTS, function(i) {
      if (i % 5 === 4) return '#0f172a';
      return (Math.random() > 0.3) ? '#ef4444' : '#6b7280';
    });
  }

  function animateCounters(target) {
    var intEl = document.getElementById('counter-int');
    var csEl = document.getElementById('counter-cs');
    var rateEl = document.getElementById('counter-rate');
    var startInt = parseInt(intEl.textContent.replace(/,/g,'')) || 0;
    var startCs = parseInt(csEl.textContent.replace(/,/g,'')) || 0;
    var startRate = parseFloat(rateEl.textContent) || 0;
    var steps = 40;
    var step = 0;
    function tick() {
      step++;
      var t = step / steps;
      // ease out
      var e = 1 - Math.pow(1 - t, 3);
      var ci = Math.round(startInt + (target.interrupts - startInt) * e);
      var cc = Math.round(startCs + (target.cs - startCs) * e);
      var cr = (startRate + (target.rate - startRate) * e).toFixed(2);
      intEl.textContent = ci.toLocaleString('en-US');
      csEl.textContent = cc.toLocaleString('en-US');
      rateEl.textContent = cr + '%';
      if (step < steps) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  function updateBars(target) {
    var maxVal = 150000;
    document.getElementById('bar-int').style.width = (target.interrupts / maxVal * 100) + '%';
    document.getElementById('bar-int-val').textContent = target.interrupts.toLocaleString('en-US');
    document.getElementById('bar-cs').style.width = (target.cs / maxVal * 100) + '%';
    document.getElementById('bar-cs-val').textContent = target.cs.toLocaleString('en-US');
    document.getElementById('bar-rate').style.width = target.rate + '%';
    document.getElementById('bar-rate-val').textContent = target.rate + '%';
  }

  function jitterTimeline() {
    if (ddosActive) {
      ddosColors();
    }
  }

  window.toggleDDoS = function() {
    ddosActive = !ddosActive;
    var btn = document.getElementById('ddos-toggle');
    var status = document.getElementById('ddos-status');

    if (ddosActive) {
      btn.style.background = '#ef4444';
      btn.textContent = '■ Stop DDoS Attack';
      status.textContent = '🔴 DDoS attack in progress — 10 slaves flooding VM1';
      status.style.color = '#f87171';
      ddosColors();
      animateCounters(DATA.ddos);
      updateBars(DATA.ddos);
      simInterval = setInterval(jitterTimeline, 500);
    } else {
      btn.style.background = '#22c55e';
      btn.textContent = '▶ Start DDoS Attack';
      status.textContent = 'Normal operation';
      status.style.color = '#888';
      normalColors();
      animateCounters(DATA.normal);
      updateBars(DATA.normal);
      if (simInterval) { clearInterval(simInterval); simInterval = null; }
    }
  };

  // Initialize
  normalColors();
})();
</script>

## Results

The numbers were striking:

| Metric (averages) | Without DDoS | With DDoS |
|---|---|---|
| **Interrupts** | 25,295 | 141,157 |
| **Context switches** | 13,504 | 95,369 |
| **Conversion rate** | 53.39% | 67.63% |

During the DDoS attack:

- Interrupts increased by **82%**
- Context switches increased by **86%**
- The CPU converted **14.23% more** interrupts into context switches compared to the baseline

This last finding is the key insight. It's not just that there are more interrupts — the *nature* of those interrupts changes. Under DDoS, a disproportionate number of interrupts are high-priority, forcing the CPU to perform expensive context switches rather than handling them in the current process context.

## Why this matters

This research, while academic, touches on something very practical: **noisy neighbor problems in shared infrastructure**. If you're running workloads on shared virtualized infrastructure (which includes most cloud environments), a DDoS attack on a co-tenant can degrade your performance even if your VM isn't the target.

The mechanism is clear: the flood of network packets generates hardware interrupts that propagate through the hypervisor, consuming CPU cycles across all VMs sharing that physical host. The non-linear relationship between interrupts and context switches means the degradation is worse than you'd expect from simple resource contention.

## Reflections

This was undergraduate research — my first real exposure to systems-level thinking. Setting up the controlled environment, writing the automation scripts, collecting and analyzing the data — it taught me how to reason about system behavior from first principles.

Looking back, the skills translate directly to what I do today in observability engineering: measuring system behavior under stress, understanding where overhead comes from, and making the invisible visible through data collection and analysis.

## What's next

It's been nearly a decade since we ran these experiments. A lot has changed in virtualization and cloud infrastructure — container runtimes, eBPF-based observability, hardware-assisted virtualization improvements, and cloud providers implementing better noisy-neighbor isolation. In an upcoming post, I'll revisit this research and explore what's different now: which of our findings still hold, what new mitigation strategies exist, and how modern observability tools would have changed our experimental approach.

---

## Full Paper (CONNEPI 2016)

<div style="width:100%; max-width:800px; margin: 2rem auto;">
  <embed src="/assets/files/cpu-context-switch-connepi-2016.pdf" type="application/pdf" width="100%" height="800px" style="border: 1px solid #333; border-radius: 4px;" />
  <p style="margin-top: 0.5rem; font-size: 0.875rem; color: #999;">
    Can't see the PDF? <a href="/assets/files/cpu-context-switch-connepi-2016.pdf" target="_blank">Download it here</a>.
  </p>
</div>
