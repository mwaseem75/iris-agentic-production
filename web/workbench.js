"use strict";
// AI Hub Workbench: Library of the AI Hub classes, Playground (placeholder) and a read-only
// map of what a production uses. Nothing here changes IRIS. Needs el, get from the dashboard script.
(function () {
  var panels = { lib: document.getElementById("wb-lib"), play: document.getElementById("wb-play"), prod: document.getElementById("wb-prod") };
  if (!panels.lib || !panels.play || !panels.prod) return;
  var TAB = { lib: "wblib", play: "wbplay", prod: "wbprod" };
  var started = false, lib = null, libType = "all", libQuery = "", mapData = null, mapSel = "", mapRes = null;

  // Library groups in page order; key is the field in /workbench/library
  var GROUPS = [
    { key: "agents", type: "agent", title: "Agents", sub: "%AI.Agent · model, instructions, tools, skills", icon: "robot", cls: "agent" },
    { key: "toolsets", type: "tool", title: "Tools", sub: "%AI.ToolSet · what the agent may call", icon: "tool", cls: "tool" },
    { key: "skills", type: "skill", title: "Skills", sub: "%AI.Agent.Skill · instructions and tools loaded when needed", icon: "puzzle", cls: "skill" },
    { key: "policies", type: "policy", title: "Policies", sub: "%AI.Policy · checked by AI Hub on every tool call", icon: "lock", cls: "pol" },
    { key: "knowledge", type: "knowledge", title: "Knowledge", sub: "%AI.RAG · IRIS vector search", icon: "database-search", cls: "kb" },
    { key: "checks", type: "check", title: "Checks around the agent", sub: "plain IRIS code, not AI Hub · run after the answer", icon: "shield-half", cls: "chk" }
  ];
  var FILTERS = [["all", "All"], ["agent", "Agents"], ["tool", "Tools"], ["skill", "Skills"], ["policy", "Policies"], ["knowledge", "Knowledge"], ["check", "Checks"]];
  var KIND = { model: ["Model", "cpu", "#a78bfa"], toolset: ["ToolSet", "tool", "#60a5fa"], skill: ["Skill", "puzzle", "#c4b5fd"], knowledge: ["Knowledge", "database-search", "#34d399"], policy: ["Policy", "lock", "#f87171"] };
  var TYPE_ICON = { service: "file-import", process: "arrows-split", operation: "send", other: "box" };

  function icon(name, extra) { return el("i", null, "ti ti-" + name + (extra ? " " + extra : "")); }
  function div(cls, text) { return el("div", text, cls); }
  function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); }
  function num(n) { return Number(n || 0).toLocaleString("en-US"); }
  // One full stop at the end, none doubled
  function tidy(t) { return String(t || "").replace(/\s*\.{2}(?!\.)/g, ".").replace(/\.\s*\.(?=\s|$)/g, "."); }
  function usd(n) { return "$" + Number(n || 0).toFixed(4); }
  function short(n) { var p = String(n || "").split("."); return p[p.length - 1]; }

  // ---- shell ---------------------------------------------------------------------------------
  // The sidebar owns the three views; showSub only asks the dashboard to switch tab
  function showSub(name) { if (window.showTab) window.showTab(TAB[name]); }

  // ---- library -------------------------------------------------------------------------------
  var libBar = div("wb-bar"), libBody = div("wb-body"), libNote = div("wb-note");
  var search = el("input", null, "form-control wb-search");
  search.placeholder = "Search agents, tools, skills, policies"; search.type = "search";
  search.addEventListener("input", function () { libQuery = search.value.toLowerCase(); renderLib(); });
  var filt = div("btn-group");
  FILTERS.forEach(function (f) {
    var b = el("button", f[1], "btn btn-sm" + (f[0] === "all" ? " active" : "")); b.type = "button"; b.dataset.type = f[0];
    b.addEventListener("click", function () {
      libType = f[0];
      Array.prototype.forEach.call(filt.children, function (c) { c.classList.toggle("active", c.dataset.type === libType); });
      renderLib();
    });
    filt.appendChild(b);
  });
  libBar.appendChild(search); libBar.appendChild(filt);
  libBar.appendChild(div("wb-hint", "Every block is a real IRIS class. Open one to read its source."));
  panels.lib.appendChild(libBar); panels.lib.appendChild(libNote); panels.lib.appendChild(libBody);

  var drawer = div("wb-drawer hidden");
  document.body.appendChild(drawer);

  function loadLib() {
    libNote.textContent = "Loading…";
    get("api/workbench/library").then(function (d) { lib = d; libNote.textContent = ""; renderLib(); })
      .catch(function (e) { libNote.textContent = "Could not load the Library: " + e.message; });
  }

  function matches(item, g) {
    if (libType !== "all" && libType !== g.type) return false;
    if (!libQuery) return true;
    var text = [item.name, item["class"], item.description, item.usedBy].join(" ").toLowerCase();
    return text.indexOf(libQuery) >= 0;
  }

  function card(item, g) {
    var c = div("wb-card"); c.tabIndex = 0;
    var h = div("wb-card-h");
    var ic = div("wb-ic t-" + g.cls); ic.appendChild(icon(g.icon));
    var t = div(); t.appendChild(div("wb-n", item.name)); t.appendChild(div("wb-c", item["class"]));
    h.appendChild(ic); h.appendChild(t); c.appendChild(h);
    c.appendChild(div("wb-d", tidy(item.description)));
    if (item.tools && item.tools.length) c.appendChild(div("wb-d wb-tools", item.tools.join(" · ")));
    var u = div("wb-u");
    if (g.type === "tool") u.appendChild(el("span", item.readOnly ? "read-only" : "can change data", "wb-tag " + (item.readOnly ? "ro" : "rw")));
    if (g.type === "agent") u.appendChild(document.createTextNode(item.model + " · " + item.toolsets + " toolset · " + item.skills + " skills" + (item.hostedBy ? " · used by operation " + item.hostedBy : "")));
    else if (item.usedBy) u.appendChild(document.createTextNode((g.type === "tool" ? " " : "") + item.usedBy));
    if (g.type === "check") u.insertBefore(el("span", "plain IRIS", "wb-tag"), u.firstChild);
    c.appendChild(u);
    var open = function () { openDrawer(item, g); };
    c.addEventListener("click", open);
    c.addEventListener("keydown", function (e) { if (e.key === "Enter") open(); });
    return c;
  }

  function renderLib() {
    clear(libBody);
    if (!lib) return;
    var shown = 0;
    GROUPS.forEach(function (g) {
      var items = (lib[g.key] || []).filter(function (i) { return matches(i, g); });
      if (!items.length) return;
      shown += items.length;
      var h = el("h4", null, "wb-h4"); h.appendChild(icon(g.icon));
      h.appendChild(document.createTextNode(g.title)); h.appendChild(el("span", g.sub, "wb-ex"));
      libBody.appendChild(h);
      var grid = div("wb-grid");
      items.forEach(function (i) { grid.appendChild(card(i, g)); });
      libBody.appendChild(grid);
    });
    if (!shown) libBody.appendChild(div("wb-note", "Nothing matches."));
  }

  function kv(label, value) {
    var r = div("wb-kv"); r.appendChild(el("span", label));
    var v = el("span"); if (value instanceof Node) v.appendChild(value); else v.textContent = value; r.appendChild(v);
    return r;
  }

  function chips(list) {
    var w = div("wb-chips");
    (list || []).forEach(function (t) { w.appendChild(el("span", t, "wb-chip")); });
    return w;
  }

  function closeDrawer() { drawer.classList.add("hidden"); }

  function openDrawer(item, g) {
    clear(drawer); drawer.classList.remove("hidden");
    var top = div("wb-drawer-h");
    var t = div(); t.appendChild(div("wb-n", item.name)); t.appendChild(div("wb-c", item["class"]));
    var x = el("button", null, "btn btn-icon btn-ghost-secondary"); x.type = "button"; x.setAttribute("aria-label", "Close");
    x.appendChild(icon("x")); x.addEventListener("click", closeDrawer);
    top.appendChild(t); top.appendChild(x); drawer.appendChild(top);
    var body = div("wb-drawer-b");
    if (item.description) body.appendChild(div("wb-d", tidy(item.description)));
    if (item.toolDescriptions) {
      item.tools.forEach(function (name, i) {
        var r = div("wb-tool"); r.appendChild(el("b", name)); r.appendChild(div("wb-d", item.toolDescriptions[i] || ""));
        body.appendChild(r);
      });
    } else if (item.tools && item.tools.length) body.appendChild(kv("Adds tools", chips(item.tools)));
    if (item.usedBy) body.appendChild(kv("Used by", item.usedBy.replace(/^used by /, "")));
    if (g.type === "knowledge") {
      body.appendChild(div("wb-note", "Built by Setup from the LOINC subset; the search runs on local vectors."));
    } else {
      var src = el("pre", "Loading the source…", "wb-src"); body.appendChild(src);
      get("api/workbench/source?class=" + encodeURIComponent(item["class"])).then(function (d) { src.textContent = d.source || "(no source)"; })
        .catch(function () { src.textContent = "The source is not available."; });
    }
    drawer.appendChild(body);
  }

  // ---- playground ----------------------------------------------------------------------------
  (function () {
    var c = div("wb-empty");
    c.appendChild(icon("player-play", "wb-empty-ic"));
    c.appendChild(div("fw-bold", "Playground"));
    c.appendChild(div("wb-d", "Run one agent on one message and watch each step. Coming in a later step of the Workbench."));
    panels.play.appendChild(c);
  })();

  // ---- production map ------------------------------------------------------------------------
  var prodBar = div("wb-bar"), pick = el("select", null, "form-select wb-pick");
  var runBadge = el("span", null, "badge"), statAi = el("span", null, "wb-stat"), stat24 = el("span", null, "wb-stat");
  var prodNote = div("wb-note"), grid = div("wb-mapgrid"), cv = div("wb-cv"), side = div("wb-side");
  prodBar.appendChild(el("span", "Production", "text-secondary")); prodBar.appendChild(pick); prodBar.appendChild(runBadge);
  prodBar.appendChild(statAi); prodBar.appendChild(stat24);
  prodBar.appendChild(div("wb-hint", "Read-only map · change components in the Library"));
  var wrap = div("wb-cvwrap"), zoomBar = div("wb-zoom");
  [["zoom-in", function () { zoom(1.2); }, "Zoom in"], ["zoom-out", function () { zoom(1 / 1.2); }, "Zoom out"], ["arrows-maximize", function () { fit(); }, "Fit to screen"]].forEach(function (z) {
    var b = el("button", null, "btn btn-sm btn-icon"); b.type = "button"; b.title = z[2]; b.setAttribute("aria-label", z[2]); b.appendChild(icon(z[0]));
    b.addEventListener("click", z[1]); zoomBar.appendChild(b);
  });
  wrap.appendChild(cv); wrap.appendChild(zoomBar);
  wrap.appendChild(div("wb-legend", "Solid line: message path · dashed: AI Hub part used by the agent · green: back to the router"));
  grid.appendChild(wrap); grid.appendChild(side);
  panels.prod.appendChild(prodBar); panels.prod.appendChild(prodNote); panels.prod.appendChild(grid);
  pick.addEventListener("change", function () {
    var v = pick.value.split("|"); openProduction(v[0], v.slice(1).join("|"));
  });
  window.addEventListener("resize", function () {
    if (panels.prod.classList.contains("hidden") || mapRes) return;
    mapRes = setTimeout(function () { mapRes = null; fit(); }, 150);
  });

  function loadProductions() {
    prodNote.textContent = "Loading…";
    get("api/workbench/productions").then(function (d) {
      clear(pick);
      var first = "";
      d.productions.forEach(function (ns) {
        ns.productions.forEach(function (p) {
          var o = el("option", ns.namespace + " · " + p.name); o.value = ns.namespace + "|" + p.name;
          if (!first || p.name === "AgenticProd.Production") first = o.value;
          pick.appendChild(o);
        });
      });
      if (!first) { prodNote.textContent = "No production found."; return; }
      prodNote.textContent = ""; pick.value = first;
      var v = first.split("|"); openProduction(v[0], v.slice(1).join("|"));
    }).catch(function (e) { prodNote.textContent = "Could not load the productions: " + e.message; });
  }

  function openProduction(ns, name) {
    prodNote.textContent = "Loading…"; clear(cv); mapSel = "";
    get("api/workbench/production?ns=" + encodeURIComponent(ns) + "&name=" + encodeURIComponent(name)).then(function (d) {
      mapData = d; prodNote.textContent = "";
      var crumb = document.getElementById("crumb"); if (crumb) crumb.textContent = d.namespace + " · " + d.name;
      runBadge.textContent = d.running ? "running" : "stopped";
      runBadge.className = "badge " + (d.running ? "bg-green-lt" : "bg-secondary-lt");
      clear(statAi);
      statAi.appendChild(el("b", d.aiItems)); statAi.appendChild(document.createTextNode(" of " + d.totalItems + " items use AI Hub"));
      var u = d.usage24h; clear(stat24);
      stat24.appendChild(document.createTextNode("Last 24 h: "));
      [[u.runs, " agent runs"], [u.toolCalls, " tool calls"], [u.denied, " denied"]].forEach(function (p) {
        stat24.appendChild(el("b", num(p[0]))); stat24.appendChild(document.createTextNode(p[1] + " · "));
      });
      stat24.appendChild(el("b", usd(u.costUsd)));
      drawMap(d);
    }).catch(function (e) { prodNote.textContent = "Could not load the production: " + e.message; });
  }

  var NW = 210, NH = 92, HW = 340, HH = 100, GAPX = 90, GAPY = 36, CW = 122;
  var stage = null, scale = 1, stageW = 0, stageH = 0;

  function nodeBox(it, host, small) {
    var n = div("wb-n-node" + (host ? " wb-host" : it.ai ? " wb-ainode" : it.checks ? " wb-chk" : " wb-plain") + (small ? " wb-small" : ""));
    n.dataset.name = it.name;
    n.title = it.name + " · " + it["class"];
    if (!small) n.appendChild(el("span", host || it.ai ? "AI HUB" : it.checks ? "checks around the agent" : "no AI Hub", "wb-tagpill" + (host || it.ai ? " hub" : "")));
    var h = div("wb-nh"); h.appendChild(icon(host ? "robot" : (it.checks ? "shield-half" : TYPE_ICON[it.type] || "box")));
    var t = div("wb-nx"); t.appendChild(div("wb-nt", short(it.name)));
    t.appendChild(div("wb-nk", host ? "Operation " + short(host.operation) + " · agent " + short(host.agentClass) : it.type + " · " + short(it["class"])));
    h.appendChild(t); n.appendChild(h);
    if (!it.enabled) n.classList.add("wb-off");
    if (small) return n;
    var m = div("wb-nm");
    if (host) {
      var u = host.usage;
      [[u.runs, "runs"], [u.toolCalls, "tool calls"], [u.tokens, "tokens"]].forEach(function (p) { var s = el("span"); s.appendChild(el("b", num(p[0]))); s.appendChild(document.createTextNode(" " + p[1])); m.appendChild(s); });
      var c = el("span"); c.appendChild(el("b", usd(u.costUsd))); m.appendChild(c);
    } else {
      var svc = it.type === "service", s1 = el("span"); s1.appendChild(el("b", num(svc ? it.sent24h : it.in24h))); s1.appendChild(document.createTextNode(svc ? " sent" : " in")); m.appendChild(s1);
      if (it.errors24h) { var s2 = el("span", null, "wb-e"); s2.appendChild(el("b", num(it.errors24h))); s2.appendChild(document.createTextNode(" errors")); m.appendChild(s2); }
      if (it.suspended) { var s3 = el("span", null, "wb-e"); s3.appendChild(el("b", num(it.suspended))); s3.appendChild(document.createTextNode(" suspended")); m.appendChild(s3); }
    }
    n.appendChild(m);
    return n;
  }

  function curve(dd, col, dash) {
    var p = document.createElementNS("http://www.w3.org/2000/svg", "path");
    p.setAttribute("d", dd); p.setAttribute("fill", "none"); p.setAttribute("stroke", col); p.setAttribute("stroke-width", dash ? 1.6 : 2);
    if (dash) p.setAttribute("stroke-dasharray", "6 6");
    return p;
  }
  function hpath(x1, y1, x2, y2, col) {
    var m = (x1 + x2) / 2;
    return curve("M" + x1 + "," + y1 + " C" + m + "," + y1 + " " + m + "," + y2 + " " + x2 + "," + y2, col);
  }
  function vpath(x1, y1, x2, y2, col, dash) {
    var m = (y1 + y2) / 2;
    return curve("M" + x1 + "," + y1 + " C" + x1 + "," + m + " " + x2 + "," + m + " " + x2 + "," + y2, col, dash);
  }

  // Main path: items reachable from the sources without entering Triage or an agent host; they sit in
  // lanes by role (services, routing processes, operations).
  // Branch: Triage first, then the hosts, then what they send to. Items with no links go to a strip.
  function plan(d) {
    var byName = {}, hostOf = {}, out = {}, hasIn = {}, linked = {};
    d.items.forEach(function (i) { byName[i.name] = i; });
    d.hosts.forEach(function (h) { hostOf[h.item] = h; });
    d.connections.forEach(function (c) {
      if (!byName[c.from] || !byName[c.to]) return;
      (out[c.from] = out[c.from] || []).push(c.to); hasIn[c.to] = true; linked[c.from] = linked[c.to] = true;
    });
    // A process that sends to an agent host belongs to the failure branch with it
    var caller = {};
    d.connections.forEach(function (c) { if (hostOf[c.to] && byName[c.from] && byName[c.from].type === "process") caller[c.from] = true; });
    var special = function (i) { return !!(hostOf[i.name] || i.checks || caller[i.name]); };
    var depth = {}, queue = [];
    d.items.forEach(function (i) { if (linked[i.name] && !special(i) && !hasIn[i.name]) { depth[i.name] = 0; queue.push(i.name); } });
    if (!queue.length) d.items.forEach(function (i) { if (!queue.length && linked[i.name] && !special(i)) { depth[i.name] = 0; queue.push(i.name); } });
    queue.forEach(function (n) {
      (out[n] || []).forEach(function (t) {
        if (depth[t] === undefined && !special(byName[t])) { depth[t] = depth[n] + 1; queue.push(t); }
      });
    });
    var seen = {}, order = [];
    var bq = d.items.filter(special).map(function (i) { return i.name; });
    bq.forEach(function (n) {
      if (seen[n]) return; seen[n] = 1; order.push(byName[n]);
      (out[n] || []).forEach(function (t) { if (depth[t] === undefined && !seen[t]) bq.push(t); });
    });
    var rank = function (i) { return hostOf[i.name] ? 1 : (i.checks || caller[i.name]) ? 0 : 2; };
    var branch = order.map(function (i, n) { return { i: i, n: n }; }).sort(function (a, b) { return rank(a.i) - rank(b.i) || a.n - b.n; }).map(function (e) { return e.i; });
    var other = d.items.filter(function (i) { return depth[i.name] === undefined && !seen[i.name]; });
    return { depth: depth, branch: branch, other: other, hostOf: hostOf, byName: byName };
  }

  function drawMap(d) {
    clear(cv); showSide(null);
    var pl = plan(d), pos = {}, hostOf = pl.hostOf;
    stage = div("wb-stage"); cv.appendChild(stage);
    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg.setAttribute("class", "wb-svg");
    stage.appendChild(svg);
    var widthOf = function (i) { return hostOf[i.name] ? HW : NW; }, heightOf = function (i) { return hostOf[i.name] ? HH : NH; };

    // Row 1: the main path by layer
    var cols = {}, maxL = -1, LANE = { service: 0, process: 1, operation: 2 };
    d.items.forEach(function (i) {
      if (pl.depth[i.name] === undefined) return;
      var l = LANE[i.type] === undefined ? 1 : LANE[i.type];
      (cols[l] = cols[l] || []).push(i); maxL = Math.max(maxL, l);
    });
    var x = 30, mainBottom = 0, W = 0;
    for (var l = 0; l <= maxL; l++) {
      if (!cols[l]) continue;
      var y = 40, w = NW;
      cols[l].forEach(function (i) { w = Math.max(w, widthOf(i)); });
      cols[l].forEach(function (i) { pos[i.name] = { x: x, y: y, w: widthOf(i), h: heightOf(i) }; y += heightOf(i) + GAPY; });
      mainBottom = Math.max(mainBottom, y - GAPY); x += w + GAPX; W = x - GAPX + 30;
    }
    // Row 2: the failure branch, starting under the item that sends to it
    var y2 = maxL >= 0 ? mainBottom + 120 : 40, bx = 30, branchBottom = y2;
    if (pl.branch.length) {
      var found = false;
      d.connections.forEach(function (c) { if (!found && c.to === pl.branch[0].name && pos[c.from]) { bx = pos[c.from].x; found = true; } });
    }
    pl.branch.forEach(function (i) {
      pos[i.name] = { x: bx, y: y2, w: widthOf(i), h: heightOf(i) };
      bx += widthOf(i) + GAPX; branchBottom = Math.max(branchBottom, y2 + heightOf(i)); W = Math.max(W, bx - GAPX + 30);
    });
    // Row 3: the parts of each host, centred under it
    var cy = branchBottom + 90, comps = [];
    d.hosts.forEach(function (h) {
      var hp = pos[h.item]; if (!hp) return;
      // One row; the spacing shrinks to fit the width, down to 92 px
      var count = h.components.length, cw = Math.max(92, Math.min(CW, Math.floor((Math.max(W, 900) - 60) / Math.max(1, count))));
      var sx = Math.max(30, hp.x + hp.w / 2 - count * cw / 2);
      W = Math.max(W, sx + count * cw + 30);
      comps.push({ h: h, hp: hp, sx: sx, cw: cw, y: cy });
      cy += 150 + 20;
    });
    // Row 4: items with no links
    if (pl.other.length) {
      var oy = cy + 10, per = Math.max(1, Math.floor((Math.max(W, 900) - 60) / 200));
      pl.other.forEach(function (i, idx) { pos[i.name] = { x: 30 + (idx % per) * 200, y: oy + 28 + Math.floor(idx / per) * 54, w: 186, h: 42, small: true }; });
      cy = oy + 28 + Math.ceil(pl.other.length / per) * 54;
      var ttl = el("span", "Other items", "wb-strip-title"); ttl.style.top = oy + "px"; stage.appendChild(ttl);
    }
    W = Math.max(W, 900);
    var H = cy + 20;

    d.items.forEach(function (i) {
      var p = pos[i.name]; if (!p) return;
      var n = nodeBox(i, hostOf[i.name], p.small);
      n.style.left = p.x + "px"; n.style.top = p.y + "px"; n.style.width = p.w + "px"; n.style.height = p.h + "px";
      stage.appendChild(n);
    });
    d.connections.forEach(function (c) {
      var a = pos[c.from], b = pos[c.to]; if (!a || !b || a.small || b.small) return;
      var col = (hostOf[c.to] || hostOf[c.from]) ? "#a78bfa" : "#9ca3af";
      if (b.y >= a.y + a.h + 30) svg.appendChild(vpath(a.x + a.w * 0.7, a.y + a.h, b.x + b.w * 0.7, b.y, col));
      else if (b.y + b.h + 30 <= a.y) svg.appendChild(vpath(a.x + a.w * 0.3, a.y, b.x + b.w * 0.3, b.y + b.h, "#34d399"));
      else if (b.x > a.x) svg.appendChild(hpath(a.x + a.w, a.y + 30, b.x, b.y + 30, col));
      else svg.appendChild(hpath(a.x, a.y + a.h - 14, b.x + b.w, b.y + b.h - 14, "#6b7280"));
    });
    comps.forEach(function (cg) {
      stage.appendChild(el("span", "AI Hub parts of " + short(cg.h.item), "wb-strip-title")).style.top = (cg.y - 30) + "px";
      cg.h.components.forEach(function (c, idx) {
        var k = KIND[c.kind], cx = cg.sx + idx * cg.cw, ty = cg.y;
        var comp = div("wb-comp"); comp.dataset.id = c.id; comp.title = c.title + " · " + c["class"];
        comp.style.left = cx + "px"; comp.style.top = ty + "px"; comp.style.width = (cg.cw - 6) + "px";
        var circle = div("wb-circle"); circle.style.color = k[2]; circle.appendChild(icon(k[1])); comp.appendChild(circle);
        var lab = div("wb-cl"); lab.appendChild(el("span", k[0], "wb-kind")); lab.appendChild(document.createElement("br")); lab.appendChild(document.createTextNode(c.title));
        comp.appendChild(lab); comp.appendChild(div("wb-cs", c.sub));
        comp.addEventListener("click", function () { mapSel = c.id; Array.prototype.forEach.call(cv.querySelectorAll(".wb-comp"), function (e) { e.classList.toggle("sel", e === comp); }); showSide(c); });
        stage.appendChild(comp);
        var mid = cx + (cg.cw - 6) / 2, ax = Math.min(Math.max(mid, cg.hp.x + 30), cg.hp.x + cg.hp.w - 30);
        svg.appendChild(vpath(ax, cg.hp.y + cg.hp.h, mid, ty, "#7b8291", true));
      });
    });
    stageW = W; stageH = H;
    stage.style.width = W + "px"; stage.style.height = H + "px";
    svg.setAttribute("width", W); svg.setAttribute("height", H); svg.style.width = W + "px";
    fit();
  }

  function applyScale() {
    if (!stage) return;
    stage.style.transform = "scale(" + scale + ")";
    // Taller than the window: the canvas scrolls inside its own box
    var availH = Math.max(360, window.innerHeight - cv.getBoundingClientRect().top - 40);
    cv.style.height = Math.min(Math.ceil(stageH * scale), availH) + "px";
  }

  // Whole map on screen at load: limited by the canvas width and the height left in the window
  function fit() {
    if (!stage) return;
    var availH = Math.max(360, window.innerHeight - cv.getBoundingClientRect().top - 40), availW = cv.clientWidth || stageW;
    // Never below 0.85: past that the labels stop being readable, so the canvas scrolls instead
    scale = Math.max(0.85, Math.min(1, availW / stageW, availH / stageH));
    applyScale();
  }

  function zoom(f) { scale = Math.max(0.3, Math.min(1.6, scale * f)); applyScale(); }

  function showSide(c) {
    clear(side);
    if (!c) {
      var how = div("card"); var b = div("card-body");
      b.appendChild(div("fw-semibold mb-2", "How to read this map"));
      b.appendChild(div("wb-d", "Grey items move messages and do not use AI Hub. The purple card hosts the AI Hub agent; the circles under it are the AI Hub parts it uses. Click a circle to see what it is. Triage is plain IRIS: it checks every agent answer before anything changes."));
      how.appendChild(b); side.appendChild(how); return;
    }
    var k = KIND[c.kind];
    var cardEl = div("card"), b2 = div("card-body");
    var hd = div("wb-sh");
    var av = div("wb-ic"); av.style.color = k[2]; av.appendChild(icon(k[1]));
    var t = div(); t.appendChild(div("fw-bold", c.title)); t.appendChild(div("wb-c", "AI Hub " + k[0]));
    hd.appendChild(av); hd.appendChild(t); b2.appendChild(hd);
    b2.appendChild(kv("Class", el("span", c["class"], "wb-mono")));
    b2.appendChild(kv(c.kind === "skill" ? "When the agent loads it" : "What it is", c.detail || ""));
    if (c.tools && c.tools.length) { b2.appendChild(div("wb-d mt-2", c.kind === "skill" ? "Adds tools" : "Tools")); b2.appendChild(chips(c.tools)); }
    b2.appendChild(kv("Used by", (c.usedBy || []).join(", ")));
    b2.appendChild(kv(c.kind === "model" ? "Agent runs, last 24 h" : "Tool calls, last 24 h", String(c.calls24h || 0)));
    var row = div("d-flex gap-2 mt-3");
    var lb = el("button", null, "btn flex-fill"); lb.type = "button"; lb.appendChild(icon("books", "me-1")); lb.appendChild(document.createTextNode("Open in Library"));
    lb.addEventListener("click", function () { openInLibrary(c); });
    var pb = el("button", null, "btn flex-fill"); pb.type = "button"; pb.appendChild(icon("player-play", "me-1")); pb.appendChild(document.createTextNode("Try in Playground"));
    pb.addEventListener("click", function () { showSub("play"); });
    row.appendChild(lb); row.appendChild(pb); b2.appendChild(row);
    cardEl.appendChild(b2); side.appendChild(cardEl);
  }

  function openInLibrary(c) {
    libType = "all"; libQuery = "";
    search.value = ""; Array.prototype.forEach.call(filt.children, function (b) { b.classList.toggle("active", b.dataset.type === "all"); });
    showSub("lib");
    var find = function () {
      renderLib();
      var hit = null;
      GROUPS.forEach(function (g) { (lib[g.key] || []).forEach(function (i) { if (!hit && i["class"] === c["class"]) hit = [i, g]; }); });
      if (hit) openDrawer(hit[0], hit[1]);
    };
    if (lib) find(); else get("api/workbench/library").then(function (d) { lib = d; find(); });
  }

  // ---- entry ---------------------------------------------------------------------------------
  window.workbenchShow = function (name) {
    var view = "";
    Object.keys(TAB).forEach(function (k) { if (TAB[k] === name) view = k; });
    if (!view) return;
    if (!started) { started = true; loadLib(); }
    if (view === "prod") { if (!mapData) loadProductions(); else fit(); }
  };
  // Read-only view for checks from the console
  window.workbenchState = function () { return { library: lib && Object.keys(lib).map(function (k) { return k + ":" + lib[k].length; }), production: mapData && mapData.name, selected: mapSel, scale: scale }; };
  var active = document.querySelector("#nav .nav-link.active");
  if (active) window.workbenchShow(active.dataset.tab);
})();
