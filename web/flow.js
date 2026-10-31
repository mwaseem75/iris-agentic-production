"use strict";
// Flow tab: the production as lanes, messages as dots on their real hops. Needs el, get, send,
// utcMs, num, money, chart, charts, showTab, showStory, COLORS and includeEval from the dashboard script.
(function () {
  var LANES = ["inbound", "router", "ai", "checks", "decision", "outcome"];
  var LANE_LABEL = { inbound: "Inbound", router: "Router", ai: "AI triage", checks: "Checks", decision: "Decision", outcome: "Outcome" };
  var LANE_COLOR = { inbound: "#2563a8", router: "#6d4aa8", ai: "#1f7a4d", checks: "#9a6400", decision: "#0f766e", outcome: "#475569" };
  var LANE_TINT = { inbound: "rgba(37,99,168,0.06)", router: "rgba(109,74,168,0.06)", ai: "rgba(31,122,77,0.06)", checks: "rgba(154,100,0,0.07)", decision: "rgba(15,118,110,0.06)", outcome: "rgba(71,85,105,0.07)" };
  // The three gates are real nodes in the Checks lane, in the order a decision passes them
  var GATES = [{ key: "injection", label: "Injection check" }, { key: "grounding", label: "Grounding check" }, { key: "triage", label: "Triage rule" }];
  var OUT_COLOR = { applied: COLORS.applied, person: COLORS.approval, rejected: COLORS.rejected, resent: COLORS.resent, observed: COLORS.other };
  var OUT_LABEL = { applied: "Applied", person: "To a person", rejected: "Rejected", resent: "Resent", observed: "Observed" };
  var OUT_ORDER = ["applied", "person", "rejected", "resent", "observed"];
  var GATE_STATES = { injection: ["clean", "flagged"], grounding: ["passed", "ungrounded", "ambiguous"], triage: [] };
  var CHIP_KIND = { clean: "g", passed: "g", applied: "g", flagged: "b", ungrounded: "b", ambiguous: "w" };
  var INFLIGHT = "#7b8794";
  var POLL_MS = 1000, HOLD_MS = 2500, LAG_MS = 3000, WINDOW_S = 120, SLIDER_S = 3600, PREFILL_S = 600, TABLE_ROWS = 12, MAX_DOTS = 60;
  var MIN_SEG_MS = 700;
  var NODE_H = 60, NODE_W = 176, HEAD_H = 34, DOT = 8, CURVE = 0.2;

  var S = null;
  var JMIN_MS = 700, JMAX_MS = 2000, JGAP_MS = 1200, JLONG_MS = 20000;
  var active = false, polling = false, timer = null, raf = null;
  var box, ns = "IRISAPP", mapAt = 0;

  function $(id) { return document.getElementById(id); }
  function evalOn() { return typeof includeEval !== "undefined" && includeEval; }
  // Burst messages are sent from this tab, so they always show; other eval traffic follows the toggle
  function visible(c) { return evalOn() || !c.eval || c.burst; }
  function serverNow() { return Date.now() + (S ? S.skew : 0); }
  // Header and item names can differ in case; the map's item name is the one that has a position
  function canon(n) { return (S && S.canon && S.canon[String(n).toUpperCase()]) || n; }
  function stamp(d) { return d.toISOString().replace("T", " ").slice(0, 23); }

  function reset() {
    var keep = S ? { skew: S.skew, speed: S.speed } : { skew: 0, speed: 1 };
    S = { map: null, pos: {}, hops: {}, sessions: {}, cards: {}, tools: [], usage: [], cursor: null, skew: keep.skew,
      mode: "live", paused: false, speed: keep.speed, vt: 0, wall: Date.now(), windowEnd: 0, dots: [], geo: {} };
  }

  // ---- data ----
  function mergeSlice(r) {
    if (r.now) S.skew = utcMs(r.now) - Date.now();
    r.hops.forEach(function (h) {
      h.m0 = utcMs(h.t0); h.m1 = h.t1 ? utcMs(h.t1) : null;
      S.hops[h.id] = h;
      var s = S.sessions[h.session] || (S.sessions[h.session] = { id: h.session, hops: [], card: null });
      if (s.hops.indexOf(h.id) < 0) s.hops.push(h.id);
    });
    r.decisions.forEach(function (c) {
      if (S.cards[c.id]) return;
      c.ms = utcMs(c.at);
      S.cards[c.id] = c;
      var s = S.sessions[c.session] || (S.sessions[c.session] = { id: c.session, hops: [], card: null });
      s.card = c;
    });
    r.tools.forEach(function (t) { S.tools.push(t); });
    r.usage.forEach(function (u) { S.usage.push(u); });
    if (S.tools.length > 400) S.tools.splice(0, S.tools.length - 400);
    if (S.usage.length > 400) S.usage.splice(0, S.usage.length - 400);
    if (r.cursor) S.cursor = r.cursor;
    prune();
  }
  // Old sessions are history: the counters keep them, the dots do not need them
  function prune() {
    var cut = serverNow() - 15 * 60 * 1000, ids = Object.keys(S.sessions);
    if (ids.length < 300) return;
    ids.forEach(function (k) {
      var s = S.sessions[k], last = 0;
      s.hops.forEach(function (h) { last = Math.max(last, S.hops[h].m1 || S.hops[h].m0); });
      if (last && last < cut) { s.hops.forEach(function (h) { delete S.hops[h]; }); delete S.sessions[k]; }
    });
  }
  // Counts of the decisions shown (eval and burst ones only with the dashboard's toggle)
  function stats() {
    var st = { out: {}, injection: {}, grounding: {}, triage: {}, cards: 0 };
    OUT_ORDER.forEach(function (o) { st.out[o] = 0; });
    Object.keys(S.cards).forEach(function (k) {
      var c = S.cards[k];
      if (!visible(c)) return;
      st.cards++;
      st.out[c.outcome] = (st.out[c.outcome] || 0) + 1;
      var g = c.gates, t = g.triage.outcome.split(":")[0].toLowerCase();
      st.injection[g.injection.status] = (st.injection[g.injection.status] || 0) + 1;
      st.grounding[g.grounding.status] = (st.grounding[g.grounding.status] || 0) + 1;
      st.triage[t] = (st.triage[t] || 0) + 1;
    });
    return st;
  }

  function evalParam() { return "&eval=" + (evalOn() ? 1 : 0); }
  function loadMap() {
    return get("api/flow/map?ns=" + ns + evalParam()).then(function (m) { S.map = m; mapAt = Date.now(); layout(); drawStatic(); });
  }
  // First fill: the last minutes as history; live polling continues from its cursor
  function prefill() {
    var to = new Date(Date.now() + S.skew), from = new Date(to.getTime() - PREFILL_S * 1000);
    return get("api/flow/window?ns=" + ns + "&from=" + stamp(from) + "&to=" + stamp(new Date(to.getTime() + 60000)) + evalParam()).then(function (r) {
      mergeSlice(r);
      // a window without rows leaves a cursor field at 0, and a poll from 0 would read the oldest rows first
      return get("api/flow/live?ns=" + ns).then(function (h) {
        var c = S.cursor || { hop: 0, dec: 0, tool: 0, usage: 0 };
        ["hop", "dec", "tool", "usage"].forEach(function (k) { if (!c[k]) c[k] = h.cursor[k]; });
        S.cursor = c;
      });
    });
  }
  var newHops = 0;
  function status(n) {
    newHops += n;
    $("flow-status").textContent = "last update: " + new Date().toLocaleTimeString("en-GB") + " · " + n + " new hops (" + newHops + " since the tab opened) · " + Object.keys(S.hops).length + " hops, " + Object.keys(S.cards).length + " decisions in view";
  }
  function poll() {
    if (!active || polling || S.paused || S.mode !== "live" || !S.cursor) return;
    polling = true;
    var c = S.cursor;
    get("api/flow/live?ns=" + ns + "&since=" + c.hop + "&dec=" + c.dec + "&tool=" + c.tool + "&usage=" + c.usage).then(function (r) {
      mergeSlice(r);
      status(r.hops.length);
      renderSide();
    }).catch(function (e) { $("flow-msg").textContent = "Live feed: " + e.message; }).then(function () { polling = false; });
  }

  // ---- layout (x and y are pixels of the chart) ----
  function laneX(i, W) { return (i + 0.5) * W / LANES.length; }
  function nodeW(W) { return Math.max(110, Math.min(NODE_W, W / LANES.length - 28)); }
  function layout() {
    var W = box.offsetWidth || 1000, H = box.offsetHeight || 560, w = nodeW(W);
    var byLane = {};
    LANES.forEach(function (l) { byLane[l] = []; });
    S.map.items.forEach(function (it) { if (byLane[it.lane]) byLane[it.lane].push(it); });
    S.pos = {}; S.W = W; S.H = H; S.w = w;
    LANES.forEach(function (l, i) {
      if (l === "checks") {
        // Gates: equal slots, node at the top of its slot, chips below it
        var slot = (H - HEAD_H) / GATES.length;
        GATES.forEach(function (g, k) { S.pos["@" + g.key] = { x: laneX(i, W), y: HEAD_H + slot * k + NODE_H / 2 + 8, w: w, h: NODE_H, lane: l }; });
        return;
      }
      var n = byLane[l].length, slot2 = (H - HEAD_H) / Math.max(1, n);
      byLane[l].forEach(function (it, k) { S.pos[it.name] = { x: laneX(i, W), y: HEAD_H + slot2 * (k + 0.5), w: w, h: NODE_H, lane: l }; });
    });
    var a = S.map.items.filter(function (i) { return i.className === "AgenticProd.Operation.Agent"; })[0];
    var t = S.map.items.filter(function (i) { return i.className === "AgenticProd.Process.Triage"; })[0];
    S.agent = a ? a.name : null; S.triage = t ? t.name : null;
    S.canon = {};
    S.map.items.forEach(function (it) { S.canon[it.name.toUpperCase()] = it.name; });
    S.geo = {};
  }
  // Curve through the edge ends, the same control point ECharts uses for lines.curveness
  function geom(from, to) {
    var key = from + ">" + to;
    if (S.geo[key]) return S.geo[key];
    var a = S.pos[from], b = S.pos[to];
    if (!a || !b) return null;
    var p0, p1;
    if (Math.abs(a.x - b.x) < 1) {
      p0 = [a.x, a.y + (b.y > a.y ? a.h / 2 : -a.h / 2)]; p1 = [b.x, b.y + (b.y > a.y ? -b.h / 2 : b.h / 2)];
    } else {
      var dir = b.x > a.x ? 1 : -1;
      p0 = [a.x + dir * a.w / 2, a.y]; p1 = [b.x - dir * b.w / 2, b.y];
    }
    var lanes = Math.abs(LANES.indexOf(a.lane) - LANES.indexOf(b.lane)), c = lanes > 1 ? 0.3 : CURVE;
    var g = { p0: p0, p1: p1, cp: [(p0[0] + p1[0]) / 2 - (p0[1] - p1[1]) * c, (p0[1] + p1[1]) / 2 - (p1[0] - p0[0]) * c], c: c };
    S.geo[key] = g;
    return g;
  }
  function bez(g, t) {
    var u = 1 - t;
    return [u * u * g.p0[0] + 2 * u * t * g.cp[0] + t * t * g.p1[0], u * u * g.p0[1] + 2 * u * t * g.cp[1] + t * t * g.p1[1]];
  }

  // ---- drawing ----
  function counterText(it) {
    return "{c|in " + it.in + " · out " + it.out + "}\n{" + (it.errors ? "e" : "c") + "|err " + it.errors + " · queue " + it.queue + "}";
  }
  // fixed: the states the gate can show, listed even at 0; others (rule names) only when they occurred
  function chipLines(counts, fixed) {
    fixed = fixed || [];
    var extra = Object.keys(counts).filter(function (k) { return counts[k] && fixed.indexOf(k) < 0; }).sort(function (a, b) { return counts[b] - counts[a]; });
    var keys = fixed.concat(extra);
    var total = keys.reduce(function (n, k) { return n + (counts[k] || 0); }, 0);
    if (!total) return "{ch|no decisions yet}";
    var shown = keys.slice(0, 6), lines = [], line = "", len = 0;
    shown.forEach(function (k) {
      var n = counts[k] || 0, txt = k + " " + n, kind = n ? (CHIP_KIND[k] || "o") : "o";
      if (len && len + txt.length > 22) { lines.push(line); line = ""; len = 0; }
      line += (line ? " " : "") + "{ch" + kind + "|" + txt + "}"; len += txt.length + 1;
    });
    lines.push(line);
    return lines.join("\n");
  }
  var RICH = {
    n: { fontSize: 13, fontWeight: "bold", lineHeight: 18, color: "#1c2430" },
    c: { fontSize: 12, lineHeight: 15, color: "#5f6b7a" },
    e: { fontSize: 12, lineHeight: 15, color: "#b42318", fontWeight: "bold" },
    ch: { fontSize: 11, backgroundColor: "#eef0f3", color: "#5f6b7a", padding: [2, 6], borderRadius: 8, lineHeight: 14 },
    chg: { fontSize: 11, backgroundColor: "#e7f4ec", color: "#1f7a4d", padding: [2, 6], borderRadius: 8, lineHeight: 14 },
    chb: { fontSize: 11, backgroundColor: "#fdeceb", color: "#b42318", padding: [2, 6], borderRadius: 8, lineHeight: 14 },
    chw: { fontSize: 11, backgroundColor: "#fdf3e1", color: "#9a6400", padding: [2, 6], borderRadius: 8, lineHeight: 14 },
    cho: { fontSize: 11, backgroundColor: "#eef0f3", color: "#5f6b7a", padding: [2, 6], borderRadius: 8, lineHeight: 14 }
  };
  function nodeData(name, p, text, color, errs, enabled) {
    return { name: name, value: [p.x, p.y], symbolSize: [p.w, p.h],
      label: { formatter: "{n|" + name + "}\n" + text, rich: RICH, width: p.w - 12, overflow: "truncate", lineHeight: 15 },
      itemStyle: { color: enabled === false ? "#eef0f3" : "#ffffff", borderColor: errs ? "#b42318" : color, borderWidth: errs ? 3 : 2 } };
  }
  function drawStatic() {
    var m = S.map;
    if (!box || !box.offsetWidth || !m) return;
    if (Math.abs(box.offsetWidth - S.W) > 2 || Math.abs(box.offsetHeight - S.H) > 2) layout();
    var st = stats(), W = S.W, H = S.H;
    var nodes = m.items.filter(function (it) { return S.pos[it.name]; }).map(function (it) {
      var p = S.pos[it.name];
      var n = nodeData(it.name, p, counterText(it), LANE_COLOR[it.lane], it.errors, it.enabled);
      n.key = it.name;
      return n;
    });
    var chips = [], on = S.mode === "journey" && S.J ? S.J.on : null;
    GATES.forEach(function (g) {
      var p = S.pos["@" + g.key], counts = st[g.key], total = Object.keys(counts).reduce(function (n, k) { return n + counts[k]; }, 0);
      var gn = nodeData(g.label, p, "{c|" + total + " decisions in view}", LANE_COLOR.checks, 0);
      gn.key = "@" + g.key;
      nodes.push(gn);
      chips.push({ value: [p.x, p.y + p.h / 2 + 4], itemStyle: { color: "rgba(0,0,0,0)" }, label: { show: true, position: "bottom", distance: 2, formatter: chipLines(counts, GATE_STATES[g.key]), rich: RICH, align: "center" } });
    });
    var edges = m.edges.map(function (e) { return { from: e.from, to: e.to, count: e.count, avgMs: e.avgMs }; });
    // The way back from the agent through the three gates to Triage has no hop of its own
    if (S.agent && S.triage && st.cards) {
      var chain = [S.agent, "@injection", "@grounding", "@triage", S.triage];
      for (var i = 0; i < chain.length - 1; i++) edges.push({ from: chain[i], to: chain[i + 1], count: st.cards, avgMs: null });
    }
    var lines = edges.map(function (e) {
      var g = geom(e.from, e.to);
      return g && { coords: [g.p0, g.p1], from: e.from, to: e.to, count: e.count, avgMs: e.avgMs, lineStyle: { width: 1.5 + Math.min(5, Math.log10(1 + e.count) * 1.8), curveness: g.c } };
    }).filter(Boolean);
    // Message journey: everything dims except the path of that message; the current step is outlined
    if (on) {
      var curStep = S.J.steps[S.J.cur] || {};
      nodes.forEach(function (n) {
        var inPath = on.nodes[n.key], isCur = canon(curStep.node) === n.key || (curStep.edge && canon(curStep.edge.to) === n.key);
        n.itemStyle.opacity = inPath ? 1 : 0.18;
        if (isCur) { n.itemStyle.borderColor = "#2563a8"; n.itemStyle.borderWidth = 4; }
      });
      lines.forEach(function (l) {
        var inPath = on.edges[l.from + ">" + l.to], isCur = curStep.edge && canon(curStep.edge.from) + ">" + canon(curStep.edge.to) === l.from + ">" + l.to;
        l.lineStyle.opacity = inPath ? 1 : 0.07;
        if (inPath) l.lineStyle.color = isCur ? "#2563a8" : "#6b7a90";
      });
      chips.forEach(function (c) { c.label.opacity = 0.35; });
    }
    var bands = LANES.map(function (l, i) {
      return [{ name: LANE_LABEL[l], xAxis: i * W / LANES.length, itemStyle: { color: LANE_TINT[l] }, label: { show: true, position: "insideTop", color: LANE_COLOR[l], fontWeight: "bold", fontSize: 13 } }, { xAxis: (i + 1) * W / LANES.length }];
    });
    chart("flow", box, {
      animation: false, grid: { left: 0, right: 0, top: 0, bottom: 0 },
      xAxis: { min: 0, max: W, show: false }, yAxis: { min: 0, max: H, inverse: true, show: false },
      tooltip: { confine: true, formatter: function (p) {
        if (p.seriesId === "edges") return p.data.from.replace("@", "") + " → " + p.data.to.replace("@", "") + "<br>" + p.data.count + " messages" + (p.data.avgMs != null ? ", avg " + p.data.avgMs + " ms" : "");
        if (p.seriesId === "dots") return dotTip(p.data);
        return p.seriesId === "chips" ? "" : p.name;
      } },
      series: [
        { id: "lanes", type: "scatter", silent: true, data: [], markArea: { silent: true, data: bands } },
        { id: "edges", type: "lines", coordinateSystem: "cartesian2d", data: lines, symbol: ["none", "arrow"], symbolSize: 9,
          lineStyle: { color: "#c5ccd6", opacity: 1 }, emphasis: { lineStyle: { color: "#8a94a3" } }, zlevel: 1 },
        { id: "nodes", type: "scatter", symbol: "roundRect", data: nodes, zlevel: 2, label: { show: true, position: "inside" } },
        { id: "chips", type: "scatter", symbol: "circle", symbolSize: 1, data: chips, zlevel: 2, silent: true },
        { id: "dots", type: "scatter", data: S.dots, symbolSize: DOT, zlevel: 4 }
      ]
    });
    if (charts.flow && !charts.flow.flowBound) {
      charts.flow.flowBound = true;
      charts.flow.on("click", function (p) {
        if (p.seriesId !== "dots" || S.mode === "journey") return;
        var s = S.sessions[p.data.sid];
        if (s && s.card) openJourney(s.card.id); else $("flow-msg").textContent = "No decision is recorded for this message yet.";
      });
    }
  }

  // A session's path: its real hops in time order, plus the agent -> gates -> Triage leg once its
  // decision is known.
  function segments(s) {
    var segs = [], hs = s.hops.map(function (id) { return S.hops[id]; }).filter(Boolean).sort(function (a, b) { return a.m0 - b.m0; });
    hs.forEach(function (h) {
      var g = geom(canon(h.from), canon(h.to));
      if (!g) return;
      segs.push({ t0: h.m0, t1: h.m1, g: g, err: h.error });
      if (s.card && S.agent && canon(h.to) === S.agent && h.m1 != null) {
        var t1 = Math.max(h.m1 + 1600, s.card.ms), chain = [S.agent, "@injection", "@grounding", "@triage", S.triage], step = (t1 - h.m1) / (chain.length - 1);
        for (var i = 0; i < chain.length - 1; i++) {
          var gg = geom(chain[i], chain[i + 1]);
          if (gg) segs.push({ t0: h.m1 + i * step, t1: h.m1 + (i + 1) * step, g: gg });
        }
      }
    });
    // Replayed hops last a few ms; stretch each leg to a visible minimum, keeping the order
    var end = 0;
    segs.forEach(function (g) {
      if (g.t1 == null) { g.t0 = Math.max(g.t0, end); return; }
      g.t0 = Math.max(g.t0, end); g.t1 = Math.max(g.t1, g.t0 + MIN_SEG_MS); end = g.t1;
    });
    return segs;
  }
  function dotAt(s, vt) {
    var segs = segments(s), last = null;
    if (!segs.length || vt < segs[0].t0) return null;
    for (var i = 0; i < segs.length; i++) {
      var g = segs[i];
      if (g.t1 == null && vt - g.t0 > 120000) return null;
      if (vt >= g.t0 && (g.t1 == null || vt < g.t1)) {
        var f = g.t1 == null ? Math.min(0.85, (vt - g.t0) / 4000) : (g.t1 === g.t0 ? 1 : (vt - g.t0) / (g.t1 - g.t0));
        return { xy: bez(g.g, f), err: g.err };
      }
      if (g.t1 != null && g.t1 <= vt && (!last || g.t1 >= last.t1)) last = g;
    }
    if (!last || vt - last.t1 > HOLD_MS) return null;
    return { xy: last.g.p1, err: last.err, held: true };
  }
  function dotColor(s) { return s.card ? OUT_COLOR[s.card.outcome] : INFLIGHT; }
  function dotTip(d) {
    var s = S.sessions[d.sid], c = s && s.card;
    if (!c) return "Message " + d.sid + " (in flight)";
    return "Message " + c.headerId + ": " + c.decision + " (" + c.errorClass + ")<br>Injection: " + c.gates.injection.status +
      "<br>Grounding: " + c.gates.grounding.status + (c.gates.grounding.check ? " (" + c.gates.grounding.check + ")" : "") +
      "<br>Triage: " + c.gates.triage.outcome + "<br>" + OUT_LABEL[c.outcome];
  }

  function frame() {
    raf = null;
    if (!active) return;
    if (!S || !S.map) { raf = setTimeout(frame, 200); return; }
    var now = Date.now(), dt = now - S.wall;
    S.wall = now;
    if (S.mode === "journey") {
      journeyFrame(dt);
      raf = requestAnimationFrame(function () { setTimeout(frame, 40); });
      return;
    }
    if (!S.paused) S.vt += dt * S.speed;
    if (S.mode === "live" && !S.paused) {
      S.vt = Math.min(Math.max(S.vt, serverNow() - 12000), serverNow() - 600);
    } else if (S.mode === "window" && S.vt >= S.windowEnd) {
      S.vt = S.windowEnd; S.paused = true; syncControls();
    }
    var dots = [], ids = Object.keys(S.sessions);
    for (var i = 0; i < ids.length && dots.length < MAX_DOTS; i++) {
      var s = S.sessions[ids[i]];
      if (s.card && !visible(s.card)) continue;
      var d = dotAt(s, S.vt);
      if (!d) continue;
      dots.push({ value: d.xy, sid: s.id, itemStyle: { color: dotColor(s), borderColor: d.err ? "#b42318" : "#ffffff", borderWidth: d.err ? 2 : 1, opacity: d.held ? 0.6 : 1 } });
    }
    S.dots = dots;
    if (charts.flow) charts.flow.setOption({ series: [{ id: "dots", data: dots }] });
    $("flow-wait").classList.toggle("hidden", dots.length > 0);
    $("flow-clock").textContent = (S.mode === "live" ? "live " : "replay ") + new Date(S.vt).toISOString().slice(11, 19) + " UTC";
    raf = requestAnimationFrame(function () { setTimeout(frame, 40); });
  }

  // ---- side panels ----
  function chip(text, kind) { return el("span", text, "tag t-" + kind); }
  function gateKind(status) { return { clean: "good", passed: "good", flagged: "bad", ungrounded: "bad", ambiguous: "warn", none: "other" }[status] || "other"; }
  function outChip(o) { var ch = chip(OUT_LABEL[o], "other"); ch.style.background = OUT_COLOR[o]; ch.style.color = "#fff"; return ch; }
  function renderSide() {
    var st = stats(), o = $("flow-outcomes"); o.textContent = "";
    OUT_ORDER.forEach(function (k) {
      var t = el("div", null, "flow-out"); t.style.borderTopColor = OUT_COLOR[k];
      t.appendChild(el("div", num(st.out[k] || 0), "n")); t.appendChild(el("div", OUT_LABEL[k], "muted"));
      o.appendChild(t);
    });
    var ag = $("flow-agent"); ag.textContent = "";
    var lastTool = S.tools[S.tools.length - 1], hid = lastTool ? lastTool.headerId : null;
    var cards = Object.keys(S.cards).map(function (k) { return S.cards[k]; }).filter(visible).sort(function (a, b) { return b.id - a.id; });
    var runTools = hid == null ? [] : S.tools.filter(function (t) { return t.headerId === hid; });
    var u = hid == null ? null : S.usage.filter(function (x) { return x.headerId === hid; }).pop();
    ag.appendChild(el("h3", "Agent" + (hid != null ? ": message " + hid : "")));
    if (!runTools.length) ag.appendChild(el("p", "No tool calls yet in this view.", "muted"));
    var ol = el("ol", null, "flow-tools");
    runTools.forEach(function (t) { var li = el("li", t.tool + " " + t.ms + " ms"); if (t.status !== "OK") li.appendChild(chip(t.status, "bad")); ol.appendChild(li); });
    ag.appendChild(ol);
    var tokens = 0, cost = 0;
    S.usage.forEach(function (x) { tokens += x.tokens; cost += x.costUsd; });
    ag.appendChild(el("p", (u ? "This run: " + num(u.tokens) + " tokens, " + money(u.costUsd, 5) + (u.replay ? " (replayed)" : "") + ". " : "This run: tokens and cost land when it ends. ") + "View total: " + num(tokens) + " tokens, " + money(cost, 5) + ".", "muted"));
    var tb = $("flow-rows"); tb.textContent = "";
    cards.slice(0, TABLE_ROWS).forEach(function (c) {
      var tr = el("tr"); tr.dataset.id = c.id;
      tr.appendChild(el("td", c.at.slice(11, 19)));
      tr.appendChild(el("td", c.headerId + (c.eval ? " (eval/burst)" : "")));
      tr.appendChild(el("td", c.decision));
      var g = c.gates;
      var t1 = el("td"); t1.appendChild(chip(g.injection.status, gateKind(g.injection.status))); tr.appendChild(t1);
      var t2 = el("td"); t2.appendChild(chip(g.grounding.status + (g.grounding.check ? ": " + g.grounding.check : ""), gateKind(g.grounding.status))); tr.appendChild(t2);
      tr.appendChild(el("td", g.triage.outcome));
      var t3 = el("td"); t3.appendChild(outChip(c.outcome)); tr.appendChild(t3);
      tr.addEventListener("click", function () { openJourney(c.id); });
      tb.appendChild(tr);
    });
    var ph = $("flow-list"); ph.textContent = "";
    Object.keys(S.hops).map(Number).sort(function (a, b) { return b - a; }).slice(0, 30).forEach(function (id) {
      var h = S.hops[id], s = S.sessions[h.session], li = el("li");
      li.appendChild(el("span", h.t0.slice(11, 19) + " ", "muted"));
      li.appendChild(el("span", h.from + " → " + h.to + " "));
      if (s && s.card) { li.appendChild(outChip(s.card.outcome)); li.addEventListener("click", function () { openJourney(s.card.id); }); }
      if (h.error) li.appendChild(chip("error", "bad"));
      ph.appendChild(li);
    });
    drawStatic();
  }
  function openStory(id) { showTab("messages"); showStory(id); }

  // ---- message journey ----
  function fmtMs(ms) { return ms < 1000 ? ms + " ms" : (ms < 60000 ? (ms / 1000).toFixed(1) + " s" : Math.round(ms / 60000) + " min"); }
  function openJourney(id) {
    if (!S || !S.map) return;
    $("flow-msg").textContent = "";
    get("api/flow/journey/" + id + "?ns=" + ns).then(enterJourney).catch(showFlowError);
  }
  // Playback times follow the real durations, but a step never plays shorter than JMIN_MS or longer than
  // JMAX_MS, and a long pause before a step plays as a short beat labelled with its real length.
  function enterJourney(j) {
    var speed = S.J ? S.J.speed : 1, off = 0, prevKey = null, on = { nodes: {}, edges: {} }, steps = j.steps;
    steps.forEach(function (st) {
      var pre = st.gapMs > JLONG_MS ? JGAP_MS : 0, run = Math.min(JMAX_MS, Math.max(JMIN_MS, st.durationMs));
      st.s0 = off; st.p0 = off + pre; st.p1 = st.p0 + run; off = st.p1;
      st.label = st.waitLabel || (st.durationMs > JMAX_MS ? "took " + fmtMs(st.durationMs) + " (shown shortened)" : "");
      var to = st.edge ? canon(st.edge.to) : (st.node ? canon(st.node) : null);
      st.mv = { from: st.edge ? canon(st.edge.from) : prevKey, to: to };
      if (st.edge) { on.nodes[canon(st.edge.from)] = 1; on.nodes[canon(st.edge.to)] = 1; on.edges[canon(st.edge.from) + ">" + canon(st.edge.to)] = 1; }
      if (st.node) on.nodes[canon(st.node)] = 1;
      if (to) prevKey = to;
    });
    // the way from the agent through the gates to Triage has no hop of its own
    if (steps.some(function (st) { return st.kind === "injection"; }) && S.agent && S.triage) {
      var chain = [S.agent, "@injection", "@grounding", "@triage", S.triage];
      chain.forEach(function (n) { on.nodes[n] = 1; });
      for (var i = 0; i < chain.length - 1; i++) on.edges[chain[i] + ">" + chain[i + 1]] = 1;
    }
    S.mode = "journey"; S.paused = false;
    S.J = { data: j, steps: steps, on: on, total: off, vt: 0, playing: true, speed: speed, cur: -1, label: "" };
    renderSteps();
    syncControls();
    drawStatic();
  }
  function renderSteps() {
    var J = S.J, j = J.data, side = $("flow-steps");
    side.textContent = "";
    side.appendChild(el("h3", "Message " + j.headerId + ": " + j.decision + ", " + OUT_LABEL[j.outcome]));
    var more = el("a", "Open the full story", "m");
    more.href = "#";
    more.addEventListener("click", function (e) { e.preventDefault(); openStory(j.id); });
    side.appendChild(more);
    var ol = el("ol");
    J.steps.forEach(function (st, i) {
      var li = el("li", null, "s-" + st.status);
      li.appendChild(el("div", st.n + ". " + st.title, "t"));
      li.appendChild(el("div", st.text, "x"));
      var m = el("div", null, "m");
      m.appendChild(document.createTextNode(st.at.slice(11, 23) + " UTC · " + (st.open ? "open, " : "") + fmtMs(st.durationMs) + (st.gapMs > 50 ? " · " + fmtMs(st.gapMs) + " after the step before" : "") + " · "));
      if (st.session) {
        var a = el("a", "Visual Trace, session " + st.session);
        a.href = j.traceUrl + st.session; a.target = "_blank"; a.rel = "noopener";
        a.addEventListener("click", function (e) { e.stopPropagation(); });
        m.appendChild(a);
      }
      li.appendChild(m);
      if (st.waitLabel) li.appendChild(chip(st.waitLabel, "warn"));
      li.addEventListener("click", function () { jumpTo(i); });
      ol.appendChild(li);
    });
    side.appendChild(ol);
  }
  function jumpTo(i) {
    var J = S.J;
    if (!J) return;
    i = Math.max(0, Math.min(J.steps.length - 1, i));
    J.vt = J.steps[i].p0; J.playing = false; syncControls();
  }
  function stepXY(st, f, prevXY) {
    var mv = st.mv, g = mv.from && mv.to && mv.from !== mv.to ? geom(mv.from, mv.to) : null;
    if (g) return bez(g, f);
    var p = mv.to && S.pos[mv.to];
    if (!p) return prevXY;
    var q = mv.from && S.pos[mv.from];
    return q && mv.from !== mv.to ? [q.x + (p.x - q.x) * f, q.y + (p.y - q.y) * f] : [p.x, p.y];
  }
  function journeyFrame(dt) {
    var J = S.J;
    if (!J || !S.map) return;
    if (J.playing) {
      J.vt += dt * J.speed;
      if (J.vt >= J.total) { J.vt = J.total; J.playing = false; syncControls(); }
    }
    var c = 0;
    for (var i = 0; i < J.steps.length; i++) if (J.vt >= J.steps[i].s0) c = i;
    var st = J.steps[c];
    if (c !== J.cur) {
      J.cur = c;
      var items = $("flow-steps").querySelectorAll("li");
      for (var k = 0; k < items.length; k++) { items[k].classList.toggle("cur", k === c); items[k].classList.toggle("done", k < c); }
      if (items[c] && items[c].scrollIntoView) items[c].scrollIntoView({ block: "nearest" });
      drawStatic();
    }
    var f = st.p1 > st.p0 ? Math.max(0, Math.min(1, (J.vt - st.p0) / (st.p1 - st.p0))) : 1;
    var prevXY = c > 0 ? stepXY(J.steps[c - 1], 1, null) : null, xy = stepXY(st, f, prevXY);
    var reached = J.steps.some(function (x, n) { return n <= c && x.kind === "triage"; });
    var label = J.vt <= st.p1 && st.label ? st.label : "";
    if (label !== J.label) { J.label = label; $("flow-jlabel").textContent = label; $("flow-jlabel").classList.toggle("hidden", !label); }
    var dots = xy ? [{ value: xy, sid: "journey", itemStyle: { color: reached ? OUT_COLOR[J.data.outcome] : INFLIGHT, borderColor: st.status === "bad" ? "#b42318" : "#ffffff", borderWidth: 2 } }] : [];
    S.dots = dots;
    if (charts.flow) charts.flow.setOption({ series: [{ id: "dots", data: dots, symbolSize: 12 }] });
    $("flow-wait").classList.add("hidden");
    $("flow-clock").textContent = "step " + (c + 1) + " of " + J.steps.length;
  }

  // ---- controls ----
  function syncControls() {
    var jr = S.mode === "journey";
    $("flow-pause").textContent = S.paused ? "Play" : "Pause";
    $("flow-speed").textContent = S.speed + "x";
    $("flow-live").classList.toggle("hidden", S.mode === "live");
    $("flow-lbar").classList.toggle("hidden", jr);
    $("flow-jbar").classList.toggle("hidden", !jr);
    $("flow-slide-box").classList.toggle("hidden", jr);
    $("flow-steps").classList.toggle("hidden", !jr);
    $("flow-jlabel").classList.toggle("hidden", !jr || !S.J || !S.J.label);
    var wasJr = $("flow-main").classList.contains("journey");
    $("flow-main").classList.toggle("journey", jr);
    var md = $("flow-mode");
    md.textContent = jr ? "Message journey" : (S.mode === "window" ? "Live: history window" : (S.paused ? "Live: paused" : "Live"));
    md.className = "tag flow-mode t-" + (jr ? "warn" : (S.paused ? "other" : "good"));
    if (jr) {
      $("fj-play").textContent = S.J && S.J.playing ? "Pause" : "Play";
      $("fj-speed").textContent = (S.J ? S.J.speed : 1) + "x";
    }
    // the map changes width when the step list opens or closes
    if (wasJr !== jr && charts.flow) setTimeout(function () { charts.flow.resize(); if (S.map) { layout(); drawStatic(); } }, 0);
  }
  function goLive() {
    $("flow-slider").value = SLIDER_S; $("flow-slider-label").textContent = "now";
    restart();
  }
  // Fresh state, then the map and the last minutes; the live poll takes over from there
  function restart() {
    reset(); S.vt = serverNow() - LAG_MS;
    newHops = 0;
    syncControls();
    Promise.all([loadMap(), prefill()]).then(function () { status(0); renderSide(); syncControls(); }).catch(showFlowError);
  }
  function sliderLabel(ago) { return ago < 2 ? "now" : "-" + Math.floor(ago / 60) + ":" + ("0" + (ago % 60)).slice(-2); }
  function sliderChanged() {
    var v = +$("flow-slider").value;
    if (v >= SLIDER_S - 2) { goLive(); return; }
    var ago = SLIDER_S - v;
    var from = new Date(serverNow() - ago * 1000), to = new Date(from.getTime() + WINDOW_S * 1000);
    reset();
    S.mode = "window"; S.vt = from.getTime(); S.windowEnd = to.getTime();
    get("api/flow/window?ns=" + ns + "&from=" + stamp(from) + "&to=" + stamp(to) + evalParam()).then(function (r) {
      S.map = r.map; layout(); mergeSlice(r); S.cursor = null; renderSide(); syncControls();
      $("flow-msg").textContent = r.capped ? "This window has more rows than the view shows (capped at 200 per kind)." : "";
    }).catch(showFlowError);
  }
  function showFlowError(e) { $("flow-msg").textContent = "Flow: " + e.message; }

  function burst(confirm) {
    var n = +$("burst-n").value, mode = $("burst-mode").value, msg = $("burst-msg");
    msg.className = "msg"; msg.textContent = "";
    $("burst-confirm").classList.add("hidden");
    send("POST", "api/burst", { n: n, mode: mode, ns: ns, confirm: !!confirm }).then(function (r) {
      msg.className = "msg ok"; msg.textContent = "Sent " + r.sent.length + " " + r.mode + " messages" + (r.estimatedCostUsd ? ", about " + money(r.estimatedCostUsd, 4) : ", no LLM cost") + ".";
    }).catch(function (e) {
      msg.className = "msg bad"; msg.textContent = e.message;
      if (/costs about/.test(e.message)) $("burst-confirm").classList.remove("hidden");
    });
  }

  function buildLegend() {
    var lg = $("flow-legend"); lg.textContent = "";
    [["In flight", INFLIGHT]].concat(OUT_ORDER.map(function (k) { return [OUT_LABEL[k], OUT_COLOR[k]]; })).forEach(function (x) {
      var s = el("span", null, "lg"), d = el("i"); d.style.background = x[1];
      s.appendChild(d); s.appendChild(document.createTextNode(x[0])); lg.appendChild(s);
    });
  }

  function start() {
    box = $("ch-flow");
    buildLegend();
    $("flow-ns").addEventListener("change", function (e) { ns = e.target.value; restart(); });
    $("flow-pause").addEventListener("click", function () {
      S.paused = !S.paused; syncControls();
      if (S.paused) $("flow-status").textContent = "paused at " + new Date().toLocaleTimeString("en-GB") + ": the view is frozen, new rows are fetched again on Play";
    });
    $("flow-speed").addEventListener("click", function () { S.speed = S.speed === 1 ? 2 : 1; syncControls(); });
    $("fj-play").addEventListener("click", function () {
      var J = S.J;
      if (!J) return;
      if (!J.playing && J.vt >= J.total) J.vt = 0;
      J.playing = !J.playing; syncControls();
    });
    $("fj-back").addEventListener("click", function () { if (S.J) jumpTo(S.J.cur - 1); });
    $("fj-fwd").addEventListener("click", function () { if (S.J) jumpTo(S.J.cur + 1); });
    $("fj-speed").addEventListener("click", function () {
      var J = S.J;
      if (J) { J.speed = J.speed === 1 ? 2 : (J.speed === 2 ? 4 : 1); syncControls(); }
    });
    $("flow-live").addEventListener("click", goLive);
    $("flow-slider").addEventListener("input", function () { $("flow-slider-label").textContent = sliderLabel(SLIDER_S - $("flow-slider").value); });
    $("flow-slider").addEventListener("change", sliderChanged);
    $("burst-go").addEventListener("click", function () { burst(false); });
    $("burst-confirm").addEventListener("click", function () { burst(true); });
    $("burst-mode").addEventListener("change", function () {
      var live = $("burst-mode").value === "live";
      $("burst-n").max = live ? 10 : 30; if (live && +$("burst-n").value > 10) $("burst-n").value = 10;
      $("burst-confirm").classList.add("hidden");
    });
    // The dashboard's own handler has already updated includeEval
    $("incl-eval").addEventListener("change", function () { if (active && S) { loadMap().then(renderSide).catch(showFlowError); } });
    window.addEventListener("resize", function () { if (active && S && S.map) { layout(); drawStatic(); } });
    reset();
  }

  // Called by the dashboard when a tab is shown
  window.flowShow = function (name) {
    var on = name === "flow";
    if (!box) start();
    if (on === active) return;
    active = on;
    if (!on) { clearInterval(timer); timer = null; return; }
    get("api/settings/productions").then(function (r) { $("burst-box").classList.toggle("hidden", !r.canEdit); }).catch(function () {});
    if (!S.map) restart(); else { layout(); drawStatic(); syncControls(); }
    S.wall = Date.now();
    if (!raf) frame();
    // Counters change slowly: one map refresh every 10 s, the rows every second
    timer = setInterval(function () {
      poll();
      if (S.mode === "live" && !S.paused && Date.now() - mapAt > 10000) { mapAt = Date.now(); loadMap().catch(function () {}); }
    }, POLL_MS);
  };
  var sel = document.querySelector(".tabs button[aria-selected=true]");
  if (sel) window.flowShow(sel.dataset.tab);
})();
