"use strict";
// Messages tab: live status for the rows, and the message panel (drawer) with the path map and the
// step-by-step journey. Needs el, get, send, money, showTab, showStory, refreshDecisions, renderSpans,
// homeNs, decNs and includeEval from the dashboard script.
(function () {
  var STATUS = {
    APPROVED: ["Approved", "good"], REVIEW_APPLIED: ["Approved, applied", "good"], REVIEW_RESENT: ["Approved, resent", "good"],
    REVIEW_CLOSED: ["Approved, closed", "good"], REVIEW_RETURNED: ["Approved, returned", "good"], REVIEW_REJECTED: ["Review rejected", "bad"],
    REVIEW_BAD_LOINC: ["Bad LOINC", "bad"], REVIEW_FIX_FAILED: ["Fix failed", "bad"], APPLIED: ["Applied", "good"], RESENT: ["Resent", "good"],
    REJECTED: ["Rejected", "bad"], SENT_FOR_APPROVAL: ["Human review", "warn"], waiting: ["Waiting", "warn"], OBSERVED: ["Observed", "other"], ERROR: ["Send failed", "bad"]
  };
  var POLL_MS = 2000, MAP_MS = 10000, STEP_MS = 1100;
  var SVGNS = "http://www.w3.org/2000/svg";

  var ns = "IRISAPP", active = false, started = false, timer = null, polling = false, lastTop = "", lastSig = "";
  var msgs = [], selId = null, J = null, jStatus = "", cur = -1, panelOpen = false;
  var panelNs = "IRISAPP", map = null, mapAt = 0, playTimer = null, speed = 2, loadSeq = 0, opening = false, openSeq = 0;

  function $(id) { return document.getElementById(id); }
  function evalOn() { return typeof includeEval !== "undefined" && includeEval; }
  function listNs() { return decNs || homeNs || "IRISAPP"; }
  function evalParam() { return "&eval=" + (evalOn() ? 1 : 0); }
  function fmtMs(ms) { return ms < 1000 ? ms + " ms" : (ms < 60000 ? (ms / 1000).toFixed(1) + " s" : Math.round(ms / 60000) + " min"); }
  function statusInfo(s) {
    if (typeof s === "string" && s.indexOf("DOWNGRADED:") === 0) return ["Downgraded to review", "warn"];
    if (typeof s === "string" && s.indexOf("PROPOSED:") === 0) return ["Mapping proposed", "warn"];
    return STATUS[s] || [String(s).replace(/^REVIEW_/, "Review ").replace(/_/g, " ").toLowerCase().replace(/^./, function (c) { return c.toUpperCase(); }), "other"];
  }
  function showError(e) { $("error").textContent = "Flow: " + e.message; $("error").classList.remove("hidden"); }

  // ---- live status for the rows ----
  function statusTag(s) { var si = statusInfo(s); return el("span", si[0], "tag t-" + si[1]); }
  function byId(id) { return msgs.filter(function (x) { return x.id === id; })[0]; }
  // Flow list entry of one decision (current status from the Workflow task), for the Messages table
  window.flowMessage = function (id) { return byId(id); };
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
    renderFacts();
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
        // jStatus is null until the journey was loaded with this message in the list: just learn it, a reload would stop the autoplay
        if (m && jStatus === null) jStatus = m.status;
        else if (m && m.status !== jStatus && !playTimer && !opening) select(selId, panelNs, true);
      }
    }).catch(showError).then(function () { polling = false; });
    if (Date.now() - mapAt > MAP_MS) { mapAt = Date.now(); loadMap(); }
  }
  function loadMap() {
    return get("api/flow/map?ns=" + (panelOpen ? panelNs : ns) + evalParam()).then(function (m) { map = m; drawMap(); if (panelOpen) renderFacts(); }).catch(showError);
  }

  // ---- journey ----
  function select(id, jns, keepStep, fresh) {
    var seq = ++loadSeq;
    selId = id; panelNs = jns;
    return get("api/flow/journey/" + id + "?ns=" + jns).then(function (j) {
      if (seq !== loadSeq) return;
      var wasLast = cur < 0 || !J || cur >= J.steps.length - 1;
      J = j; selKey = "";
      var m = byId(id);
      jStatus = m ? m.status : null;
      stopPlay();
      cur = fresh ? -1 : keepStep && !wasLast ? Math.min(cur, j.steps.length - 1) : j.steps.length - 1;
      renderSteps(); drawMap(); headStatus(); syncControls();
    }).catch(showError);
  }
  function renderSteps() {
    var ol = $("fl-steps");
    ol.textContent = "";
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
      li.addEventListener("click", function () { var was = !!playTimer; stopPlay(); goTo(i); if (was) play(); });
      ol.appendChild(li);
    });
    markCurrent(false);
  }
  function markCurrent(scroll) {
    var items = $("fl-steps").querySelectorAll("li");
    for (var k = 0; k < items.length; k++) {
      items[k].classList.toggle("cur", k === cur);
      items[k].classList.toggle("future", k > cur);
      items[k].classList.toggle("sel", !!(selKey && cvUi[selKey] && cvUi[selKey].steps.indexOf(k + 1) >= 0));
    }
    var ol = $("fl-steps"), li = items[cur];
    if (scroll && li) {
      if (li.offsetTop < ol.scrollTop || li.offsetTop + li.offsetHeight > ol.scrollTop + ol.clientHeight) ol.scrollTop = Math.max(0, li.offsetTop - ol.clientHeight / 2 + li.offsetHeight / 2);
    }
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
    $("fj-play").firstChild.className = "ti " + (playTimer ? "ti-player-pause" : "ti-player-play");
    Array.prototype.forEach.call(document.querySelectorAll("#fj-speeds button"), function (b) { b.classList.toggle("on", +b.dataset.speed === speed); });
    $("fj-back").disabled = !J || cur <= 0;
    $("fj-fwd").disabled = !J || cur >= J.steps.length - 1;
    $("fj-replay").disabled = !J;
    var n = J ? J.steps.length : 0, pos = $("fj-pos");
    pos.textContent = "";
    if (J) {
      pos.appendChild(document.createTextNode("Step "));
      pos.appendChild(el("b", String(cur + 1)));
      pos.appendChild(document.createTextNode(" of " + n + (cur >= 0 ? " · " : "")));
      if (cur >= 0) pos.appendChild(el("b", J.steps[cur].title));
    }
    $("fj-bar").style.width = (n ? Math.round((cur + 1) * 100 / n) : 0) + "%";
  }
  // Header facts: what came in, what the agent proposed, what Triage did, what it cost
  function renderFacts() {
    var box = $("mp-facts"), m = byId(selId), a = J && J.agent || {};
    box.textContent = "";
    if (!J) return;
    var used = a.used, conf = used && a.confidence !== "" ? " · " + Number(a.confidence).toFixed(2) : "";
    [["Received", J.createdAt ? J.createdAt.slice(5, 19) + " UTC" : "—"],
     ["Production", panelNs + (map && map.production ? " · " + map.production : "")],
     ["Problem", EC_LABEL[J.errorClass] || J.errorClass || "—"],
     ["Agent proposed", used ? (ACT_LABEL[J.decision] || J.decision) + conf : "Agent not used"],
     ["Final decision", m ? statusInfo(m.status)[0] : (J.outcome || "—")],
     ["AI cost", used ? money(a.costUsd, 4) + " · " + Number(a.tokens).toLocaleString() + " tokens" : "No LLM cost"]
    ].forEach(function (f) {
      var d = el("div");
      d.appendChild(el("div", f[0], "k")); d.appendChild(el("div", f[1], "v"));
      box.appendChild(d);
    });
    var task = $("mp-task"), inbox = $("inbox-link").href;
    var has = J.steps.some(function (s) { return s.kind === "workflow"; }) && inbox;
    task.classList.toggle("hidden", !has);
    if (has) task.href = inbox;
  }

  function svg(tag, attrs, text) {
    var e = document.createElementNS(SVGNS, tag);
    Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    if (text != null) e.textContent = text;
    return e;
  }

  // ---- workflow canvas ----
  var CW = 1000, CH = 456;
  var ORDER = ["trigger", "router", "agent", "guard", "triage"];
  var SUBS = ["model", "memory", "tools", "skills", "knowledge", "policies"];
  var ICON = {
    trigger: "M4 12h10M10 7l5 5-5 5M18 5v14", router: "M5 6h6v12H5zM13 9h6M13 15h6M11 12h2", agent: "M12 4v3M7 8h10v9H7zM9.5 12h.01M14.5 12h.01M10 15h4",
    guard: "M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z", triage: "M5 5h14l-5 7v6l-4 2v-8z", ehr: "M4 6h16v10H4zM9 20h6M12 16v4", fhir: "M12 3l8 4.5v9L12 21l-8-4.5v-9zM12 12l8-4.5M12 12v9M12 12L4 7.5",
    human: "M12 4a3 3 0 100 6 3 3 0 000-6zM5 20c0-4 3-6 7-6s7 2 7 6", rejected: "M6 6l12 12M18 6L6 18", resent: "M4 12a8 8 0 0114-5l2-2v6h-6l2.5-2.5A5 5 0 007 12M20 12a8 8 0 01-14 5l-2 2v-6h6l-2.5 2.5A5 5 0 0017 12",
    model: "M12 3v4M12 17v4M3 12h4M17 12h4M8 8h8v8H8z", memory: "M5 7c0-2 14-2 14 0v10c0 2-14 2-14 0zM5 12c0 2 14 2 14 0", tools: "M14 6a4 4 0 00-5 5l-5 5 3 3 5-5a4 4 0 005-5l-3 2-2-2z",
    skills: "M5 5h6v6H5zM13 5h6v6h-6zM5 13h6v6H5zM16 13v6M13 16h6", knowledge: "M11 4a7 7 0 100 14 7 7 0 000-14zM16 16l4 4", policies: "M7 11V8a5 5 0 0110 0v3M6 11h12v9H6z"
  };
  var SUB_TITLE = { model: "Model", memory: "Memory", tools: "Tools", skills: "Skills", knowledge: "Knowledge", policies: "Policies" };
  var GUARDS = ["injection", "grounding", "ambiguity"];
  var selKey = "", cv = null, cvKey = "", anim = null, raf = 0, cvUi = {};

  function h(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function icon(name) {
    var s = svg("svg", { "class": "ic", viewBox: "0 0 24 24" });
    s.appendChild(svg("path", { d: ICON[name] || ICON.router }));
    return s;
  }
  function laneOf(name) {
    var n = (name || "").toUpperCase(), l = "";
    if (map) map.items.forEach(function (it) { if (it.name.toUpperCase() === n) l = it.lane; });
    return l;
  }
  // Canvas node a step belongs to. A hop to Triage keeps the message at the router: Triage lights when its rule runs.
  function keyOf(st) {
    var to = st.edge ? st.edge.to : st.node, lane = laneOf(to);
    switch (st.kind) {
      case "inbound": return "trigger";
      case "router": return "router";
      case "agent": case "tool": return "agent";
      case "injection": case "grounding": return "guard";
      case "triage": case "learning": return "triage";
      case "workflow": return "out:human";
      case "hop":
        if (lane === "ai") return "agent";
        return lane === "outcome" ? "out:human" : "router";
      default: // out, resend
        return lane === "outcome" ? "out:" + to : "out:Resent";
    }
  }
  function nodeTitle(k) {
    if (k === "out:human") return "Human review";
    return k.replace(/^out:/, "");
  }
  function outIcon(k) { return k === "out:human" ? "human" : k === "out:Resent" ? "resent" : k === "out:Rejected" ? "rejected" : /fhir/i.test(k) ? "fhir" : "ehr"; }

  function mkNode(key, x, y, w, hh, title, ico, extra, small) {
    var n = h("div", "fl-nd" + (extra ? " " + extra : ""));
    if (SUBS.indexOf(ico) >= 0) n.classList.add("subn");
    n.style.left = x + "px"; n.style.top = y + "px"; n.style.width = w + "px"; n.style.height = hh + "px";
    var head = h("div", "h"), st = h("span", "st"), sub = h("div", "s");
    var wrapIco = SUBS.indexOf(ico) >= 0 || extra === "agent";
    var ic = icon(ico);
    if (wrapIco) { var ring = h("span", "ico"); ring.appendChild(ic); head.appendChild(ring); } else head.appendChild(ic);
    if (extra === "agent") {
      var tt = h("span", "tt"), b = h("b", null, title);
      tt.appendChild(b); tt.appendChild(sub); head.appendChild(tt); head.appendChild(st); n.appendChild(head);
    } else {
      var tl = h("span", "ttl", title); tl.title = title + (small ? " / " + small : "");
      if (small) tl.appendChild(h("small", null, small));
      head.appendChild(tl); head.appendChild(st); n.appendChild(head); n.appendChild(sub);
    }
    n.appendChild(h("span", "port i")); n.appendChild(h("span", "port o"));
    var bd = h("div", "bd");
    n.appendChild(bd);
    cv.root.appendChild(n);
    cvUi[key] = { el: n, st: st, sub: sub, bd: bd, groups: [], x: x, y: y, w: w, h: hh };
    return cvUi[key];
  }
  function wire(a, b, cls, idx, cnt) {
    var A = cvUi[a], B = cvUi[b];
    if (!A || !B) return;
    var x1, y1, x2, y2, d;
    if (cls === "sub") {
      x1 = A.x + A.w * (idx + 1) / (cnt + 1); y1 = A.y + A.h; x2 = B.x + B.w / 2; y2 = B.y;
      d = "M" + x1 + "," + y1 + " C" + x1 + "," + (y1 + 45) + " " + x2 + "," + (y2 - 45) + " " + x2 + "," + y2;
    } else {
      x1 = A.x + A.w; y1 = A.y + A.h / 2; x2 = B.x; y2 = B.y + B.h / 2;
      var dx = Math.max(24, Math.abs(x2 - x1) / 2);
      d = "M" + x1 + "," + y1 + " C" + (x1 + dx) + "," + y1 + " " + (x2 - dx) + "," + y2 + " " + x2 + "," + y2;
    }
    var p = svg("path", { "class": "w " + (cls || ""), d: d });
    cv.wires.appendChild(p);
    cv.paths[a + ">" + b] = p;
  }

  // Nodes and wires for the whole journey; paintCanvas then lights the part reached at the current step
  function buildCanvas() {
    var root = $("fl-canvas");
    if (!root) return;
    root.textContent = ""; cvUi = {};
    var wires = svg("svg", { "class": "wires", viewBox: "0 0 " + CW + " " + CH });
    root.appendChild(wires);
    root.onclick = function () { if (selKey) { selKey = ""; markCurrent(false); paintCanvas(1); } };
    cv = { root: root, wires: wires, paths: {}, dot: null, label: null };
    if (!J) return;
    var ag = J.agent || {}, outs = [];
    J.steps.forEach(function (st) { var k = keyOf(st); if (/^out:/.test(k) && outs.indexOf(k) < 0) outs.push(k); });
    if (J.outcome === "rejected" && outs.indexOf("out:Rejected") < 0) outs.push("out:Rejected");
    var names = {};
    J.steps.forEach(function (s) {
      if (s.kind === "inbound" && s.edge && !names.trigger) names.trigger = s.edge.from;
      if (s.kind === "router" && s.node && !names.router) { names.router = s.node; if (s.failedAt) names.fail = s.failedAt; }
    });
    // Real item names along the path when a Sentinel carried the failure to Triage
    var old = root.parentNode.querySelector(".fl-path");
    if (old) old.parentNode.removeChild(old);
    if (J.path && J.path.length) {
      var strip = h("div", "fl-path");
      J.path.forEach(function (p, i) {
        if (i) strip.appendChild(h("span", "sep", "\u2192"));
        strip.appendChild(h("span", /fails\)$/.test(p) ? "nm bad" : "nm", p));
      });
      root.parentNode.insertBefore(strip, root);
    }
    mkNode("trigger", 8, 92, 112, 96, "Trigger", "trigger", "main", names.trigger);
    mkNode("router", 142, 92, 112, 96, "Router", "router", "main", (names.router || "") + (names.fail ? " \u2192 " + names.fail + " \u2717" : ""));
    mkNode("agent", 280, 55, 250, 170, "AI Hub Agent", "agent", "agent").sub.textContent = (ag.name || "TriageAgent") + " · " + (ag.agentClass || ag["class"] || "%AI.Agent");
    cvUi.agent.live = h("div", "s live");
    cvUi.agent.sub.parentNode.appendChild(cvUi.agent.live);
    var g = mkNode("guard", 562, 75, 130, 130, "Guardrails", "guard");
    GUARDS.forEach(function (r) {
      var row = h("div", "rw"), mark = h("i", null, "·");
      row.appendChild(mark); row.appendChild(h("span", null, r.charAt(0).toUpperCase() + r.slice(1)));
      g.sub.appendChild(row); g[r] = mark;
    });
    mkNode("triage", 722, 92, 96, 96, "Triage", "triage", "main", J.checkName || "");
    // the human review card carries wrapped status text, so it is the tall one
    var oh = function (k) { return k === "out:human" ? 108 : 56; }, oy = outs.length > 1 ? 8 : 100;
    outs.forEach(function (k) { mkNode(k, 840, oy, 152, oh(k), nodeTitle(k), outIcon(k), undefined, k === "out:human" ? J.workflowName : undefined); oy += oh(k) + 8; });
    SUBS.forEach(function (k, i) { mkNode(k, 8 + i * 166, 312, 156, 136, SUB_TITLE[k], k); });
    (ag.tools || []).forEach(function (t) { if (t !== "search_loinc" && t !== "load_skill") cvUi.tools.sub.appendChild(h("span", "chip", t)); });
    (ag.skills || []).forEach(function (t) { cvUi.skills.sub.appendChild(h("span", "chip", t)); });
    cvUi.skills.sub.appendChild(h("div", "note", "inferred from tools"));
    var calls = {};
    J.steps.forEach(function (s) { if (s.kind === "tool") calls[s.tool] = (calls[s.tool] || 0) + 1; });
    var anyTool = Object.keys(calls).length > 0;
    var unused = { model: !ag.used, memory: !ag.sessionId && !ag.learned, tools: !(ag.tools || []).some(function (t) { return t !== "search_loinc" && t !== "load_skill"; }),
      skills: !(ag.skillsUsed || []).length, knowledge: !calls.search_loinc, policies: !anyTool };
    SUBS.forEach(function (k) {
      var nu = h("div", "nu", "not used");
      cvUi[k].el.appendChild(nu);
      if (unused[k]) cvUi[k].el.classList.add("unused");
    });
    for (var i = 0; i < ORDER.length - 1; i++) wire(ORDER[i], ORDER[i + 1]);
    outs.forEach(function (k) { wire("triage", k); });
    SUBS.forEach(function (k, i) { wire("agent", k, "sub", i, SUBS.length); });
    addBadges();
    cv.dot = svg("circle", { "class": "dot", r: 6, cx: 0, cy: 0, visibility: "hidden" });
    cv.label = svg("text", { "class": "wl", x: 0, y: 0, visibility: "hidden" }, "1 message");
    wires.appendChild(cv.dot); wires.appendChild(cv.label);
  }
  // Numbered badges: the journey steps each node took part in, consecutive numbers as a range
  function addBadges() {
    var nums = {};
    function put(k, n) { if (cvUi[k]) (nums[k] = nums[k] || []).push(n); }
    J.steps.forEach(function (s) {
      var k = keyOf(s);
      if (k === "triage" && s.kind !== "triage" && s.kind !== "learning") return;
      put(k, s.n);
      if (s.sub && s.sub !== k) put(s.sub, s.n);
      if (s.kind === "tool") put("policies", s.n);
    });
    Object.keys(nums).forEach(function (k) {
      var list = nums[k].filter(function (n, i, a) { return a.indexOf(n) === i; }), from = list[0], prev = from, u = cvUi[k];
      u.steps = list;
      u.el.classList.add("click");
      u.el.title = "steps " + (list.length > 1 && list[list.length - 1] - list[0] === list.length - 1 ? list[0] + "–" + list[list.length - 1] : list.join(", "));
      u.tip = u.el.title;
      u.el.addEventListener("click", function (e) { e.stopPropagation(); pick(k, list[0]); });
      function flush(last) {
        var from0 = from;
        var g = h("span", null, from === last ? String(from) : from + "\u2013" + last);
        u.bd.appendChild(g); u.groups.push({ from: from, to: last, el: g });
        g.addEventListener("click", function (e) { e.stopPropagation(); pick(k, from0); });
      }
      list.slice(1).forEach(function (n) { if (n !== prev + 1) { flush(prev); from = n; } prev = n; });
      flush(prev);
    });
  }
  // Select a node (and jump to step n of it); playback stops so Play resumes from there
  function pick(key, n) {
    stopPlay();
    selKey = key;
    goTo(n - 1);
    markCurrent(false);
    paintCanvas(1);
  }
  // Sub text of a node; the card's tooltip carries the full text when the card clips it
  function setSub(key, text) { cvUi[key].sub.textContent = text; cvUi[key].el.title = (cvUi[key].tip ? cvUi[key].tip + " · " : "") + text.replace(/\n/g, " · "); }
  function fitCanvas() {
    var wrap = $("fl-wrap"), root = $("fl-canvas");
    if (!wrap || !root || !wrap.clientWidth) return;
    var sc = Math.min(1.2, wrap.clientWidth / CW);
    root.style.width = CW + "px"; root.style.height = CH + "px";
    root.style.transform = "scale(" + sc + ")";
    wrap.style.height = Math.round(CH * sc) + "px";
  }

  // Everything the canvas shows at step cur; prog (0..1) is how far that step has run while playing
  function paintCanvas(prog) {
    if (!cv || !J || !cvUi.agent) return;
    var ag = J.agent || {}, st = {}, i;
    Object.keys(cvUi).forEach(function (key) { cvUi[key].el.classList.toggle("pick", key === selKey); });
    Object.keys(cvUi).forEach(function (key) { cvUi[key].groups.forEach(function (g) { g.el.classList.toggle("cur", cur + 1 >= g.from && cur + 1 <= g.to); }); });
    Object.keys(cvUi).forEach(function (key) { cvUi[key].el.classList.remove("run", "done", "fail", "wait", "lit", "bad", "seen"); });
    SUBS.forEach(function (key) { cvUi[key].el.classList.add("seen"); });
    var tokens = 0, cost = 0, allowed = 0, denied = 0, searches = 0, called = {}, learned = "", guard = {};
    var prevKey = "", curKey = "", lit = "", litBad = false, seq = [];
    for (i = 0; i <= cur && i < J.steps.length; i++) {
      var s = J.steps[i], key = keyOf(s), running = i === cur && prog < 1;
      var state = s.status === "wait" ? "wait" : (s.status === "bad" && !/^(tool|injection|grounding)$/.test(s.kind) ? "fail" : "done");
      if (cvUi[key]) { st[key] = running && state !== "wait" ? "run" : state; cvUi[key].el.classList.add("seen"); }
      if (seq[seq.length - 1] !== key) seq.push(key);
      if (i === cur) { curKey = key; if (seq.length > 1) prevKey = seq[seq.length - 2]; }
      if (s.kind === "agent") { if (running) { tokens = Math.round(s.tokens * prog); cost = s.costUsd * prog; } else { tokens = s.tokens; cost = s.costUsd; } if (i === cur) lit = "model"; }
      if (s.kind === "tool") {
        called[s.tool] = 1;
        if (s.denied) denied++; else allowed++;
        if (s.tool === "search_loinc") searches++;
        if (i === cur) { lit = s.denied ? "policies" : s.sub; litBad = !!s.denied; }
      }
      if (s.kind === "learning") { learned = s.learned; if (i === cur) lit = "memory"; }
      if (s.kind === "injection") guard.injection = s.status === "bad" ? "bad" : "ok";
      if (s.kind === "grounding") {
        var bad = false, amb = false;
        (s.checks || []).forEach(function (c) { if (!c.pass) { if (/ambig/i.test(c.text)) amb = true; else bad = true; } });
        guard.grounding = bad ? "bad" : "ok"; guard.ambiguity = amb ? "bad" : "ok";
      }
      if (s.kind === "triage" && cvUi["out:Rejected"] && J.outcome === "rejected") { st["out:Rejected"] = running ? "run" : "fail"; cvUi["out:Rejected"].el.classList.add("seen"); }
    }
    Object.keys(st).forEach(function (key) {
      var u = cvUi[key], c = st[key];
      u.el.classList.add(c);
      u.st.className = "st " + (c === "run" ? "spin" : c === "done" ? "ok" : c === "fail" ? "no" : "hold");
      u.st.textContent = c === "done" ? "✓" : c === "fail" ? "✕" : c === "wait" ? "…" : "";
    });
    GUARDS.forEach(function (r) {
      var v = guard[r], m = cvUi.guard[r];
      m.textContent = v === "ok" ? "✓" : v === "bad" ? "✕" : "·";
      m.style.color = v === "ok" ? "#36a56b" : v === "bad" ? "#ef6a5b" : "#6b7c92";
    });
    setSub("model", ag.used ? ag.provider + " · " + ag.model + (ag.replay ? " (replay)" : "") + "\n" + tokens + " tokens · $" + cost.toFixed(5) : "agent not used");
    setSub("memory", (ag.sessionId ? "session " + ag.sessionId : "no agent session") + (learned ? "\nlearned " + learned : ""));
    setSub("knowledge", "search_loinc on IRIS vector search" + (searches ? "\n" + searches + " search" + (searches > 1 ? "es" : "") + " run" : ""));
    setSub("policies", "ReadOnly + Audit\nallowed " + allowed + " · denied " + denied);
    Array.prototype.forEach.call(cvUi.tools.sub.querySelectorAll(".chip"), function (c) { c.classList.toggle("on", !!called[c.textContent]); });
    Array.prototype.forEach.call(cvUi.skills.sub.querySelectorAll(".chip"), function (c) { c.classList.toggle("on", Object.keys(called).length > 0 && (ag.skillsUsed || []).indexOf(c.textContent) >= 0); });
    var first = -1, last = -1;
    J.steps.forEach(function (s, ix) { if (s.kind === "agent" || s.kind === "tool") { if (first < 0) first = ix; last = ix; } });
    var live = "", cs = J.steps[cur] || {};
    if (!ag.used) live = first < 0 && cur >= 0 ? "agent not used" : "";
    else if (cur >= first && first >= 0) {
      if (cur < last || (cur === last && prog < 1)) live = cs.kind === "tool" ? "calling " + cs.tool : "model call";
      else if (cur >= last) live = "Decision: " + ag.decision + (ag.confidence !== "" && Number(ag.confidence) > 0 ? " · confidence " + Number(ag.confidence).toFixed(2) : "") + "\n" + ag.tokens + " tokens · $" + Number(ag.costUsd).toFixed(5);
    }
    cvUi.agent.live.textContent = live;
    if (!cvUi.tools.sub.firstChild) cvUi.tools.sub.textContent = "no tool called";
    if (lit && cvUi[lit]) {
      var le = cvUi[lit].el;
      le.classList.add("lit"); if (litBad) le.classList.add("bad");
      if (prog < 1) { le.classList.remove("pulse"); void le.offsetWidth; le.classList.add("pulse"); }
    }
    if (denied) cvUi.policies.el.classList.add("bad");
    cvUi.agent.el.classList.toggle("glow", prog < 1 && /^(agent|tool)$/.test((J.steps[cur] || {}).kind || ""));
    var hs = J.steps.filter(function (x) { return x.kind === "workflow"; })[0];
    if (cvUi["out:human"]) {
      var reached = hs && J.steps.indexOf(hs) <= cur, txt = "";
      if (reached) {
        var wl = hs.waitLabel || "", who = /for (.+)$/.exec(wl), wait = wl.replace(/ for .*$/, "");
        txt = (hs.status === "wait" ? "waiting for human approval" : hs.status === "bad" ? "rejected by " + (who ? who[1] : "reviewer") : "approved by " + (who ? who[1] : "reviewer")) + (wait ? "\n" + wait : "");
      }
      setSub("out:human", txt);
    }
    Object.keys(cv.paths).forEach(function (p) { cv.paths[p].classList.remove("on", "lit", "bad"); });
    for (i = 1; i < seq.length; i++) { var w = cv.paths[seq[i - 1] + ">" + seq[i]]; if (w) w.classList.add("on"); }
    if (lit && cv.paths["agent>" + lit]) { var sw = cv.paths["agent>" + lit]; sw.classList.add("lit"); if (litBad) sw.classList.add("bad"); }
    var wp = prevKey && prevKey !== curKey ? cv.paths[prevKey + ">" + curKey] : null;
    if (wp && prog < 1) {
      var pt = wp.getPointAtLength(wp.getTotalLength() * Math.min(1, prog / 0.6));
      cv.dot.setAttribute("cx", pt.x); cv.dot.setAttribute("cy", pt.y); cv.label.setAttribute("x", pt.x - 22); cv.label.setAttribute("y", pt.y - 12);
      cv.dot.setAttribute("visibility", "visible"); cv.label.setAttribute("visibility", "visible");
    } else { cv.dot.setAttribute("visibility", "hidden"); cv.label.setAttribute("visibility", "hidden"); }
  }
  function frame(now) {
    raf = 0;
    if (!anim) return;
    var p = (now - anim.t0) / anim.dur;
    if (p >= 1) { anim = null; paintCanvas(1); return; }
    paintCanvas(Math.max(0, p));
    raf = requestAnimationFrame(frame);
  }
  // While playing the current step runs as an animation; a plain jump shows the settled state
  function startAnim() {
    anim = null;
    if (raf) { cancelAnimationFrame(raf); raf = 0; }
    if (playTimer && cur >= 0) { anim = { t0: performance.now(), dur: Math.max(300, STEP_MS / speed - 100) }; raf = requestAnimationFrame(frame); }
    else paintCanvas(1);
  }
  function drawMap() {
    var key = J ? J.id + ":" + J.steps.length + ":" + (map ? map.items.length : 0) : "";
    if (key !== cvKey || !cv || !cv.root.firstChild) { cvKey = key; buildCanvas(); }
    fitCanvas();
    if (anim && key === cvKey) return;
    startAnim();
  }
  window.addEventListener("resize", fitCanvas);

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
    stopPlay();
    var mine = ++openSeq;
    opening = true; speed = 2; selKey = "";
    panelOpen = true; selId = id; panelNs = jns; J = null; cur = -1;
    $("msg-panel").classList.remove("hidden"); $("mp-back").classList.remove("hidden");
    $("mp-title").textContent = "Message " + id; $("mp-links").textContent = "";
    mpTab("journey");
    renderSteps(); headStatus(); syncControls();
    var h = "msg=" + id + (jns !== (homeNs || "IRISAPP") ? "&ns=" + jns : "");
    try { history.replaceState(null, "", "#" + h); } catch (e) { location.hash = h; }
    if (!started) start();
    mapAt = Date.now();
    // start from the first step once the data is in and the canvas has been laid out
    Promise.all([loadMap(), select(id, jns, false, true)]).then(function () {
      requestAnimationFrame(function () {
        if (mine !== openSeq) return;
        opening = false;
        if (!panelOpen || selId !== id || !J) return;
        fitCanvas(); stopPlay(); cur = -1; play();
      });
    });
    showStory(id);
    if (!byId(id)) poll();
  }
  function closePanel() {
    if (!panelOpen) return;
    panelOpen = false; openSeq++; stopPlay();
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
    Array.prototype.forEach.call(document.querySelectorAll("#fj-speeds button"), function (b) {
      b.addEventListener("click", function () {
        speed = +b.dataset.speed;
        if (playTimer) { stopPlay(); play(); }
        syncControls();
      });
    });
    $("fj-replay").addEventListener("click", function () { stopPlay(); cur = -1; play(); });
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
  // Read-only view of the player for checks from the console
  window.flowState = function () { return { open: panelOpen, id: selId, cur: cur, speed: speed, playing: !!playTimer, steps: J ? J.steps.length : 0 }; };
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
  var sel = document.querySelector("#nav .nav-link.active");
  if (sel) window.flowShow(sel.dataset.tab);
  if (location.hash) fromHash();
})();