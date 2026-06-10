// ============================================================================
// Parts Finder - public catalog search.
//
// Ported from the original demo's inline <script>. The scoring search engine,
// highlighting, category chips and card rendering are unchanged; only the data
// source moved: instead of inline JSON, the catalog is fetched once from the
// Supabase `parts_with_details` view (read-only via RLS) and scored client-side.
//
// When the catalog grows beyond a couple thousand parts, switch loadCatalog()
// to the server-side `search_parts` RPC (see supabase/schema.sql) + pagination.
// ============================================================================

import { supabase, isConfigured } from "./supabase-client.js";

var PARTS = [];
var state = { query: "", category: "ALL" };

var resultsEl = document.getElementById("results");
var countEl = document.getElementById("result-count");
var chipsEl = document.getElementById("filter-chips");
var inputEl = document.getElementById("search-input");

// ---------------------------------------------------------------------------
// Search engine
// ---------------------------------------------------------------------------

function normalize(text) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function scorePart(part, rawQuery) {
  var query = rawQuery.trim().toLowerCase();
  if (!query) return 0;

  var partNumber = part.partNumber.toLowerCase();
  var name = part.name.toLowerCase();
  var haystack = normalize([
    part.partNumber, part.name, part.category, part.supplier,
    part.description, part.keywords.join(" "), part.models.join(" ")
  ].join(" "));

  // Exact part number match wins outright.
  if (partNumber === query || normalize(partNumber) === normalize(query)) return 1000;

  var score = 0;
  if (partNumber.indexOf(query) === 0) score += 400;          // part number prefix
  else if (partNumber.indexOf(query) !== -1) score += 250;    // part number fragment
  if (name === query) score += 300;                           // exact name
  if (name.indexOf(query) !== -1) score += 150;               // name contains phrase

  var tokens = normalize(query).split(" ").filter(Boolean);
  var matched = 0;
  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i];
    if (haystack.indexOf(token) === -1) continue;
    matched++;
    if (normalize(name).indexOf(token) !== -1) score += 60;
    else if (normalize(part.keywords.join(" ")).indexOf(token) !== -1) score += 45;
    else score += 25;
  }
  if (tokens.length > 1 && matched === tokens.length) score += 40; // all tokens hit

  return matched > 0 ? score : score; // score is 0 if nothing matched
}

