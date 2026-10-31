"use strict";
// AI Studio tab: one agent in the middle of the canvas, what it watches on the left, what it can
// do on the right, what it may use underneath. Every edit goes to the draft (PUT api/studio/draft);
// nothing here touches the production. Needs el, get, send from the dashboard script.
(function () {
  var NEXT = "next step";
  // Port order on the agent node; model is the only required one
  var PORTS = [
    { id: "model", label: "Model", req: true, icon: "cpu", col: "p", title: "Model" },
    { id: "memory", label: "Memory", icon: "brain", col: "g", title: "Add memory", hint: "What the agent remembers." },
    { id: "tools", label: "Tools", icon: "tool", col: "b", title: "Add a tool", hint: "What the agent may look up. All tools are read-only." },
    { id: "skills", label: "Skills", icon: "puzzle", col: "p", title: "Add a skill", hint: "Instructions the agent loads when it needs them." },
    { id: "knowledge", label: "Knowledge", icon: "database-search", col: "g", title: "Add knowledge", hint: "Vector search over your own tables." },
    { id: "guardrails", label: "Guardrails", icon: "shield-lock", col: "r", title: "Add a guardrail", hint: "Rules checked on every tool call." }
  ];
  var OUTS = [
    { id: "fix", label: "auto-fix", icon: "wand", col: "#34d399", title: "Apply fix", sub: "re-send fixed message to LabRouter" },
    { id: "review", label: "map code · escalate", icon: "user-check", col: "#fbbf24", title: "Human review", sub: "Workflow · " },
    { id: "resend", label: "resend", icon: "refresh", col: "#60a5fa", title: "Resend", sub: "when the target is back · max 3" },
    { id: "reject", label: "reject", icon: "ban", col: "#f87171", title: "Reject to sender", sub: "with the reason" }
  ];
  var MODES = [["observe", "Explain"], ["propose", "Propose"], ["act", "Fix safe cases"]];
  var MODE_HELP = {
    observe: "Explain: the agent writes an explanation and changes nothing.",
    propose: "Propose: a person approves every change.",
    act: "Fix safe cases: whitelisted fixes are applied, the rest go to a person."
  };
  var SCENE_H = 800;

  var started = false, catalog = null, canEdit = false, rootEl = null;
  var prods = [], cur = null;              // cur = { ns, name }
  var prod = null, draft = null, savedJson = "", savedAt = "";
  var sel = null, scale = 1, seq = 0;      // sel = { t: "agent" | "trigger" | "out" | "add" | "sub", id, key }

  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]; }); }
  function btn(html, cls, title) {
    var b = el("button", null, "btn btn-sm " + (cls || ""));
    b.type = "button"; b.innerHTML = html;
    if (title) b.title = title;
    return b;
  }
  function stub(b) { b.disabled = true; b.title = NEXT; return b; }
  function hhmm(ts) { return ts ? String(ts).replace("T", " ").substr(11, 5) : ""; }
  function short(c) { return String(c).split(".").pop(); }
  function usd(n) { return "$" + (+n || 0).toFixed(4); }
  function q() { return "?ns=" + encodeURIComponent(cur.ns) + "&name=" + encodeURIComponent(cur.name); }

  // ---- page skeleton ------------------------------------------------------------------------
  function build() {
    rootEl = $("studio-root");
    rootEl.innerHTML =
      '<div class="st-top" id="st-top"></div>' +
      '<div class="st-grid"><div class="st-canvas" id="st-canvas"><div class="st-pan"><div class="st-scene" id="st-scene"></div></div>' +
      '<div class="st-hint" id="st-hint"><i class="ti ti-hand-click me-1"></i>Click any block to change it · use <b>+ Add</b> to give the agent more abilities</div>' +
      '<div class="st-legend"><span><i class="ti ti-minus"></i> message path</span><span><i class="ti ti-line-dashed"></i> what the agent can use</span></div>' +
      '<div class="st-tools" id="st-tools"></div></div>' +
      '<div class="st-side" id="st-side"></div></div>';
    buildTop();
    var t = $("st-tools");
    [["zoom-in", "Zoom in", function () { zoom(scale * 1.15); }], ["zoom-out", "Zoom out", function () { zoom(scale / 1.15); }], ["arrows-maximize", "Fit", fit]].forEach(function (z) {
      var b = btn('<i class="ti ti-' + z[0] + '"></i>', "btn-icon", z[1]);
      b.addEventListener("click", z[2]);
      t.appendChild(b);
    });
    $("st-canvas").addEventListener("click", function (e) { if (e.target === $("st-canvas") || e.target === $("st-scene")) { sel = null; paint(); } });
  }

  function buildTop() {
    var top = $("st-top");
    top.textContent = "";
    top.appendChild(el("h3", "AI Studio", "m-0 me-2"));
    top.appendChild(el("span", "Agent", "text-secondary fw-medium"));
    var ag = el("select", null, "form-select"); ag.id = "st-agent"; ag.style.width = "240px"; ag.style.fontWeight = "600";
    ag.addEventListener("change", function () { pickAgent(ag.value); });
    top.appendChild(ag);
    top.appendChild(el("span", "runs in", "text-secondary fw-medium"));
    var pick = el("select", null, "form-select"); pick.id = "st-pick"; pick.style.width = "300px";
    pick.addEventListener("change", function () { var v = pick.value.split("|"); openProduction(v[0], v.slice(1).join("|")); });
    top.appendChild(pick);
    var chip = el("span", "", "st-run"); chip.id = "st-run";
    top.appendChild(chip);
    top.appendChild(el("span", "", "spacer"));
    var cnt = el("span", "", "st-count"); cnt.id = "st-count";
    top.appendChild(cnt);
    top.appendChild(stub(btn('<i class="ti ti-code me-1"></i>Code')));
    top.appendChild(stub(btn('<i class="ti ti-player-play me-1"></i>Test')));
    var save = btn('<i class="ti ti-device-floppy me-1"></i>Save draft'); save.id = "st-save";
    save.addEventListener("click", saveDraft);
    top.appendChild(save);
    top.appendChild(stub(btn('<i class="ti ti-rocket me-1"></i>Apply', "btn-primary")));
  }

  // ---- data ---------------------------------------------------------------------------------
  function init() {
    build();
    Promise.all([get("api/studio/productions"), get("api/studio/catalog")]).then(function (r) {
      prods = r[0].productions; canEdit = !!r[0].canEdit; catalog = r[1];
      fillProductions();
      var last = null;
      try { last = JSON.parse(localStorage.getItem("agenticprod.studio") || "null"); } catch (e) {}
      var want = last && find(last.ns, last.name) ? last : firstRunning();
      if (want) { $("st-pick").value = want.ns + "|" + want.name; openProduction(want.ns, want.name); }
      else side();
    }).catch(showError);
  }

  function find(ns, name) {
    for (var i = 0; i < prods.length; i++) if (prods[i].namespace === ns)
      for (var j = 0; j < prods[i].productions.length; j++) if (prods[i].productions[j].name === name) return { ns: ns, name: name };
    return null;
  }
  function firstRunning() {
    var first = null;
    for (var i = 0; i < prods.length; i++) for (var j = 0; j < prods[i].productions.length; j++) {
      var p = prods[i].productions[j], o = { ns: prods[i].namespace, name: p.name };
      if (p.running && prods[i].namespace !== "IRISAPP") return o;
      if (!first) first = o;
    }
    return first;
  }
  function fillProductions() {
    var s = $("st-pick");
    s.textContent = "";
    prods.forEach(function (n) {
      var g = el("optgroup"); g.label = n.namespace;
      n.productions.forEach(function (p) {
        var o = el("option", n.namespace + " · " + p.name + (p.running ? "" : " (stopped)"));
        o.value = n.namespace + "|" + p.name;
        g.appendChild(o);
      });
      s.appendChild(g);
    });
  }
  function fillAgents() {
    var s = $("st-agent");
    s.textContent = "";
    var have = {};
    here().forEach(function (a) {
      var o = el("option", a.name); o.value = "c:" + a.class; s.appendChild(o); have["c:" + a.class] = 1;
    });
    if (draft.agent.isNew) { var n = el("option", draft.agent.name + " (new)"); n.value = "n:" + draft.agent.id; s.appendChild(n); have["n:" + draft.agent.id] = 1; }
    var add = el("option", "+ New agent from the triage template"); add.value = "new"; s.appendChild(add);
    s.value = draft.agent.isNew ? "n:" + draft.agent.id : "c:" + draft.agent.cls;
  }

  // The template carries the triage agent's setup; an existing agent starts from it too, because
  // the live class is not read back yet
  function freshAgent(cls, name, isNew) {
    var t = JSON.parse(JSON.stringify(catalog.template)), c = agentOf(cls);
    t.id = "a" + Date.now().toString(36) + (++seq);
    t.cls = cls; t.name = name; t.isNew = !!isNew;
    if (c) { t.provider = c.provider; t.model = c.model; }
    return t;
  }
  function agentOf(cls) {
    for (var i = 0; i < catalog.agents.length; i++) if (catalog.agents[i].class === cls) return catalog.agents[i];
    return null;
  }
  // The triage agent belongs to its own namespace; other productions only get agents made here
  function here() { return catalog.agents.filter(function (a) { return a.namespace === cur.ns; }); }
  function todayOf(a) { var c = agentOf(a.cls); return (c && c.today[cur.ns]) || { runs: 0, cost: 0, toolCalls: 0 }; }
  function defaultWatches() {
    return prod.items.filter(function (i) { return !i.ai && (i.errors24h || i.suspended); }).map(function (i) { return i.name; });
  }
  function emptyDraft() {
    var a = here()[0] || null;
    return { version: 2, ns: cur.ns, production: cur.name, agent: freshAgent(a ? a.class : "", a ? a.name : "TriageAgent", !a), watches: defaultWatches(), role: catalog.roles[0] || "IntegrationSupport" };
  }
  function baseline() { return { agent: freshAgent(draft.agent.cls, draft.agent.name, draft.agent.isNew), watches: defaultWatches(), role: catalog.roles[0] || "IntegrationSupport" }; }

  function openProduction(ns, name) {
    cur = { ns: ns, name: name };
    try { localStorage.setItem("agenticprod.studio", JSON.stringify(cur)); } catch (e) {}
    Promise.all([get("api/studio/production" + q()), get("api/studio/draft" + q())]).then(function (r) {
      prod = r[0];
      var d = r[1].draft;
      // Version 1 drafts (production-item canvas) have no agent: start again from the template
      draft = d && d.version === 2 && d.agent ? d : emptyDraft();
      savedJson = d && d.version === 2 ? JSON.stringify(draft) : "";
      savedAt = r[1].savedAt || "";
      sel = { t: "agent" };
      fillAgents();
      paint();
    }).catch(showError);
  }

  function pickAgent(v) {
    if (v === "new") {
      var base = "TriageAgent", n = base, i = 1, taken = {};
      here().forEach(function (a) { taken[a.name] = 1; });
      while (taken[n]) n = base + (++i);
      draft.agent = freshAgent("", n, true);
    } else if (v.indexOf("c:") === 0) {
      var c = agentOf(v.substr(2));
      if (c && c.class !== draft.agent.cls) draft.agent = freshAgent(c.class, c.name, false);
    }
    sel = { t: "agent" };
    fillAgents();
    paint();
  }

  function dirty() { return JSON.stringify(draft) !== savedJson; }

  // Count of settings that differ from the template defaults
  function changeCount() {
    var b = baseline(), n = 0;
    ["instructions", "mode", "budget", "toolCalls", "provider", "model"].forEach(function (k) { if (String(draft.agent[k]) !== String(b.agent[k])) n++; });
    ["tools", "skills", "knowledge", "guardrails", "memory"].forEach(function (k) {
      var x = draft.agent[k] || [], y = b.agent[k] || [];
      x.forEach(function (v) { if (y.indexOf(v) < 0) n++; });
      y.forEach(function (v) { if (x.indexOf(v) < 0) n++; });
    });
    if (JSON.stringify(draft.watches) !== JSON.stringify(b.watches)) n++;
    if (draft.role !== b.role) n++;
    if (draft.agent.isNew) n++;
    return n;
  }

  function edit(fn) { fn(); paint(); }

  function saveDraft() {
    var b = $("st-save");
    b.disabled = true;
    send("PUT", "api/studio/draft" + q(), draft).then(function (r) {
      savedJson = JSON.stringify(draft); savedAt = r.savedAt || ""; chrome();
    }).catch(function (e) { $("st-count").textContent = e.message; }).then(function () { b.disabled = !canEdit; });
  }

  function chrome() {
    var run = $("st-run");
    run.textContent = prod && prod.running ? "running" : "stopped";
    run.className = "st-run" + (prod && prod.running ? "" : " off");
    var n = changeCount(), c = $("st-count");
    c.textContent = (n ? n + (n === 1 ? " change" : " changes") : "In sync with production") + (dirty() ? " · unsaved" : (savedAt ? " · draft saved " + hhmm(savedAt) : ""));
    var save = $("st-save");
    save.disabled = !canEdit || !dirty();
    save.title = canEdit ? "" : "Saving a draft needs the AgenticProd_Admin role";
  }

  // ---- catalog lookups ----------------------------------------------------------------------
  function lookup(port, key) {
    var list = { tools: catalog.toolsets, skills: catalog.skills, knowledge: catalog.knowledgeBases, guardrails: catalog.policies, memory: catalog.memory }[port] || [];
    for (var i = 0; i < list.length; i++) if ((list[i].class || list[i].id || list[i].name) === key) return list[i];
    return { name: short(key), description: "" };
  }
  function itemsOf(port) {
    var a = draft.agent;
    if (port === "model") return [a.model || a.provider || "not set"];
    return a[port] || [];
  }
  function itemSub(port, key) {
    var x = lookup(port, key);
    return port === "skills" ? "skill" : port === "knowledge" ? "knowledge · vector search" : x.description || "";
  }

  // ---- canvas -------------------------------------------------------------------------------
  function node(id, cls, x, y, w, h, html, on) {
    var d = el("div", null, "n " + cls);
    d.id = id; d.style.left = x + "px"; d.style.top = y + "px"; d.style.width = w + "px"; d.style.height = h + "px";
    d.innerHTML = html;
    d.addEventListener("click", function (e) { e.stopPropagation(); on(); });
    return d;
  }
  function pick(s) { sel = s; paint(); }
  function isSel(t, id, key) { return sel && sel.t === t && sel.id === id && sel.key === key; }

  function paint() {
    if (!prod) return;
    chrome();
    scene();
    side();
  }

  function scene() {
    var sc = $("st-scene"), a = draft.agent, svg = "", H = [];
    sc.textContent = "";
    sc.style.width = "1500px"; sc.style.height = SCENE_H + "px";
    var runs = todayOf(a).runs;

    var T = { x: 50, y: 250, w: 210, h: 96 }, A = { x: 340, y: 235, w: 500, h: 126 }, D = { x: 930, y: 223, w: 130, h: 150 };
    var watched = draft.watches.length + (draft.watches.length === 1 ? " item watched" : " items watched");
    sc.appendChild(node("n-trig", "trig" + (isSel("trigger") ? " sel" : ""), T.x, T.y, T.w, T.h,
      '<i class="ic ti ti-alert-triangle" style="color:#fb923c"></i><div><div class="t">When a message fails</div><div class="s">' + esc(watched) + "</div></div>", function () { pick({ t: "trigger" }); }));
    sc.appendChild(node("n-agent", "agent" + (isSel("agent") ? " sel" : ""), A.x, A.y, A.w, A.h,
      '<span class="count">' + runs + ' runs today</span><i class="ic ti ti-robot" style="color:#c4b5fd;font-size:38px"></i><div><div class="t" style="font-size:18px">' + esc(a.name) +
      '</div><div class="s">AI Hub agent · %AI.Agent · ' + esc(a.mode) + "</div></div>", function () { pick({ t: "agent" }); }));
    sc.appendChild(node("n-dec", "dec", D.x, D.y, D.w, D.h, '<i class="ic ti ti-arrows-split-2" style="color:#34d399"></i><div class="t" style="font-size:14px">Decision</div>', function () {}));

    function path(d, dash, col, w) { svg += '<path d="' + d + '" fill="none" stroke="' + (col || "#c4c9d4") + '" stroke-width="' + (w || 2) + '"' + (dash ? ' stroke-dasharray="7 6"' : "") + "/>"; }
    function curve(x1, y1, x2, y2) { var m = (x1 + x2) / 2; return "M" + x1 + "," + y1 + " C" + m + "," + y1 + " " + m + "," + y2 + " " + x2 + "," + y2; }
    function dot(x, y) { H.push('<span class="dot" style="left:' + (x - 7) + "px;top:" + (y - 7) + 'px"></span>'); }
    function arrow(x, y) { svg += '<path d="M' + (x - 9) + "," + (y - 6) + " L" + x + "," + y + " L" + (x - 9) + "," + (y + 6) + ' Z" fill="#c4c9d4"/>'; }
    path(curve(T.x + T.w, T.y + T.h / 2, A.x, A.y + A.h / 2)); dot(T.x + T.w, T.y + T.h / 2); arrow(A.x, A.y + A.h / 2);
    path(curve(A.x + A.w, A.y + A.h / 2, D.x, D.y + D.h / 2)); dot(A.x + A.w, A.y + A.h / 2); arrow(D.x, D.y + D.h / 2);

    // Outcomes: fixed targets the Triage process acts on, so they are read-only here
    OUTS.forEach(function (o, i) {
      var ox = 1240, oy = 70 + i * 120, oh = 70, y1 = D.y + 30 + i * 30, sx = D.x + D.w + 70, mid = oy + oh / 2;
      svg += '<path d="M' + (D.x + D.w) + "," + y1 + " L" + sx + "," + y1 + " C" + (sx + 50) + "," + y1 + " " + (ox - 50) + "," + mid + " " + ox + "," + mid + '" fill="none" stroke="#c4c9d4" stroke-width="2"/>';
      dot(D.x + D.w, y1); arrow(ox, mid);
      H.push('<span class="olab" style="left:' + (D.x + D.w + 12) + "px;top:" + (y1 - 9) + 'px">' + o.label + "</span>");
      var sub = o.id === "review" ? o.sub + draft.role : o.sub;
      sc.appendChild(node("n-o-" + o.id, isSel("out", o.id) ? "sel" : "", ox, oy, 220, oh,
        '<i class="ic ti ti-' + o.icon + '" style="color:' + o.col + ';font-size:24px"></i><div><div class="t" style="font-size:14px">' + o.title + '</div><div class="s">' + esc(sub) + "</div></div>", function () { pick({ t: "out", id: o.id }); }));
    });

    // One dashed box under the agent with a card per kind of ability
    var K = { x: 150, y: 470, w: 1060 }, kit = el("div", null, "kit");
    kit.style.left = K.x + "px"; kit.style.top = K.y + "px"; kit.style.width = K.w + "px";
    PORTS.forEach(function (p) {
      var items = itemsOf(p.id), c = el("div", null, "kcard");
      c.innerHTML = '<div class="kh"><i class="ti ti-' + p.icon + ' ' + p.col + '"></i>' + p.label + (p.req ? "<b>*</b>" : "") + (p.id !== "model" ? '<span class="kn">' + items.length + "</span>" : "") + "</div>";
      var body = el("div", null, "kb");
      items.forEach(function (key) {
        var r = el("span", p.id === "model" ? (a.model || a.provider || "not set") : lookup(p.id, key).name, "kc" + (isSel("sub", p.id, key) ? " on" : ""));
        r.addEventListener("click", function (e) { e.stopPropagation(); pick({ t: "sub", id: p.id, key: key }); });
        body.appendChild(r);
      });
      if (p.id === "model" && a.provider) body.appendChild(el("span", a.provider + " · key in IRIS Wallet", "kc off"));
      c.appendChild(body);
      var b = el("button", null, "kadd" + (isSel("add", p.id) ? " hot" : ""));
      b.type = "button"; b.innerHTML = '<i class="ti ti-plus"></i> ' + (p.id === "model" ? "Change" : "Add");
      b.addEventListener("click", function (e) { e.stopPropagation(); pick(p.id === "model" ? { t: "sub", id: "model" } : { t: "add", id: p.id }); });
      c.appendChild(b);
      kit.appendChild(c);
    });
    sc.appendChild(kit);
    path("M" + (A.x + A.w / 2) + "," + (A.y + A.h) + " L" + (A.x + A.w / 2) + "," + K.y, true, "#7b8291");
    H.push('<span class="plab" style="left:' + (A.x + A.w / 2 + 30) + "px;top:" + (A.y + A.h + 40) + 'px">uses</span>');
    [[T.x, 190, 1, "Starts when"], [A.x, 190, 2, "The AI Hub agent and what it can use"], [1240, 30, 3, "What happens next"]].forEach(function (h) {
      H.push('<div class="stephead" style="left:' + h[0] + "px;top:" + h[1] + 'px"><span>' + h[2] + "</span>" + h[3] + "</div>");
    });
    var s = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    s.innerHTML = svg;
    sc.insertBefore(s, sc.firstChild);
    var holder = el("div"); holder.innerHTML = H.join("");
    while (holder.firstChild) sc.appendChild(holder.firstChild);
    applyScale();
  }

  function zoom(k) { scale = Math.max(0.4, Math.min(1.6, k)); applyScale(); }
  function fit() { var w = $("st-canvas").clientWidth, s = $("st-scene"); scale = Math.min(1, w / (parseInt(s.style.width, 10) || 1500)); applyScale(); }
  function applyScale() { var s = $("st-scene"); if (s) s.style.transform = "scale(" + scale + ")"; }

  // ---- right panel --------------------------------------------------------------------------
  function head(s, icon, bg, fg, title, sub, close) {
    var h = el("div", null, "d-flex align-items-center gap-2 mb-3");
    h.innerHTML = '<span class="avatar avatar-sm" style="background:' + bg + ";color:" + fg + '"><i class="ti ti-' + icon + '"></i></span><div><div class="fw-bold">' + esc(title) + '</div><div class="text-secondary" style="font-size:12px">' + esc(sub) + "</div></div>";
    if (close) {
      var x = btn('<i class="ti ti-x"></i>', "btn-icon btn-ghost-secondary ms-auto", "Close");
      x.addEventListener("click", function () { sel = null; paint(); });
      h.appendChild(x);
    }
    s.appendChild(h);
  }
  function field(label, input) {
    var d = el("div", null, "mb-2");
    d.appendChild(el("label", label, "form-label"));
    d.appendChild(input);
    return d;
  }
  function select(opts, value, onChange) {
    var sl = el("select", null, "form-select");
    opts.forEach(function (o) { var op = el("option", o[1]); op.value = o[0]; sl.appendChild(op); });
    sl.value = value;
    sl.addEventListener("change", function () { onChange(sl.value); });
    return sl;
  }
  function text(value, onChange, tag) {
    var i = el(tag || "input", null, "form-control");
    i.value = value == null ? "" : value;
    if (tag === "textarea") i.rows = 5;
    i.addEventListener("change", function () { onChange(i.value); });
    return i;
  }

  function side() {
    var s = $("st-side");
    s.textContent = "";
    $("st-hint").style.display = sel ? "none" : "";
    if (!prod) { s.appendChild(el("div", "Pick a production to start.", "text-secondary")); return; }
    if (!sel) { s.appendChild(el("div", "Click the agent, the trigger or an outcome to change it.", "text-secondary")); return; }
    ({ agent: agentPanel, trigger: triggerPanel, out: outPanel, add: addPanel, sub: subPanel })[sel.t](s);
  }

  function agentPanel(s) {
    var a = draft.agent, cat = agentOf(a.cls) ? todayOf(a) : null;
    head(s, "robot", "#f3e8ff", "#7c3aed", a.name, "AI Hub agent · " + (a.cls || "new, created on Apply"));
    s.appendChild(el("h5", "What it does"));
    s.appendChild(text(a.instructions, function (v) { edit(function () { a.instructions = v; }); }, "textarea"));
    s.appendChild(el("h5", "What it may do"));
    var seg = el("div", null, "btn-group w-100 mb-2");
    MODES.forEach(function (m) {
      var x = btn(m[1], a.mode === m[0] ? "active" : "");
      x.addEventListener("click", function () { edit(function () { a.mode = m[0]; }); });
      seg.appendChild(x);
    });
    s.appendChild(seg);
    s.appendChild(el("div", MODE_HELP[a.mode], "text-secondary"));
    s.appendChild(el("h5", "Limits"));
    var row = el("div", null, "row g-2"), c1 = el("div", null, "col-6"), c2 = el("div", null, "col-6");
    c1.appendChild(field("Budget per day", select([["0.50", "$0.50"], ["2.00", "$2"], ["10.00", "$10"]], a.budget, function (v) { edit(function () { a.budget = v; }); })));
    c2.appendChild(field("Tool calls / message", text(a.toolCalls, function (v) { edit(function () { a.toolCalls = v; }); })));
    row.appendChild(c1); row.appendChild(c2); s.appendChild(row);
    s.appendChild(el("h5", "Today"));
    var t = el("div", null, "d-flex justify-content-between");
    t.appendChild(el("span", cat ? cat.runs + " runs · " + cat.toolCalls + " tool calls" : "not created yet"));
    t.appendChild(el("span", cat ? usd(cat.cost) : "", "fw-semibold"));
    s.appendChild(t);
    if (a.isNew) {
      s.appendChild(el("h5", "Name"));
      s.appendChild(text(a.name, function (v) { edit(function () { a.name = v.replace(/[^A-Za-z0-9]/g, "") || a.name; fillAgents(); }); }));
    }
  }

  function triggerPanel(s) {
    head(s, "alert-triangle", "#ffedd5", "#c2410c", "When a message fails", "Pick the items whose failures go to the agent", true);
    var items = prod.items.filter(function (i) { return !i.ai; });
    if (!items.length) s.appendChild(el("div", "This production has no items.", "text-secondary"));
    items.forEach(function (it) {
      var l = el("label", null, "form-check");
      var c = el("input", null, "form-check-input"); c.type = "checkbox"; c.checked = draft.watches.indexOf(it.name) >= 0;
      c.addEventListener("change", function () {
        edit(function () { draft.watches = c.checked ? draft.watches.concat([it.name]) : draft.watches.filter(function (w) { return w !== it.name; }); });
      });
      var sp = el("span", it.name, "form-check-label");
      sp.appendChild(el("span", " · " + it.type + (it.errors24h ? " · " + it.errors24h + " errors" : ""), "text-secondary"));
      l.appendChild(c); l.appendChild(sp);
      s.appendChild(l);
    });
  }

  function outPanel(s) {
    var o = null;
    OUTS.forEach(function (x) { if (x.id === sel.id) o = x; });
    head(s, o.icon, "#f2f4f7", o.col, o.title, "Done by the Triage process, not by the agent", true);
    var why = {
      fix: "Only whitelisted, meaning-preserving fixes, and only when validation passed. Needs mode Fix safe cases. The fixed message is re-sent to LabRouter.",
      review: "Everything else goes to a person as a Workflow task. Pick the role that approves.",
      resend: "For timeouts and outages: the message is sent again when the target is back, up to 3 times.",
      reject: "The sender gets the message back with the reason."
    }[o.id];
    s.appendChild(el("div", why, "mb-3"));
    if (o.id === "review") {
      var roles = catalog.roles.map(function (r) { return [r, r]; });
      if (draft.role && catalog.roles.indexOf(draft.role) < 0) roles.push([draft.role, draft.role + " (new)"]);
      if (!roles.length) roles = [["IntegrationSupport", "IntegrationSupport (new)"]];
      s.appendChild(field("Role that approves", select(roles, draft.role, function (v) { edit(function () { draft.role = v; }); })));
    }
  }

  function addPanel(s) {
    var p = null;
    PORTS.forEach(function (x) { if (x.id === sel.id) p = x; });
    head(s, p.icon, "#e0f2fe", "#0369a1", p.title, p.hint, true);
    var list = {
      tools: catalog.toolsets.map(function (x) { return { key: x.class, name: x.name, desc: x.description }; }),
      skills: catalog.skills.map(function (x) { return { key: x.class, name: x.name, desc: x.description }; }),
      knowledge: catalog.knowledgeBases.map(function (x) { return { key: x.name, name: x.name, desc: x.description }; }),
      guardrails: catalog.policies.map(function (x) { return { key: x.class, name: x.name, desc: x.description }; }),
      memory: catalog.memory.map(function (x) { return { key: x.id, name: x.name, desc: x.description }; })
    }[p.id];
    var have = draft.agent[p.id] || [];
    list.forEach(function (it) {
      var added = have.indexOf(it.key) >= 0, r = el("div", null, "pick" + (added ? " added" : ""));
      r.innerHTML = '<span class="ic2 ' + p.col + '"><i class="ti ti-' + p.icon + '"></i></span><div class="flex-fill"><div class="t">' + esc(it.name) + '</div><div class="d">' + esc(it.desc || "") + "</div></div>";
      if (added) r.appendChild(el("span", "added", "badge bg-purple-lt"));
      else {
        var b = btn("Add", "btn-primary");
        b.addEventListener("click", function () { edit(function () { draft.agent[p.id] = have.concat([it.key]); }); });
        r.appendChild(b);
      }
      s.appendChild(r);
    });
    var soon = { skills: ["Import a skill", "from a SKILL.md folder or Git", "puzzle"], knowledge: ["New knowledge base", "upload a CSV · IRIS vector search", "database-plus"] }[p.id];
    if (soon) {
      var r = el("div", null, "pick");
      r.innerHTML = '<span class="ic2 ' + p.col + '"><i class="ti ti-' + soon[2] + '"></i></span><div class="flex-fill"><div class="t">' + soon[0] + '</div><div class="d">' + soon[1] + "</div></div>";
      var c = btn(p.id === "skills" ? "Import" : "Create"); stub(c); c.title = "Coming soon";
      r.appendChild(c);
      s.appendChild(r);
    }
  }

  function subPanel(s) {
    var p = null, a = draft.agent;
    PORTS.forEach(function (x) { if (x.id === sel.id) p = x; });
    if (p.id === "model") {
      head(s, p.icon, "#f3e8ff", "#7c3aed", "Model", "Required. The AI the agent thinks with.", true);
      var provs = catalog.providers.map(function (x) { return [x.name, x.name + (x.model ? " · " + x.model : "")]; });
      if (a.provider && !catalog.providers.some(function (x) { return x.name === a.provider; })) provs.unshift([a.provider, a.provider]);
      if (!provs.length) provs = [["", "No provider configured"]];
      s.appendChild(field("Provider", select(provs, a.provider, function (v) {
        edit(function () { a.provider = v; catalog.providers.forEach(function (x) { if (x.name === v) a.model = x.model || ""; }); });
      })));
      s.appendChild(field("Model", text(a.model, function (v) { edit(function () { a.model = v; }); })));
      return;
    }
    var it = lookup(p.id, sel.key);
    head(s, p.icon, "#e0f2fe", "#0369a1", it.name, p.label, true);
    s.appendChild(el("div", it.description || itemSub(p.id, sel.key), "mb-3"));
    if (it.class) { var c = el("div", null, "mb-3"); c.appendChild(el("code", it.class)); s.appendChild(c); }
    var rm = btn('<i class="ti ti-trash me-1"></i>Remove from ' + a.name);
    rm.addEventListener("click", function () { edit(function () { a[p.id] = a[p.id].filter(function (k) { return k !== sel.key; }); sel = null; }); });
    s.appendChild(rm);
  }

  // ---- entry --------------------------------------------------------------------------------
  window.studioShow = function (name) {
    if (name !== "studio") return;
    if (!started) { started = true; init(); }
    else if (cur && !(draft && dirty())) { openProduction(cur.ns, cur.name); }
  };
  // Read-only view for checks from the console
  window.studioState = function () { return { production: cur, agent: draft ? draft.agent.name : null, selected: sel, dirty: draft ? dirty() : false, canEdit: canEdit }; };
  var active = document.querySelector("#nav .nav-link.active");
  if (active) window.studioShow(active.dataset.tab);
})();
