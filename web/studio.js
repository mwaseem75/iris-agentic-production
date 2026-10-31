"use strict";
// AI Studio tab: pick a production, see its items on a Drawflow canvas, add AI blocks from a
// recipe into a draft. The draft is the only thing written (PUT api/studio/draft); nothing here
// touches the production itself. Needs el, get, send from the dashboard script and Drawflow.
(function () {
  var ICONS = { service: "file-import", process: "arrows-split", operation: "send", other: "box" };
  var BLOCKS = {
    sentinel: { icon: "alert-triangle", cls: "tr", title: "Failure Sentinel", sub: "Trigger" },
    agent: { icon: "robot", cls: "ai", title: "Triage agent", sub: "%AI.Agent" },
    human: { icon: "user-check", cls: "hu", title: "Human review", sub: "Workflow" }
  };
  var NEXT = "next step";

  var started = false, editor = null, catalog = null, canEdit = false, rootEl = null;
  var prods = [], cur = null;              // cur = { ns, name }
  var prod = null, draft = null, savedJson = "", savedAt = "", history = [];
  var sel = null, nodeKey = {}, keyNode = {}, rendering = false, advanced = false, seq = 0;

  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c]; }); }
  function btn(html, cls, title) {
    var b = el("button", null, "btn btn-sm " + (cls || ""));
    b.type = "button"; b.innerHTML = html;
    if (title) b.title = title;
    return b;
  }
  function stub(b) { b.disabled = true; b.title = NEXT; return b; }
  function emptyDraft() { return { version: 1, ns: cur.ns, production: cur.name, blocks: [] }; }
  function hhmm(ts) { return ts ? String(ts).replace("T", " ").substr(11, 5) : ""; }

  // ---- page skeleton ------------------------------------------------------------------------
  function build() {
    rootEl = $("studio-root");
    rootEl.innerHTML =
      '<div class="st-top" id="st-top"></div>' +
      '<div class="st-grid">' +
      '<div class="st-palette" id="st-palette"></div>' +
      '<div class="st-canvas" id="st-canvas"><div id="st-df"></div>' +
      '<div class="st-legend"><i class="ti ti-square-filled text-secondary"></i> existing production &nbsp; <i class="ti ti-square-filled" style="color:#7c3aed"></i> AI Hub blocks</div>' +
      '<div class="st-tools" id="st-tools"></div></div>' +
      '<div class="st-side" id="st-side"></div></div>' +
      '<div class="st-bottom"><div class="pane" id="st-chg"></div><div class="pane" id="st-val"></div></div>';
    buildTop();
    buildTools();
    editor = new Drawflow($("st-df"));
    editor.reroute = false;
    editor.start();
    wireEditor();
    $("st-canvas").addEventListener("dragover", function (e) { e.preventDefault(); });
    $("st-canvas").addEventListener("drop", onDrop);
  }

  function buildTop() {
    var top = $("st-top");
    top.textContent = "";
    top.appendChild(el("h3", "AI Studio", "m-0 me-2"));
    var pick = el("select", null, "form-select");
    pick.id = "st-pick"; pick.style.width = "340px"; pick.style.fontWeight = "600";
    pick.addEventListener("change", function () {
      var v = pick.value.split("|");
      openProduction(v[0], v.slice(1).join("|"));
    });
    top.appendChild(el("span", "Production", "text-secondary fw-medium"));
    top.appendChild(pick);
    var chip = el("span", "", "st-run"); chip.id = "st-run";
    top.appendChild(chip);
    top.appendChild(el("span", "", "spacer"));
    var cnt = el("span", "", "st-count"); cnt.id = "st-count";
    top.appendChild(cnt);
    var seg = el("div", null, "btn-group");
    var cv = btn("Canvas", "active"), code = stub(btn("Code"));
    seg.appendChild(cv); seg.appendChild(code);
    top.appendChild(seg);
    var undo = btn('<i class="ti ti-arrow-back-up me-1"></i>Undo'); undo.id = "st-undo";
    undo.addEventListener("click", undoLast);
    top.appendChild(undo);
    top.appendChild(stub(btn('<i class="ti ti-checklist me-1"></i>Validate')));
    top.appendChild(stub(btn('<i class="ti ti-player-play me-1"></i>Test')));
    var save = btn('<i class="ti ti-device-floppy me-1"></i>Save draft'); save.id = "st-save";
    save.addEventListener("click", saveDraft);
    top.appendChild(save);
    top.appendChild(stub(btn('<i class="ti ti-rocket me-1"></i>Apply to production', "btn-primary")));
  }

  function buildTools() {
    var t = $("st-tools");
    var zi = btn('<i class="ti ti-zoom-in"></i>', "btn-icon", "Zoom in"), zo = btn('<i class="ti ti-zoom-out"></i>', "btn-icon", "Zoom out");
    var fit = btn('<i class="ti ti-arrows-maximize"></i>', "btn-icon", "Fit"), lay = btn('<i class="ti ti-wand me-1"></i>Auto-layout');
    zi.addEventListener("click", function () { editor.zoom_in(); placeBar(); });
    zo.addEventListener("click", function () { editor.zoom_out(); placeBar(); });
    fit.addEventListener("click", function () { editor.canvas_x = 0; editor.canvas_y = 0; editor.zoom = 1; editor.zoom_refresh(); placeBar(); });
    lay.addEventListener("click", function () { draftBlocks().forEach(function (b) { delete b.x; delete b.y; }); render(); });
    [zi, zo, fit, lay].forEach(function (b) { t.appendChild(b); });
  }

  function buildPalette() {
    var p = $("st-palette");
    p.textContent = "";
    function head(t) { p.appendChild(el("h6", t)); }
    function blk(kind, cls, icon, title, desc, drag) {
      var b = el("div", null, "st-blk" + (drag ? "" : " off"));
      b.innerHTML = '<span class="ic ' + cls + '"><i class="ti ti-' + icon + '"></i></span><div><div class="t">' + esc(title) + '</div><div class="d">' + esc(desc) + "</div></div>";
      if (drag) {
        b.draggable = true;
        b.addEventListener("dragstart", function (e) { e.dataTransfer.setData("text/plain", kind); });
      } else {
        b.title = kind === "soon" ? "Coming soon" : NEXT;
      }
      p.appendChild(b);
    }
    head("Triggers");
    blk("sentinel", "tr", "alert-triangle", "On failure", "Errors and suspended messages", true);
    head("Agents");
    blk("agent", "ai", "robot", "Triage agent", "%AI.Agent: diagnose and propose a fix", true);
    blk("soon", "ai", "tags", "Classifier agent", "Coming soon", false);
    blk("soon", "ai", "users-group", "Sub-agent", "Coming soon", false);
    head("Capabilities");
    blk("x", "ai", "tool", "Toolset", "Set in the agent's Advanced panel", false);
    blk("x", "ai", "puzzle", "Skill", "Set in the agent's Advanced panel", false);
    blk("x", "kb", "database-search", "Knowledge base", "RAG on IRIS vector search", false);
    head("Safety");
    blk("x", "po", "lock", "Policy", "ReadOnly and Audit are always on", false);
    head("People");
    blk("human", "hu", "user-check", "Human review", "Workflow task, approve or reject", true);
  }

  // ---- data ---------------------------------------------------------------------------------
  function init() {
    build();
    buildPalette();
    Promise.all([get("api/studio/productions"), get("api/studio/catalog")]).then(function (r) {
      prods = r[0].productions; canEdit = !!r[0].canEdit; catalog = r[1];
      fillPicker();
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
  function fillPicker() {
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

  function openProduction(ns, name) {
    cur = { ns: ns, name: name };
    try { localStorage.setItem("agenticprod.studio", JSON.stringify(cur)); } catch (e) {}
    var q = "?ns=" + encodeURIComponent(ns) + "&name=" + encodeURIComponent(name);
    Promise.all([get("api/studio/production" + q), get("api/studio/draft" + q)]).then(function (r) {
      prod = r[0];
      draft = r[1].draft || emptyDraft();
      if (!draft.blocks) draft.blocks = [];
      savedJson = r[1].draft ? JSON.stringify(draft) : JSON.stringify(emptyDraft());
      savedAt = r[1].savedAt || "";
      history = []; sel = null;
      render();
    }).catch(showError);
  }

  function draftBlocks() { return draft ? draft.blocks : []; }
  function dirty() { return JSON.stringify(draft) !== savedJson; }

  // ---- changes ------------------------------------------------------------------------------
  function pkg() { var i = cur.name.lastIndexOf("."); return i > 0 ? cur.name.substr(0, i) : cur.name; }
  function changes() {
    var out = [];
    draftBlocks().forEach(function (b) {
      if (b.kind === "sentinel") out.push(["Business service", b.name, "watching " + (b.watches && b.watches.length ? b.watches.join(", ") : "nothing yet")]);
      else if (b.kind === "agent") {
        out.push(["Class", pkg() + ".AI." + b.name, "extends %AI.Agent (" + (b.toolsets || []).length + " toolsets, " + (b.skills || []).length + " skills)"]);
        out.push(["Business operation", b.name, "mode " + b.mode + (b.budget ? " · $" + b.budget + "/day" : "")]);
      } else out.push(["Workflow role", b.role || "unset", "and operation " + b.name]);
    });
    return out;
  }

  // ---- canvas -------------------------------------------------------------------------------
  function nodeHtml(icon, name, sub, chips) {
    var h = '<div class="sn-hd"><i class="ti ti-' + icon + '"></i><div><div class="sn-nm">' + esc(name) + '</div><div class="sn-ty">' + esc(sub) + "</div></div></div>";
    if (chips.length) h += '<div class="sn-bd">' + chips.map(function (c) { return '<span class="sn-chip ' + (c[1] || "") + '">' + esc(c[0]) + "</span>"; }).join("") + "</div>";
    return h;
  }

  // Columns by distance from the entry items, rows by order; blocks that were dragged keep x, y.
  function layout() {
    var depth = {}, items = prod.items, inc = {}, queue = [];
    items.forEach(function (i) { inc[i.name] = 0; });
    prod.connections.forEach(function (c) { if (c.to in inc) inc[c.to]++; });
    items.forEach(function (i) { if (!inc[i.name]) { depth[i.name] = 0; queue.push(i.name); } });
    while (queue.length) {
      var n = queue.shift();
      prod.connections.forEach(function (c) {
        if (c.from === n && !(c.to in depth)) { depth[c.to] = depth[n] + 1; queue.push(c.to); }
      });
    }
    var rows = {}, pos = {};
    items.forEach(function (i) {
      var d = depth[i.name] || 0;
      rows[d] = (rows[d] || 0) + 1;
      pos[i.name] = [30 + d * 260, 30 + (rows[d] - 1) * 90];
    });
    return pos;
  }

  function render() {
    if (!prod) return;
    rendering = true;
    editor.clear();
    nodeKey = {}; keyNode = {};
    var pos = layout(), maxY = 0, hasLive = false;
    prod.items.forEach(function (it) {
      var chips = [];
      if (it.errors24h) chips.push([it.errors24h + " errors", "r"]);
      if (it.suspended) chips.push([it.suspended + " suspended", "o"]);
      if (it.ai) { chips.push([it.mode ? "AI · " + it.mode : "AI", ""]); hasLive = true; }
      if (!it.enabled) chips.push(["disabled", "o"]);
      var id = editor.addNode(it.name, 1, 1, pos[it.name][0], pos[it.name][1], it.ai ? "live" : "prod", { key: "item:" + it.name },
        nodeHtml(ICONS[it.type] || "box", it.name, cap(it.type) + (it.ai ? "" : " · existing"), chips));
      nodeKey[id] = "item:" + it.name; keyNode["item:" + it.name] = id;
      maxY = Math.max(maxY, pos[it.name][1]);
    });
    prod.connections.forEach(function (c) { link("item:" + c.from, "item:" + c.to, ""); });
    var top = maxY + 190, col = {}, zone = null;
    draftBlocks().forEach(function (b, n) {
      var g = b.group || "g0";
      if (!(g in col)) col[g] = Object.keys(col).length;
      if (b.x == null) { b.x = 60 + { sentinel: 0, agent: 260, human: 560 }[b.kind] || 0; b.y = top + col[g] * 130; }
      var meta = BLOCKS[b.kind], chips = [];
      if (b.kind === "agent") {
        if ((b.toolsets || []).length) chips.push(["Tools: " + b.toolsets.map(short).join(", ")]);
        (b.skills || []).forEach(function (s) { chips.push(["Skill: " + short(s)]); });
        chips.push(["ReadOnly + Audit", "r"]);
        if (b.budget) chips.push(["Budget $" + b.budget + "/day", "b"]);
      }
      var sub = b.kind === "sentinel" ? "Trigger · watches " + ((b.watches || []).length || 0) + " item"
        : b.kind === "agent" ? "%AI.Agent · " + (b.model || "provider default") + " · " + b.mode
        : "Workflow · role " + (b.role || "unset");
      var id = editor.addNode(b.name, 1, 1, b.x, b.y, "ain", { key: "blk:" + b.id }, nodeHtml(meta.icon, b.name, sub, chips));
      nodeKey[id] = "blk:" + b.id; keyNode["blk:" + b.id] = id;
    });
    // Links inside a group in the order the blocks were added; sentinel watches its items
    var last = {};
    draftBlocks().forEach(function (b) {
      var g = b.group || "g0";
      if (last[g]) link("blk:" + last[g], "blk:" + b.id, "ai");
      last[g] = b.id;
      (b.watches || []).forEach(function (w) { link("item:" + w, "blk:" + b.id, "watch"); });
    });
    if (draftBlocks().length) addZone();
    rendering = false;
    chrome();
    side();
    placeBar();
  }

  function short(c) { return String(c).split(".").pop(); }
  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : ""; }

  function link(a, b, cls) {
    var x = keyNode[a], y = keyNode[b];
    if (!x || !y) return;
    editor.addConnection(x, y, "output_1", "input_1");
    if (cls) {
      var c = $("st-df").querySelector(".connection.node_out_node-" + x + ".node_in_node-" + y);
      if (c) c.classList.add(cls);
    }
  }

  function addZone() {
    var bs = draftBlocks(), x1 = 1e9, y1 = 1e9, x2 = 0, y2 = 0;
    bs.forEach(function (b) { x1 = Math.min(x1, b.x); y1 = Math.min(y1, b.y); x2 = Math.max(x2, b.x + 240); y2 = Math.max(y2, b.y + 110); });
    var z = el("div", null, "st-zone");
    z.style.left = (x1 - 20) + "px"; z.style.top = (y1 - 24) + "px"; z.style.width = (x2 - x1 + 40) + "px"; z.style.height = (y2 - y1 + 44) + "px";
    z.appendChild(el("span", "AI added by AI Studio · in the draft, removable"));
    editor.precanvas.insertBefore(z, editor.precanvas.firstChild);
  }

  function wireEditor() {
    editor.on("nodeSelected", function (id) { sel = nodeKey[id] || null; advanced = false; side(); placeBar(); });
    editor.on("nodeUnselected", function () { sel = null; side(); placeBar(); });
    editor.on("nodeMoved", function (id) {
      var k = nodeKey[id], b = k && block(k.substr(4));
      if (!b || k.indexOf("blk:") !== 0) { placeBar(); return; }
      var n = editor.getNodeFromId(id);
      b.x = n.pos_x; b.y = n.pos_y;
      chrome();
      placeBar();
    });
    editor.on("nodeRemoved", function (id) {
      if (rendering) return;
      var k = nodeKey[id];
      // Existing items and connections are read-only: put them back
      if (k && k.indexOf("blk:") === 0) { removeBlock(k.substr(4)); return; }
      setTimeout(render, 0);
    });
    editor.on("connectionRemoved", function () { if (!rendering) setTimeout(render, 0); });
    editor.on("connectionCreated", function () { if (!rendering) setTimeout(render, 0); });
    editor.on("zoom", placeBar);
    editor.on("translate", placeBar);
  }

  function block(id) {
    var bs = draftBlocks();
    for (var i = 0; i < bs.length; i++) if (bs[i].id === id) return bs[i];
    return null;
  }

  function onDrop(e) {
    e.preventDefault();
    var kind = e.dataTransfer.getData("text/plain");
    if (!BLOCKS[kind] || !draft) return;
    var r = editor.precanvas.getBoundingClientRect(), z = editor.zoom;
    var b = newBlock(kind, "manual-" + (++seq));
    b.x = (e.clientX - r.left) / z; b.y = (e.clientY - r.top) / z;
    if (kind === "sentinel" && sel && sel.indexOf("item:") === 0) b.watches = [sel.substr(5)];
    commit(function () { draft.blocks.push(b); });
  }

  // ---- draft edits --------------------------------------------------------------------------
  function uid() { return "b" + Date.now().toString(36) + (++seq); }
  function uniqueName(base) {
    var taken = {}, n = base, i = 1;
    prod.items.forEach(function (it) { taken[it.name] = 1; });
    draftBlocks().forEach(function (b) { taken[b.name] = 1; });
    while (taken[n]) n = base + (++i);
    return n;
  }
  function newBlock(kind, group, target, recipe) {
    var b = { id: uid(), kind: kind, group: group };
    if (kind === "sentinel") { b.name = uniqueName("Failure Sentinel"); b.watches = target ? [target] : []; }
    else if (kind === "human") { b.name = uniqueName("Human review"); b.role = (catalog.roles[0]) || "IntegrationSupport"; }
    else {
      var base = (target || "Production").replace(/[^A-Za-z0-9]/g, "");
      b.name = uniqueName(base + "TriageAgent");
      b.mode = recipe ? recipe.mode : "propose";
      b.toolsets = recipe ? recipe.toolsets.slice() : [];
      b.skills = recipe ? recipe.skills.slice() : [];
      b.provider = catalog.providers.length ? catalog.providers[0].name : "";
      b.model = catalog.providers.length ? catalog.providers[0].model || "" : "";
      b.temperature = "0"; b.instructions = ""; b.budget = "0.50"; b.tokensPerDay = 50000; b.toolCalls = 10;
    }
    return b;
  }

  function addRecipe(r, target) {
    var g = "r" + (++seq) + "-" + Date.now().toString(36);
    commit(function () {
      r.blocks.forEach(function (k) { draft.blocks.push(newBlock(k, g, target, r)); });
    });
    var agent = null;
    draftBlocks().forEach(function (b) { if (b.group === g && b.kind === "agent") agent = b; });
    if (agent) { sel = "blk:" + agent.id; side(); }
  }

  function removeBlock(id) {
    commit(function () {
      var b = block(id), g = b && b.group;
      // A recipe group goes together; blocks dropped by hand go one at a time
      draft.blocks = draft.blocks.filter(function (x) { return g && g.indexOf("manual") !== 0 ? x.group !== g : x.id !== id; });
    });
    sel = null; side();
  }

  function commit(fn) {
    history.push(JSON.stringify(draft));
    if (history.length > 50) history.shift();
    fn();
    render();
  }
  function undoLast() {
    if (!history.length) return;
    draft = JSON.parse(history.pop());
    sel = null;
    render();
  }

  function saveDraft() {
    var b = $("st-save");
    b.disabled = true;
    var q = "?ns=" + encodeURIComponent(cur.ns) + "&name=" + encodeURIComponent(cur.name);
    send("PUT", "api/studio/draft" + q, draft).then(function (r) {
      savedJson = JSON.stringify(draft); savedAt = r.savedAt || ""; chrome();
    }).catch(function (e) { $("st-count").textContent = e.message; }).then(function () { b.disabled = !canEdit; });
  }

  // ---- chrome: top bar counters and the bottom lists ----------------------------------------
  function chrome() {
    var run = $("st-run");
    run.textContent = prod && prod.running ? "running" : "stopped";
    run.className = "st-run" + (prod && prod.running ? "" : " off");
    var ch = changes(), c = $("st-count");
    c.textContent = !ch.length ? "No changes" : draftBlocks().length + " blocks · " + (dirty() ? "unsaved" : "draft saved " + hhmm(savedAt));
    $("st-undo").disabled = !history.length;
    var save = $("st-save");
    save.disabled = !canEdit || !dirty();
    save.title = canEdit ? "" : "Saving a draft needs the AgenticProd_Admin role";
    var pane = $("st-chg");
    pane.textContent = "";
    pane.appendChild(el("h6", "Changes to apply · " + cur.name));
    if (!ch.length) pane.appendChild(el("div", "No changes yet", "text-secondary"));
    ch.forEach(function (x) {
      var row = el("div", null, "st-chg");
      row.appendChild(el("span", "+", "plus"));
      var t = el("span"); t.appendChild(document.createTextNode(x[0] + " ")); t.appendChild(el("b", x[1])); t.appendChild(document.createTextNode(" " + x[2]));
      row.appendChild(t);
      pane.appendChild(row);
    });
    var v = $("st-val");
    v.textContent = "";
    v.appendChild(el("h6", "Validation"));
    v.appendChild(el("div", "Checks run in the next step.", "text-secondary"));
  }

  // ---- floating "Add AI" button and recipe menu ---------------------------------------------
  function placeBar() {
    var bar = $("st-bar"), pop = $("st-pop");
    if (bar) bar.remove();
    var hint = $("st-hint");
    if (hint) hint.remove();
    var cv = $("st-canvas");
    if (!prod) return;
    var item = sel && sel.indexOf("item:") === 0 ? sel.substr(5) : null;
    if (!item) {
      if (pop) pop.remove();
      if (!draftBlocks().length) {
        var h = el("div", null, "st-hint"); h.id = "st-hint";
        h.innerHTML = '<i class="ti ti-hand-click me-1"></i> Click any item, then press <b>Add AI</b>. Existing items are never changed.';
        cv.appendChild(h);
      }
      return;
    }
    var node = $("node-" + keyNode[sel]);
    if (!node) return;
    var nr = node.getBoundingClientRect(), cr = cv.getBoundingClientRect();
    bar = el("div", null, "st-nodebar"); bar.id = "st-bar";
    bar.style.left = Math.max(4, nr.right - cr.left - 120) + "px"; bar.style.top = Math.max(4, nr.top - cr.top - 36) + "px";
    var add = btn('<i class="ti ti-sparkles me-1"></i>Add AI', "st-btn-ai");
    add.addEventListener("click", function () { recipeMenu(item); });
    bar.appendChild(add);
    cv.appendChild(bar);
    if (pop) { pop.style.left = Math.max(4, nr.left - cr.left) + "px"; pop.style.top = (nr.bottom - cr.top + 8) + "px"; }
  }

  function recipeMenu(item) {
    var old = $("st-pop");
    if (old) { old.remove(); return; }
    var pop = el("div", null, "st-pop"); pop.id = "st-pop";
    pop.appendChild(el("h6", "Add AI to " + item + " · pick a recipe"));
    catalog.recipes.forEach(function (r) {
      var d = el("div", null, "st-rec");
      d.innerHTML = '<span class="ic ' + (r.kind || "nn") + '"><i class="ti ti-' + esc(r.icon) + '"></i></span><div><div class="t">' + esc(r.title) +
        (r.recommended ? '<span class="rc">recommended</span>' : "") + '</div><div class="d">' + esc(r.description) + "</div></div>";
      d.addEventListener("click", function () { pop.remove(); addRecipe(r, item); });
      pop.appendChild(d);
    });
    $("st-canvas").appendChild(pop);
    placeBar();
  }

  // ---- right panel --------------------------------------------------------------------------
  // Selection is also kept in our own class: render() rebuilds the nodes, Drawflow forgets its own
  function hilite() {
    Array.prototype.forEach.call(document.querySelectorAll("#st-df .st-sel"), function (n) { n.classList.remove("st-sel"); });
    var n = sel && keyNode[sel] ? $("node-" + keyNode[sel]) : null;
    if (n) n.classList.add("st-sel");
  }

  function side() {
    hilite();
    var s = $("st-side");
    s.textContent = "";
    if (!prod) { s.appendChild(el("div", "Pick a production to start.", "text-secondary")); return; }
    if (!sel) { s.appendChild(el("div", "Select an item on the canvas to see its health and add AI to it.", "text-secondary")); return; }
    if (sel.indexOf("item:") === 0) { itemPanel(s, sel.substr(5)); return; }
    var b = block(sel.substr(4));
    if (!b) return;
    if (b.kind === "agent") agentPanel(s, b); else smallPanel(s, b);
  }

  function itemPanel(s, name) {
    var it = null;
    prod.items.forEach(function (i) { if (i.name === name) it = i; });
    if (!it) return;
    var h = el("div", null, "d-flex align-items-center gap-2 mb-3");
    h.innerHTML = '<span class="avatar avatar-sm" style="background:#eef1f5"><i class="ti ti-' + (ICONS[it.type] || "box") + '"></i></span><div><div class="fw-bold">' + esc(it.name) +
      '</div><div class="text-secondary" style="font-size:12px">Business ' + esc(it.type) + (it.ai ? " · AI block (live)" : " · existing · read-only") + "</div></div>";
    s.appendChild(h);
    var attached = draftBlocks().filter(function (b) { return b.watches && b.watches.indexOf(name) >= 0; }).length + (it.ai ? 1 : 0);
    var row = el("div", null, "row g-2 mb-3");
    [[it.errors24h, "errors · 24 h", it.errors24h ? "text-red" : ""], [it.suspended, "suspended", ""], [attached, "AI attached", ""]].forEach(function (x) {
      var c = el("div", null, "col st-stat");
      c.appendChild(el("div", String(x[0]), "n " + x[2])); c.appendChild(el("div", x[1], "l"));
      row.appendChild(c);
    });
    s.appendChild(row);
    s.appendChild(el("div", "Class", "text-secondary mb-1")); var cls = el("div", null, "mb-2"); cls.appendChild(el("code", it.class)); s.appendChild(cls);
    if (it.lastError) { s.appendChild(el("div", "Last error", "text-secondary mb-1")); s.appendChild(el("div", it.lastError, "mb-3")); }
    if (!it.ai) {
      var add = btn('<i class="ti ti-sparkles me-1"></i>Add AI to this item', "st-btn-ai w-100");
      add.addEventListener("click", function () { recipeMenu(name); });
      s.appendChild(add);
    }
  }

  function field(label, input) {
    var d = el("div", null, "mb-2");
    d.appendChild(el("label", label, "form-label"));
    d.appendChild(input);
    return d;
  }
  function select(opts, value, onChange, cls) {
    var sl = el("select", null, "form-select " + (cls || ""));
    opts.forEach(function (o) { var op = el("option", o[1]); op.value = o[0]; sl.appendChild(op); });
    sl.value = value;
    sl.addEventListener("change", function () { onChange(sl.value); });
    return sl;
  }
  function text(value, onChange, tag) {
    var i = el(tag || "input", null, "form-control");
    i.value = value == null ? "" : value;
    if (tag === "textarea") i.rows = 4;
    i.addEventListener("change", function () { onChange(i.value); });
    return i;
  }
  function edit(fn) { commit(fn); }

  function groupBlock(b, kind) {
    var bs = draftBlocks();
    for (var i = 0; i < bs.length; i++) if (bs[i].group === b.group && bs[i].kind === kind) return bs[i];
    return null;
  }

  function agentPanel(s, b) {
    var head = el("div", null, "d-flex align-items-center gap-2 mb-3");
    head.innerHTML = '<span class="avatar avatar-sm ic ai"><i class="ti ti-robot"></i></span><div><div class="fw-bold">' + esc(b.name) + '</div><div class="text-secondary" style="font-size:12px">' +
      (advanced ? "Agent · class " + esc(pkg()) + ".AI." + esc(b.name) : "Recipe · blocks added to the draft") + "</div></div>";
    s.appendChild(head);
    if (advanced) advancedPanel(s, b); else simplePanel(s, b);
    var foot = el("div", null, "d-flex gap-2 mt-4");
    var done = btn('<i class="ti ti-check me-1"></i>Done', "btn-primary flex-fill");
    done.addEventListener("click", function () { sel = null; side(); placeBar(); });
    var rm = btn("Remove");
    rm.addEventListener("click", function () { removeBlock(b.id); });
    foot.appendChild(done); foot.appendChild(rm);
    s.appendChild(foot);
  }

  function simplePanel(s, b) {
    var modes = [["observe", "Explain only", "observe · nothing changes"], ["propose", "Propose a fix, a person approves", "propose · recommended to start"],
      ["act", "Fix safe cases on its own", "act · whitelisted fixes only, the rest to a person"]];
    var q1 = el("div", null, "st-q");
    q1.innerHTML = '<div class="qt"><span class="qn">1</span>What should the AI do with a failure?</div>';
    modes.forEach(function (m) {
      var o = el("label", null, "st-opt" + (b.mode === m[0] ? " on" : ""));
      var r = el("input", null, "form-check-input mt-1"); r.type = "radio"; r.name = "st-mode"; r.checked = b.mode === m[0];
      r.addEventListener("change", function () { edit(function () { b.mode = m[0]; }); });
      var d = el("div"); d.appendChild(document.createTextNode(m[1])); d.appendChild(el("div", m[2], "d"));
      o.appendChild(r); o.appendChild(d);
      q1.appendChild(o);
    });
    s.appendChild(q1);

    var q2 = el("div", null, "st-q");
    q2.innerHTML = '<div class="qt"><span class="qn">2</span>Who approves?</div>';
    var h = groupBlock(b, "human");
    if (h) {
      var roles = catalog.roles.map(function (r) { return [r, "Role " + r]; });
      if (h.role && catalog.roles.indexOf(h.role) < 0) roles.push([h.role, "Role " + h.role + " (new)"]);
      q2.appendChild(select(roles, h.role, function (v) { edit(function () { h.role = v; }); }));
    } else q2.appendChild(el("div", "This recipe has no human review: nothing is applied or sent for approval.", "text-secondary"));
    s.appendChild(q2);

    var q3 = el("div", null, "st-q");
    q3.innerHTML = '<div class="qt"><span class="qn">3</span>Which AI model and budget?</div>';
    var row = el("div", null, "row g-2");
    var c1 = el("div", null, "col-7"), c2 = el("div", null, "col-5");
    var provs = catalog.providers.map(function (p) { return [p.name, p.name + (p.model ? " · " + p.model : "")]; });
    if (!provs.length) provs = [["", "No provider configured"]];
    c1.appendChild(select(provs, b.provider, function (v) {
      edit(function () { b.provider = v; catalog.providers.forEach(function (p) { if (p.name === v) b.model = p.model || ""; }); });
    }));
    c2.appendChild(select([["0.50", "$0.50 / day"], ["2.00", "$2 / day"], ["10.00", "$10 / day"]], b.budget, function (v) { edit(function () { b.budget = v; }); }));
    row.appendChild(c1); row.appendChild(c2); q3.appendChild(row);
    q3.appendChild(el("div", "Stops at the budget, then sends the message to a person.", "text-secondary mt-1"));
    s.appendChild(q3);

    var adv = el("a", null); adv.href = "#"; adv.style.fontSize = "13px";
    adv.innerHTML = '<i class="ti ti-adjustments me-1"></i>Advanced: instructions, tools, skills, limits';
    adv.addEventListener("click", function (e) { e.preventDefault(); advanced = true; side(); });
    s.appendChild(adv);
  }

  function advancedPanel(s, b) {
    var back = el("a", null); back.href = "#"; back.style.fontSize = "13px";
    back.innerHTML = '<i class="ti ti-arrow-left me-1"></i>Back to the 3 questions';
    back.addEventListener("click", function (e) { e.preventDefault(); advanced = false; side(); });
    s.appendChild(back);

    s.appendChild(el("h5", "Model"));
    var provs = catalog.providers.map(function (p) { return [p.name, p.name]; });
    if (!provs.length) provs = [["", "No provider configured"]];
    s.appendChild(field("Provider", select(provs, b.provider, function (v) { edit(function () { b.provider = v; }); })));
    var row = el("div", null, "row g-2");
    var a = el("div", null, "col-7"), t = el("div", null, "col-5");
    a.appendChild(field("Model", text(b.model, function (v) { edit(function () { b.model = v; }); })));
    t.appendChild(field("Temperature", text(b.temperature, function (v) { edit(function () { b.temperature = v; }); })));
    row.appendChild(a); row.appendChild(t); s.appendChild(row);

    s.appendChild(el("h5", "Instructions"));
    s.appendChild(text(b.instructions, function (v) { edit(function () { b.instructions = v; }); }, "textarea"));
    s.lastChild.placeholder = "Empty: the triage agent template for the recipe";

    s.appendChild(el("h5", "Tools & skills"));
    function checks(list, picked, key, label) {
      list.forEach(function (x) {
        var l = el("label", null, "form-check");
        var c = el("input", null, "form-check-input"); c.type = "checkbox"; c.checked = picked.indexOf(x.cls) >= 0;
        c.addEventListener("change", function () {
          edit(function () { b[key] = c.checked ? picked.concat([x.cls]) : picked.filter(function (p) { return p !== x.cls; }); });
        });
        var sp = el("span", label + x.name, "form-check-label");
        if (x.desc) sp.appendChild(el("span", " · " + x.desc, "text-secondary"));
        l.appendChild(c); l.appendChild(sp);
        s.appendChild(l);
      });
    }
    checks(catalog.toolsets.map(function (x) { return { cls: x.class, name: x.name }; }), b.toolsets || [], "toolsets", "Tools.");
    checks(catalog.skills.map(function (x) { return { cls: x.class, name: x.name, desc: x.description }; }), b.skills || [], "skills", "Skill ");

    s.appendChild(el("h5", "What it may do"));
    var seg = el("div", null, "btn-group w-100 mb-2");
    ["observe", "propose", "act"].forEach(function (m) {
      var x = btn(cap(m), b.mode === m ? "active" : "");
      x.addEventListener("click", function () { edit(function () { b.mode = m; }); });
      seg.appendChild(x);
    });
    s.appendChild(seg);
    s.appendChild(el("div", "Propose: every decision goes to Human review. Act: whitelisted fixes are applied, the rest go to review.", "text-secondary"));

    s.appendChild(el("h5", "Limits"));
    var lr = el("div", null, "row g-2");
    var l1 = el("div", null, "col-6"), l2 = el("div", null, "col-6");
    l1.appendChild(field("Tokens / day", text(b.tokensPerDay, function (v) { edit(function () { b.tokensPerDay = v; }); })));
    l2.appendChild(field("Tool calls / msg", text(b.toolCalls, function (v) { edit(function () { b.toolCalls = v; }); })));
    lr.appendChild(l1); lr.appendChild(l2); s.appendChild(lr);
  }

  function smallPanel(s, b) {
    var meta = BLOCKS[b.kind];
    var head = el("div", null, "d-flex align-items-center gap-2 mb-3");
    head.innerHTML = '<span class="avatar avatar-sm ic ' + meta.cls + '"><i class="ti ti-' + meta.icon + '"></i></span><div><div class="fw-bold">' + esc(b.name) + '</div><div class="text-secondary" style="font-size:12px">' + esc(meta.title) + "</div></div>";
    s.appendChild(head);
    if (b.kind === "sentinel") {
      var names = prod.items.map(function (i) { return i.name; });
      s.appendChild(el("h5", "Watches"));
      names.forEach(function (n) {
        var l = el("label", null, "form-check");
        var c = el("input", null, "form-check-input"); c.type = "checkbox"; c.checked = (b.watches || []).indexOf(n) >= 0;
        c.addEventListener("change", function () {
          edit(function () { b.watches = c.checked ? (b.watches || []).concat([n]) : b.watches.filter(function (w) { return w !== n; }); });
        });
        l.appendChild(c); l.appendChild(el("span", n, "form-check-label"));
        s.appendChild(l);
      });
    } else {
      var roles = catalog.roles.map(function (r) { return [r, r]; });
      if (b.role && catalog.roles.indexOf(b.role) < 0) roles.push([b.role, b.role + " (new)"]);
      s.appendChild(field("Role that approves", select(roles, b.role, function (v) { edit(function () { b.role = v; }); })));
    }
    var rm = btn("Remove", "mt-3");
    rm.addEventListener("click", function () { removeBlock(b.id); });
    s.appendChild(rm);
  }

  // ---- entry --------------------------------------------------------------------------------
  window.studioShow = function (name) {
    if (name !== "studio") return;
    if (!started) { started = true; init(); }
    else if (cur && !(draft && dirty())) { openProduction(cur.ns, cur.name); }
  };
  // Read-only view for checks from the console
  window.studioState = function () { return { production: cur, blocks: draftBlocks().length, selected: sel, dirty: draft ? dirty() : false, canEdit: canEdit }; };
  var active = document.querySelector("#nav .nav-link.active");
  if (active) window.studioShow(active.dataset.tab);
})();