function runSearch() {
  var results = [];
  for (var i = 0; i < PARTS.length; i++) {
    var part = PARTS[i];
    if (state.category !== "ALL" && part.category !== state.category) continue;
    if (!state.query) {
      results.push({ part: part, score: 0 });
      continue;
    }
    var score = scorePart(part, state.query);
    if (score > 0) results.push({ part: part, score: score });
  }
  results.sort(function (a, b) { return b.score - a.score; });
  return results;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function escapeHtml(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
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

function render() {
  var results = runSearch();
  var query = state.query.trim();
  var html = "";

  if (!query && state.category === "ALL") {
    countEl.innerHTML = "<strong>" + PARTS.length + "</strong> PARTS IN CATALOG";
    html += '<div class="section-label">Full Catalog</div>';
    html += '<div class="parts-grid">' + results.map(function (r, i) {
      return renderCard(r.part, false, i);
    }).join("") + "</div>";
    resultsEl.innerHTML = html;
    return;
  }

  if (results.length === 0) {
    countEl.innerHTML = "<strong>0</strong> RESULTS";
    resultsEl.innerHTML =
      '<div class="state-panel">' +
        '<div class="big">No matching parts</div>' +
        "<p>Nothing in the catalog matches <span class=\"mono\">" + escapeHtml(query || state.category) + "</span>. " +
        "Check the part number on the rating plate inside the boiler casing, or try a broader keyword like " +
        "<span class=\"mono\">valve</span>, <span class=\"mono\">sensor</span> or <span class=\"mono\">leaking</span>.</p>" +
      "</div>";
    return;
  }

  var exact = results[0].score >= 1000 ? results[0] : null;
  var rest = exact ? results.slice(1) : results;

  countEl.innerHTML = "<strong>" + results.length + "</strong> RESULT" + (results.length === 1 ? "" : "S") +
    (query ? ' FOR "' + escapeHtml(query.toUpperCase()) + '"' : "");

  if (exact) {
    html += '<div class="exact-banner">Exact part number match</div>';
    html += '<div class="parts-grid">' + renderCard(exact.part, true, 0) + "</div>";
    // Related = same category or shared boiler model, already in scored order.
    var related = rest.filter(function (r) {
      return r.part.category === exact.part.category ||
        r.part.models.some(function (m) { return exact.part.models.indexOf(m) !== -1; });
    });
    if (related.length === 0) related = rest;
    related = related.slice(0, 6);
    countEl.innerHTML = "<strong>1</strong> EXACT MATCH + " + related.length + " RELATED" +
      ' FOR "' + escapeHtml(query.toUpperCase()) + '"';
    if (related.length) {
      html += '<div class="section-label">Related Parts</div>';
      html += '<div class="parts-grid">' + related.map(function (r, i) {
        return renderCard(r.part, false, i);
      }).join("") + "</div>";
    }
  } else {
    html += '<div class="section-label">' + (query ? "Matching Parts" : escapeHtml(state.category)) + "</div>";
    html += '<div class="parts-grid">' + results.map(function (r, i) {
      return renderCard(r.part, false, i);
    }).join("") + "</div>";
  }

  resultsEl.innerHTML = html;
}

// ---------------------------------------------------------------------------
// Filters & events
// ---------------------------------------------------------------------------

function renderChips() {
  var categories = ["ALL"];
  for (var i = 0; i < PARTS.length; i++) {
    if (categories.indexOf(PARTS[i].category) === -1) categories.push(PARTS[i].category);
  }
  chipsEl.innerHTML = categories.map(function (category) {
    return '<button type="button" class="filter-chip' +
      (state.category === category ? " on" : "") +
      '" data-cat="' + escapeHtml(category) + '">' + escapeHtml(category) + "</button>";
  }).join("");
}

chipsEl.addEventListener("click", function (event) {
  var chip = event.target.closest(".filter-chip");
  if (!chip) return;
  state.category = chip.getAttribute("data-cat");
  renderChips();
  render();
});

document.getElementById("search-form").addEventListener("submit", function (event) {
  event.preventDefault();
  state.query = inputEl.value;
  render();
});

var debounceTimer = null;
inputEl.addEventListener("input", function () {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(function () {
    state.query = inputEl.value;
    render();
  }, 160);
});

document.querySelectorAll(".try-chip").forEach(function (chip) {
  chip.addEventListener("click", function () {
    inputEl.value = chip.getAttribute("data-q");
    state.query = inputEl.value;
    render();
    document.querySelector(".results-wrap").scrollIntoView({ behavior: "smooth" });
  });
});

// ---------------------------------------------------------------------------
// Data loading (Supabase)
// ---------------------------------------------------------------------------

function showState(big, detailHtml) {
  resultsEl.innerHTML =
    '<div class="state-panel"><div class="big">' + big + "</div>" +
    (detailHtml ? "<p>" + detailHtml + "</p>" : "") + "</div>";
}

// Map a `parts_with_details` row to the shape the search/render code expects.
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

async function loadCatalog() {
  if (!isConfigured) {
    countEl.innerHTML = "";
    showState("Backend not configured",
      "Set your Supabase project URL and anon key in " +
      '<span class="mono">assets/js/config.js</span> to load the live catalog.');
    return;
  }

  showState("Loading catalog", "Fetching parts from the database...");

  var response = await supabase
    .from("parts_with_details")
    .select("*")
    .order("name", { ascending: true });

  if (response.error) {
    console.error(response.error);
    countEl.innerHTML = "";
    showState("Could not load catalog",
      "The database request failed: <span class=\"mono\">" +
      escapeHtml(response.error.message) + "</span>");
    return;
  }

  PARTS = (response.data || []).map(mapRow);
  renderChips();
  render();
}

loadCatalog();
