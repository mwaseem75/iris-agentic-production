"use strict";
// Workbench builders: template picker and the four forms (SQL tool, skill, protect-arguments
// policy, agent). Form on the left, generated class on the right. Nothing is saved until
// Save & compile; the server checks admin, the MyAI.* package and the compile again.
// Needs el, get, send from the dashboard script and window.workbenchReload from workbench.js.
(function () {
  var host = document.getElementById("wb-lib");
  if (!host) return;
  var view = el("div", null, "wb-builder hidden");
  host.appendChild(view);
  var opts = null, cur = null, genTimer = null, genSeq = 0;
  var TYPES = ["%String", "%Integer", "%Numeric", "%Boolean"];
  var OPS = ["equals", "contains", "starts with"];

  var TEMPLATES = [
    { group: "Tool", cls: "tool", items: [
      { id: "tool", icon: "database", title: "SQL query tool", text: "The agent runs one read-only query you write. No code." },
      { icon: "code", title: "Method tool", text: "Expose an existing ClassMethod as a tool." },
      { icon: "route", title: "Interoperability pack", text: "Message, queue and error tools for any production." },
      { icon: "plug-connected", title: "Remote MCP server", text: "Use tools from an MCP server, key from the Wallet." } ] },
    { group: "Skill", cls: "skill", items: [
      { id: "skill", icon: "file-text", title: "Skill", text: "When to load, steps, rules, tools." },
      { icon: "file-import", title: "Import SKILL.md", text: "From a folder or Git." } ] },
    { group: "Agent", cls: "agent", items: [
      { id: "agent-triage", icon: "first-aid-kit", title: "Triage agent", text: "Explain or fix failed messages." },
      { id: "agent-blank", icon: "square-plus", title: "Blank agent", text: "Your instructions, your tools." } ] },
    { group: "Policy", cls: "pol", items: [
      { icon: "list-check", title: "Allow only these tools", text: "Authorization by tool name." },
      { id: "policy", icon: "forbid", title: "Protect arguments", text: "Block calls that touch given fields or values." },
      { icon: "notes", title: "Audit to a table", text: "Log every call, allowed or denied." } ] },
    { group: "Knowledge", cls: "kb", items: [
      { icon: "file-spreadsheet", title: "From a CSV", text: "Vector search tool, local embeddings." } ] }
  ];

  function fresh(id) {
    if (id === "tool") return { kind: "tool", class: "MyAI.Tools.Queue", tool: "get_queue_status", maxRows: 20,
      description: "Show how many messages are waiting for one production item and the oldest one. itemName is the config name, e.g. \"EhrOut\". Use it to decide whether a target is down before you propose RESEND.",
      args: [{ name: "itemName", type: "%String", required: true }],
      sql: "SELECT COUNT(*) AS Waiting, MIN(TimeCreated) AS Oldest\nFROM Ens.MessageHeader\nWHERE TargetConfigName = :itemName AND Status = 'Queued'" };
    if (id === "skill") return { kind: "skill", class: "MyAI.Skill.QueueCheck", name: "queue-check", tools: [],
      description: "Load when a target system may be down, before proposing RESEND.",
      instructions: "# Queue check\n\n1. Call the queue tool for the target item.\n2. If messages are waiting and the oldest is old, propose RESEND later; otherwise ESCALATE." };
    if (id === "policy") return { kind: "policy", class: "MyAI.Policy.ProtectIdentity", tools: [], message: "Patient identity is protected. Escalate instead.",
      rules: [{ arg: "segmentRef", op: "equals", value: "PID" }] };
    var triage = id === "agent-triage";
    var p = opts && opts.providers && opts.providers[0];
    return { kind: "agent", class: triage ? "MyAI.Agent.OrdersTriage" : "MyAI.Agent.MyAgent",
      providerConfig: p ? p.name : "", model: p ? p.model : "",
      toolsets: triage ? ["AgenticProd.Tools.Base"] : [], skills: triage ? ["AgenticProd.Skill.CodeMapping"] : [],
      authPolicy: triage ? "AgenticProd.Policy.ReadOnly" : "", auditPolicy: triage ? "AgenticProd.Policy.Audit" : "",
      instructions: triage ? "You triage failed order messages. Read the error first, then the message. Never change patient identity. If unsure, escalate. Answer with one decision JSON." : "" };
  }

  function div(cls, text) { return el("div", text, cls); }
  function icon(n) { return el("i", null, "ti ti-" + n); }
  function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); }
  function btn(text, cls, ic, fn) {
    var b = el("button", null, "btn " + (cls || "")); b.type = "button";
    if (ic) { b.appendChild(icon(ic)); b.firstChild.className += " me-1"; }
    b.appendChild(document.createTextNode(text)); b.addEventListener("click", fn); return b;
  }
  function field(label, node, help, cls) {
    var f = div(cls || "wb-f"); f.appendChild(el("label", label, "form-label")); f.appendChild(node);
    if (help) f.appendChild(div("wb-help", help));
    return f;
  }
  // Inputs write straight into cur and ask for a new preview
  function text(key, mono) {
    var i = el("input", null, "form-control" + (mono ? " wb-mono-in" : "")); i.value = cur[key] == null ? "" : cur[key];
    i.addEventListener("input", function () { cur[key] = i.value; changed(); }); return i;
  }
  function area(key, rows) {
    var a = el("textarea", null, "form-control"); a.rows = rows; a.value = cur[key] || "";
    a.addEventListener("input", function () { cur[key] = a.value; changed(); }); return a;
  }
  function choose(list, value, fn) {
    var s = el("select", null, "form-select");
    list.forEach(function (o) { var op = el("option", o[1]); op.value = o[0]; s.appendChild(op); });
    s.value = value; s.addEventListener("change", function () { fn(s.value); }); return s;
  }
  function checks(list, key, none) {
    var w = div("wb-checks");
    if (!list.length) w.appendChild(div("wb-help", none));
    list.forEach(function (o) {
      var l = el("label", null, "form-check"); var c = el("input", null, "form-check-input"); c.type = "checkbox";
      c.checked = cur[key].indexOf(o[0]) >= 0;
      c.addEventListener("change", function () {
        cur[key] = cur[key].filter(function (x) { return x !== o[0]; });
        if (c.checked) cur[key].push(o[0]);
        changed();
      });
      l.appendChild(c); l.appendChild(el("span", o[1], "form-check-label")); w.appendChild(l);
    });
    return w;
  }
  function rowsTable(key, cols, blank, heads) {
    var t = el("table", null, "table table-sm mb-1"), hd = el("tr");
    heads.concat([""]).forEach(function (h) { hd.appendChild(el("th", h)); });
    t.appendChild(el("thead")).appendChild(hd);
    var tb = el("tbody"); t.appendChild(tb);
    cur[key].forEach(function (r, i) {
      var tr = el("tr");
      cols.forEach(function (c) {
        var td = el("td"), inp;
        if (c.type === "select") inp = choose(c.list.map(function (x) { return [x, x]; }), r[c.key], function (v) { r[c.key] = v; changed(); });
        else if (c.type === "check") { inp = el("input", null, "form-check-input"); inp.type = "checkbox"; inp.checked = !!r[c.key]; inp.addEventListener("change", function () { r[c.key] = inp.checked; changed(); }); }
        else { inp = el("input", null, "form-control form-control-sm wb-mono-in"); inp.value = r[c.key] || ""; inp.addEventListener("input", function () { r[c.key] = inp.value; changed(); }); }
        td.appendChild(inp); tr.appendChild(td);
      });
      var x = btn("", "btn-sm btn-ghost-secondary btn-icon", "x", function () { cur[key].splice(i, 1); redraw(); changed(); });
      x.setAttribute("aria-label", "Remove"); var td2 = el("td"); td2.appendChild(x); tr.appendChild(td2); tb.appendChild(tr);
    });
    var wrap = div(); wrap.appendChild(t);
    wrap.appendChild(btn("Add", "btn-sm", "plus", function () { cur[key].push(JSON.parse(JSON.stringify(blank))); redraw(); changed(); }));
    return wrap;
  }

  // ---- shell ---------------------------------------------------------------------------------
  var left = null, codeEl, errEl, badge, msgEl, testBox, testOut, saveB, valB, argInputs = {}, polTool, polArgs;
  var META = { tool: ["tool", "database", "New SQL query tool", "Template · read-only · no ObjectScript needed"],
    skill: ["skill", "puzzle", "New skill", "Instructions and tools the agent loads only when it needs them"],
    policy: ["pol", "forbid", "New policy · Protect arguments", "Authorization · AI Hub runs it before every tool call; a deny stops the call"],
    agent: ["agent", "robot", "New agent", "An agent = model + instructions + tools + skills + policies"] };

  function redraw() { build(); }

  function build() {
    clear(view);
    var m = META[cur.kind], editing = !!cur.$editing;
    var bar = div("wb-bar");
    bar.appendChild(btn("Library", "btn-sm", "arrow-left", close));
    var hd = div("wb-sh"), ic = div("wb-ic t-" + m[0]); ic.appendChild(icon(m[1]));
    var t = div(); t.appendChild(div("fw-bold", editing ? "Edit " + cur.class : m[2])); t.appendChild(div("wb-d", m[3]));
    hd.appendChild(ic); hd.appendChild(t); bar.appendChild(hd); view.appendChild(bar);
    if (opts && !opts.canEdit) view.appendChild(div("wb-note", "Only administrators can validate and save. You can read the form and the generated class."));
    var grid = div("wb-bgrid"), card = div("card"), body = div("card-body");
    card.appendChild(body); grid.appendChild(card); left = body;
    var cls = text("class", true); if (editing) cls.readOnly = true;
    body.appendChild(field("Class", cls, "Must be under MyAI. Letters and digits only."));
    ({ tool: formTool, skill: formSkill, policy: formPolicy, agent: formAgent })[cur.kind](body);
    var right = div("wb-bcol");
    var c1 = div("card"), h1 = div("card-header"), t1 = el("h3", "Generated class", "card-title");
    h1.appendChild(t1); badge = el("span", "", "wb-badge"); h1.appendChild(badge); c1.appendChild(h1);
    var b1 = div("card-body p-2"); errEl = div("wb-errs"); codeEl = el("pre", "", "wb-src");
    b1.appendChild(errEl); b1.appendChild(codeEl); c1.appendChild(b1); right.appendChild(c1);
    if (cur.kind === "tool" || cur.kind === "policy") right.appendChild(testCard());
    msgEl = div("wb-note");
    var acts = div("wb-acts");
    valB = btn("Validate", "", "checklist", function () { act("validate"); });
    saveB = btn("Save & compile", "btn-primary", "device-floppy", function () { act("save"); });
    acts.appendChild(msgEl); acts.appendChild(btn("Cancel", "", null, close)); acts.appendChild(valB); acts.appendChild(saveB);
    if (opts && !opts.canEdit) { valB.disabled = true; saveB.disabled = true; }
    right.appendChild(acts); grid.appendChild(right); view.appendChild(grid);
    changed();
  }

  function formTool(b) {
    b.appendChild(field("Tool name (what the AI calls)", text("tool", true)));
    b.appendChild(field("Description", area("description", 4), "The AI only sees this text. Say when to use the tool and what each argument means."));
    b.appendChild(field("Arguments", rowsTable("args", [{ key: "name" }, { key: "type", type: "select", list: TYPES }, { key: "required", type: "check" }], { name: "", type: "%String", required: true }, ["Name", "Type", "Required"])));
    var sql = area("sql", 5); sql.className += " wb-mono-in";
    b.appendChild(field("SQL", sql, "One SELECT. Use :name for arguments. Nothing else is accepted."));
    var mr = text("maxRows"); mr.type = "number"; mr.addEventListener("input", function () { cur.maxRows = Number(mr.value); });
    b.appendChild(field("Max rows", mr));
  }
  function formSkill(b) {
    b.appendChild(field("Skill name", text("name", true), "Letters, digits and hyphens, like code-mapping."));
    b.appendChild(field("When to load it", area("description", 2), "The AI reads this line to decide whether to load the skill."));
    b.appendChild(field("Instructions", area("instructions", 8)));
    b.appendChild(field("Tools the skill adds", checks(((opts && opts.toolsets) || []).map(function (t) { return [t.class, t.name + " · " + t.class]; }), "tools", "No tool classes yet.")));
  }
  function toolNames() {
    var seen = {}, out = [];
    ((opts && opts.toolsets) || []).concat((opts && opts.skills) || []).forEach(function (s) { (s.tools || []).forEach(function (n) { if (!seen[n]) { seen[n] = 1; out.push(n); } }); });
    return out;
  }
  function formPolicy(b) {
    b.appendChild(field("Applies to tools", checks(toolNames().map(function (n) { return [n, n]; }), "tools", "No tools found."), "Leave all unchecked to apply to every tool."));
    b.appendChild(field("Rules", rowsTable("rules", [{ key: "arg" }, { key: "op", type: "select", list: OPS }, { key: "value" }], { arg: "", op: "equals", value: "" }, ["Argument", "Rule", "Value"]), "Case does not matter. Read-only tiers still apply first."));
    b.appendChild(field("Message to the agent when denied", text("message")));
  }
  function formAgent(b) {
    var ps = (opts && opts.providers) || [];
    var sel = choose(ps.map(function (p) { return [p.name, "AI.LLM." + p.name + " · " + p.model]; }).concat(ps.length ? [] : [["", "No model configuration (Settings tab)"]]), cur.providerConfig, function (v) {
      cur.providerConfig = v; var p = ps.filter(function (x) { return x.name === v; })[0]; if (p) { cur.model = p.model; mdl.value = p.model; } changed();
    });
    var mdl = text("model", true);
    var row = div("wb-two"); row.appendChild(field("Model configuration", sel, "Config Store entry; the key stays in the Wallet.")); row.appendChild(field("Model", mdl));
    b.appendChild(row);
    b.appendChild(field("Instructions", area("instructions", 6)));
    b.appendChild(field("Tools · always available", checks(((opts && opts.toolsets) || []).map(function (t) { return [t.class, t.name + " · " + t.class]; }), "toolsets", "No tool classes yet.")));
    b.appendChild(field("Skills · loaded only when needed", checks(((opts && opts.skills) || []).map(function (t) { return [t.class, t.name]; }), "skills", "No skills yet.")));
    var pol = function (list) { return [["", "None"]].concat(list.map(function (p) { return [p.class, p.name + " · " + p.class]; })); };
    var r2 = div("wb-two");
    r2.appendChild(field("Authorization policy", choose(pol((opts && opts.authorization) || []), cur.authPolicy, function (v) { cur.authPolicy = v; changed(); })));
    r2.appendChild(field("Audit policy", choose(pol((opts && opts.audit) || []), cur.auditPolicy, function (v) { cur.auditPolicy = v; changed(); })));
    b.appendChild(r2);
  }

  // ---- tests (no AI) -------------------------------------------------------------------------
  function testCard() {
    var c = div("card"), h = div("card-header");
    h.appendChild(el("h3", cur.kind === "tool" ? "Test the tool" : "Test the policy", "card-title"));
    h.appendChild(div("wb-help", cur.kind === "tool" ? "runs the query directly · no AI · $0" : "simulated tool call · no AI · $0"));
    c.appendChild(h); testBox = div("card-body"); c.appendChild(testBox); testOut = div("wb-tout");
    argInputs = {};
    if (cur.kind === "tool") {
      var row = div("wb-targs");
      cur.args.forEach(function (a) {
        if (!a.name) return;
        var i = el("input", null, "form-control wb-mono-in"); i.placeholder = a.type; argInputs[a.name] = [i, a.type];
        row.appendChild(field(a.name, i, "", "wb-f"));
      });
      if (!cur.args.length) row.appendChild(div("wb-help", "This tool has no arguments."));
      testBox.appendChild(row);
      testBox.appendChild(btn("Run", "btn-primary mt-2", "player-play", testTool));
    } else {
      var names = cur.tools.length ? cur.tools : toolNames();
      polTool = el("input", null, "form-control wb-mono-in"); polTool.value = names[0] || ""; polTool.setAttribute("list", "wb-tools-dl");
      var dl = el("datalist"); dl.id = "wb-tools-dl"; names.forEach(function (n) { var o = el("option"); o.value = n; dl.appendChild(o); });
      polArgs = el("input", null, "form-control wb-mono-in");
      var r0 = cur.rules[0], sample = {};
      if (r0 && r0.arg) sample[r0.arg] = r0.value || "";
      polArgs.value = JSON.stringify(sample);
      var row2 = div("wb-two"); row2.appendChild(field("Tool", polTool)); row2.appendChild(field("Arguments (JSON)", polArgs));
      testBox.appendChild(dl); testBox.appendChild(row2);
      testBox.appendChild(btn("Check", "btn-primary mt-2", "player-play", testPolicy));
    }
    testBox.appendChild(testOut);
    return c;
  }
  function testTool() {
    var args = {};
    Object.keys(argInputs).forEach(function (n) {
      var v = argInputs[n][0].value.trim(); if (v === "") return;
      var t = argInputs[n][1]; args[n] = (t === "%Integer" || t === "%Numeric") ? Number(v) : (t === "%Boolean" ? (v === "1" || v === "true" ? 1 : 0) : v);
    });
    clear(testOut); testOut.textContent = "Running…";
    send("POST", "api/workbench/builder/test-tool", { kind: "tool", spec: cur, args: args }).then(function (r) {
      clear(testOut);
      if (r.errors && r.errors.length) { testOut.appendChild(errList(r.errors)); return; }
      testOut.appendChild(el("pre", r.result, "wb-src wb-small"));
      testOut.appendChild(div("wb-help", r.elapsedMs + " ms · ran as you; the agent itself runs with SELECT only."));
    }).catch(function (e) { testOut.textContent = e.message; });
  }
  function testPolicy() {
    var args;
    try { args = JSON.parse(polArgs.value || "{}"); } catch (e) { testOut.textContent = "Arguments must be valid JSON."; return; }
    clear(testOut); testOut.textContent = "Checking…";
    send("POST", "api/workbench/builder/test-policy", { kind: "policy", spec: cur, tool: polTool.value.trim(), args: args }).then(function (r) {
      clear(testOut);
      if (r.errors && r.errors.length) { testOut.appendChild(errList(r.errors)); return; }
      var d = div("wb-verdict " + (r.allowed ? "ok" : "no"));
      d.appendChild(el("b", r.allowed ? "ALLOWED" : "DENIED"));
      if (!r.allowed) d.appendChild(div("wb-mono", r.message));
      testOut.appendChild(d);
    }).catch(function (e) { testOut.textContent = e.message; });
  }

  // ---- preview, validate, save ---------------------------------------------------------------
  function errList(list) {
    var u = el("ul", null, "wb-errl"); list.forEach(function (t) { u.appendChild(el("li", t)); }); return u;
  }
  function body() { return { kind: cur.kind, spec: cur }; }
  function changed() {
    clearTimeout(genTimer); setBadge("", "");
    genTimer = setTimeout(function () {
      var seq = ++genSeq;
      send("POST", "api/workbench/builder/generate", body()).then(function (r) {
        if (seq !== genSeq) return;
        showResult(r);
      }).catch(function (e) { if (seq === genSeq) { clear(errEl); errEl.appendChild(errList([e.message])); } });
    }, 300);
  }
  function setBadge(t, cls) { if (badge) { badge.textContent = t; badge.className = "wb-badge " + cls; } }
  function showResult(r) {
    clear(errEl);
    if (r.code) codeEl.textContent = r.code;
    if (r.errors && r.errors.length) { errEl.appendChild(errList(r.errors)); setBadge("needs changes", "bad"); }
    else if (r.ok) setBadge("compiles", "ok");
    else setBadge("", "");
  }
  function act(name) {
    clearTimeout(genTimer); ++genSeq;
    msgEl.textContent = name === "save" ? "Saving…" : "Compiling a scratch copy…";
    valB.disabled = saveB.disabled = true;
    send("POST", "api/workbench/builder/" + name, body()).then(function (r) {
      showResult(r);
      if (name === "save" && r.saved) {
        cur.$editing = true; msgEl.textContent = "Saved and compiled " + r.class + ".";
        if (window.workbenchReload) window.workbenchReload();
      } else msgEl.textContent = r.ok ? "Compiled. Nothing was saved." : "Not saved.";
    }).catch(function (e) { msgEl.textContent = e.message; })
      .then(function () { if (opts && opts.canEdit) valB.disabled = saveB.disabled = false; });
  }

  // ---- entry points --------------------------------------------------------------------------
  function show() { host.classList.add("wb-building"); view.classList.remove("hidden"); window.scrollTo(0, 0); }
  function close() { host.classList.remove("wb-building"); view.classList.add("hidden"); cur = null; }
  function withOpts(fn) {
    if (opts) return fn();
    get("api/workbench/builder/options").then(function (o) { opts = o; fn(); }).catch(function () { opts = { canEdit: false, providers: [], toolsets: [], skills: [], authorization: [], audit: [] }; fn(); });
  }

  function picker() {
    var bg = div("wb-modalbg"), box = div("wb-modal");
    var hd = div("wb-mhd"), t = div(); t.appendChild(div("fw-bold", "New from template")); t.appendChild(div("wb-d", "Each template writes a real IRIS class you can read, test and keep"));
    var x = btn("", "btn-icon btn-ghost-secondary", "x", function () { document.body.removeChild(bg); }); x.setAttribute("aria-label", "Close");
    hd.appendChild(t); hd.appendChild(x); box.appendChild(hd);
    var inner = div("wb-mbody");
    TEMPLATES.forEach(function (g) {
      var sec = div("wb-tgroup"); sec.appendChild(div("fw-semibold mb-2", g.group));
      var row = div("wb-tgrid");
      g.items.forEach(function (it) {
        var c = div("wb-tpl" + (it.id ? "" : " soon")), ic = div("wb-ic t-" + g.cls); ic.appendChild(icon(it.icon));
        var tx = div(); tx.appendChild(div("wb-n", it.title)); tx.appendChild(div("wb-d", it.text));
        if (!it.id) tx.appendChild(el("span", "coming soon", "wb-tag"));
        c.appendChild(ic); c.appendChild(tx);
        if (it.id) c.addEventListener("click", function () { document.body.removeChild(bg); startNew(it.id); });
        row.appendChild(c);
      });
      sec.appendChild(row); inner.appendChild(sec);
    });
    box.appendChild(inner); bg.appendChild(box);
    bg.addEventListener("click", function (e) { if (e.target === bg) document.body.removeChild(bg); });
    document.body.appendChild(bg);
  }
  function startNew(id) { withOpts(function () { cur = fresh(id); show(); build(); }); }

  window.wbBuilder = {
    templates: function () { withOpts(picker); },
    // MyAI classes written by a builder reopen in it; others fall back to the read-only drawer
    edit: function (cls, fallback) {
      get("api/workbench/builder/open?class=" + encodeURIComponent(cls)).then(function (d) {
        withOpts(function () { cur = d.spec; cur.$editing = true; show(); build(); });
      }).catch(function () { if (fallback) fallback(); });
    },
    editable: function (cls) { return cls.indexOf("MyAI.") === 0; }
  };
})();
