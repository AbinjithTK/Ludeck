// The public orchard page: /t/?h=<handle>.
//
// Reads the published orchard straight from Supabase's REST API with the
// publishable key (world-readable rows only, migration 0001) and renders it.
// Every value from the database goes into the page through textContent or a
// validated URL, never innerHTML, so a crafted title cannot inject markup.
(function () {
  "use strict";
  const cfg = window.LUDECK || {};
  const $ = (id) => document.getElementById(id);
  const HANDLE_RE = /^[a-z0-9_]{3,30}$/;   // the server's own rule

  const handle = new URLSearchParams(location.search).get("h") || "";
  const valid = HANDLE_RE.test(handle);

  // Install attribution: Play hands this referrer to the app on first open,
  // and Play Console's acquisition report groups installs by it. The campaign
  // is the sharer's handle, so each orchard's pull is measurable.
  const referrer = "utm_source=ludeck_share&utm_medium=orchard_link&utm_campaign=" +
    encodeURIComponent(valid ? handle : "unknown");
  const play = "https://play.google.com/store/apps/details?id=" +
    encodeURIComponent(cfg.playPackage) + "&referrer=" + encodeURIComponent(referrer);
  $("get").href = play;

  // "Open in Ludeck": an Android intent with the Play listing as its fallback,
  // so one tap opens the app if it is installed and the store if it is not.
  const android = /Android/i.test(navigator.userAgent);
  if (valid && android) {
    $("open").href = "intent://t/" + handle + "#Intent;scheme=" + cfg.playPackage +
      ";package=" + cfg.playPackage + ";S.browser_fallback_url=" +
      encodeURIComponent(play) + ";end";
  } else {
    $("open").remove();   // desktop, iOS or a bad link: the store button is the path
  }

  const STATUS = {
    finished: { mark: "✓", label: "Finished" },
    playing: { mark: "▶", label: "Playing" },
  };

  function fail(msg) {
    $("sub").textContent = msg;
  }

  async function rest(path) {
    const r = await fetch(cfg.supabaseUrl + "/rest/v1/" + path, {
      headers: { apikey: cfg.publishableKey, Accept: "application/json" },
    });
    if (!r.ok) throw new Error("HTTP " + r.status);
    return r.json();
  }

  function safeImage(url) {
    try {
      const u = new URL(url);
      return u.protocol === "https:" ? u.href : null;
    } catch (_) {
      return null;
    }
  }

  function card(g) {
    const fig = document.createElement("figure");
    fig.className = "fruit" + (g.status === "finished" ? " done" : "");
    const src = g.cover_url ? safeImage(g.cover_url) : null;
    if (src) {
      const img = document.createElement("img");
      img.src = src;
      img.alt = "";
      img.loading = "lazy";
      img.referrerPolicy = "no-referrer";
      fig.appendChild(img);
    } else {
      const ph = document.createElement("div");
      ph.className = "letter";
      ph.textContent = (g.title || "?").trim().charAt(0).toUpperCase();
      fig.appendChild(ph);
    }
    const st = STATUS[g.status];
    if (st) {
      const b = document.createElement("span");
      b.className = "badge";
      b.textContent = st.mark;
      b.title = st.label;
      fig.appendChild(b);
    }
    const cap = document.createElement("figcaption");
    cap.textContent = g.title || "";
    if (g.rating) {
      const r = document.createElement("span");
      r.className = "stars";
      r.textContent = " " + "★".repeat(Math.max(0, Math.min(5, g.rating)));
      r.setAttribute("aria-label", g.rating + " out of 5");
      cap.appendChild(r);
    }
    fig.appendChild(cap);
    fig.setAttribute("aria-label", (g.title || "") + (st ? ", " + st.label : ""));
    return fig;
  }

  async function load() {
    if (!valid) return fail("This link doesn't point to an orchard.");
    if (!cfg.supabaseUrl || !cfg.publishableKey) {
      return fail("This orchard can't be shown yet. Open it in the Ludeck app.");
    }
    try {
      const prof = await rest("profiles?select=id,display_name&handle=eq." + handle);
      if (!prof.length) return fail("This orchard isn't public any more.");
      const owner = prof[0];
      const [trees, games] = await Promise.all([
        rest("published_trees?select=level&owner_id=eq." + owner.id),
        rest("published_games?select=title,cover_url,status,rating,branch_name&owner_id=eq." +
          owner.id + "&order=branch_name.asc,title.asc"),
      ]);
      if (!trees.length) return fail("This orchard isn't public any more.");

      const name = owner.display_name || "Someone";
      document.title = name + "'s orchard on Ludeck";
      $("title").textContent = name + "'s orchard";
      const finished = games.filter((g) => g.status === "finished").length;
      $("sub").textContent = games.length + (games.length === 1 ? " game" : " games") +
        " · " + finished + " finished · level " + trees[0].level;

      const byTree = new Map();
      for (const g of games) {
        const k = g.branch_name || "On the ground";
        if (!byTree.has(k)) byTree.set(k, []);
        byTree.get(k).push(g);
      }
      const root = $("trees");
      for (const [treeName, list] of byTree) {
        const sec = document.createElement("section");
        sec.className = "tree";
        const h = document.createElement("h2");
        h.textContent = treeName;
        const n = document.createElement("span");
        n.className = "count";
        n.textContent = " " + list.length;
        h.appendChild(n);
        const row = document.createElement("div");
        row.className = "row";
        list.forEach((g) => row.appendChild(card(g)));
        sec.append(h, row);
        root.appendChild(sec);
      }
    } catch (e) {
      fail("Couldn't load this orchard. Check your connection and try again.");
    }
  }

  load();
})();
