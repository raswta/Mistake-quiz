(function () {
  "use strict";

  const cfg = window.APP_CONFIG || {};
  const app = document.getElementById("app");
  const ADMIN = "rasta1387";

  if (!cfg.SUPABASE_URL || cfg.SUPABASE_URL.includes("YOUR-")) {
    app.innerHTML = '<section class="card pad narrow"><h2>One more step</h2><p>Open <code>config.js</code> and paste your Supabase project URL and anon key.</p></section>';
    return;
  }

  const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);

  let user = localStorage.getItem("mq_user");
  let adminPw = sessionStorage.getItem("mq_apw") || "";
  if (user === ADMIN && !adminPw) user = null; // admin must re-enter the password each session
  const isAdmin = () => user === ADMIN && !!adminPw;

  const $ = (s, el) => (el || document).querySelector(s);
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const loading = (t) => { app.innerHTML = '<div class="loading">' + esc(t || "Loading...") + "</div>"; };

  function toast(msg, bad) {
    const t = document.createElement("div");
    t.className = "toast" + (bad ? " bad" : "");
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 3500);
  }
  const fail = (e, fallback) => toast((e && e.message) || fallback || "Something went wrong.", true);

  async function withBusy(btn, label, fn) {
    const old = btn.textContent;
    btn.disabled = true; btn.textContent = label;
    try { return await fn(); } finally { btn.disabled = false; btn.textContent = old; }
  }

  /* ---------- header ---------- */
  function renderBar(active) {
    const box = $("#userbox"), nav = $("#nav");
    if (!user) { box.innerHTML = ""; nav.innerHTML = ""; return; }
    box.innerHTML = '<span class="chip">@' + esc(user) + "</span>" +
      (isAdmin() ? '<span class="badge">Admin</span>' : "") +
      '<button class="link" id="logout">Log out</button>';
    $("#logout").onclick = logout;
    nav.innerHTML = '<button id="nv-f" class="' + (active === "folders" ? "on" : "") + '">My folders</button>' +
      (isAdmin() ? '<button id="nv-p" class="' + (active === "prompts" ? "on" : "") + '">Prompts</button>' : "");
    $("#nv-f").onclick = showFolders;
    if (isAdmin()) $("#nv-p").onclick = showPrompts;
  }

  function logout() {
    localStorage.removeItem("mq_user");
    sessionStorage.removeItem("mq_apw");
    user = null; adminPw = "";
    showLogin();
  }

  /* ---------- login ---------- */
  function showLogin() {
    renderBar();
    app.innerHTML =
      '<section class="card pad narrow">' +
      "<h2>Sign in with a username</h2>" +
      '<p class="muted">A new username is created automatically. Your folders and mistakes are saved under it.</p>' +
      '<div class="warn"><strong>Write your username down.</strong> There is no password and it can\'t be recovered. If you forget it, you lose access to your mistakes.</div>' +
      '<form id="lf">' +
      '<label>Username<input id="u" autocomplete="off" autocapitalize="none" spellcheck="false" maxlength="24" placeholder="e.g. sara_2026" required></label>' +
      '<label id="pwrow" hidden>Admin password<input id="pw" type="password" autocomplete="current-password"></label>' +
      '<p class="err" id="er" hidden></p>' +
      '<button class="btn primary" id="go">Continue</button>' +
      "</form></section>";

    const u = $("#u");
    u.oninput = () => { $("#pwrow").hidden = u.value.trim().toLowerCase() !== ADMIN; };
    $("#lf").onsubmit = async (e) => {
      e.preventDefault();
      const er = $("#er"); er.hidden = true;
      await withBusy($("#go"), "Checking...", async () => {
        try { await login(u.value, $("#pw").value); }
        catch (err) { er.textContent = err.message || "Could not sign in."; er.hidden = false; }
      });
    };
    u.focus();
  }

  async function login(raw, pw) {
    const name = raw.trim().toLowerCase();
    if (!/^[a-z0-9_]{3,24}$/.test(name)) throw new Error("Use 3 to 24 characters: English letters, numbers or underscore.");
    if (name === ADMIN) {
      if (!pw) throw new Error("Enter the admin password.");
      const { data, error } = await sb.rpc("admin_check", { p_username: name, p_password: pw });
      if (error) throw new Error("Could not check the admin password. Is the SQL installed?");
      if (!data) throw new Error("Wrong admin password.");
      adminPw = pw; sessionStorage.setItem("mq_apw", pw);
    } else {
      const { error } = await sb.from("app_users").upsert({ username: name }, { onConflict: "username", ignoreDuplicates: true });
      if (error) throw new Error("Could not reach the database. Check config.js and the SQL setup.");
    }
    user = name; localStorage.setItem("mq_user", name);
    showFolders();
  }

  /* ---------- folders ---------- */
  async function showFolders() {
    renderBar("folders");
    loading("Loading your folders...");
    const { data, error } = await sb.from("folders").select("id,name,created_at,mistakes(count)")
      .eq("username", user).order("created_at", { ascending: true });
    if (error) { app.innerHTML = '<div class="empty">Could not load folders.</div>'; return fail(error); }

    app.innerHTML =
      "<h2>My folders</h2>" +
      '<form id="nf" class="row"><input id="fn" maxlength="60" placeholder="New folder name, e.g. Past tense" required>' +
      '<button class="btn primary" id="fb">Add folder</button></form>' +
      (data.length
        ? '<div class="grid">' + data.map((f) => {
            const n = f.mistakes && f.mistakes[0] ? f.mistakes[0].count : 0;
            return '<button class="card folder" data-id="' + f.id + '"><h3>' + esc(f.name) + '</h3><span class="muted">' + n + (n === 1 ? " mistake" : " mistakes") + "</span></button>";
          }).join("") + "</div>"
        : '<div class="empty">No folders yet. Create one above, for example "Grammar" or "Unit 3 vocabulary".</div>');

    $("#nf").onsubmit = async (e) => {
      e.preventDefault();
      const name = $("#fn").value.trim();
      if (!name) return;
      await withBusy($("#fb"), "Adding...", async () => {
        const { error: er } = await sb.from("folders").insert({ username: user, name });
        if (er) return fail(er, "Could not add the folder.");
        showFolders();
      });
    };
    app.querySelectorAll(".folder").forEach((b) => { b.onclick = () => showFolder(b.dataset.id); });
  }

  /* ---------- one folder ---------- */
  async function showFolder(id) {
    renderBar("folders");
    loading("Opening folder...");
    const f = await sb.from("folders").select("*").eq("id", id).eq("username", user).maybeSingle();
    if (f.error || !f.data) { toast("Folder not found.", true); return showFolders(); }
    const m = await sb.from("mistakes").select("*").eq("folder_id", id).order("created_at", { ascending: false });
    if (m.error) { toast("Could not load mistakes.", true); return showFolders(); }
    const folder = f.data, items = m.data;

    app.innerHTML =
      '<div class="row between"><button class="btn small ghost" id="back">Back to folders</button>' +
      '<button class="btn small ghost" id="delf">Delete folder</button></div>' +
      '<h2 style="margin-top:1rem">' + esc(folder.name) + "</h2>" +
      '<section class="card pad"><form id="mf">' +
      '<label>What did you get wrong?<textarea id="mc" maxlength="2000" placeholder="Paste the question or sentence from your lesson" required></textarea></label>' +
      '<label>Correct answer or note (optional)<input id="mn" maxlength="500" placeholder="e.g. Correct: She has lived here since 2020."></label>' +
      '<button class="btn primary" id="ma">Save mistake</button></form></section>' +
      '<section class="card pad" style="margin-top:1.25rem"><div class="row between">' +
      "<div><h3>Quiz from this folder</h3><span class=\"muted\">AI builds new questions from your mistakes.</span></div>" +
      '<div class="row"><select id="qc" aria-label="Number of questions"><option>5</option><option selected>8</option><option>10</option><option>15</option></select>' +
      '<button class="btn primary" id="qs">Start quiz</button></div></div></section>' +
      '<h3 style="margin-top:1.5rem">' + items.length + (items.length === 1 ? " saved mistake" : " saved mistakes") + "</h3>" +
      (items.length ? items.map((x) =>
        '<article class="card mistake" data-id="' + x.id + '"><div class="txt">' + esc(x.content) + "</div>" +
        (x.note ? '<div class="note">' + esc(x.note) + "</div>" : "") +
        '<div class="tools"><button class="btn small" data-act="explain">Explain</button><button class="btn small ghost" data-act="del">Delete</button></div>' +
        '<div class="explain" hidden></div></article>').join("")
        : '<div class="empty">Nothing here yet. Save your first mistake above.</div>');

    $("#back").onclick = showFolders;
    $("#delf").onclick = async () => {
      if (!confirm('Delete the folder "' + folder.name + '" and all its mistakes?')) return;
      const { error } = await sb.from("folders").delete().eq("id", id).eq("username", user);
      if (error) return fail(error);
      showFolders();
    };
    $("#mf").onsubmit = async (e) => {
      e.preventDefault();
      const content = $("#mc").value.trim();
      if (!content) return;
      await withBusy($("#ma"), "Saving...", async () => {
        const { error } = await sb.from("mistakes").insert({ folder_id: id, username: user, content, note: $("#mn").value.trim() || null });
        if (error) return fail(error, "Could not save.");
        showFolder(id);
      });
    };
    app.querySelectorAll(".mistake").forEach((card) => {
      const mid = card.dataset.id, item = items.find((z) => z.id === mid);
      card.querySelector('[data-act="del"]').onclick = async () => {
        const { error } = await sb.from("mistakes").delete().eq("id", mid).eq("username", user);
        if (error) return fail(error);
        showFolder(id);
      };
      const exBtn = card.querySelector('[data-act="explain"]'), box = card.querySelector(".explain");
      exBtn.onclick = () => withBusy(exBtn, "Thinking...", async () => {
        try {
          const tpl = await getPrompt("explain");
          const text = item.content + (item.note ? "\nCorrect answer / note: " + item.note : "");
          box.textContent = cleanAI(await askAI(tpl.replaceAll("{{mistake}}", text)));
          box.hidden = false;
        } catch (e) { fail(e); }
      });
    });
    $("#qs").onclick = () => startQuiz(folder, items, parseInt($("#qc").value, 10), $("#qs"));
  }

  /* ---------- AI ---------- */
  async function getPrompt(key) {
    const { data, error } = await sb.from("prompts").select("content").eq("key", key).maybeSingle();
    if (error || !data) throw new Error("Prompt \"" + key + "\" is missing. Run the SQL file again.");
    return data.content;
  }

  async function askAI(prompt) {
    let lastErr;
    for (let i = 0; i < 3; i++) {
      try {
        const res = await fetch(cfg.AI_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ model: cfg.AI_MODEL || "openai", messages: [{ role: "user", content: prompt }] })
        });
        if (!res.ok) throw new Error("status " + res.status);
        const j = await res.json();
        const text = j && j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content;
        if (!text) throw new Error("empty");
        return text;
      } catch (e) {
        lastErr = e;
        await new Promise((r) => setTimeout(r, 1200 * (i + 1)));
      }
    }
    throw new Error("The free AI is busy right now. Please try again in a moment.");
  }

  const cleanAI = (t) => t.replace(/\n*---[\s\S]*?(pollinations|sponsor|support)[\s\S]*$/i, "").trim();

  function parseQuiz(text) {
    const s = text.indexOf("["), e = text.lastIndexOf("]");
    if (s < 0 || e <= s) throw new Error("bad json");
    const arr = JSON.parse(text.slice(s, e + 1));
    const qs = arr.filter((q) => q && typeof q.question === "string" && Array.isArray(q.options) && q.options.length >= 2 &&
      Number.isInteger(q.answer) && q.answer >= 0 && q.answer < q.options.length);
    if (!qs.length) throw new Error("no questions");
    return qs;
  }

  async function startQuiz(folder, items, count, btn) {
    if (!items.length) return toast("Save at least one mistake first.", true);
    await withBusy(btn, "Writing your quiz...", async () => {
      try {
        const tpl = await getPrompt("quiz");
        const list = items.slice(0, 40).map((x, i) => (i + 1) + ". " + x.content + (x.note ? " (correct answer / note: " + x.note + ")" : "")).join("\n");
        const prompt = tpl.replaceAll("{{mistakes}}", list).replaceAll("{{count}}", String(count));
        let qs = null;
        for (let t = 0; t < 2 && !qs; t++) {
          try { qs = parseQuiz(await askAI(prompt)); } catch (e) { if (t === 1) throw new Error("The AI answer could not be read. Please try again."); }
        }
        runQuiz(folder, qs);
      } catch (e) { fail(e); }
    });
  }

  /* ---------- quiz ---------- */
  function runQuiz(folder, qs) {
    let i = 0, score = 0, done = false;
    const draw = () => {
      if (i >= qs.length) return result();
      const q = qs[i]; done = false;
      app.innerHTML =
        '<div class="row between"><button class="btn small ghost" id="qx">Quit quiz</button><span class="muted">' + esc(folder.name) + "</span></div>" +
        '<div class="progress" style="margin-top:1rem"><i style="width:' + (i / qs.length * 100) + '%"></i></div>' +
        '<section class="card pad"><p class="muted">Question ' + (i + 1) + " of " + qs.length + "</p><h3>" + esc(q.question) + "</h3>" +
        q.options.map((o, k) => '<button class="opt" data-k="' + k + '">' + esc(o) + "</button>").join("") +
        '<div id="fbk"></div></section>';
      $("#qx").onclick = () => showFolder(folder.id);
      app.querySelectorAll(".opt").forEach((b) => {
        b.onclick = () => {
          if (done) return; done = true;
          const k = +b.dataset.k, ok = k === q.answer;
          if (ok) score++;
          app.querySelectorAll(".opt").forEach((x) => {
            x.disabled = true;
            if (+x.dataset.k === q.answer) x.classList.add("right");
          });
          if (!ok) b.classList.add("wrong");
          $("#fbk").innerHTML = '<div class="fb"><strong>' + (ok ? "Correct." : "Not quite.") + "</strong> " + esc(q.explanation || "") +
            '</div><div style="margin-top:1rem"><button class="btn primary" id="nx">' + (i + 1 === qs.length ? "See results" : "Next question") + "</button></div>";
          $("#nx").onclick = () => { i++; draw(); };
          $("#nx").focus();
        };
      });
    };
    const result = () => {
      const pct = Math.round(score / qs.length * 100);
      app.innerHTML = '<section class="card pad narrow" style="text-align:center"><p class="muted">Your score</p><div class="score">' + score + "/" + qs.length + "</div>" +
        "<p>" + (pct >= 80 ? "Strong work. These mistakes are getting fixed." : pct >= 50 ? "Getting there. Review the ones you missed and try again." : "Keep going. Repeating the quiz is the fastest way to fix these.") + "</p>" +
        '<div class="row" style="justify-content:center"><button class="btn primary" id="again">Back to folder</button><button class="btn" id="fl">All folders</button></div></section>';
      $("#again").onclick = () => showFolder(folder.id);
      $("#fl").onclick = showFolders;
    };
    draw();
  }

  /* ---------- admin prompts ---------- */
  async function showPrompts() {
    if (!isAdmin()) return showFolders();
    renderBar("prompts");
    loading("Loading prompts...");
    const { data, error } = await sb.from("prompts").select("*").order("key");
    if (error) { app.innerHTML = '<div class="empty">Could not load prompts.</div>'; return fail(error); }
    app.innerHTML = "<h2>Ready-made prompts</h2><p class=\"muted\">Changes apply to every user straight away. Keep the {{placeholders}} in place.</p>" +
      data.map((p) =>
        '<section class="card prompt-box" data-key="' + esc(p.key) + '"><h3>' + esc(p.title) + "</h3><p class=\"muted\">" + esc(p.description) + "</p>" +
        '<textarea>' + esc(p.content) + '</textarea><div class="row" style="margin-top:.75rem"><button class="btn primary" data-act="save">Save changes</button></div></section>').join("");
    app.querySelectorAll(".prompt-box").forEach((box) => {
      const btn = $('[data-act="save"]', box);
      btn.onclick = () => withBusy(btn, "Saving...", async () => {
        const { error: er } = await sb.rpc("admin_update_prompt", { p_username: user, p_password: adminPw, p_key: box.dataset.key, p_content: $("textarea", box).value });
        if (er) return fail(er, "Could not save the prompt.");
        toast("Saved.");
      });
    });
  }

  /* ---------- start ---------- */
  if (user) showFolders(); else showLogin();
})();
