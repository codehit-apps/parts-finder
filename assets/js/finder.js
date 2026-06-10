// ============================================================================
// Parts Finder - public catalog search (search-first + server-side paging).
//
// The catalog is NOT downloaded on load. Nothing is fetched until the visitor
// searches or picks a category; each query asks Supabase for ONE page of results
// via the search_parts RPC + .range() + { count: 'exact' }. This keeps initial
// egress at zero and scales to large catalogs without truncation or browser jank.
//
// Search ranking (exact part number first, then name) happens in Postgres;
// highlighting is still applied client-side on the returned page.
// ============================================================================

import { supabase, isConfigured } from "./supabase-client.js";

var PAGE_SIZE = 12;

var state = { query: "", category: "ALL", page: 0 };
var lastCount = 0;

var resultsEl = document.getElementById("results");
var countEl = document.getElementById("result-count");
var chipsEl = document.getElementById("filter-chips");
var inputEl = document.getElementById("search-input");
var pagerEl = document.getElementById("pagination");

// ---------------------------------------------------------------------------
// Rendering helpers (unchanged from the client-side version)
// ---------------------------------------------------------------------------

function escapeHtml(text) {
  return String(text == null ? "" : text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function highlight(text, query) {
  var safe = escapeHtml(text);
  var trimmed = query.trim();
  if (!trimmed) return safe;
  var tokens = trimmed.split(/\s+/).filter(function (t) { return t.length > 1; });
  if (trimmed.length > 1) tokens.unshift(trimmed);
  for (var i = 0; i < tokens.length; i++) {
    var escaped = tokens[i].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    var pattern = new RegExp("(" + escaped + ")(?![^<]*>)", "i");
    if (pattern.test(safe)) { safe = safe.replace(pattern, "<mark>$1</mark>"); break; }
  }
  return safe;
}

function formatPrice(value) {
  return Number(value).toFixed(2);
}

function stockLabel(stock) {
  if (stock === "in") return '<span class="stock-line in">In stock</span>';
  if (stock === "low") return '<span class="stock-line low">Low stock</span>';
  return '<span class="stock-line out">On order</span>';
}

// Map a parts_with_details / search_parts row to the card shape.
function mapRow(row) {
  return {
    partNumber: row.part_number,
    name: row.name,
    category: row.category,
    supplier: row.supplier || "",
    price: row.price,
    stock: row.stock,
    replacement: row.replacement,
    description: row.description || "",
    supersedes: row.supersedes || "",
    keywords: row.keywords || [],
    models: row.models || []
  };
}

function renderCard(part, isExact, index) {
  var badges = part.replacement
    ? '<span class="badge warranty">Free under warranty</span>'
    : '<span class="badge oem">Service item</span>';

  var models = part.models.map(function (model) {
    return '<span class="model-tag">' + escapeHtml(model) + "</span>";
  }).join("");

  var supersedes = part.supersedes
    ? '<div class="part-supersedes">Supersedes <b>' + escapeHtml(part.supersedes) + "</b></div>"
    : "";

  return (
    '<article class="part-card' + (isExact ? " exact" : "") + '" style="animation-delay:' + (index * 45) + 'ms">' +
      '<div class="part-head">' +
        '<span class="part-number">' + highlight(part.partNumber, state.query) + "</span>" +
        '<span class="part-cat">' + escapeHtml(part.category) + "</span>" +
      "</div>" +
      '<div class="part-body">' +
        '<h3 class="part-name">' + highlight(part.name, state.query) + "</h3>" +
        '<p class="part-desc">' + escapeHtml(part.description || "") + "</p>" +
        '<div class="part-meta">' +
          "Supplier: <b>" + escapeHtml(part.supplier || "Unknown") + "</b><br>" +
          stockLabel(part.stock) +
        "</div>" +
        supersedes +
        '<div class="part-models">' + models + "</div>" +
      "</div>" +
      '<div class="part-foot">' +
        '<div class="price"><span class="cur">USD</span>' + formatPrice(part.price) + "</div>" +
        badges +
      "</div>" +
    "</article>"
  );
}

function showState(big, detailHtml) {
  resultsEl.innerHTML =
    '<div class="state-panel"><div class="big">' + big + "</div>" +
    (detailHtml ? "<p>" + detailHtml + "</p>" : "") + "</div>";
}

// ---------------------------------------------------------------------------
// Pagination control
// ---------------------------------------------------------------------------

function renderPager() {
  var totalPages = Math.max(1, Math.ceil(lastCount / PAGE_SIZE));
  if (lastCount === 0) { pagerEl.innerHTML = ""; return; }
  var current = state.page + 1;
  pagerEl.innerHTML =
    '<button type="button" class="pager-btn" id="pager-prev"' + (state.page <= 0 ? " disabled" : "") + ">Prev</button>" +
    '<span class="pager-info">Page ' + current + " of " + totalPages + "</span>" +
    '<button type="button" class="pager-btn" id="pager-next"' + (current >= totalPages ? " disabled" : "") + ">Next</button>";

  var prev = document.getElementById("pager-prev");
  var next = document.getElementById("pager-next");
  if (prev) prev.addEventListener("click", function () { goToPage(state.page - 1); });
  if (next) next.addEventListener("click", function () { goToPage(state.page + 1); });
}

function goToPage(page) {
  state.page = page;
  runSearch();
  document.querySelector(".results-wrap").scrollIntoView({ behavior: "smooth" });
}

// ---------------------------------------------------------------------------
// Search (server-side, one page per request)
// ---------------------------------------------------------------------------

function isBrowsingNothing() {
  return state.query.trim() === "" && state.category === "ALL";
}

async function runSearch() {
  if (isBrowsingNothing()) {
    lastCount = 0;
    countEl.innerHTML = "";
    pagerEl.innerHTML = "";
    showState("Search the catalog",
      "Enter a part number, name, or symptom above to begin " +
      '(try <span class="mono">0020132683</span>, <span class="mono">pump</span>, ' +
      'or <span class="mono">no hot water</span>), or pick a category.');
    return;
  }

  var query = state.query.trim();
  var from = state.page * PAGE_SIZE;
  var to = from + PAGE_SIZE - 1;

  var response = await supabase
    .rpc("search_parts",
      { query: query, filter_category: state.category === "ALL" ? null : state.category },
      { count: "exact" })
    .range(from, to);

  if (response.error) {
    console.error(response.error);
    countEl.innerHTML = "";
    pagerEl.innerHTML = "";
    showState("Search failed",
      'The database request failed: <span class="mono">' +
      escapeHtml(response.error.message) + "</span>");
    return;
  }

  lastCount = response.count || 0;
  var rows = (response.data || []).map(mapRow);

  if (lastCount === 0) {
    countEl.innerHTML = "<strong>0</strong> RESULTS";
    pagerEl.innerHTML = "";
    showState("No matching parts",
      "Nothing matches <span class=\"mono\">" + escapeHtml(query || state.category) + "</span>. " +
      "Check the part number on the rating plate inside the boiler casing, or try a broader " +
      "keyword like <span class=\"mono\">valve</span>, <span class=\"mono\">sensor</span> or " +
      "<span class=\"mono\">leaking</span>.");
    return;
  }

  // Exact part-number match: only meaningful on the first page, top-ranked row.
  var exactFirst = state.page === 0 && query &&
    rows.length > 0 && rows[0].partNumber.toLowerCase() === query.toLowerCase();

  var label = query
    ? ' FOR "' + escapeHtml(query.toUpperCase()) + '"'
    : " IN " + escapeHtml(state.category.toUpperCase());
  countEl.innerHTML = "<strong>" + lastCount + "</strong> RESULT" + (lastCount === 1 ? "" : "S") + label;

  var html = "";
  if (exactFirst) html += '<div class="exact-banner">Exact part number match</div>';
  html += '<div class="parts-grid">' + rows.map(function (part, i) {
    return renderCard(part, exactFirst && i === 0, i);
  }).join("") + "</div>";
  resultsEl.innerHTML = html;

  renderPager();
}

// ---------------------------------------------------------------------------
// Category chips (built from the tiny part_categories view)
// ---------------------------------------------------------------------------

function renderChips(categories) {
  var chips = [{ category: "ALL", n: null }].concat(categories);
  chipsEl.innerHTML = chips.map(function (item) {
    var labelText = item.category === "ALL" ? "ALL" : escapeHtml(item.category);
    return '<button type="button" class="filter-chip' +
      (state.category === item.category ? " on" : "") +
      '" data-cat="' + escapeHtml(item.category) + '">' + labelText + "</button>";
  }).join("");
}

chipsEl.addEventListener("click", function (event) {
  var chip = event.target.closest(".filter-chip");
  if (!chip) return;
  state.category = chip.getAttribute("data-cat");
  state.page = 0;
  // Reflect active state without another DB call.
  Array.prototype.forEach.call(chipsEl.querySelectorAll(".filter-chip"), function (c) {
    c.classList.toggle("on", c.getAttribute("data-cat") === state.category);
  });
  runSearch();
});

// ---------------------------------------------------------------------------
// Search input events
// ---------------------------------------------------------------------------

document.getElementById("search-form").addEventListener("submit", function (event) {
  event.preventDefault();
  state.query = inputEl.value;
  state.page = 0;
  runSearch();
});

var debounceTimer = null;
inputEl.addEventListener("input", function () {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(function () {
    state.query = inputEl.value;
    state.page = 0;
    runSearch();
  }, 160);
});

document.querySelectorAll(".try-chip").forEach(function (chip) {
  chip.addEventListener("click", function () {
    inputEl.value = chip.getAttribute("data-q");
    state.query = inputEl.value;
    state.page = 0;
    runSearch();
    document.querySelector(".results-wrap").scrollIntoView({ behavior: "smooth" });
  });
});

// ---------------------------------------------------------------------------
// Boot: load category chips only, then show the search prompt.
// ---------------------------------------------------------------------------

async function boot() {
  if (!isConfigured) {
    countEl.innerHTML = "";
    showState("Backend not configured",
      "Set your Supabase project URL and anon key in " +
      '<span class="mono">assets/js/config.js</span> to enable search.');
    return;
  }

  var response = await supabase
    .from("part_categories")
    .select("category, n")
    .order("category", { ascending: true });

  if (response.error) {
    console.error(response.error);
  } else {
    renderChips(response.data || []);
  }

  runSearch(); // shows the search-first prompt (no catalog fetch)
}

boot();
