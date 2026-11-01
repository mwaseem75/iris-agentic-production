"use strict";
// AI Hub Workbench tab: Library of the AI Hub classes, Playground (placeholder) and a read-only
// map of what a production uses. Nothing here changes IRIS. Needs el, get from the dashboard script.
(function () {
  var root = document.getElementById("wb-root");
  if (!root) return;
  var started = false, lib = null, libType = "all", libQuery = "", mapData = null, mapSel = "";

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
  function usd(n) { return "$" + Number(n || 0).toFixed(4); }

  // ---- shell ---------------------------------------------------------------------------------
  var subs = {}, panels = {};
  var head = div("wb-sub");
  [["lib", "books", "Library"], ["play", "player-play", "Playground"], ["prod", "route", "In productions"]].forEach(function (t) {
    var a = el("a", null, "wb-subtab"); a.href = "#";
    a.appendChild(icon(t[1], "me-1")); a.appendChild(document.createTextNode(t[2]));
    a.addEventListener("click", function (e) { e.preventDefault(); showSub(t[0]); });
    head.appendChild(a); subs[t[0]] = a;
  });
  root.appendChild(head);
  ["lib", "play", "prod"].forEach(function (k) { panels[k] = div("wb-panel hidden"); root.appendChild(panels[k]); });

  function showSub(name) {
    Object.keys(subs).forEach(function (k) {
      subs[k].classList.toggle("on", k === name);
      panels[k].classList.toggle("hidden", k !== name);
    });
    try { localStorage.setItem("agenticprod.wbsub", name); } catch (e) {}
    if (name === "prod" && !mapData) loadProductions();
  }

  // ---- library -------------------------------------------------------------------------------
  panels.lib.innerHTML = "";
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
    c.appendChild(div("wb-d", item.description || ""));
    if (item.tools && item.tools.length) c.appendChild(div("wb-d wb-tools", item.tools.join(" · ")));
    var u = div("wb-u");
    if (g.type === "tool") u.appendChild(el("span", item.readOnly ? "read-only" : "can change data", "wb-tag " + (item.readOnly ? "ro" : "rw")));
    if (g.type === "agent") u.appendChild(document.createTextNode(item.model + " · " + item.toolsets + " toolset · " + item.skills + " skills" + (item.hostedBy ? " · run by " + item.hostedBy : "")));
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
    if (item.description) body.appendChild(div("wb-d", item.description));
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

  // ---- in productions ------------------------------------------------------------------------
  var prodBar = div("wb-bar"), pick = el("select", null, "form-select wb-pick");
  var runBadge = el("span", null, "badge"), statAi = el("span", null, "wb-stat"), stat24 = el("span", null, "wb-stat");
  var prodNote = div("wb-note"), grid = div("wb-mapgrid"), cv = div("wb-cv"), side = div("wb-side");
  prodBar.appendChild(el("span", "Production", "text-secondary")); prodBar.appendChild(pick); prodBar.appendChild(runBadge);
  prodBar.appendChild(statAi); prodBar.appendChild(stat24);
  prodBar.appendChild(div("wb-hint", "Read-only map · change components in the Library"));
  grid.appendChild(cv); grid.appendChild(side);
  panels.prod.appendChild(prodBar); panels.prod.appendChild(prodNote); panels.prod.appendChild(grid);
  pick.addEventListener("change", function () {
    var v = pick.value.split("|"); openProduction(v[0], v.slice(1).join("|"));
  });

  function loadProductions() {
    prodNote.textContent = "Loading…";
    get("api/workbench/productions").then(function (d) {
      clear(pick);
      var first = "";
      d.productions.forEach(function (ns) {
        ns.productions.forEach(function (p) {
          var o = el("option", ns.namespace + " · " + p.name); o.value = ns.namespace + "|" + p.name;
          if (!first || p.current && !/\|AgenticProd\./.test(first)) first = o.value;
          if (p.name === "AgenticProd.Production") first = o.value;
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
      drawMap(d); showSide(null);
    }).catch(function (e) { prodNote.textContent = "Could not load the production: " + e.message; });
  }

  // Layers by distance from the items nothing sends to; cycles stop at the first visit
  function layers(d) {
    var layer = {}, out = {}, hasIn = {};
    d.connections.forEach(function (c) { (out[c.from] = out[c.from] || []).push(c.to); hasIn[c.to] = true; });
    var queue = [];
    d.items.forEach(function (i) { if (!hasIn[i.name]) { layer[i.name] = 0; queue.push(i.name); } });
    d.items.forEach(function (i) { if (layer[i.name] === undefined) { layer[i.name] = 0; queue.push(i.name); } });
    var seen = {};
    while (queue.length) {
      var n = queue.shift(); if (seen[n]) continue; seen[n] = 1;
      (out[n] || []).forEach(function (t) { if (!seen[t] && layer[t] !== undefined && layer[t] <= layer[n]) { layer[t] = layer[n] + 1; queue.push(t); } });
    }
    return layer;
  }

  var NW = 210, NH = 92, HW = 340, GAPX = 90, GAPY = 36;

  function nodeBox(it, host) {
    var n = div("wb-n-node" + (host ? " wb-host" : it.ai ? " wb-ainode" : it.checks ? " wb-chk" : " wb-plain"));
    n.dataset.name = it.name;
    var tagText = host ? "AI HUB" : it.ai ? "AI HUB" : it.checks ? "checks around the agent" : "no AI Hub";
    n.appendChild(el("span", tagText, "wb-tagpill" + (host || it.ai ? " hub" : "")));
    var h = div("wb-nh"); h.appendChild(icon(host ? "robot" : (it.checks ? "shield-half" : TYPE_ICON[it.type] || "box")));
    var t = div(); t.appendChild(div("wb-nt", it.name));
    t.appendChild(div("wb-nk", host ? "Operation " + host.operation + " · agent " + host.agentClass : it.type + " · " + it["class"]));
    h.appendChild(t); n.appendChild(h);
    var m = div("wb-nm");
    if (host) {
      var u = host.usage;
      [[u.runs, "runs"], [u.toolCalls, "tool calls"], [u.tokens, "tokens"]].forEach(function (p) { var s = el("span"); s.appendChild(el("b", num(p[0]))); s.appendChild(document.createTextNode(" " + p[1])); m.appendChild(s); });
      var c = el("span"); c.appendChild(el("b", usd(u.costUsd))); m.appendChild(c);
    } else {
      var s1 = el("span"); s1.appendChild(el("b", num(it.in24h))); s1.appendChild(document.createTextNode(" in")); m.appendChild(s1);
      if (it.errors24h) { var s2 = el("span", null, "wb-e"); s2.appendChild(el("b", num(it.errors24h))); s2.appendChild(document.createTextNode(" errors")); m.appendChild(s2); }
      if (it.suspended) { var s3 = el("span", null, "wb-e"); s3.appendChild(el("b", num(it.suspended))); s3.appendChild(document.createTextNode(" suspended")); m.appendChild(s3); }
    }
    n.appendChild(m);
    if (!it.enabled) n.classList.add("wb-off");
    return n;
  }

  function path(x1, y1, x2, y2, col, dash) {
    var m = (x1 + x2) / 2;
    var p = document.createElementNS("http://www.w3.org/2000/svg", "path");
    p.setAttribute("d", "M" + x1 + "," + y1 + " C" + m + "," + y1 + " " + m + "," + y2 + " " + x2 + "," + y2);
    p.setAttribute("fill", "none"); p.setAttribute("stroke", col); p.setAttribute("stroke-width", dash ? 1.6 : 2);
    if (dash) p.setAttribute("stroke-dasharray", "6 6");
    return p;
  }

  function drawMap(d) {
    clear(cv);
    var layer = layers(d), cols = {}, pos = {}, maxLayer = 0;
    var hostOf = {}; d.hosts.forEach(function (h) { hostOf[h.item] = h; });
    d.items.forEach(function (i) { var l = layer[i.name] || 0; (cols[l] = cols[l] || []).push(i); maxLayer = Math.max(maxLayer, l); });
    var x = 30, bottom = 0, colW = {};
    for (var l = 0; l <= maxLayer; l++) {
      var list = cols[l] || [], w = NW;
      list.forEach(function (i) { if (hostOf[i.name]) w = Math.max(w, HW); });
      colW[l] = w; var y = 40;
      list.forEach(function (i) { pos[i.name] = { x: x, y: y, w: hostOf[i.name] ? HW : NW, h: NH }; y += NH + GAPY; });
      bottom = Math.max(bottom, y); x += w + GAPX;
    }
    var width = Math.max(x, 900);
    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg.setAttribute("class", "wb-svg");
    cv.appendChild(svg);
    d.items.forEach(function (i) {
      var p = pos[i.name], n = nodeBox(i, hostOf[i.name]);
      n.style.left = p.x + "px"; n.style.top = p.y + "px"; n.style.width = p.w + "px";
      cv.appendChild(n);
    });
    d.connections.forEach(function (c) {
      var a = pos[c.from], b = pos[c.to]; if (!a || !b) return;
      var toAi = hostOf[c.to] || hostOf[c.from];
      var forward = b.x > a.x;
      svg.appendChild(forward ? path(a.x + a.w, a.y + 30, b.x, b.y + 30, toAi ? "#a78bfa" : "#9ca3af")
        : path(a.x, a.y + 60, b.x + b.w, b.y + 60, "#6b7280"));
    });
    // Component strip of each host under the map
    var cy = bottom + 40;
    d.hosts.forEach(function (h) {
      var hp = pos[h.item]; if (!hp) return;
      var perRow = Math.max(4, Math.floor((width - 60) / 122)), count = h.components.length;
      cv.appendChild(el("span", "AI Hub parts of " + h.item, "wb-strip-title")).style.top = (cy - 28) + "px";
      h.components.forEach(function (c, idx) {
        var k = KIND[c.kind], col = idx % perRow, row = Math.floor(idx / perRow);
        var cx = 30 + col * 122, ty = cy + row * 150;
        var comp = div("wb-comp"); comp.dataset.id = c.id;
        comp.style.left = cx + "px"; comp.style.top = ty + "px";
        var circle = div("wb-circle"); circle.style.color = k[2]; circle.appendChild(icon(k[1])); comp.appendChild(circle);
        var lab = div("wb-cl"); lab.appendChild(el("span", k[0], "wb-kind")); lab.appendChild(document.createElement("br")); lab.appendChild(document.createTextNode(c.title));
        comp.appendChild(lab); comp.appendChild(div("wb-cs", c.sub));
        comp.addEventListener("click", function () { mapSel = c.id; Array.prototype.forEach.call(cv.querySelectorAll(".wb-comp"), function (e) { e.classList.toggle("sel", e === comp); }); showSide(c); });
        cv.appendChild(comp);
        var ax = Math.min(Math.max(cx + 56, hp.x + 30), hp.x + hp.w - 30);
        svg.appendChild(path(ax, hp.y + hp.h, cx + 56, ty, "#7b8291", true));
      });
      cy += Math.ceil(count / perRow) * 150 + 40;
    });
    var h2 = Math.max(cy, 520);
    cv.style.height = h2 + "px"; svg.setAttribute("width", width); svg.setAttribute("height", h2); svg.style.width = width + "px";
    cv.style.minWidth = "0";
  }

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
    if (name !== "workbench") return;
    if (!started) {
      started = true; loadLib();
      var sub = "lib"; try { sub = localStorage.getItem("agenticprod.wbsub") || "lib"; } catch (e) {}
      showSub(subs[sub] ? sub : "lib");
    }
  };
  // Read-only view for checks from the console
  window.workbenchState = function () { return { library: lib && Object.keys(lib).map(function (k) { return k + ":" + lib[k].length; }), production: mapData && mapData.name, selected: mapSel }; };
  var active = document.querySelector("#nav .nav-link.active");
  if (active) window.workbenchShow(active.dataset.tab);
})();
