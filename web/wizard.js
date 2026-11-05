"use strict";
// Workbench "Create an agent": Goal, Abilities, Rules, Try & save. The page only collects choices;
// /workbench/wizard/* turns them into classes and the builders' compile check stays in charge.
// Needs el, get, send from the dashboard script and window.wbTable from builder.js.
(function () {
  var host = document.getElementById("wb-new");
  if (!host) return;
  var opts = null, S = null, step = 1, composed = null, drawerEl = null, nameTouched = false;
  var preview = null, previewSeq = 0, runBox = null, saveMsg = null;
  var STEPS = [["Goal", "what it should do"], ["Abilities", "what it may look up"], ["Rules", "what it must never do"], ["Try & save", "one test run"]];
  var TYPES = [["%String", "text"], ["%Integer", "number"]];
  var OPS = ["equals", "contains", "starts with"];

  function div(cls, text) { return el("div", text, cls); }
  function icon(n, extra) { return el("i", null, "ti ti-" + n + (extra ? " " + extra : "")); }
  function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); }
  function btn(text, cls, ic, fn) {
    var b = el("button", null, "btn " + (cls || "")); b.type = "button";
    if (ic) b.appendChild(icon(ic, "me-1"));
    b.appendChild(document.createTextNode(text)); if (fn) b.addEventListener("click", fn); return b;
  }
  function money(n) { return n === "" || n == null ? "" : "$" + Number(n).toFixed(Number(n) < 0.01 ? 4 : 3); }
  function idOf(name) {
    return String(name || "").split(/[^A-Za-z0-9]+/).filter(Boolean).map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1); }).join("");
  }
  function snake(name) { return String(name || "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, ""); }
  function provider() { return (opts.providers || [])[S.provider] || { name: "", model: "", price: "" }; }
  function ability(cls) { return (opts.abilities || []).filter(function (a) { return a["class"] === cls; })[0]; }

  function fresh(starter) {
    var p = (opts.providers || [])[0];
    return { starter: starter.id, name: starter.name, provider: 0, instructions: starter.instructions, on: (function () {
      var m = {}; starter.toolsets.concat(starter.skills).forEach(function (c) { m[c] = true; }); return m; })(),
      protectPid: !!starter.protectPid, audit: true, customOn: false, custom: [], maxOn: true, maxSteps: 8, budgetOn: true, dailyBudget: 0.5, sample: "", p: p };
  }

  function spec() {
    var pr = provider(), ts = [], sk = [];
    (opts.abilities || []).forEach(function (a) { if (S.on[a["class"]]) (a.kind === "skill" ? sk : ts).push(a["class"]); });
    return { starter: S.starter, name: S.name, providerConfig: pr.name, provider: pr.provider || "", apiKey: pr.apiKey || "", model: pr.model, instructions: S.instructions, toolsets: ts, skills: sk,
      rules: { protectPid: S.protectPid, audit: S.audit, custom: S.customOn ? S.custom.filter(function (r) { return r.arg && r.value; }) : [],
        maxSteps: S.maxOn ? Number(S.maxSteps) || 0 : 0, dailyBudget: S.budgetOn ? Number(S.dailyBudget) || 0 : 0 } };
  }

  var stepper = div("wz-stepper"), lay = div("wz-lay"), mainCol = div(), sumCol = div();
  lay.appendChild(mainCol); lay.appendChild(sumCol);
  host.appendChild(stepper); host.appendChild(lay);

  function draw() {
    clear(stepper);
    STEPS.forEach(function (s, i) {
      var n = i + 1, c = div("wz-st" + (n < step ? " done" : "") + (n === step ? " on" : ""));
      var nb = div("wz-nb"); if (n < step) nb.appendChild(icon("check")); else nb.textContent = n;
      var t = div(); t.appendChild(document.createTextNode(s[0])); t.appendChild(el("small", s[1]));
      c.appendChild(nb); c.appendChild(t);
      c.addEventListener("click", function () { go(n); });
      stepper.appendChild(c);
    });
    clear(mainCol);
    [goal, abilities, rules, trySave][step - 1](mainCol);
    drawSummary();
  }
  function go(n) { step = n; draw(); window.scrollTo(0, 0); }
  function nav(back, next, nextText) {
    var r = div("wz-nav");
    if (back) r.appendChild(btn("Back", "", "arrow-left", function () { go(step - 1); })); else r.appendChild(el("span"));
    if (next) { var nb = btn(nextText, "btn-primary", null, function () { go(step + 1); }); nb.appendChild(icon("arrow-right", "ms-1")); r.appendChild(nb); }
    return r;
  }
  function card(title, sub) {
    var c = div("card"), b = div("card-body p-4"); c.appendChild(b);
    b.appendChild(div("wz-q", title)); if (sub) b.appendChild(div("wz-qs", sub));
    c.body = b; return c;
  }
  function field(label, node, help) {
    var f = div("wz-f"); f.appendChild(el("label", label, "form-label")); f.appendChild(node);
    if (help) f.appendChild(div("wb-help", help)); return f;
  }
  function sw(checked, fn, disabled) {
    var l = el("label", null, "form-check form-switch m-0 wz-sw"), i = el("input", null, "form-check-input");
    i.type = "checkbox"; i.checked = !!checked; i.disabled = !!disabled;
    i.addEventListener("change", function () { fn(i.checked); }); l.appendChild(i); return l;
  }

  function goal(root) {
    var c = card("What should your agent do?", "Pick a starting point. You can change everything later.");
    var row = div("wz-goals");
    opts.starters.forEach(function (st) {
      var g = div("wz-goal" + (S.starter === st.id ? " on" : "")), ic = div("wz-gic"); ic.appendChild(icon(st.icon));
      var t = div(); t.appendChild(div("wz-gt", st.title)); t.appendChild(div("wz-gd", st.text));
      g.appendChild(ic); g.appendChild(t);
      g.addEventListener("click", function () { var keep = S.provider; S = fresh(st); S.provider = keep; nameTouched = false; draw(); });
      row.appendChild(g);
    });
    c.body.appendChild(row);
    var name = el("input", null, "form-control"), cls = el("span", null, "wb-mono");
    name.value = S.name;
    function setCls() { var id = idOf(S.name); cls.textContent = id ? "MyAI.Agent." + id : "(give it a name)"; }
    name.addEventListener("input", function () { S.name = name.value; nameTouched = true; setCls(); drawSummary(); });
    var help = div("wb-help"); help.appendChild(document.createTextNode("Saved as class ")); help.appendChild(cls);
    var f1 = div("wz-f"); f1.appendChild(el("label", "Agent name", "form-label")); f1.appendChild(name); f1.appendChild(help); setCls();
    var sel = el("select", null, "form-select");
    (opts.providers || []).forEach(function (p, i) {
      var o = el("option", (p.name || "Key from .env (" + p.provider + ")") + " · " + p.model + (p.price !== "" ? " · ≈ " + money(p.price) + " per message" : " · no price on file")); o.value = i; sel.appendChild(o);
    });
    if (!(opts.providers || []).length) { var none = el("option", "No model configuration yet (Settings tab)"); none.value = 0; sel.appendChild(none); }
    sel.value = S.provider; sel.addEventListener("change", function () { S.provider = Number(sel.value); drawSummary(); });
    var ins = el("textarea", null, "form-control"); ins.rows = 6; ins.value = S.instructions;
    ins.addEventListener("input", function () { S.instructions = ins.value; });
    var two = div("wz-two"); two.appendChild(f1); two.appendChild(field("AI model", sel, "From the Config Store; the key stays in the Wallet."));
    c.body.appendChild(two);
    var fi = field("Instructions", ins); fi.appendChild(div("wz-reads", "The AI reads this first, every time. Short numbered steps work best."));
    c.body.appendChild(fi);
    // Goals that run in the failure flow get the answer format Triage parses; it cannot be edited
    var st0 = opts.starters.filter(function (s) { return s.id === S.starter; })[0];
    if (st0 && st0.contract && opts.outputFormat) {
      var fo = field("Answer format (required by Triage)", el("pre", opts.outputFormat, "wb-src wb-small"));
      fo.appendChild(div("wz-reads", "Added after your instructions when the agent is saved. Triage reads this JSON to decide what happens next."));
      c.body.appendChild(fo);
    }
    root.appendChild(c); root.appendChild(nav(false, true, "Next: abilities"));
  }

  function abilities(root) {
    var c = card("What may the agent look up?", "Each ability is a read-only tool. Switch on only what it needs.");
    var add = btn("New ability", "btn-primary wz-add", "plus", openDrawer);
    if (!opts.canEdit) { add.disabled = true; add.title = "Only administrators can add abilities."; }
    c.body.appendChild(add);
    var list = div("wz-abs");
    (opts.abilities || []).forEach(function (a) {
      var r = div("wz-ab"), ic = div("wz-aic " + (a.kind === "skill" ? "sk" : "tl")); ic.appendChild(icon(a.kind === "skill" ? "file-code" : (a.mine ? "history" : "file-alert")));
      var t = div("flex-fill"), h = div("wz-at", a.title);
      if (a.mine) h.appendChild(el("span", "yours", "wz-mine"));
      if (a.kind === "skill") h.appendChild(el("span", " · loaded only when needed", "wz-soft"));
      t.appendChild(h); t.appendChild(div("wz-ad", a.text)); t.appendChild(div("wz-tech", a.tech));
      r.appendChild(ic); r.appendChild(t);
      r.appendChild(sw(S.on[a["class"]], function (v) { S.on[a["class"]] = v; drawSummary(); }));
      list.appendChild(r);
    });
    if (!(opts.abilities || []).length) list.appendChild(div("wb-note", "No abilities found in this namespace."));
    c.body.appendChild(list);
    root.appendChild(c); root.appendChild(nav(true, true, "Next: rules"));
  }

  // New ability: one SQL tool, saved at once so it shows up in the list
  function openDrawer() {
    closeDrawer();
    var T = { ready: opts.ready[0].id, mode: "ready", name: "Recent messages for an item", desc: opts.ready[0].description, arg: opts.ready[0].arg, type: "%String", sql: opts.ready[0].sql, example: opts.ready[0].example };
    var shade = div("wz-shade"), dr = div("wz-drawer");
    drawerEl = div(); drawerEl.appendChild(shade); drawerEl.appendChild(dr); document.body.appendChild(drawerEl);
    shade.addEventListener("click", closeDrawer);
    var hd = div("wz-dhd"), t = div(); t.appendChild(div("fw-bold", "New ability")); t.appendChild(div("wz-qs", "Something the agent can look up with one query"));
    var x = btn("", "btn-icon btn-ghost-secondary ms-auto", "x", closeDrawer); x.setAttribute("aria-label", "Close");
    hd.appendChild(t); hd.appendChild(x); dr.appendChild(hd);
    var bd = div("wz-dbd"), ft = div("wz-dft"); dr.appendChild(bd); dr.appendChild(ft);
    var msg = div("wb-note me-auto"), out = div("wz-try-out"), code = el("pre", null, "wb-src wb-small hidden");

    function toolSpec() {
      var id = idOf(T.name), a = { name: T.arg, type: T.type, required: true };
      return { kind: "tool", "class": "MyAI.Tools." + id, tool: snake(T.name), description: T.desc, maxRows: 20, args: [a], sql: T.sql };
    }
    function ref() { var s = toolSpec(); help.textContent = ""; help.appendChild(document.createTextNode("Tool ")); help.appendChild(el("span", s.tool || "(name)", "wb-mono")); help.appendChild(document.createTextNode(" in ")); help.appendChild(el("span", s["class"], "wb-mono")); }
    function pickReady(id) {
      var q = opts.ready.filter(function (r) { return r.id === id; })[0]; T.ready = id;
      T.name = { newest: "Recent messages for an item", errors: "Recent errors for an item", order: "Earlier messages for the same order" }[id] || q.label;
      T.desc = q.description; T.arg = q.arg; T.type = q.arg === "headerId" ? "%Integer" : "%String"; T.sql = q.sql; T.example = q.example;
      render();
    }
    var help = div("wb-help");
    function render() {
      clear(bd);
      var d = el("textarea", null, "form-control"); d.rows = 3; d.value = T.desc; d.addEventListener("input", function () { T.desc = d.value; });
      bd.appendChild(field("What does it do? (the AI reads this)", d));
      var nm = el("input", null, "form-control"); nm.value = T.name; nm.addEventListener("input", function () { T.name = nm.value; ref(); });
      var ar = el("input", null, "form-control wb-mono-in"); ar.value = T.arg; ar.readOnly = T.mode === "ready"; ar.addEventListener("input", function () { T.arg = ar.value; });
      var ty = el("select", null, "form-select"); TYPES.forEach(function (o) { var op = el("option", o[1]); op.value = o[0]; ty.appendChild(op); });
      ty.value = T.type; ty.disabled = T.mode === "ready"; ty.addEventListener("change", function () { T.type = ty.value; });
      var two = div("wz-two"), f1 = field("Name", nm), ag = div("d-flex gap-2"); ag.appendChild(ar); ag.appendChild(ty);
      f1.appendChild(help); ref(); two.appendChild(f1); two.appendChild(field("The AI must give", ag, "Its name is in the SQL as :" + (T.arg || "name")));
      bd.appendChild(two);
      var mode = div("btn-group mb-2");
      [["ready", "Pick a ready query"], ["sql", "Write SQL"]].forEach(function (m) {
        var b = el("button", m[1], "btn btn-sm" + (T.mode === m[0] ? " active" : "")); b.type = "button";
        b.addEventListener("click", function () { T.mode = m[0]; if (m[0] === "ready") pickReady(T.ready); else render(); }); mode.appendChild(b);
      });
      bd.appendChild(div("form-label mt-3", "Query")); bd.appendChild(mode);
      if (T.mode === "ready") {
        var rs = el("select", null, "form-select");
        opts.ready.forEach(function (q) { var o = el("option", q.label); o.value = q.id; rs.appendChild(o); });
        rs.value = T.ready; rs.addEventListener("change", function () { pickReady(rs.value); });
        bd.appendChild(rs); bd.appendChild(div("wb-help", "Ready queries are tested SELECTs on interoperability tables."));
      } else {
        var q = el("textarea", null, "form-control wb-mono-in"); q.rows = 5; q.value = T.sql; q.addEventListener("input", function () { T.sql = q.value; });
        bd.appendChild(q); bd.appendChild(div("wb-help", "One SELECT. Use :" + (T.arg || "name") + " for the argument. Nothing else is accepted."));
      }
      var tr = div("wz-try"), row = div("d-flex align-items-center gap-2");
      var ex = el("input", null, "form-control form-control-sm wb-mono-in"); ex.style.width = "160px"; ex.value = T.example || "";
      var run = btn("Run · no AI · $0", "btn-sm btn-primary", "player-play", function () {
        var a = {}; a[T.arg] = T.type === "%Integer" ? Number(ex.value) : ex.value; T.example = ex.value;
        clear(out); out.textContent = "Running…";
        send("POST", "api/workbench/builder/test-tool", { kind: "tool", spec: toolSpec(), args: a }).then(function (r) {
          clear(out);
          if (r.errors && r.errors.length) { out.appendChild(errs(r.errors)); return; }
          out.appendChild(window.wbTable(r.result));
          out.appendChild(div("wb-help", "This is exactly what the AI will see · " + r.elapsedMs + " ms"));
        }).catch(function (e) { out.textContent = e.message; });
      });
      row.appendChild(el("b", "Try it")); row.appendChild(ex); row.appendChild(run); tr.appendChild(row); tr.appendChild(out); bd.appendChild(tr);
      var dt = el("details", null, "mt-3"), sm = el("summary", "See the code", "text-secondary wz-sum"); dt.appendChild(sm); dt.appendChild(code);
      dt.addEventListener("toggle", function () { if (dt.open) showCode(); });
      bd.appendChild(dt);
    }
    function showCode() {
      send("POST", "api/workbench/builder/generate", { kind: "tool", spec: toolSpec() }).then(function (r) {
        code.classList.remove("hidden"); code.textContent = r.errors && r.errors.length ? r.errors.join("\n") : r.code;
      }).catch(function (e) { code.textContent = e.message; });
    }
    var addB = btn("Add ability", "btn-primary", null, function () {
      addB.disabled = true; msg.textContent = "Saving…";
      send("POST", "api/workbench/builder/save", { kind: "tool", spec: toolSpec() }).then(function (r) {
        if (!r.saved) { msg.textContent = ""; clear(out); out.appendChild(errs(r.errors || ["Not saved."])); return; }
        return get("api/workbench/wizard/options").then(function (o) {
          opts = o; S.on[r["class"]] = true; closeDrawer(); draw();
          if (window.workbenchReload) window.workbenchReload();
        });
      }).catch(function (e) { msg.textContent = e.message; }).then(function () { addB.disabled = false; });
    });
    ft.appendChild(el("span", null, "")); var lock = div("wb-note me-auto"); lock.appendChild(icon("lock", "me-1")); lock.appendChild(document.createTextNode("Read-only · only SELECT")); ft.appendChild(lock);
    ft.appendChild(msg); ft.appendChild(btn("Cancel", "", null, closeDrawer)); ft.appendChild(addB);
    render();
  }
  function closeDrawer() { if (drawerEl) { document.body.removeChild(drawerEl); drawerEl = null; } }
  function errs(list) { var u = el("ul", null, "wb-errl"); list.forEach(function (t) { u.appendChild(el("li", t)); }); return u; }

  function rules(root) {
    var c = card("What must the agent never do?", "AI Hub checks these rules before every tool call. A blocked call never runs.");
    var list = div("wz-rules");
    function rule(on, fn, title, text, locked) {
      var r = div("wz-rule"); r.appendChild(sw(on, fn, locked));
      var t = div("flex-fill"), h = div("wz-at", title); if (locked) h.appendChild(el("span", "always on", "wz-lock"));
      t.appendChild(h); if (text) t.appendChild(div("wz-ad", text)); r.appendChild(t); r.body = t; list.appendChild(r); return r;
    }
    rule(true, function () {}, "Never change data", "Only read-only abilities can run.", true);
    var pid = rule(S.protectPid, function (v) { S.protectPid = v; drawSummary(); }, "Never read patient identity fields", "Blocks any call that asks for PID or changes PID-3, PID-5, PID-7.");
    var ex = div("wz-try"); ex.appendChild(el("b", "Example: ")); ex.appendChild(el("span", 'get_segment(segmentRef = "PID")', "wb-mono")); ex.appendChild(document.createTextNode(" is blocked with \"" + "Patient identity is protected. Escalate instead." + "\"; "));
    ex.appendChild(el("span", '"OBX(1)"', "wb-mono")); ex.appendChild(document.createTextNode(" is allowed.")); pid.body.appendChild(ex);
    rule(S.audit, function (v) { S.audit = v; }, "Log every tool call", "One row per call, allowed or blocked, plus a line in Visual Trace.");
    var cu = rule(S.customOn, function (v) { S.customOn = v; if (v && !S.custom.length) S.custom.push({ arg: "", op: "contains", value: "" }); draw(); drawSummary(); }, "Block my own words or values", "A rule like \"segmentRef equals NK1\": the call is blocked when the argument matches.");
    if (S.customOn) {
      var t = el("table", null, "table table-sm mb-1 mt-2"), hd = el("tr");
      ["Argument", "Rule", "Value", ""].forEach(function (h) { hd.appendChild(el("th", h)); }); t.appendChild(el("thead")).appendChild(hd);
      var tb = el("tbody"); t.appendChild(tb);
      S.custom.forEach(function (r, i) {
        var tr = el("tr");
        var a = el("input", null, "form-control form-control-sm wb-mono-in"); a.value = r.arg; a.placeholder = "segmentRef"; a.addEventListener("input", function () { r.arg = a.value; });
        var o = el("select", null, "form-select form-select-sm"); OPS.forEach(function (p) { var op = el("option", p); op.value = p; o.appendChild(op); }); o.value = r.op; o.addEventListener("change", function () { r.op = o.value; });
        var v = el("input", null, "form-control form-control-sm wb-mono-in"); v.value = r.value; v.addEventListener("input", function () { r.value = v.value; });
        var x = btn("", "btn-sm btn-ghost-secondary btn-icon", "x", function () { S.custom.splice(i, 1); if (!S.custom.length) S.customOn = false; draw(); }); x.setAttribute("aria-label", "Remove");
        [a, o, v, x].forEach(function (n) { var td = el("td"); td.appendChild(n); tr.appendChild(td); }); tb.appendChild(tr);
      });
      cu.body.appendChild(t);
      cu.body.appendChild(btn("Add", "btn-sm", "plus", function () { S.custom.push({ arg: "", op: "contains", value: "" }); draw(); }));
    }
    var bu = rule(S.maxOn || S.budgetOn, function (v) { S.maxOn = S.budgetOn = v; draw(); }, "Stop after a budget", "");
    var line = bu.body, sp = el("span", "Max "); line.appendChild(sp);
    var ms = el("input", null, "form-control form-control-sm d-inline-block wz-num"); ms.type = "number"; ms.min = 1; ms.max = 50; ms.value = S.maxSteps; ms.disabled = !S.maxOn;
    ms.addEventListener("input", function () { S.maxSteps = ms.value; drawSummary(); });
    var db = el("input", null, "form-control form-control-sm d-inline-block wz-num"); db.type = "number"; db.min = 0; db.step = "0.05"; db.value = S.dailyBudget; db.disabled = !S.budgetOn;
    db.addEventListener("input", function () { S.dailyBudget = db.value; drawSummary(); });
    line.appendChild(ms); line.appendChild(document.createTextNode(" steps per message · max $")); line.appendChild(db);
    line.appendChild(document.createTextNode(" per day, then send to a human."));
    line.appendChild(div("wb-help", "The step limit applies to every run. The daily amount is enforced when a production hosts the agent (next step)."));
    c.body.appendChild(list); root.appendChild(c); root.appendChild(nav(true, true, "Next: try & save"));
  }

  function trySave(root) {
    var pr = provider();
    var c = card("Try it on one message", "A dry run: the agent reads, nothing is sent or changed.");
    var bar = div("wz-runbar"), sel = el("select", null, "form-select");
    (opts.samples || []).forEach(function (s) { var o = el("option", s.label); o.value = s.id; sel.appendChild(o); });
    if (!(opts.samples || []).length) { var o0 = el("option", "No recorded failed messages yet"); o0.value = ""; sel.appendChild(o0); }
    if (S.sample) sel.value = S.sample; S.sample = sel.value; sel.addEventListener("change", function () { S.sample = sel.value; });
    var run = btn("Run" + (pr.price !== "" ? " · ≈ " + money(pr.price) : ""), "btn-primary", "player-play", function () { doRun(false); });
    var why = "";
    if (opts.killSwitch) why = "The AI kill switch is on. Turn it off on the Settings tab to run the agent.";
    else if (!opts.canEdit) why = "Only administrators can run the agent.";
    else if (!(opts.samples || []).length) why = "Send a broken message first (Overview).";
    if (why) { run.disabled = true; run.title = why; }
    bar.appendChild(sel); bar.appendChild(run); c.body.appendChild(bar);
    if (why) c.body.appendChild(div("wb-note", why));
    runBox = div("wz-steps"); c.body.appendChild(runBox);
    var dt = el("details", null, "mt-3"), sm = el("summary", "See the code it will save", "text-secondary wz-sum"); dt.appendChild(sm);
    var codeHost = div(); dt.appendChild(codeHost); c.body.appendChild(dt);
    dt.addEventListener("toggle", function () { if (dt.open) loadPreview(sm, codeHost); });
    root.appendChild(c);

    var nv = div("wz-nav"); nv.appendChild(btn("Back", "", "arrow-left", function () { go(3); }));
    var right = div("d-flex gap-2 align-items-center"); saveMsg = div("wb-note"); right.appendChild(saveMsg);
    var save = btn("Save agent", "btn-primary", "device-floppy", doSave);
    if (!opts.canEdit) { save.disabled = true; save.title = "Only administrators can save."; }
    var add = btn("Save & add to a production", "", "route", doSaveAndAdd);
    if (!opts.canEdit) { add.disabled = true; add.title = "Only administrators can save."; }
    right.appendChild(save); right.appendChild(add); nv.appendChild(right); root.appendChild(nv);
  }
  function loadPreview(sm, hostEl) {
    clear(hostEl); hostEl.appendChild(div("wb-note", "Generating…"));
    send("POST", "api/workbench/wizard/compose", { spec: spec() }).then(function (r) {
      clear(hostEl); composed = r;
      if (r.errors && r.errors.length) { hostEl.appendChild(errs(r.errors)); return; }
      sm.textContent = "See the code it will save (" + r.parts.length + " class" + (r.parts.length === 1 ? "" : "es") + ")";
      r.parts.forEach(function (p) { hostEl.appendChild(div("wb-mono mt-2", p["class"])); hostEl.appendChild(el("pre", p.code, "wb-src wb-small")); });
    }).catch(function (e) { clear(hostEl); hostEl.appendChild(div("wb-note", e.message)); });
  }
  function doRun(confirm) {
    clear(runBox); runBox.appendChild(div("wb-note", confirm ? "Running…" : "Checking…"));
    send("POST", "api/workbench/wizard/run", { spec: spec(), sample: Number(S.sample), confirm: confirm }).then(function (r) {
      clear(runBox);
      if (r.state === "needs-confirm") {
        var b = div("wz-confirm");
        b.appendChild(document.createTextNode("This calls " + r.model + " once with at most 3 tool rounds" + (r.price !== "" ? ", about " + money(r.price) + "." : ". No price is on file for this model.") + " "));
        b.appendChild(btn("Confirm and run", "btn-sm btn-primary", null, function () { doRun(true); }));
        b.appendChild(btn("Cancel", "btn-sm", null, function () { clear(runBox); })); runBox.appendChild(b); return;
      }
      if (r.state === "blocked") { runBox.appendChild(div("wb-note", r.reason)); return; }
      if (r.state === "invalid") { runBox.appendChild(errs(r.errors || ["Check the form."])); return; }
      if (r.state === "failed") { runBox.appendChild(div("wb-note", "The run failed: " + r.error)); return; }
      var ICON = { read: ["file-alert", "wz-d-read"], blocked: ["ban", "wz-d-deny"], failed: ["alert-triangle", "wz-d-deny"], answer: ["flag", "wz-d-ok"] };
      r.steps.forEach(function (s) {
        var row = div("wz-step"), dot = div("wz-dot " + ICON[s.kind][1]); dot.appendChild(icon(ICON[s.kind][0]));
        var t = div("flex-fill"); t.appendChild(div(s.kind === "blocked" ? "wz-deny" : "", s.text));
        if (s.detail) t.appendChild(div("wz-ad", s.detail)); row.appendChild(dot); row.appendChild(t); runBox.appendChild(row);
      });
      runBox.appendChild(div("wb-help mt-2", (r.ms / 1000).toFixed(1) + " s · " + (r.promptTokens + r.completionTokens) + " tokens · " + money(r.costUsd)));
    }).catch(function (e) { clear(runBox); runBox.appendChild(div("wb-note", e.message)); });
  }
  function doSave(then) {
    saveMsg.textContent = "Saving…";
    send("POST", "api/workbench/wizard/save", { spec: spec() }).then(function (r) {
      if (!r.saved) { saveMsg.textContent = ""; clear(runBox); runBox.appendChild(errs(r.errors || ["Not saved."])); return; }
      saveMsg.textContent = "Saved " + r.classes.join(" and ") + ". Find it in the Library.";
      if (window.workbenchReload) window.workbenchReload();
      if (typeof then === "function") then(r.classes[r.classes.length - 1]);
    }).catch(function (e) { saveMsg.textContent = e.message; });
  }
  // The agent class is the last one saved; the dialog adds it to a production
  function doSaveAndAdd() {
    doSave(function (cls) { if (window.wbAddProd) window.wbAddProd.open({ agentClass: cls, name: idOf(S.name) }); });
  }

  function drawSummary() {
    clear(sumCol);
    var st = opts.starters.filter(function (s) { return s.id === S.starter; })[0], pr = provider();
    var c = div("card wz-sum-card"), b = div("card-body p-4"); c.appendChild(b);
    var hd = div("d-flex align-items-center gap-2"), av = div("wz-sav"); av.appendChild(icon("robot"));
    var t = div(); t.appendChild(div("fw-bold wz-sname", S.name || "Your agent"));
    t.appendChild(div("wz-qs", (pr.model || "no model") + (pr.price !== "" ? " · ≈ " + money(pr.price) + " per message" : "")));
    hd.appendChild(av); hd.appendChild(t); b.appendChild(hd);
    function list(title, items, cls, ic) {
      b.appendChild(el("h6", title, "wz-h6")); var u = el("ul", null, "wz-ul " + cls);
      if (!items.length) { var e = el("li", "Nothing yet", "wz-soft"); u.appendChild(e); }
      items.forEach(function (x) { var li = el("li"); li.appendChild(icon(ic, "me-1")); li.appendChild(document.createTextNode(x)); u.appendChild(li); });
      b.appendChild(u);
    }
    list("It will", st ? st.does : [], "y", "check");
    var can = [];
    (opts.abilities || []).forEach(function (a) { if (S.on[a["class"]]) can.push(a.title + (a.kind === "skill" ? " (when needed)" : "")); });
    list("It can look up", can, "y", "check");
    var never = ["Change data"];
    if (S.protectPid) never.push("Read patient identity fields");
    if (S.customOn && S.custom.filter(function (r) { return r.arg && r.value; }).length) never.push("Break your own rules");
    if (S.maxOn && Number(S.maxSteps)) never.push("Take more than " + S.maxSteps + " steps");
    if (S.budgetOn && Number(S.dailyBudget)) never.push("Spend more than $" + Number(S.dailyBudget).toFixed(2) + " a day");
    list("It will never", never, "n", "x");
    var nT = 0, nS = 0; (opts.abilities || []).forEach(function (a) { if (S.on[a["class"]]) { if (a.kind === "skill") nS++; else nT++; } });
    b.appendChild(div("wz-qs mt-3", "Built with AI Hub: one agent, " + nT + " toolset" + (nT === 1 ? "" : "s") + ", " + nS + " skill" + (nS === 1 ? "" : "s") + ", " + (S.protectPid || S.customOn ? 2 : 1) + " polic" + ((S.protectPid || S.customOn) ? "ies" : "y") + "."));
    sumCol.appendChild(c);
  }

  function start() {
    get("api/workbench/wizard/options").then(function (o) {
      opts = o; S = fresh(o.starters[0]); step = 1; draw();
    }).catch(function (e) { host.appendChild(div("wb-note", "The wizard could not load: " + e.message)); });
  }
  var started = false;
  window.wizardShow = function (name) {
    if (name !== "wbnew") return;
    // Reload the lists on every visit: abilities saved elsewhere appear, the kill switch may have moved
    if (!started) { started = true; start(); return; }
    get("api/workbench/wizard/options").then(function (o) { opts = o; if (S) draw(); });
  };
  var active = document.querySelector("#nav .nav-link.active");
  if (active) window.wizardShow(active.dataset.tab);
})();
