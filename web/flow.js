"use strict";
// Messages tab: live status for the rows, and the message panel (drawer) with the path map and the
// step-by-step journey. Needs el, get, send, money, showTab, showStory, refreshDecisions, renderSpans,
// homeNs, decNs and includeEval from the dashboard script.
(function () {
  var LANES = ["inbound", "router", "ai", "checks", "decision", "outcome"];
  var LANE_LABEL = { inbound: "Inbound", router: "Router", ai: "AI triage", checks: "Checks", decision: "Decision", outcome: "Outcome" };
  var LANE_COLOR = { inbound: "#2563a8", router: "#6d4aa8", ai: "#1f7a4d", checks: "#9a6400", decision: "#0f766e", outcome: "#475569" };
  // The three gates are real steps of every decision, so they are always drawn in the Checks lane
  var GATES = [{ key: "@injection", label: "Injection check" }, { key: "@grounding", label: "Grounding check" }, { key: "@triage", label: "Triage rule" }];
  var STATUS = {
    APPROVED: ["Approved", "good"], REVIEW_APPLIED: ["Approved, applied", "good"], REVIEW_RESENT: ["Approved, resent", "good"],
    REVIEW_CLOSED: ["Approved, closed", "good"], REVIEW_RETURNED: ["Approved, returned", "good"], REVIEW_REJECTED: ["Review rejected", "bad"],
    REVIEW_BAD_LOINC: ["Bad LOINC", "bad"], REVIEW_FIX_FAILED: ["Fix failed", "bad"], APPLIED: ["Applied", "good"], RESENT: ["Resent", "good"],
    REJECTED: ["Rejected", "bad"], waiting: ["Waiting", "warn"], OBSERVED: ["Observed", "other"], ERROR: ["Send failed", "bad"]
  };
  var BORDER = { good: "#1f7a4d", bad: "#b42318", warn: "#9a6400", other: "#7b8794" };
  var POLL_MS = 2000, MAP_MS = 10000, STEP_MS = 1100;
  var MAP_W = 900, LANE_W = MAP_W / LANES.length, NODE_W = 132, NODE_H = 40, ROW_H = 54, HEAD_H = 30;
  var SVGNS = "http://www.w3.org/2000/svg";

  var ns = "IRISAPP", active = false, started = false, timer = null, polling = false, lastTop = "", lastSig = "";
  var msgs = [], selId = null, J = null, jStatus = "", cur = -1, panelOpen = false;
  var panelNs = "IRISAPP", map = null, mapAt = 0, playTimer = null, speed = 1, loadSeq = 0;

  function $(id) { return document.getElementById(id); }
  function evalOn() { return typeof includeEval !== "undefined" && includeEval; }
  function listNs() { return decNs || homeNs || "IRISAPP"; }
  function evalParam() { return "&eval=" + (evalOn() ? 1 : 0); }
  function fmtMs(ms) { return ms < 1000 ? ms + " ms" : (ms < 60000 ? (ms / 1000).toFixed(1) + " s" : Math.round(ms / 60000) + " min"); }
  function statusInfo(s) {
    return STATUS[s] || [String(s).replace(/^REVIEW_/, "Review ").replace(/_/g, " ").toLowerCase().replace(/^./, function (c) { return c.toUpperCase(); }), "other"];
  }
  function showError(e) { $("error").textContent = "Flow: " + e.message; $("error").classList.remove("hidden"); }

  // ---- live status for the rows ----
  function statusTag(s) { var si = statusInfo(s); return el("span", si[0], "tag t-" + si[1]); }
  function byId(id) { return msgs.filter(function (x) { return x.id === id; })[0]; }
  window.flowDecorate = function () {
    Array.prototype.forEach.call(document.querySelectorAll("#decisions tr[data-id]"), function (tr) {
      var m = byId(+tr.dataset.id), td = tr.querySelector("td.st");
      if (td) td.replaceChildren(m ? statusTag(m.status) : document.createTextNode(""));
    });
  };
  function headStatus() {
    var m = byId(selId), box = $("mp-status");
    box.textContent = "";
    if (m) box.appendChild(statusTag(m.status));
  }
  function poll() {
    if (!active || polling) return;
    polling = true;
    ns = listNs();
    get("api/flow/messages?ns=" + ns + evalParam()).then(function (r) {
      msgs = r.messages;
      // a new message or a changed status: reload the table so the row appears
      var sig = msgs.map(function (m) { return m.id + m.status; }).join(",");
      if (sig !== lastSig) {
        var firstPoll = lastSig === "";
        lastSig = sig;
        var top = msgs.length ? String(msgs[0].id) : "";
        if (!firstPoll && top !== lastTop) refreshDecisions();
        lastTop = top;
      }
      window.flowDecorate();
      if (panelOpen && selId != null) {
        headStatus();
        var m = byId(selId);
        // the reviewer answered or a resend finished: the journey has new steps
        if (m && m.status !== jStatus && !playTimer) select(selId, panelNs, true);
      }
    }).catch(showError).then(function () { polling = false; });
    if (Date.now() - mapAt > MAP_MS) { mapAt = Date.now(); loadMap(); }
  }
  function loadMap() {
    return get("api/flow/map?ns=" + (panelOpen ? panelNs : ns) + evalParam()).then(function (m) { map = m; drawMap(); }).catch(showError);
  }

  // ---- journey ----
  function select(id, jns, keepStep) {
    var seq = ++loadSeq;
    selId = id; panelNs = jns;
    return get("api/flow/journey/" + id + "?ns=" + jns).then(function (j) {
      if (seq !== loadSeq) return;
      var wasLast = cur < 0 || !J || cur >= J.steps.length - 1;
      J = j;
      var m = byId(id);
      jStatus = m ? m.status : "";
      stopPlay();
      cur = keepStep && !wasLast ? Math.min(cur, j.steps.length - 1) : j.steps.length - 1;
      renderSteps(); drawMap(); headStatus(); syncControls();
    }).catch(showError);
  }
  function renderSteps() {
    var ol = $("fl-steps");
    ol.textContent = "";
    $("fl-title").textContent = J ? "Journey (agent proposed " + J.decision + ")" : "Journey";
    if (!J) { ol.appendChild(el("li", "No message selected.", "m")); return; }
    J.steps.forEach(function (st, i) {
      var li = el("li", null, "s-" + st.status);
      li.appendChild(el("div", st.n + ". " + st.title, "t"));
      li.appendChild(el("div", st.text, "x"));
      var m = el("div", null, "m");
      m.appendChild(document.createTextNode(st.at.slice(11, 23) + " UTC · " + (st.open ? "open, " : "") + fmtMs(st.durationMs) + (st.gapMs > 50 ? " · " + fmtMs(st.gapMs) + " after the step before" : "") + " · "));
      if (st.session) {
        var a = el("a", "Visual Trace, session " + st.session);
        a.href = J.traceUrl + st.session; a.target = "_blank"; a.rel = "noopener";
        a.addEventListener("click", function (e) { e.stopPropagation(); });
        m.appendChild(a);
      }
      li.appendChild(m);
      if (st.waitLabel) li.appendChild(el("span", st.waitLabel, "tag t-warn"));
      li.addEventListener("click", function () { stopPlay(); goTo(i); });
      ol.appendChild(li);
    });
    markCurrent(false);
  }
  function markCurrent(scroll) {
    var items = $("fl-steps").querySelectorAll("li");
    for (var k = 0; k < items.length; k++) {
      items[k].classList.toggle("cur", k === cur);
      items[k].classList.toggle("future", k > cur);
    }
    if (scroll && items[cur] && items[cur].scrollIntoView) items[cur].scrollIntoView({ block: "nearest" });
  }
  function goTo(i) {
    if (!J) return;
    cur = Math.max(0, Math.min(J.steps.length - 1, i));
    markCurrent(true); drawMap(); syncControls();
  }
  function stopPlay() { if (playTimer) { clearInterval(playTimer); playTimer = null; } syncControls(); }
  function play() {
    if (!J) return;
    if (playTimer) { stopPlay(); return; }
    if (cur >= J.steps.length - 1) { cur = -1; }
    playTimer = setInterval(function () {
      if (cur >= J.steps.length - 1) { stopPlay(); return; }
      goTo(cur + 1);
    }, STEP_MS / speed);
    if (cur < 0) goTo(0);
    syncControls();
  }
  function syncControls() {
    $("fj-play").textContent = playTimer ? "Pause" : "Play";
    $("fj-speed").textContent = speed + "x";
    $("fj-back").disabled = !J || cur <= 0;
    $("fj-fwd").disabled = !J || cur >= J.steps.length - 1;
  }

  // ---- map ----
  function canonOf() {
    var c = {};
    (map ? map.items : []).forEach(function (it) { c[it.name.toUpperCase()] = it.name; });
    return function (n) { return n ? (n.charAt(0) === "@" ? n : (c[String(n).toUpperCase()] || n)) : null; };
  }
  // Nodes a step touches, in the order the message passed them
  function stepNodes(st, canon) {
    if (st.edge) return [canon(st.edge.from), canon(st.edge.to)];
    return st.node ? [canon(st.node)] : [];
  }
  function pathUpTo(last, canon) {
    var seq = [];
    if (J) for (var i = 0; i <= last && i < J.steps.length; i++) {
      stepNodes(J.steps[i], canon).forEach(function (n) { if (n && seq[seq.length - 1] !== n) seq.push(n); });
    }
    return seq;
  }
  function svg(tag, attrs, text) {
    var e = document.createElementNS(SVGNS, tag);
    Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (text != null) e.textContent = text;
    return e;
  }
  function drawMap() {
    var root = $("fl-map");
    if (!root || !map) return;
    var canon = canonOf(), full = {};
    pathUpTo(J ? J.steps.length - 1 : -1, canon).forEach(function (n) { full[n] = 1; });
    // Only the nodes this message passed, resend targets (LabRouter, EhrOut, FhirOut) included
    var lanes = {};
    LANES.forEach(function (l) { lanes[l] = []; });
    map.items.forEach(function (it) {
      if (lanes[it.lane] && full[it.name]) lanes[it.lane].push({ key: it.name, label: it.name, sub: "in " + it.in + " · out " + it.out + (it.errors ? " · err " + it.errors : ""), err: it.errors > 0 });
    });
    GATES.forEach(function (g) { if (full[g.key]) lanes.checks.push({ key: g.key, label: g.label, sub: "" }); });
    var rows = Math.max.apply(null, LANES.map(function (l) { return lanes[l].length; }).concat([3])), H = HEAD_H + rows * ROW_H + 4;
    root.textContent = "";
    root.setAttribute("viewBox", "0 0 " + MAP_W + " " + H);
    var pos = {};
    LANES.forEach(function (l, i) {
      var x0 = i * LANE_W;
      root.appendChild(svg("rect", { x: x0, y: 0, width: LANE_W, height: H, fill: LANE_COLOR[l], opacity: i % 2 ? 0.05 : 0.09 }));
      root.appendChild(svg("text", { x: x0 + LANE_W / 2, y: 18, "text-anchor": "middle", class: "lane-h", style: "fill:" + LANE_COLOR[l] }, LANE_LABEL[l]));
      lanes[l].forEach(function (n, k) { pos[n.key] = { x: x0 + LANE_W / 2, y: HEAD_H + k * ROW_H + ROW_H / 2, n: n }; });
    });
    var curNodes = J && cur >= 0 ? stepNodes(J.steps[cur], canon) : [];
    var seq = pathUpTo(cur, canon).filter(function (n) { return pos[n]; }), onPath = {};
    seq.forEach(function (n) { onPath[n] = 1; });
    // Path under the nodes, so a node keeps its label readable
    var pts = [];
    seq.forEach(function (n, i) {
      var p = pos[n], prev = i > 0 ? pos[seq[i - 1]] : null, next = i < seq.length - 1 ? pos[seq[i + 1]] : null;
      function edgePt(o, toward) {
        if (toward.x > o.x + 1) return [o.x + NODE_W / 2, o.y];
        if (toward.x < o.x - 1) return [o.x - NODE_W / 2, o.y];
        return [o.x, o.y + (toward.y > o.y ? NODE_H / 2 : -NODE_H / 2)];
      }
      if (prev) pts.push(edgePt(p, prev));
      else if (!next) pts.push([p.x, p.y]);
      if (next) pts.push(edgePt(p, next));
    });
    if (pts.length > 1) root.appendChild(svg("polyline", { class: "fl-path", points: pts.map(function (q) { return q[0] + "," + q[1]; }).join(" ") }));
    Object.keys(pos).forEach(function (k) {
      var p = pos[k], n = p.n, cls = "node" + (onPath[k] ? " on" : "") + (curNodes.indexOf(k) >= 0 ? " cur" : "") + (n.err ? " err" : "");
      root.appendChild(svg("rect", { class: cls, x: p.x - NODE_W / 2, y: p.y - NODE_H / 2, width: NODE_W, height: NODE_H, rx: 6 }));
      root.appendChild(svg("text", { x: p.x, y: p.y - (n.sub ? 3 : -4), "text-anchor": "middle" }, n.label.length > 20 ? n.label.slice(0, 19) + "…" : n.label));
      if (n.sub) root.appendChild(svg("text", { x: p.x, y: p.y + 11, "text-anchor": "middle", class: "sub" }, n.sub));
    });
  }

  // ---- burst ----
  function burst(confirm) {
    var n = +$("burst-n").value, mode = $("burst-mode").value, msg = $("burst-msg");
    msg.className = "msg"; msg.textContent = "";
    $("burst-confirm").classList.add("hidden");
    send("POST", "api/burst", { n: n, mode: mode, ns: ns, confirm: !!confirm }).then(function (r) {
      msg.className = "msg ok"; msg.textContent = "Sent " + r.sent.length + " " + r.mode + " messages" + (r.estimatedCostUsd ? ", about " + money(r.estimatedCostUsd, 4) : ", no LLM cost") + ".";
      lastTop = "";
      poll();
    }).catch(function (e) {
      msg.className = "msg bad"; msg.textContent = e.message;
      if (/costs about/.test(e.message)) $("burst-confirm").classList.remove("hidden");
    });
  }

  function openPanel(id, jns) {
    jns = jns || listNs();
    panelOpen = true; selId = id; panelNs = jns; J = null; cur = -1;
    $("msg-panel").classList.remove("hidden"); $("mp-back").classList.remove("hidden");
    $("mp-title").textContent = "Message " + id; $("mp-sub").textContent = ""; $("mp-links").textContent = "";
    mpTab("journey");
    renderSteps(); headStatus(); syncControls();
    var h = "msg=" + id + (jns !== (homeNs || "IRISAPP") ? "&ns=" + jns : "");
    try { history.replaceState(null, "", "#" + h); } catch (e) { location.hash = h; }
    if (!started) start();
    mapAt = Date.now(); loadMap();
    select(id, jns);
    showStory(id);
    if (!byId(id)) poll();
  }
  function closePanel() {
    if (!panelOpen) return;
    panelOpen = false; stopPlay();
    $("msg-panel").classList.add("hidden"); $("mp-back").classList.add("hidden");
    try { history.replaceState(null, "", location.pathname + location.search); } catch (e) { location.hash = ""; }
  }
  function mpTab(name) {
    Array.prototype.forEach.call(document.querySelectorAll(".mp-tabs button"), function (b) { b.setAttribute("aria-selected", b.dataset.mp === name ? "true" : "false"); });
    $("mp-journey").classList.toggle("hidden", name !== "journey");
    $("mp-details").classList.toggle("hidden", name !== "details");
    if (name === "details" && lastStory) renderSpans(lastStory);
    if (name === "journey") drawMap();
  }
  function fromHash() {
    var m = /^#msg=(\d+)(?:&ns=(\w+))?$/.exec(location.hash);
    if (!m) { closePanel(); return; }
    showTab("messages");
    if (!(panelOpen && String(selId) === m[1])) openPanel(+m[1], m[2] || homeNs || "IRISAPP");
  }

  function start() {
    started = true;
    $("mp-close").addEventListener("click", closePanel);
    $("mp-back").addEventListener("click", closePanel);
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") closePanel(); });
    Array.prototype.forEach.call(document.querySelectorAll(".mp-tabs button"), function (b) { b.addEventListener("click", function () { mpTab(b.dataset.mp); }); });
    window.addEventListener("hashchange", fromHash);
    $("fj-play").addEventListener("click", play);
    $("fj-back").addEventListener("click", function () { stopPlay(); goTo(cur - 1); });
    $("fj-fwd").addEventListener("click", function () { stopPlay(); goTo(cur + 1); });
    $("fj-speed").addEventListener("click", function () {
      speed = speed === 1 ? 2 : (speed === 2 ? 4 : 1);
      if (playTimer) { var on = playTimer; stopPlay(); if (on) play(); }
      syncControls();
    });
    $("burst-go").addEventListener("click", function () { burst(false); });
    $("burst-confirm").addEventListener("click", function () { burst(true); });
    $("burst-mode").addEventListener("change", function () {
      var live = $("burst-mode").value === "live";
      $("burst-n").max = live ? 10 : 30; if (live && +$("burst-n").value > 10) $("burst-n").value = 10;
      $("burst-confirm").classList.add("hidden");
    });
    // The dashboard's own handler has already updated includeEval
    $("incl-eval").addEventListener("change", function () { lastSig = ""; if (active) poll(); });
    renderSteps(); syncControls();
  }

  window.flowOpen = openPanel;
  // Called by the dashboard when a tab is shown: poll live status while Messages is on screen
  window.flowShow = function (name) {
    var on = name === "messages";
    if (!started) start();
    if (on === active) return;
    active = on;
    if (!on) { clearInterval(timer); timer = null; return; }
    get("api/settings/productions").then(function (r) { $("burst-box").classList.toggle("hidden", !r.canEdit); }).catch(function () {});
    lastSig = ""; poll();
    timer = setInterval(poll, POLL_MS);
  };
  var sel = document.querySelector(".tabs button[aria-selected=true]");
  if (sel) window.flowShow(sel.dataset.tab);
  if (location.hash) fromHash();
})();