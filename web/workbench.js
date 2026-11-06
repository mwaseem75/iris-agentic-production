"use strict";
// AI Hub Workbench: the AI Hub Library of the AI Hub classes, and AI Hub in Production,
// a read-only map of what a production uses. Nothing here changes IRIS. Needs el, get, send from the dashboard script.
(function () {
  var panels = { lib: document.getElementById("wb-lib"), prod: document.getElementById("wb-prod") };
  if (!panels.lib || !panels.prod) return;
  var TAB = { lib: "wblib", prod: "wbprod" };
  var started = false, lib = null, libType = "all", libQuery = "", libSource = "", agentSel = "", mapData = null, mapSel = "", mapRes = null;

  // Library groups in page order; key is the field in /workbench/library. Agents are not a tab:
  // they show in the "How the agent is built" card and open from there.
  var GROUPS = [
    { key: "agents", type: "agent", title: "Agents", sub: "%AI.Agent · model, instructions and the parts below", icon: "robot", tab: false, base: "%AI.Agent" },
    { key: "toolsets", type: "tool", title: "Tools", sub: "what the agent may call", icon: "tool", base: "%AI.ToolSet", own: "tools", test: true },
    { key: "skills", type: "skill", title: "Skills", sub: "know-how the agent loads only when needed", icon: "puzzle", base: "%AI.Agent.Skill", own: "skills" },
    { key: "policies", type: "policy", title: "Policies", sub: "rules applied to every tool call", icon: "lock", base: "%AI.Policy.*", own: "policies", test: true },
    { key: "knowledge", type: "knowledge", title: "Knowledge", sub: "what the agent can search", icon: "database-search", base: "%AI.RAG", own: "knowledge" },
    { key: "checks", type: "check", title: "Checks", sub: "plain IRIS code around the agent, not AI Hub · run after its answer", icon: "shield-half", base: "plain IRIS", own: "checks" }
  ];
  var KIND = { model: ["Model", "cpu", "#a78bfa"], toolset: ["ToolSet", "tool", "#60a5fa"], skill: ["Skill", "puzzle", "#c4b5fd"], knowledge: ["Knowledge", "database-search", "#34d399"], policy: ["Policy", "lock", "#f87171"] };
  var TYPE_ICON = { service: "file-import", process: "arrows-split", operation: "send", other: "box" };
  var NEW_ITEMS = [
    ["tool", "database", "Tool", "A read-only SQL query the agent can call"],
    ["skill", "puzzle", "Skill", "Instructions the agent loads when needed"],
    ["policy", "lock", "Policy", "A rule checked on every tool call"],
    ["agent-blank", "robot", "Agent", "Your instructions, your tools"]
  ];

  function icon(name, extra) { return el("i", null, "ti ti-" + name + (extra ? " " + extra : "")); }
  function div(cls, text) { return el("div", text, cls); }
  function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); }
  function num(n) { return Number(n || 0).toLocaleString("en-US"); }
  // One full stop at the end, none doubled
  function tidy(t) { return String(t || "").replace(/\s*\.{2}(?!\.)/g, ".").replace(/\.\s*\.(?=\s|$)/g, "."); }
  function usd(n) { return "$" + Number(n || 0).toFixed(4); }
  function short(n) { var p = String(n || "").split("."); return p[p.length - 1]; }
  function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s"); }

  // The sidebar owns the three views; showSub only asks the dashboard to switch tab
  function showSub(name) { if (window.showTab) window.showTab(TAB[name]); }

  function groupOf(type) { for (var i = 0; i < GROUPS.length; i++) if (GROUPS[i].type === type) return GROUPS[i]; return null; }
  function itemsOf(g) { return (lib && lib[g.key]) || []; }
  function isYours(item) { return String(item["class"]).indexOf("MyAI.") === 0; }
  function byClass(key, cls) { var l = (lib && lib[key]) || []; for (var i = 0; i < l.length; i++) if (l[i]["class"] === cls) return l[i]; return null; }
  function byName(key, name) { var l = (lib && lib[key]) || []; for (var i = 0; i < l.length; i++) if (l[i].name === name) return l[i]; return null; }
  // Skills are titled by class, like everywhere else on the page; the name the model loads is in the drawer
  function titleOf(item, g) { return g.type === "skill" ? short(item["class"]) : item.name; }
  function descOf(item, g) {
    var d = tidy(item.description);
    // The policy description is "<kind> · <class comment>"; the kind has its own badge
    return g.type === "policy" ? d.replace(/^(authorization|audit) · /i, "") : d;
  }

  // What an agent is built from, as the API reports it. An older API without it gives an empty agent.
  function wiringOf(a) {
    var w = (a && a.wiring) || {};
    return { toolsets: w.toolsets || [], skills: w.skills || [], policies: w.policies || [], knowledge: w.knowledge || [] };
  }
  function curAgent() {
    var l = (lib && lib.agents) || [];
    for (var i = 0; i < l.length; i++) if (l[i]["class"] === agentSel) return l[i];
    return l[0] || null;
  }
  // Tool sets the agent reaches: its own and the ones its skills add
  function reachableToolsets(a) {
    var w = wiringOf(a), seen = {}, out = [];
    function add(c) { if (c && !seen[c]) { seen[c] = 1; out.push(c); } }
    w.toolsets.forEach(add);
    w.skills.forEach(function (sc) {
      var sk = byClass("skills", sc);
      if (sk) String(sk.toolsets || "").split(", ").forEach(function (n) { var ts = byName("toolsets", n); if (ts) add(ts["class"]); });
    });
    return out;
  }

  // [{agent, via}]: the agents that use one part, from their wiring
  function usedBy(item, g) {
    var out = [];
    ((lib && lib.agents) || []).forEach(function (a) {
      var w = wiringOf(a);
      if (g.type === "tool") {
        if (w.toolsets.indexOf(item["class"]) >= 0) out.push({ agent: a.name, via: "" });
        itemsOf(groupOf("skill")).forEach(function (s) {
          if (w.skills.indexOf(s["class"]) >= 0 && String(s.toolsets || "").split(", ").indexOf(item.name) >= 0) out.push({ agent: a.name, via: "skill " + short(s["class"]) });
        });
      } else if (g.type === "skill") {
        if (w.skills.indexOf(item["class"]) >= 0) out.push({ agent: a.name, via: "" });
      } else if (g.type === "policy") {
        if (w.policies.indexOf(item["class"]) >= 0) out.push({ agent: a.name, via: "" });
      } else if (g.type === "knowledge") {
        if (w.knowledge.indexOf(item["class"]) >= 0) { var m = /via (skill .+)$/.exec(item.usedBy || ""); out.push({ agent: a.name, via: m ? m[1] : "" }); }
      }
    });
    return out;
  }
  // "used by A via skill S", agents in bold, as parts for meta()
  function usedParts(list, verb) {
    var by = {}, order = [], parts = [];
    list.forEach(function (u) { if (!by[u.agent]) { by[u.agent] = []; order.push(u.agent); } if (u.via) by[u.agent].push(u.via); });
    order.forEach(function (n, i) {
      parts.push((i ? " · " : "") + verb + " ");
      parts.push({ b: n });
      if (by[n].length) parts.push(" via " + by[n].join(", "));
    });
    return parts;
  }
  function meta(parts) {
    var m = div("wb-l-meta");
    parts.forEach(function (p) { if (p && p.b !== undefined) m.appendChild(el("b", p.b)); else m.appendChild(document.createTextNode(p)); });
    return m;
  }
  function metaOf(item, g) {
    var parts = [];
    if (g.type === "tool") {
      var n = (item.tools || []).length;
      parts.push({ b: plural(n, "tool") }); parts.push(item.readOnly ? ", all read-only" : ", can change data");
      var u = usedParts(usedBy(item, g), "used by");
      parts = parts.concat(u.length ? [" · "].concat(u) : [" · not used by an agent yet"]);
    } else if (g.type === "skill") {
      parts.push("uses toolset "); parts.push({ b: item.toolsets || "none" });
      var us = usedParts(usedBy(item, g), "used by");
      if (us.length) parts = parts.concat([" · "], us);
    } else if (g.type === "policy") {
      var up = usedParts(usedBy(item, g), "applies to");
      parts = up.length ? up : ["not attached to an agent"];
    } else if (g.type === "knowledge") {
      var uk = usedParts(usedBy(item, g), "used by");
      parts = (uk.length ? uk : ["not used by an agent yet"]).concat([" · local vector search"]);
    } else {
      parts.push(item.usedBy || "plain IRIS");
    }
    return meta(parts);
  }

  // ---------- page parts
  var anat = div("card wb-l-anat"), libTabs = div("wb-tabs"), libBar = div("wb-bar"), libBody = div("wb-l-body"), libNote = div("wb-note");
  var search = el("input", null, "form-control wb-search");
  search.placeholder = "Search by name, class or description"; search.type = "search"; search.setAttribute("aria-label", "Search the AI Hub Library");
  search.addEventListener("input", function () { libQuery = search.value.toLowerCase(); renderLib(); });
  var sourceBox = el("select", null, "form-select wb-pickbox"); sourceBox.setAttribute("aria-label", "Source");
  [["", "Any source"], ["builtin", "Ships with the app"], ["yours", "Created in Workbench"]].forEach(function (o) { var op = el("option", o[1]); op.value = o[0]; sourceBox.appendChild(op); });
  sourceBox.addEventListener("change", function () { libSource = sourceBox.value; renderLib(); });

  // Create new: a small menu that opens the existing builders
  var newWrap = div("wb-newwrap ms-auto"), newMenu = div("wb-newmenu hidden");
  var newBtn = el("button", null, "btn btn-primary btn-sm"); newBtn.type = "button"; newBtn.setAttribute("aria-haspopup", "true"); newBtn.setAttribute("aria-expanded", "false");
  newBtn.appendChild(icon("plus", "me-1")); newBtn.appendChild(document.createTextNode("Create new")); newBtn.appendChild(icon("chevron-down", "ms-1"));
  function closeNew() { newMenu.classList.add("hidden"); newBtn.setAttribute("aria-expanded", "false"); }
  newBtn.addEventListener("click", function (e) {
    e.stopPropagation();
    var open = newMenu.classList.contains("hidden");
    newMenu.classList.toggle("hidden", !open); newBtn.setAttribute("aria-expanded", open ? "true" : "false");
  });
  NEW_ITEMS.forEach(function (n) {
    var b = el("button", null, "wb-newitem"); b.type = "button";
    b.appendChild(icon(n[1]));
    var t = div(); t.appendChild(el("b", n[2])); t.appendChild(div("wb-d", n[3])); b.appendChild(t);
    b.addEventListener("click", function () { closeNew(); if (window.wbBuilder) window.wbBuilder.create(n[0]); });
    newMenu.appendChild(b);
  });
  newWrap.appendChild(newBtn); newWrap.appendChild(newMenu);
  document.addEventListener("click", closeNew);

  libBar.appendChild(search); libBar.appendChild(sourceBox); libBar.appendChild(newWrap);
  panels.lib.appendChild(anat); panels.lib.appendChild(libTabs); panels.lib.appendChild(libBar); panels.lib.appendChild(libNote); panels.lib.appendChild(libBody);

  function loadLib() {
    libNote.textContent = "Loading…";
    get("api/workbench/library").then(function (d) { lib = d; libNote.textContent = ""; renderLib(); })
      .catch(function (e) { libNote.textContent = "Could not load the AI Hub Library: " + e.message; });
  }

  // ---------- how the agent is built
  function chip(count, title, text, fn, cls) {
    var b = el("button", null, "wb-achip" + (cls ? " " + cls : "")); b.type = "button";
    b.appendChild(el("i", String(count), "wb-acount")); b.appendChild(el("b", title)); b.appendChild(el("span", text));
    b.addEventListener("click", fn);
    return b;
  }
  function sign(t) { return el("span", t, "wb-asign"); }
  function goTo(type) {
    libType = type; renderLib();
    var s = libBody.querySelector('[data-type="' + type + '"]');
    if (s && s.scrollIntoView) s.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function renderAnat() {
    clear(anat);
    var a = curAgent();
    if (!a) { anat.classList.add("hidden"); return; }
    anat.classList.remove("hidden");
    var w = wiringOf(a), sets = reachableToolsets(a), nTools = 0;
    sets.forEach(function (c) { var t = byClass("toolsets", c); if (t) nTools += (t.tools || []).length; });
    var body = div("card-body");
    var top = div("wb-l-anat-h");
    var t = div(); t.appendChild(el("h3", "How the " + a.name + " is built", "wb-l-h3"));
    t.appendChild(div("wb-l-sub", "An agent is its instructions plus these parts. Click a part to see it."));
    top.appendChild(t);
    if (lib.agents.length > 1) {
      var sel = el("select", null, "form-select wb-pickbox"); sel.setAttribute("aria-label", "Agent");
      lib.agents.forEach(function (x) { var o = el("option", x.name); o.value = x["class"]; sel.appendChild(o); });
      sel.value = a["class"];
      sel.addEventListener("change", function () { agentSel = sel.value; renderAnat(); });
      top.appendChild(sel);
    }
    body.appendChild(top);
    var row = div("wb-arow");
    row.appendChild(chip(1, a.name, "model " + (a.model || "none") + " · the agent itself", function () { openDrawer(a, groupOf("agent")); }, "agent"));
    row.appendChild(sign("="));
    row.appendChild(chip(sets.length, "Tools", plural(nTools, "tool") + " · what it can call", function () { goTo("tool"); }));
    row.appendChild(sign("+"));
    row.appendChild(chip(w.skills.length, "Skills", "know-how it loads when needed", function () { goTo("skill"); }));
    row.appendChild(sign("+"));
    row.appendChild(chip(w.policies.length, "Policies", "rules checked on every call", function () { goTo("policy"); }));
    row.appendChild(sign("+"));
    row.appendChild(chip(w.knowledge.length, "Knowledge", "what it can search", function () { goTo("knowledge"); }));
    body.appendChild(row);
    var checks = itemsOf(groupOf("check"));
    if (checks.length) {
      var plain = div("wb-aplain"); plain.appendChild(document.createTextNode("Plain IRIS checks around the agent (not AI Hub):"));
      checks.forEach(function (c) {
        var b = el("button", c.name, "wb-achk"); b.type = "button";
        b.addEventListener("click", function () { openDrawer(c, groupOf("check")); });
        plain.appendChild(b);
      });
      body.appendChild(plain);
    }
    anat.appendChild(body);
  }

  // ---------- tabs, filters and the cards
  function matches(item, g) {
    if (libSource && (libSource === "yours") !== isYours(item)) return false;
    if (!libQuery) return true;
    return (String(item.name) + " " + titleOf(item, g) + " " + item["class"] + " " + descOf(item, g)).toLowerCase().indexOf(libQuery) >= 0;
  }

  function tabGroups() { return GROUPS.filter(function (g) { return g.tab !== false; }); }

  function renderTabs() {
    clear(libTabs);
    var total = 0;
    tabGroups().forEach(function (g) { total += itemsOf(g).length; });
    [["all", "All", total]].concat(tabGroups().map(function (g) { return [g.type, g.title, itemsOf(g).length]; })).forEach(function (f) {
      var b = el("button", null, "wb-tab" + (f[0] === libType ? " active" : "")); b.type = "button";
      b.appendChild(document.createTextNode(f[1] + " "));
      b.appendChild(el("span", String(f[2]), "wb-tabn"));
      b.addEventListener("click", function () { libType = f[0]; renderLib(); });
      libTabs.appendChild(b);
    });
  }

  function badge(text, cls) { return el("span", text, "wb-l-badge " + cls); }
  function sourceBadge(item) { return isYours(item) ? badge("Created in Workbench", "mine") : badge("Ships with the app", "ship"); }

  function btn(label, ic, fn, cls) {
    var b = el("button", null, "btn btn-sm " + (cls || "")); b.type = "button";
    if (ic) b.appendChild(icon(ic, label ? "me-1" : ""));
    if (label) b.appendChild(document.createTextNode(label));
    b.addEventListener("click", function (e) { e.stopPropagation(); fn(b); });
    return b;
  }

  function card(item, g) {
    var c = div("card wb-l-card"); c.tabIndex = 0; c.setAttribute("role", "button");
    c.setAttribute("aria-label", "Open " + titleOf(item, g));
    var h = div("wb-l-ch"); h.appendChild(el("b", titleOf(item, g), "wb-l-name"));
    var badges = div("wb-l-badges");
    if (g.type === "policy") badges.appendChild(badge(item.kind === "audit" ? "Audit" : "Authorization", "kind"));
    if (g.type !== "check") badges.appendChild(sourceBadge(item));
    h.appendChild(badges); c.appendChild(h);
    c.appendChild(div("wb-l-desc", descOf(item, g)));
    c.appendChild(metaOf(item, g));
    var acts = div("wb-l-acts");
    acts.appendChild(btn("Open", "", function () { openDrawer(item, g); }));
    if (g.test) acts.appendChild(btn("Test · $0", "", function () { openDrawer(item, g, "test"); }));
    if (isYours(item) && window.wbBuilder && window.wbBuilder.editable(item["class"]) && g.type !== "knowledge" && g.type !== "check") {
      acts.appendChild(btn("", "pencil", function () { window.wbBuilder.edit(item["class"], function () { openDrawer(item, g); }); }, "btn-icon"));
      acts.lastChild.title = "Edit"; acts.lastChild.setAttribute("aria-label", "Edit " + titleOf(item, g));
    }
    c.appendChild(acts);
    c.addEventListener("click", function () { openDrawer(item, g); });
    c.addEventListener("keydown", function (e) { if (e.key === "Enter" && e.target === c) openDrawer(item, g); });
    return c;
  }

  function emptyHint(g, raw) {
    var word = g.title.toLowerCase();
    if (libQuery) return "Nothing in " + word + " matches the search.";
    if (libSource === "yours") return "No " + word + " of your own yet. Create one from a template.";
    if (!raw) return "No " + word + " found in this namespace.";
    return "Nothing in " + word + " matches the filter.";
  }

  function renderLib() {
    clear(libBody);
    if (!lib) return;
    renderAnat(); renderTabs();
    var shown = 0;
    tabGroups().forEach(function (g) {
      if (libType !== "all" && libType !== g.type) return;
      var raw = itemsOf(g), items = raw.filter(function (i) { return matches(i, g); });
      // With a search running, an empty section is noise in the All view
      if (!items.length && libType === "all" && libQuery) return;
      shown += items.length;
      var sec = div("wb-l-sec"); sec.dataset.type = g.type;
      var h = div("wb-l-sh"); h.appendChild(icon(g.icon)); h.appendChild(el("h2", g.title, "wb-l-h2"));
      h.appendChild(el("span", g.base ? g.base + " · " + g.sub : g.sub, "wb-l-ex")); sec.appendChild(h);
      if (items.length) {
        var grid = div("wb-l-grid"); items.forEach(function (i) { grid.appendChild(card(i, g)); }); sec.appendChild(grid);
      } else sec.appendChild(div("wb-note", emptyHint(g, raw.length)));
      libBody.appendChild(sec);
    });
  }

  function resetLibFilters() {
    libType = "all"; libQuery = ""; libSource = "";
    search.value = ""; sourceBox.value = "";
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

  // ---------- drawer: Overview, Source, Test
  var drawer = div("wb-drawer hidden"); drawer.setAttribute("role", "dialog"); drawer.setAttribute("aria-label", "Part details");
  document.body.appendChild(drawer);
  function closeDrawer() { drawer.classList.add("hidden"); }
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape") return;
    if (!drawer.classList.contains("hidden")) closeDrawer();
    closeNew();
  });

  function section(title) { return el("h4", title, "wb-l-h4"); }
  function listItem(head, sub, mono) {
    var li = div("wb-l-li"); li.appendChild(el(mono ? "code" : "span", head, mono ? "wb-l-code" : "wb-l-lih"));
    if (sub) li.appendChild(el("small", sub));
    return li;
  }

  function overviewPane(item, g) {
    var b = div("wb-l-pane");
    var d = descOf(item, g);
    if (d) b.appendChild(div("wb-l-desc", d));
    if (g.type === "tool") {
      b.appendChild(section("Tools in this set"));
      (item.tools || []).forEach(function (name, i) { b.appendChild(listItem(name, (item.toolDescriptions || [])[i] || "", true)); });
    } else if (g.type === "skill") {
      if ((item.tools || []).length) { b.appendChild(section("Adds tools")); b.appendChild(chips(item.tools)); }
      if (item.toolsets) b.appendChild(kv("Uses toolset", item.toolsets));
      b.appendChild(kv("Loaded by the model as", item.name));
    } else if (g.type === "agent") {
      var w = wiringOf(item);
      b.appendChild(kv("Model", item.model || "none"));
      b.appendChild(section("Built from"));
      reachableToolsets(item).forEach(function (c) { var t = byClass("toolsets", c); if (t) b.appendChild(partButton(t, groupOf("tool"), plural((t.tools || []).length, "tool"))); });
      w.skills.forEach(function (c) { var s = byClass("skills", c); if (s) b.appendChild(partButton(s, groupOf("skill"), "skill")); });
      w.policies.forEach(function (c) { var p = byClass("policies", c); if (p) b.appendChild(partButton(p, groupOf("policy"), p.kind || "policy")); });
      w.knowledge.forEach(function (c) { var k = byClass("knowledge", c); if (k) b.appendChild(partButton(k, groupOf("knowledge"), "knowledge")); });
      if (item.hostedBy) b.appendChild(kv("Runs in", item.hostedBy));
      var acts = div("wb-l-dacts");
      if (window.wbAddProd && window.wbAddProd.canAdd(item["class"])) acts.appendChild(btn("Add to production", "", function () { window.wbAddProd.openFor(item, loadLib); }, "btn-outline-primary"));
      if (isYours(item) && window.wbBuilder && window.wbBuilder.editable(item["class"])) acts.appendChild(btn("Edit", "pencil", function () { window.wbBuilder.edit(item["class"], function () {}); }));
      (item.installs || []).forEach(function (i) {
        acts.appendChild(btn("Remove from " + i.namespace + " " + short(i.production), "arrow-back-up", function (x) { window.wbAddProd.removeInstall(i, x, loadLib); }, "btn-outline-danger"));
      });
      if (acts.firstChild) b.appendChild(acts);
    } else if (g.type === "knowledge") {
      b.appendChild(div("wb-note", "Built by Setup from the LOINC subset; the search runs on local vectors."));
    }
    if (g.type !== "agent") {
      b.appendChild(section("Used by"));
      var users = usedBy(item, g);
      if (users.length) users.forEach(function (u) { b.appendChild(listItem(u.agent, u.via ? "via " + u.via : "")); });
      else b.appendChild(div("wb-note", g.type === "check" ? (item.usedBy || "Runs in the Triage process.") : "No agent uses it yet."));
    }
    return b;
  }
  // An agent's part, as a row that opens that part
  function partButton(item, g, kind) {
    var li = el("button", null, "wb-l-li wb-l-partbtn"); li.type = "button";
    li.appendChild(el("span", titleOf(item, g), "wb-l-lih")); li.appendChild(el("small", kind));
    li.addEventListener("click", function () { openDrawer(item, g); });
    return li;
  }

  function sourcePane(item) {
    var b = div("wb-l-pane");
    if (item["class"] === "search_loinc") { b.appendChild(div("wb-note", "The knowledge base is built by Setup from the LOINC subset; it has no class source.")); return b; }
    var src = el("pre", "Loading the source…", "wb-src"); b.appendChild(src);
    get("api/workbench/source?class=" + encodeURIComponent(item["class"])).then(function (d) { src.textContent = d.source || "(no source)"; })
      .catch(function () { src.textContent = "The source is not available."; });
    return b;
  }

  // The no-LLM test is the builder's: it runs a scratch copy built from the saved form values,
  // so it exists for the parts created in Workbench, and for administrators.
  function testPane(item, g) {
    var b = div("wb-l-pane");
    var note = div("wb-l-testnote");
    note.appendChild(el("b", "Test · no LLM call, $0. "));
    note.appendChild(document.createTextNode(g.type === "tool" ? "Runs the tool with the arguments you give and shows the result." : "Simulates a tool call and shows whether the policy allows it."));
    b.appendChild(note);
    if (!isYours(item) || !window.wbBuilder || !window.wbBuilder.editable(item["class"])) {
      b.appendChild(div("wb-note", "This part ships with the app, and its tests run in the unit suite. Here you can test the parts you create in Workbench."));
      return b;
    }
    var box = div("wb-l-testbox"), out = div("wb-tout");
    b.appendChild(box); b.appendChild(out);
    box.textContent = "Loading the form…";
    get("api/workbench/builder/open?class=" + encodeURIComponent(item["class"])).then(function (d) {
      var spec = d.spec; clear(box);
      if (g.type === "tool") toolForm(spec, box, out); else policyForm(spec, box, out);
    }).catch(function () { box.textContent = "This class was not written by a builder, so there is no test form for it."; });
    return b;
  }
  function field(label, node) { var f = div("wb-f"); f.appendChild(el("label", label, "form-label")); f.appendChild(node); return f; }
  function errList(list) { var u = el("ul", null, "wb-errl"); list.forEach(function (t) { u.appendChild(el("li", t)); }); return u; }
  function toolForm(spec, box, out) {
    var inputs = {}, row = div("wb-targs");
    (spec.args || []).forEach(function (a) {
      if (!a.name) return;
      var i = el("input", null, "form-control wb-mono-in"); i.placeholder = a.type; inputs[a.name] = [i, a.type]; row.appendChild(field(a.name, i));
    });
    if (!(spec.args || []).length) row.appendChild(div("wb-help", "This tool has no arguments."));
    box.appendChild(row);
    box.appendChild(btn("Run", "player-play", function () {
      var args = {};
      Object.keys(inputs).forEach(function (n) {
        var v = inputs[n][0].value.trim(); if (v === "") return;
        var t = inputs[n][1]; args[n] = (t === "%Integer" || t === "%Numeric") ? Number(v) : (t === "%Boolean" ? (v === "1" || v === "true" ? 1 : 0) : v);
      });
      clear(out); out.textContent = "Running…";
      send("POST", "api/workbench/builder/test-tool", { kind: "tool", spec: spec, args: args }).then(function (r) {
        clear(out);
        if (r.errors && r.errors.length) { out.appendChild(errList(r.errors)); return; }
        out.appendChild(window.wbTable(r.result));
        out.appendChild(div("wb-help", r.elapsedMs + " ms · ran as you; the agent itself runs with SELECT only."));
      }).catch(function (e) { out.textContent = e.message; });
    }, "btn-primary mt-2"));
  }
  function policyForm(spec, box, out) {
    var tool = el("input", null, "form-control wb-mono-in"); tool.value = (spec.tools && spec.tools[0]) || "";
    var args = el("input", null, "form-control wb-mono-in"), sample = {}, r0 = (spec.rules || [])[0];
    if (r0 && r0.arg) sample[r0.arg] = r0.value || "";
    args.value = JSON.stringify(sample);
    var two = div("wb-two"); two.appendChild(field("Tool", tool)); two.appendChild(field("Arguments (JSON)", args));
    box.appendChild(two);
    box.appendChild(btn("Check", "player-play", function () {
      var a;
      try { a = JSON.parse(args.value || "{}"); } catch (e) { out.textContent = "Arguments must be valid JSON."; return; }
      clear(out); out.textContent = "Checking…";
      send("POST", "api/workbench/builder/test-policy", { kind: "policy", spec: spec, tool: tool.value.trim(), args: a }).then(function (r) {
        clear(out);
        if (r.errors && r.errors.length) { out.appendChild(errList(r.errors)); return; }
        var d = div("wb-verdict " + (r.allowed ? "ok" : "no")); d.appendChild(el("b", r.allowed ? "ALLOWED" : "DENIED"));
        if (!r.allowed) d.appendChild(div("wb-mono", r.message));
        out.appendChild(d);
      }).catch(function (e) { out.textContent = e.message; });
    }, "btn-primary mt-2"));
  }

  function baseOf(item, g) {
    if (g.type === "policy") return item.kind === "audit" ? "%AI.Policy.Audit" : "%AI.Policy.Authorization";
    return g.base;
  }

  function openDrawer(item, g, tab) {
    clear(drawer); drawer.classList.remove("hidden");
    var top = div("wb-drawer-h");
    var t = div(); t.appendChild(el("h3", titleOf(item, g), "wb-l-dname")); t.appendChild(div("wb-c", item["class"] + " · " + baseOf(item, g)));
    var x = el("button", null, "btn btn-icon btn-ghost-secondary"); x.type = "button"; x.setAttribute("aria-label", "Close");
    x.appendChild(icon("x")); x.addEventListener("click", closeDrawer);
    top.appendChild(t); top.appendChild(x); drawer.appendChild(top);
    var tags = div("wb-l-dtags");
    if (g.type === "policy") tags.appendChild(badge(item.kind === "audit" ? "Audit" : "Authorization", "kind"));
    if (g.type !== "check") tags.appendChild(sourceBadge(item));
    if (tags.firstChild) drawer.appendChild(tags);
    var names = [["overview", "Overview"], ["source", "Source"]];
    if (g.test) names.push(["test", "Test"]);
    var bar = div("wb-l-dtabs"), body = div("wb-drawer-b"), buttons = {};
    function show(which) {
      Object.keys(buttons).forEach(function (k) { buttons[k].classList.toggle("active", k === which); });
      clear(body);
      body.appendChild(which === "source" ? sourcePane(item) : which === "test" ? testPane(item, g) : overviewPane(item, g));
    }
    names.forEach(function (n) {
      var b = el("button", n[1], "wb-l-dtab"); b.type = "button"; buttons[n[0]] = b;
      b.addEventListener("click", function () { show(n[0]); });
      bar.appendChild(b);
    });
    drawer.appendChild(bar); drawer.appendChild(body);
    show(tab || "overview");
  }

  var prodBar = div("wb-bar"), pick = el("select", null, "form-select wb-pick");
  var runBadge = el("span", null, "badge"), statAi = el("span", null, "wb-stat"), stat24 = el("span", null, "wb-stat");
  var prodNote = div("wb-note"), grid = div("wb-mapgrid"), cv = div("wb-cv"), side = div("wb-side");
  prodBar.appendChild(el("span", "Production", "text-secondary")); prodBar.appendChild(pick); prodBar.appendChild(runBadge);
  prodBar.appendChild(statAi); prodBar.appendChild(stat24);
  prodBar.appendChild(div("wb-hint", "Read-only map · change components in the AI Hub Library"));
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
  var stage = null, scale = 1, stageW = 0, stageH = 0, PAD = 48, FITPAD = 24, LEGENDH = 22, CANVASMIN = 520;

  function nodeBox(it, host, small) {
    var n = div("wb-n-node" + (host ? " wb-host" : it.ai ? " wb-ainode" : it.checks ? " wb-chk" : " wb-plain") + (small ? " wb-small" : ""));
    n.dataset.name = it.name;
    n.title = it.name + " · " + it["class"];
    if (!small) n.appendChild(el("span", host || it.ai ? "AI HUB" : it.added ? "added by " + it.added : it.checks ? "checks around the agent" : "no AI Hub", "wb-tagpill" + (host || it.ai ? " hub" : it.added ? " added" : "")));
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

  // Roles: host runs the AI Hub agent; checker is the process that sends to a host (Triage); workflow is a
  // human-task operation; helper is a service that only feeds checker/workflow/host. The rest is the main path.
  function plan(d) {
    var byName = {}, hostOf = {}, out = {}, role = {};
    d.items.forEach(function (i) { byName[i.name] = i; });
    d.hosts.forEach(function (h) { hostOf[h.item] = h; });
    d.connections.forEach(function (c) {
      if (byName[c.from] && byName[c.to]) (out[c.from] = out[c.from] || []).push(c.to);
    });
    d.items.forEach(function (i) {
      if (hostOf[i.name]) role[i.name] = "host";
      else if (/Plugin\.Sentinel$/.test(i["class"])) role[i.name] = "sentinel";
      else if (i.checks || (i.type === "process" && (out[i.name] || []).some(function (t) { return hostOf[t]; }))) role[i.name] = "checker";
      else if (/Workflow/i.test(i["class"])) role[i.name] = "workflow";
    });
    d.items.forEach(function (i) {
      if (role[i.name] || i.type !== "service" || !(out[i.name] || []).length) return;
      if (out[i.name].every(function (t) { return role[t]; })) role[i.name] = "helper";
    });
    d.items.forEach(function (i) { if (!role[i.name]) role[i.name] = "main"; });
    var pick = function (r) { return d.items.filter(function (i) { return role[i.name] === r; }); };
    return { role: role, hostOf: hostOf, out: out, byName: byName, main: pick("main"),
      branch: pick("sentinel").concat(pick("checker"), pick("host"), pick("workflow")), other: pick("helper") };
  }

  function drawMap(d) {
    clear(cv); showSide(null);
    var pl = plan(d), pos = {}, hostOf = pl.hostOf, role = pl.role;
    stage = div("wb-stage"); cv.appendChild(stage);
    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg.setAttribute("class", "wb-svg");
    stage.appendChild(svg);
    var widthOf = function (i) { return hostOf[i.name] ? HW : NW; }, heightOf = function (i) { return hostOf[i.name] ? HH : NH; };
    var label = function (t, x, y, col) { var l = div("wb-lbl", t); l.style.left = x + "px"; l.style.top = y + "px"; if (col) l.style.color = col; stage.appendChild(l); };

    // Row 1: services, routing processes, then every operation stacked in the last column; columns centred on the tallest
    var cols = [[], [], []], LANE = { service: 0, process: 1, operation: 2 };
    pl.main.forEach(function (i) { cols[LANE[i.type] === undefined ? 1 : LANE[i.type]].push(i); });
    var colH = cols.map(function (c) { return c.length ? c.length * NH + (c.length - 1) * GAPY : 0; });
    var mainH = Math.max.apply(null, colH), x = 30, W = 0, procX = 330;
    cols.forEach(function (c, l) {
      if (!c.length) return;
      if (l === 1) procX = x;
      var y = 40 + (mainH - colH[l]) / 2;
      c.forEach(function (i) { pos[i.name] = { x: x, y: y, w: NW, h: NH }; y += NH + GAPY; });
      x += NW + GAPX; W = x - GAPX + 30;
    });
    var mainBottom = mainH > 0 ? 40 + mainH : 0;

    // Row 2: checker, agent host, workflow, starting under the routing column
    var y2 = mainBottom ? mainBottom + 110 : 50, bx = procX, branchBottom = y2;
    pl.branch.forEach(function (i) {
      pos[i.name] = { x: bx, y: y2, w: widthOf(i), h: heightOf(i) };
      bx += widthOf(i) + GAPX; branchBottom = Math.max(branchBottom, y2 + heightOf(i)); W = Math.max(W, bx - GAPX + 30);
    });
    // Row 3: the parts of each host in one row directly under it
    var cy = branchBottom + 90, comps = [];
    d.hosts.forEach(function (h) {
      var hp = pos[h.item]; if (!hp) return;
      var count = h.components.length, cw = Math.max(92, Math.min(CW, Math.floor((Math.max(W, 900) - 60) / Math.max(1, count))));
      var sx = Math.max(30, hp.x + hp.w / 2 - count * cw / 2);
      W = Math.max(W, sx + count * cw + 30);
      comps.push({ h: h, hp: hp, sx: sx, cw: cw, y: cy });
      cy += 150 + 20;
    });
    // Row 4: helper items as small chips, no lines
    if (pl.other.length) {
      var oy = cy + 10, per = Math.max(1, Math.floor((Math.max(W, 900) - 60) / 200));
      pl.other.forEach(function (i, idx) { pos[i.name] = { x: 30 + (idx % per) * 200, y: oy + 28 + Math.floor(idx / per) * 54, w: 186, h: 42, small: true }; });
      cy = oy + 28 + Math.ceil(pl.other.length / per) * 54;
      var ttl = el("span", "Other items", "wb-strip-title"); ttl.style.top = oy + "px"; stage.appendChild(ttl);
    }
    W = Math.max(W, 900);
    var H = cy + 50;

    d.items.forEach(function (i) {
      var p = pos[i.name]; if (!p) return;
      var n = nodeBox(i, hostOf[i.name], p.small);
      if (p.small) n.querySelector(".wb-nk").textContent = "-> " + ((pl.out[i.name] || []).map(short).join(", ") || "none");
      n.style.left = p.x + "px"; n.style.top = p.y + "px"; n.style.width = p.w + "px"; n.style.height = p.h + "px";
      stage.appendChild(n);
    });
    var PURPLE = "#a78bfa", GREY = "#9ca3af", seenArc = {};
    // Watched items -> Sentinel (red dashed), then Sentinel -> check process
    d.items.forEach(function (i) {
      var s = pos[i.name]; if (role[i.name] !== "sentinel" || !s) return;
      String(i.watches || "").split(",").forEach(function (w) {
        var a = pos[w.trim()]; if (!a || a.small) return;
        svg.appendChild(vpath(a.x + a.w / 2, a.y + a.h, s.x + s.w / 2, s.y, "#f87171", true));
      });
    });
    d.connections.forEach(function (c) {
      var a = pos[c.from], b = pos[c.to]; if (!a || !b || a.small || b.small) return;
      var ra = role[c.from], rb = role[c.to];
      if (ra === "sentinel" && rb === "checker") {
        svg.appendChild(curve("M" + (a.x + a.w) + "," + (a.y + a.h / 2) + " C" + (a.x + a.w + 40) + "," + (a.y + a.h / 2) + " " + (b.x - 40) + "," + (b.y + b.h / 2) + " " + b.x + "," + (b.y + b.h / 2), "#f87171", true));
      } else if (ra === "main" && rb === "main") {
        if (b.x >= a.x + a.w) svg.appendChild(hpath(a.x + a.w, a.y + a.h / 2, b.x, b.y + b.h / 2, GREY));
      } else if (ra === "main" && rb === "checker") {
        svg.appendChild(vpath(a.x + a.w * 0.7, a.y + a.h, b.x + b.w * 0.7, b.y, "#f87171"));
        label("failed", a.x + a.w * 0.7 + 8, (a.y + a.h + b.y) / 2 - 8, "#f87171");
      } else if (ra === "checker" && rb === "main") {
        svg.appendChild(vpath(a.x + a.w * 0.3, a.y, b.x + b.w * 0.3, b.y + b.h, "#34d399"));
        label("fixed / resend", a.x + a.w * 0.3 - 92, (a.y + b.y + b.h) / 2 - 8, "#34d399");
      } else if (ra === "checker" && rb === "host") {
        svg.appendChild(hpath(a.x + a.w, a.y + a.h / 2, b.x, b.y + b.h / 2, PURPLE));
      } else if (rb === "workflow" && (ra === "host" || ra === "checker")) {
        if (seenArc[c.to]) return; seenArc[c.to] = 1;
        if (ra === "host") {
          svg.appendChild(hpath(a.x + a.w, a.y + a.h / 2, b.x, b.y + b.h / 2, GREY));
          label("human review", a.x + a.w + 6, a.y + a.h / 2 - 24, "#cbd5e1");
        } else {
          var ax = a.x + a.w * 0.85, bxm = b.x + b.w / 2, top = a.y - 26;
          svg.appendChild(curve("M" + ax + "," + a.y + " L" + ax + "," + top + " L" + bxm + "," + top + " L" + bxm + "," + b.y, GREY));
          label("human review", (ax + bxm) / 2 - 36, top - 20, "#cbd5e1");
        }
      }
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
    // The banners above the page can appear after the data loads and move the canvas down
    setTimeout(fit, 500);
  }

  // Canvas height: what is left of the window below the controls, never under CANVASMIN
  function sizeCanvas() {
    var top = wrap.getBoundingClientRect().top;
    cv.style.height = Math.max(CANVASMIN, Math.floor(window.innerHeight - top - 20)) + "px";
  }

  function applyScale() {
    if (!stage) return;
    stage.style.transform = "scale(" + scale + ")";
    // Top pad keeps the zoom buttons clear of the nodes; a graph narrower than the canvas is centred
    stage.style.top = PAD + "px";
    stage.style.left = Math.max(0, Math.floor((cv.clientWidth - stageW * scale) / 2)) + "px";
  }

  // Whole graph in view with a little padding, so nothing is cut at the right or bottom. On a narrow
  // screen the floor stops labels shrinking to nothing; the canvas scrolls instead.
  function fit() {
    if (!stage) return;
    sizeCanvas();
    var floor = window.innerWidth < 768 ? 0.45 : 0.3;
    var w = (cv.clientWidth - 2 * FITPAD) / stageW, h = (cv.clientHeight - PAD - FITPAD - LEGENDH) / stageH;
    scale = Math.max(floor, Math.min(1, w, h));
    applyScale();
    cv.scrollLeft = 0; cv.scrollTop = 0;
  }

  function zoom(f) { scale = Math.max(0.3, Math.min(1.6, scale * f)); applyScale(); }

  function showSide(c) {
    clear(side);
    if (!c) {
      var how = div("card"); var b = div("card-body");
      b.appendChild(div("fw-semibold mb-2", "How to read this map"));
      b.appendChild(div("wb-d", "Grey items move messages and do not use AI Hub. The purple card hosts the AI Hub agent; the circles under it are the AI Hub parts it uses. Click a circle to see what it is. Triage is plain IRIS: it checks every agent answer before anything changes."));
      how.appendChild(b); side.appendChild(how);
      if (window.wbAddProd && mapData && mapData.installs && mapData.installs.length) side.appendChild(window.wbAddProd.installCards(mapData.installs, function () { openProduction(mapData.namespace, mapData.name); }));
      return;
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
    var lb = el("button", null, "btn flex-fill"); lb.type = "button"; lb.appendChild(icon("books", "me-1")); lb.appendChild(document.createTextNode("Open in AI Hub Library"));
    lb.addEventListener("click", function () { openInLibrary(c); });
    row.appendChild(lb); b2.appendChild(row);
    cardEl.appendChild(b2); side.appendChild(cardEl);
  }

  function openInLibrary(c) {
    resetLibFilters();
    showSub("lib");
    var find = function () {
      renderLib();
      var hit = null;
      GROUPS.forEach(function (g) { (lib[g.key] || []).forEach(function (i) { if (!hit && i["class"] === c["class"]) hit = [i, g]; }); });
      if (hit) openDrawer(hit[0], hit[1]);
    };
    if (lib) find(); else get("api/workbench/library").then(function (d) { lib = d; find(); });
  }

  window.workbenchReload = loadLib;
  window.workbenchRefresh = function () { loadProductions(); };

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
