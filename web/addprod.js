"use strict";
// Workbench "Add to production": dialog opened from the wizard's last step and from a MyAI agent card.
// /workbench/addprod/* plans and applies; nothing is sent until "Add to production". Needs el, get,
// send from the dashboard script.
(function () {
  var WAYS = [
    ["failure", "alert-triangle", "When a message fails", "We watch the items you tick. Failures go to the agent, its proposal to a human.", "no code", "var(--red-bg)", "var(--red-fg)"],
    ["process", "code", "From my own process", "Your BPL or ObjectScript calls the agent when you decide.", "", "var(--sky-bg)", "var(--sky-fg)"],
    ["rule", "arrows-split", "From a routing rule", "Add the agent as a target; matching messages go to it.", "", "var(--green-bg)", "var(--green-fg)"]
  ];
  var MODES = [["observe", "Explain only"], ["propose", "Propose, a human approves"], ["act", "Fix safe cases"]];
  var NEWROLE = "__new__";
  var S = null, root = null, planSeq = 0, planTimer = null, onDone = null;

  function icon(n, extra) { return el("i", null, "ti ti-" + n + (extra ? " " + extra : "")); }
  function div(cls, text) { return el("div", text, cls); }
  function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); }
  function btn(text, cls, ic, fn) {
    var b = el("button", null, "btn " + (cls || "")); b.type = "button";
    if (ic) b.appendChild(icon(ic, "me-1"));
    b.appendChild(document.createTextNode(text)); if (fn) b.addEventListener("click", fn); return b;
  }
  function idOf(name) {
    return String(name || "").split(/[^A-Za-z0-9]+/).filter(Boolean).map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1); }).join("");
  }
  function short(c) { var p = String(c || "").split("."); return p[p.length - 1]; }
  function key() { return S.ns + "|" + S.prod; }

  // ---- public ---------------------------------------------------------------------------------
  function canAdd(cls) { return /^MyAI\.Agent\./.test(cls || ""); }

  // The Library card's part: the button and one chip per install with its Remove.
  function cardBits(item, reload) {
    var box = div("ap-card");
    box.addEventListener("click", function (e) { e.stopPropagation(); });
    (item.installs || []).forEach(function (i) { box.appendChild(installRow(i, reload)); });
    var b = btn("Add to production", "btn-sm", "route", function () { open({ agentClass: item["class"], name: idOf(short(item["class"])), done: reload }); });
    box.appendChild(b);
    return box;
  }

  function installRow(i, reload) {
    var r = div("ap-inst");
    r.appendChild(el("span", "AI HUB", "wb-tagpill hub"));
    var t = div("ap-inst-t");
    t.appendChild(el("b", i.owner));
    t.appendChild(document.createTextNode(" in " + i.namespace + " · " + short(i.production) + " · " + i.items.length + " item" + (i.items.length === 1 ? "" : "s")));
    r.appendChild(t);
    var x = btn("Remove", "btn-sm btn-outline-danger", "arrow-back-up", function () { remove(i, x, reload); });
    r.appendChild(x);
    return r;
  }

  function installCards(list, reload) {
    var out = div();
    (list || []).forEach(function (i) {
      var c = div("card mt-3"), b = div("card-body");
      b.appendChild(div("fw-semibold mb-1", "Added by Add to production"));
      b.appendChild(installRow(i, reload));
      b.appendChild(div("wb-d mt-2", "Items: " + i.items.join(", ")));
      c.appendChild(b); out.appendChild(c);
    });
    return out;
  }

  function remove(i, button, reload) {
    if (!window.confirm("Remove " + i.items.join(", ") + " from " + i.production + "? Other items stay as they are.")) return;
    button.disabled = true;
    send("POST", "api/workbench/addprod/remove", { namespace: i.namespace, production: i.production, owner: i.owner }).then(function (r) {
      if (!r.ok) { button.disabled = false; window.alert((r.errors || ["Not removed."]).join("\n")); return; }
      if (reload) reload();
      if (window.workbenchReload) window.workbenchReload();
    }).catch(function (e) { button.disabled = false; window.alert(e.message); });
  }

  // ---- dialog ---------------------------------------------------------------------------------
  function open(o) {
    close();
    S = { agentClass: o.agentClass, name: o.name || "", ns: "", prod: "", way: "failure", watch: {}, mode: "propose", role: NEWROLE, roleNew: "",
      tab: "objectscript", items: [], roles: [], canFail: true, plan: null, msg: "", busy: false, prods: [] };
    onDone = o.done || null;
    root = div("ap-root");
    document.body.appendChild(root);
    root.appendChild(div("ap-shade"));
    root.firstChild.addEventListener("click", close);
    get("api/workbench/productions").then(function (list) {
      S.prods = [];
      list.forEach(function (n) { n.productions.forEach(function (p) { S.prods.push({ ns: n.namespace, name: p.name, running: p.running }); }); });
      if (!S.prods.length) { draw(); S.msg = "No production found."; return; }
      var first = S.prods[0]; S.ns = first.ns; S.prod = first.name;
      loadWatch(true);
    }).catch(function (e) { draw(); S.msg = e.message; });
    draw();
  }

  function close() { if (root && root.parentNode) root.parentNode.removeChild(root); root = null; S = null; }

  function loadWatch(redraw) {
    S.items = []; S.roles = []; S.watch = {};
    get("api/workbench/addprod/watch?ns=" + encodeURIComponent(S.ns) + "&name=" + encodeURIComponent(S.prod) + "&class=" + encodeURIComponent(S.agentClass)).then(function (r) {
      S.items = r.items || []; S.roles = r.roles || [];
      // An agent without the Triage answer format cannot sit behind "When a message fails"
      S.canFail = r.canFail !== false;
      if (!S.canFail && S.way === "failure") S.way = "process";
      S.items.forEach(function (i) { if (i.errors24h) S.watch[i.name] = true; });
      S.roleNew = S.roleNew || (S.name ? S.name + "Support" : "");
      if (redraw !== false) draw();
      queuePlan();
    }).catch(function (e) { S.msg = e.message; draw(); });
  }

  function spec() {
    var watch = Object.keys(S.watch).filter(function (k) { return S.watch[k]; });
    return { agentClass: S.agentClass, namespace: S.ns, production: S.prod, name: S.name, way: S.way, watch: watch, mode: S.mode,
      role: S.role === NEWROLE ? "" : S.role, roleNew: S.roleNew };
  }

  function queuePlan() {
    clearTimeout(planTimer);
    planTimer = setTimeout(function () {
      if (!S) return;
      var seq = ++planSeq;
      send("POST", "api/workbench/addprod/plan", spec()).then(function (r) {
        if (!S || seq !== planSeq) return;
        S.plan = r; drawSide(); drawFoot();
        if (S.way !== "failure") drawWays();
      }).catch(function (e) { if (S) { S.plan = { ok: false, errors: [e.message], items: [] }; drawSide(); drawFoot(); } });
    }, 250);
  }

  var elMain, elSide, elFoot, elWays, elPanel;

  function draw() {
    if (!root) return;
    while (root.childNodes.length > 1) root.removeChild(root.lastChild);
    var m = div("ap-modal"), head = div("ap-head");
    var av = el("span", null, "ap-av"); av.appendChild(icon("route")); head.appendChild(av);
    var t = div(); t.appendChild(div("ap-title", "Add \"" + short(S.agentClass) + "\" to a production"));
    t.appendChild(div("wb-note", "Adds only the items listed on the right. Nothing that exists is changed or restarted."));
    head.appendChild(t);
    var x = btn("", "btn-icon btn-ghost-secondary ms-auto", "x", close); x.setAttribute("aria-label", "Close"); head.appendChild(x);
    m.appendChild(head);
    var body = div("ap-body"); elMain = div(); elSide = div(); body.appendChild(elMain); body.appendChild(elSide); m.appendChild(body);
    elFoot = div("ap-foot"); m.appendChild(elFoot);
    root.appendChild(m);
    drawMain(); drawSide(); drawFoot();
  }

  function lbl(n, text) { var l = div("ap-lbl"); l.appendChild(el("span", String(n), "ap-num")); l.appendChild(document.createTextNode(text)); return l; }

  function drawMain() {
    clear(elMain);
    elMain.appendChild(lbl(1, "Which production?"));
    var row = div("ap-row");
    var sel = el("select", null, "form-select ap-prod");
    S.prods.forEach(function (p) {
      var o = el("option", p.ns + " · " + p.name + (p.running ? "" : " (not running)")); o.value = p.ns + "|" + p.name; sel.appendChild(o);
    });
    sel.value = key();
    sel.addEventListener("change", function () { var v = sel.value.split("|"); S.ns = v[0]; S.prod = v.slice(1).join("|"); S.plan = null; loadWatch(true); });
    var g = div("input-group ap-name"); g.appendChild(el("span", "Item name", "input-group-text"));
    var inp = el("input", null, "form-control wb-mono-in"); inp.value = S.name;
    inp.addEventListener("input", function () { S.name = inp.value.trim(); queuePlan(); });
    g.appendChild(inp);
    row.appendChild(sel); row.appendChild(g); elMain.appendChild(row);

    elMain.appendChild(lbl(2, "How should messages reach the agent?"));
    elWays = div("ap-ways"); elMain.appendChild(elWays); drawWays();
    elPanel = div(); elMain.appendChild(elPanel); drawPanel();
  }

  function drawWays() {
    clear(elWays);
    WAYS.forEach(function (w) {
      var off = w[0] === "failure" && !S.canFail;
      var o = div("ap-opt" + (S.way === w[0] ? " on" : "") + (off ? " off" : "")); o.tabIndex = off ? -1 : 0;
      if (off) o.title = "This agent has no answer format for Triage. Build it with the Fix or Explain goal to use this way.";
      var ic = el("span", null, "ap-ic"); ic.style.background = w[5]; ic.style.color = w[6]; ic.appendChild(icon(w[1])); o.appendChild(ic);
      var t = div(); var h = div("ap-t", w[2]);
      if (w[4]) h.appendChild(el("span", w[4], "ap-rec"));
      t.appendChild(h); t.appendChild(div("ap-d", w[3])); o.appendChild(t);
      var pick = function () { if (off) return; S.way = w[0]; drawWays(); drawPanel(); queuePlan(); };
      o.addEventListener("click", pick); o.addEventListener("keydown", function (e) { if (e.key === "Enter") pick(); });
      elWays.appendChild(o);
    });
  }

  function drawPanel() {
    clear(elPanel);
    if (S.way === "failure") failurePanel(); else snippetPanel();
  }

  function failurePanel() {
    elPanel.appendChild(lbl(3, "Which items should we watch?"));
    var grid = div("ap-items");
    if (!S.items.length) grid.appendChild(div("wb-note", "No items to watch in this production."));
    S.items.forEach(function (i) {
      var c = div("ap-item" + (S.watch[i.name] ? " on" : ""));
      var cb = el("input", null, "form-check-input m-0"); cb.type = "checkbox"; cb.checked = !!S.watch[i.name];
      cb.addEventListener("change", function () { S.watch[i.name] = cb.checked; c.classList.toggle("on", cb.checked); queuePlan(); });
      var t = div("flex-fill"); t.appendChild(div("ap-n", i.name)); t.appendChild(div("ap-k", i.type + " · " + short(i["class"])));
      c.appendChild(cb); c.appendChild(t);
      c.appendChild(el("span", i.errors24h ? i.errors24h + " error" + (i.errors24h === 1 ? "" : "s") + " · 24 h" : "no errors", i.errors24h ? "ap-err" : "ap-zero"));
      grid.appendChild(c);
    });
    elPanel.appendChild(grid);
    var two = div("ap-two");
    var a = div(); a.appendChild(lbl(4, "What may the agent do with a failure?"));
    var seg = div("btn-group w-100");
    MODES.forEach(function (m) {
      var b = btn(m[1], S.mode === m[0] ? "active" : "", null, function () { S.mode = m[0]; Array.prototype.forEach.call(seg.children, function (c, i) { c.classList.toggle("active", MODES[i][0] === S.mode); }); queuePlan(); });
      seg.appendChild(b);
    });
    a.appendChild(seg); a.appendChild(div("wb-note", "Start with Propose. Fix safe cases only applies whitelisted fixes; everything else still goes to a human."));
    var b2 = div(); b2.appendChild(lbl(5, "Who approves?"));
    var rs = el("select", null, "form-select");
    var on = el("option", "New role"); on.value = NEWROLE; rs.appendChild(on);
    S.roles.forEach(function (r) { var o = el("option", r); o.value = r; rs.appendChild(o); });
    rs.value = S.role;
    var rn = el("input", null, "form-control wb-mono-in mt-2"); rn.value = S.roleNew; rn.placeholder = "Role name";
    rn.style.display = S.role === NEWROLE ? "" : "none";
    rs.addEventListener("change", function () { S.role = rs.value; rn.style.display = S.role === NEWROLE ? "" : "none"; queuePlan(); });
    rn.addEventListener("input", function () { S.roleNew = rn.value.trim(); queuePlan(); });
    b2.appendChild(rs); b2.appendChild(rn);
    two.appendChild(a); two.appendChild(b2); elPanel.appendChild(two);
  }

  function snippetPanel() {
    var snip = S.plan && S.plan.snippets;
    if (S.way === "rule") {
      elPanel.appendChild(lbl(3, "Add the agent as a rule target"));
      var ol = el("ol", null, "ap-steps");
      ["Add the item below to the production (this dialog does that).",
        "Make a data transformation that builds an AgenticProd.Msg.AgentRequest from your message (Question = the text the agent should answer).",
        "In the routing rule, add a send action: pick that transformation and set the target to " + (S.name || "your item") + "."].forEach(function (s) { ol.appendChild(el("li", s)); });
      elPanel.appendChild(ol);
      codeBlock(snip ? snip.rule : "");
      elPanel.appendChild(div("wb-note", "The agent's answer is a proposal. The rule decides what to do with it."));
      return;
    }
    elPanel.appendChild(lbl(3, "Call the agent from your code"));
    elPanel.appendChild(div("wb-note", "The operation " + (S.name || "your item") + " is added. Send it a request; you get the agent's answer back. Every call shows in Visual Trace."));
    var tabs = div("btn-group mb-2");
    [["objectscript", "ObjectScript"], ["bpl", "BPL"]].forEach(function (t) {
      tabs.appendChild(btn(t[1], S.tab === t[0] ? "active" : "", null, function () { S.tab = t[0]; drawPanel(); }));
    });
    elPanel.appendChild(tabs);
    codeBlock(snip ? snip[S.tab] : "");
    elPanel.appendChild(div("wb-note", "The answer is a proposal. Your code decides what to apply."));
  }

  function codeBlock(text) {
    var pre = el("pre", text || "", "ap-code");
    elPanel.appendChild(pre);
    var b = btn("Copy", "btn-sm mt-2", "copy", function () {
      var done = function () { b.lastChild.textContent = "Copied"; setTimeout(function () { b.lastChild.textContent = "Copy"; }, 1500); };
      if (navigator.clipboard) navigator.clipboard.writeText(pre.textContent).then(done, function () { selectText(pre); });
      else selectText(pre);
    });
    elPanel.appendChild(b);
  }
  function selectText(n) { var r = document.createRange(); r.selectNodeContents(n); var s = window.getSelection(); s.removeAllRanges(); s.addRange(r); }

  // ---- right side: what will be added, preview map -------------------------------------------
  function drawSide() {
    if (!elSide) return;
    clear(elSide);
    var c = div("card mb-3"), b = div("card-body");
    b.appendChild(div("fw-semibold mb-1", "Will be added to " + short(S.prod)));
    var plan = S.plan;
    if (!plan) b.appendChild(div("wb-note", "Checking…"));
    else {
      (plan.items || []).forEach(function (i) {
        var r = div("ap-add"); r.appendChild(el("span", "+", "ap-plus"));
        var t = div(); var h = div(); h.appendChild(document.createTextNode(typeLabel(i["class"]) + " ")); h.appendChild(el("b", i.name));
        t.appendChild(h); t.appendChild(div("ap-k", i.note)); r.appendChild(t); b.appendChild(r);
      });
      (plan.errors || []).forEach(function (e) { b.appendChild(div("ap-bad", e)); });
    }
    var u = div("ap-undo"); u.appendChild(icon("arrow-back-up", "me-1")); u.appendChild(document.createTextNode("Remove later takes out exactly these items."));
    b.appendChild(u); c.appendChild(b); elSide.appendChild(c);
    var c2 = div("card"), b2 = div("card-body");
    b2.appendChild(div("fw-semibold mb-2", "Preview"));
    var mini = div("ap-mini"); b2.appendChild(mini);
    b2.appendChild(div("wb-note", "Dashed = new · purple = AI Hub"));
    c2.appendChild(b2); elSide.appendChild(c2);
    drawMini(mini);
  }
  function typeLabel(cls) {
    return { "AgenticProd.Operation.Agent": "Operation", "AgenticProd.Plugin.Sentinel": "Service", "AgenticProd.Process.Triage": "Process", "EnsLib.Workflow.Operation": "Operation" }[cls] || "Item";
  }

  // Existing items on the left column (up to 4), new ones on the right
  function drawMini(mini) {
    var ns = "http://www.w3.org/2000/svg", svg = document.createElementNS(ns, "svg"); mini.appendChild(svg);
    var pos = {}, plan = S.plan && S.plan.items ? S.plan.items : [];
    function node(name, x, y, cls) {
      var n = div("ap-nd" + (cls ? " " + cls : ""), name); n.style.left = x + "px"; n.style.top = y + "px"; mini.appendChild(n); pos[name] = n; return n;
    }
    var old = S.items.slice(0, 4);
    old.forEach(function (i, k) { node(i.name, 10, 10 + k * 36, S.watch[i.name] && S.way === "failure" ? "watched" : ""); });
    var host = plan.filter(function (i) { return i.name === S.name; })[0];
    var rest = plan.filter(function (i) { return i.name !== S.name; });
    rest.forEach(function (i, k) { node(i.name, 150, 10 + k * 36, "new"); });
    if (host) node(host.name, S.way === "failure" ? 150 : 150, 10 + rest.length * 36, "hub");
    function line(a, b, col) {
      var A = pos[a], B = pos[b]; if (!A || !B) return;
      var x1 = A.offsetLeft + A.offsetWidth, y1 = A.offsetTop + A.offsetHeight / 2, x2 = B.offsetLeft, y2 = B.offsetTop + B.offsetHeight / 2;
      var p = document.createElementNS(ns, "path");
      p.setAttribute("d", "M" + x1 + "," + y1 + " C" + (x1 + 20) + "," + y1 + " " + (x2 - 20) + "," + y2 + " " + x2 + "," + y2);
      p.setAttribute("fill", "none"); p.setAttribute("stroke", col); p.setAttribute("stroke-width", "1.5"); p.setAttribute("stroke-dasharray", "4 4"); svg.appendChild(p);
    }
    if (S.way === "failure") {
      Object.keys(S.watch).forEach(function (n) { if (S.watch[n] && rest[0]) line(n, rest[0].name, "#f87171"); });
      for (var k = 0; k + 1 < rest.length; k++) line(rest[k].name, rest[k + 1].name, "#a78bfa");
      if (host && rest.length) line(rest[rest.length - 1].name, host.name, "#a78bfa");
    }
  }

  // ---- footer ---------------------------------------------------------------------------------
  function drawFoot() {
    if (!elFoot) return;
    clear(elFoot);
    var n = div("ap-safe"); n.appendChild(icon("shield-check", "me-1 text-green"));
    n.appendChild(document.createTextNode("Agent tools are read-only · daily budget and kill switch on the item"));
    elFoot.appendChild(n);
    elFoot.appendChild(div("ap-msg", S.msg));
    var cancel = btn("Cancel", "ms-auto", null, close);
    var add = btn(S.busy ? "Adding…" : "Add to production", "btn-primary", "rocket", apply);
    add.disabled = S.busy || !S.plan || !S.plan.ok;
    if (S.plan && !S.plan.ok && S.plan.errors && S.plan.errors.length) add.title = S.plan.errors[0];
    elFoot.appendChild(cancel); elFoot.appendChild(add);
  }

  function apply() {
    S.busy = true; S.msg = ""; drawFoot();
    send("POST", "api/workbench/addprod/apply", spec()).then(function (r) {
      S.busy = false;
      if (!r.ok) { S.msg = (r.errors || ["Not added."]).join(" "); drawFoot(); return; }
      var cb = onDone, nm = S.name;
      close();
      if (window.workbenchReload) window.workbenchReload();
      if (cb) cb(nm);
    }).catch(function (e) { S.busy = false; S.msg = e.message; drawFoot(); });
  }

  window.wbAddProd = { open: open, removeInstall: remove, openFor: function (item, reload) { open({ agentClass: item["class"], name: idOf(short(item["class"])), done: reload }); }, canAdd: canAdd, cardBits: cardBits, installCards: installCards, state: function () { return S; } };
})();
