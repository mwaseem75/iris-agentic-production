"use strict";
// Flow tab: live message list, a compact production map, and a step-by-step journey of the selected
// message. Needs el, get, send, money, showTab, showStory and includeEval from the dashboard script.
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

  var ns = "IRISAPP", active = false, started = false, timer = null, polling = false, paused = false;
  var msgs = [], selId = null, auto = true, J = null, jStatus = "", cur = -1;
  var map = null, mapAt = 0, playTimer = null, speed = 1, loadSeq = 0;

  function $(id) { return document.getElementById(id); }
  function evalOn() { return typeof includeEval !== "undefined" && includeEval; }
  function evalParam() { return "&eval=" + (evalOn() ? 1 : 0); }
  function fmtMs(ms) { return ms < 1000 ? ms + " ms" : (ms < 60000 ? (ms / 1000).toFixed(1) + " s" : Math.round(ms / 60000) + " min"); }
  function statusInfo(s) {
    return STATUS[s] || [String(s).replace(/^REVIEW_/, "Review ").replace(/_/g, " ").toLowerCase().replace(/^./, function (c) { return c.toUpperCase(); }), "other"];
  }
  function showError(e) { $("flow-msg").textContent = "Flow: " + e.message; }

  // ---- message list ----
  function renderList() {
    var ul = $("fl-list");
    ul.textContent = "";
    msgs.forEach(function (m) {
      var si = statusInfo(m.status), li = el("li", null, m.id === selId ? "sel" : "");
      li.style.borderLeftColor = BORDER[si[1]];
      var r1 = el("div", null, "r1");
      r1.appendChild(el("span", (m.at || "").slice(11, 19) + "  " + (m.controlId || "#" + m.headerId), "id"));
      r1.appendChild(el("span", si[0], "tag t-" + si[1]));
      li.appendChild(r1);
      li.appendChild(el("div", m.errorClass + (m.error ? ": " + m.error : "") + (m.burst ? " (burst)" : (m.eval ? " (eval)" : "")), "r2"));
      li.title = m.error || m.errorClass;
      li.addEventListener("click", function () { auto = false; select(m.id); });
      ul.appendChild(li);
    });
    if (!msgs.length) ul.appendChild(el("li", "No messages yet. Send a burst to see one.", "r2"));
  }
  function poll() {
    if (!active || polling || paused) return;
    polling = true;
    get("api/flow/messages?ns=" + ns + evalParam()).then(function (r) {
      msgs = r.messages;
      $("flow-msg").textContent = "";
      $("flow-status").textContent = "updated " + new Date().toLocaleTimeString("en-GB") + " · " + msgs.length + " messages";
      if (auto && msgs.length && msgs[0].id !== selId) select(msgs[0].id);
      else if (selId != null) {
        var m = msgs.filter(function (x) { return x.id === selId; })[0];
        // the reviewer answered or a resend finished: the journey has new steps
        if (m && m.status !== jStatus && !playTimer) select(selId, true);
      }
      renderList();
    }).catch(showError).then(function () { polling = false; });
    if (Date.now() - mapAt > MAP_MS) { mapAt = Date.now(); loadMap(); }
  }
  function loadMap() {
    return get("api/flow/map?ns=" + ns + evalParam()).then(function (m) { map = m; drawMap(); }).catch(showError);
  }

  // ---- journey ----
  function select(id, keepStep) {
    var seq = ++loadSeq;
    selId = id;
    get("api/flow/journey/" + id + "?ns=" + ns).then(function (j) {
      if (seq !== loadSeq) return;
      var wasLast = cur < 0 || !J || cur >= J.steps.length - 1;
      J = j;
      var m = msgs.filter(function (x) { return x.id === id; })[0];
      jStatus = m ? m.status : "";
      stopPlay();
      cur = keepStep && !wasLast ? Math.min(cur, j.steps.length - 1) : j.steps.length - 1;
      renderSteps(); drawMap(); renderList(); syncControls();
    }).catch(showError);
  }
  function renderSteps() {
    var ol = $("fl-steps");
    ol.textContent = "";
    $("fl-title").textContent = J ? "Journey: message " + J.headerId + " (" + J.decision + ")" : "Journey";
    $("fj-story").classList.toggle("hidden", !J);
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
    // Items with no traffic in the window stay out of the picture unless the selected message used them
    var lanes = {};
    LANES.forEach(function (l) { lanes[l] = []; });
    map.items.forEach(function (it) {
      if (lanes[it.lane] && (it.in + it.out > 0 || full[it.name])) lanes[it.lane].push({ key: it.name, label: it.name, sub: "in " + it.in + " · out " + it.out + (it.errors ? " · err " + it.errors : ""), err: it.errors > 0 });
    });
    GATES.forEach(function (g) { lanes.checks.push({ key: g.key, label: g.label, sub: "" }); });
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
      auto = true;
    }).catch(function (e) {
      msg.className = "msg bad"; msg.textContent = e.message;
      if (/costs about/.test(e.message)) $("burst-confirm").classList.remove("hidden");
    });
  }

  function start() {
    started = true;
    $("flow-ns").addEventListener("change", function (e) {
      ns = e.target.value; msgs = []; J = null; selId = null; cur = -1; auto = true; map = null; stopPlay();
      renderList(); renderSteps(); loadMap(); poll();
    });
    $("fl-pause").addEventListener("click", function () {
      paused = !paused;
      $("fl-pause").textContent = paused ? "Resume" : "Pause";
      if (paused) $("flow-status").textContent = "list paused at " + new Date().toLocaleTimeString("en-GB");
    });
    $("fj-play").addEventListener("click", play);
    $("fj-back").addEventListener("click", function () { stopPlay(); goTo(cur - 1); });
    $("fj-fwd").addEventListener("click", function () { stopPlay(); goTo(cur + 1); });
    $("fj-speed").addEventListener("click", function () {
      speed = speed === 1 ? 2 : (speed === 2 ? 4 : 1);
      if (playTimer) { var on = playTimer; stopPlay(); if (on) play(); }
      syncControls();
    });
    $("fj-story").addEventListener("click", function (e) { e.preventDefault(); if (J) { showTab("messages"); showStory(J.id); } });
    $("burst-go").addEventListener("click", function () { burst(false); });
    $("burst-confirm").addEventListener("click", function () { burst(true); });
    $("burst-mode").addEventListener("change", function () {
      var live = $("burst-mode").value === "live";
      $("burst-n").max = live ? 10 : 30; if (live && +$("burst-n").value > 10) $("burst-n").value = 10;
      $("burst-confirm").classList.add("hidden");
    });
    // The dashboard's own handler has already updated includeEval
    $("incl-eval").addEventListener("change", function () { if (active) { auto = true; selId = null; mapAt = 0; poll(); } });
    renderSteps(); syncControls();
  }

  // Called by the dashboard when a tab is shown
  window.flowShow = function (name) {
    var on = name === "flow";
    if (!started) start();
    if (on === active) return;
    active = on;
    if (!on) { clearInterval(timer); timer = null; stopPlay(); return; }
    get("api/settings/productions").then(function (r) { $("burst-box").classList.toggle("hidden", !r.canEdit); }).catch(function () {});
    mapAt = Date.now(); loadMap(); poll();
    timer = setInterval(poll, POLL_MS);
  };
  var sel = document.querySelector(".tabs button[aria-selected=true]");
  if (sel) window.flowShow(sel.dataset.tab);
})();
