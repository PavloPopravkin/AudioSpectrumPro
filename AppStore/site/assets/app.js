/* Audio Spectrum Pro — landing interactions
   All animation is decorative and disabled under prefers-reduced-motion. */
(function () {
  "use strict";
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- mobile nav ---------- */
  var toggle = document.querySelector(".nav-toggle");
  var links = document.querySelector(".nav-links");
  if (toggle && links) {
    toggle.addEventListener("click", function () { links.classList.toggle("open"); });
    links.addEventListener("click", function (e) {
      if (e.target.tagName === "A") links.classList.remove("open");
    });
  }

  /* ---------- scroll reveal ---------- */
  var reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && !reduce) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.12 });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("in"); });
  }

  /* ---------- language tabs (legal/support pages) ---------- */
  var langbar = document.querySelector(".langbar");
  if (langbar) {
    var blocks = document.querySelectorAll(".lang-block");
    langbar.addEventListener("click", function (e) {
      var b = e.target.closest("button");
      if (!b) return;
      var lang = b.getAttribute("data-lang");
      langbar.querySelectorAll("button").forEach(function (x) { x.classList.toggle("active", x === b); });
      blocks.forEach(function (bl) { bl.classList.toggle("active", bl.getAttribute("data-lang") === lang); });
      try { history.replaceState(null, "", "#" + lang); } catch (_) {}
    });
    // honor #lang on load
    var hash = (location.hash || "").replace("#", "");
    if (hash) {
      var btn = langbar.querySelector('button[data-lang="' + hash + '"]');
      if (btn) btn.click();
    }
  }

  /* ---------- hero spectrum analyzer (canvas) ---------- */
  var canvas = document.getElementById("heroSpectrum");
  if (canvas && canvas.getContext) {
    var ctx = canvas.getContext("2d");
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var W = 0, H = 0, bars = 0;
    var BAR_W = 7, GAP = 4;
    var vals = [], targets = [], peaks = [];

    function resize() {
      W = canvas.clientWidth; H = canvas.clientHeight;
      canvas.width = W * dpr; canvas.height = H * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      bars = Math.floor(W / (BAR_W + GAP));
      vals = new Array(bars).fill(0);
      targets = new Array(bars).fill(0);
      peaks = new Array(bars).fill(0);
    }
    resize();
    window.addEventListener("resize", resize);

    // a pink-noise-ish spectral envelope: stronger lows, gentle roll-off,
    // with a couple of roving resonant peaks for life.
    var t = 0;
    function envelope(i, n) {
      var x = i / n;                       // 0..1 across frequency
      var base = Math.pow(1 - x, 1.5) * 0.7 + 0.12;   // tilt down with freq
      var res1 = 0.42 * Math.exp(-Math.pow((x - (0.30 + 0.05 * Math.sin(t * 0.7))) / 0.05, 2));
      var res2 = 0.30 * Math.exp(-Math.pow((x - (0.62 + 0.06 * Math.sin(t * 0.5 + 1))) / 0.04, 2));
      return Math.min(1, base + res1 + res2);
    }

    function colorFor(h) {
      // green (low energy) -> cyan -> amber -> red (hot)
      if (h < 0.5) return "rgba(46,232,158,";
      if (h < 0.72) return "rgba(53,197,240,";
      if (h < 0.88) return "rgba(245,166,35,";
      return "rgba(255,92,92,";
    }

    function frame() {
      t += 0.016;
      ctx.clearRect(0, 0, W, H);

      // baseline grid line
      ctx.strokeStyle = "rgba(255,255,255,0.06)";
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(0, H - 0.5); ctx.lineTo(W, H - 0.5); ctx.stroke();

      var off = (W - bars * (BAR_W + GAP)) / 2;
      for (var i = 0; i < bars; i++) {
        // new target with flicker
        targets[i] = envelope(i, bars) * (0.78 + Math.random() * 0.22);
        // smooth toward target
        vals[i] += (targets[i] - vals[i]) * 0.25;
        var h = vals[i];
        if (h > peaks[i]) peaks[i] = h; else peaks[i] -= 0.006;
        if (peaks[i] < 0) peaks[i] = 0;

        var bh = h * (H - 6);
        var x = off + i * (BAR_W + GAP);
        var y = H - bh;
        var c = colorFor(h);
        var grad = ctx.createLinearGradient(0, y, 0, H);
        grad.addColorStop(0, c + "0.95)");
        grad.addColorStop(1, c + "0.10)");
        ctx.fillStyle = grad;
        roundRectTop(ctx, x, y, BAR_W, bh, 2);
        ctx.fill();

        // peak cap
        var py = H - peaks[i] * (H - 6);
        ctx.fillStyle = c + "0.85)";
        ctx.fillRect(x, py - 2, BAR_W, 2);
      }
      if (!reduce) raf = requestAnimationFrame(frame);
    }
    function roundRectTop(c, x, y, w, h, r) {
      r = Math.min(r, w / 2, h);
      c.beginPath();
      c.moveTo(x, y + h);
      c.lineTo(x, y + r);
      c.arcTo(x, y, x + r, y, r);
      c.lineTo(x + w - r, y);
      c.arcTo(x + w, y, x + w, y + r, r);
      c.lineTo(x + w, y + h);
      c.closePath();
    }
    var raf;
    if (reduce) { // single static frame
      for (var k = 0; k < 60; k++) { for (var j = 0; j < bars; j++) { vals[j] = envelope(j, bars); } t += 0.016; }
      frame();
    } else {
      raf = requestAnimationFrame(frame);
      // pause when offscreen to save battery
      document.addEventListener("visibilitychange", function () {
        if (document.hidden) { cancelAnimationFrame(raf); }
        else { raf = requestAnimationFrame(frame); }
      });
    }
  }

  /* ---------- loudness meter (built; no screenshot exists) ---------- */
  var meter = document.getElementById("loudMeter");
  if (meter && !reduce) {
    var rms = meter.querySelector(".bar-fill.rms");
    var peak = meter.querySelector(".bar-fill.peak");
    var hist = meter.querySelector(".history");
    var rmsLbl = meter.querySelector("[data-rms]");
    var peakLbl = meter.querySelector("[data-peak]");
    var NB = 28, bars2 = [];
    for (var b = 0; b < NB; b++) {
      var el = document.createElement("i"); hist.appendChild(el); bars2.push(el);
    }
    var lvl = 0.4, pk = 0.55, tt = 0;
    setInterval(function () {
      tt += 0.2;
      var target = 0.35 + 0.28 * (0.5 + 0.5 * Math.sin(tt)) + Math.random() * 0.12;
      lvl += (target - lvl) * 0.3;
      var instPeak = Math.min(1, lvl + 0.15 + Math.random() * 0.18);
      if (instPeak > pk) pk = instPeak; else pk -= 0.02;
      if (rms) rms.style.width = (lvl * 100).toFixed(0) + "%";
      if (peak) peak.style.width = (pk * 100).toFixed(0) + "%";
      if (rmsLbl) rmsLbl.textContent = (-(1 - lvl) * 48).toFixed(1) + " dB";
      if (peakLbl) peakLbl.textContent = (-(1 - pk) * 36).toFixed(1) + " dB";
      // shift history
      for (var i = 0; i < bars2.length - 1; i++) { bars2[i].style.height = bars2[i + 1].style.height || "20%"; }
      bars2[bars2.length - 1].style.height = (lvl * 100).toFixed(0) + "%";
    }, 110);
  }

  /* ---------- footer year ---------- */
  var y = document.getElementById("yr");
  if (y) y.textContent = new Date().getFullYear();
})();
