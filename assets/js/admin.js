// ============================================================================
// Parts Finder - admin panel (server-side paginated CRUD).
//
//   - login / logout via Supabase Auth (email + password)
//   - parts list paginated server-side via the search_parts RPC (one page per
//     request, .range() + { count: 'exact' }); text + category filters re-query
//   - create / edit parts (supplier, compatible models, keywords)
//   - delete parts (with confirmation)
//   - manage the supplier and boiler_model lookup tables
//
// Lookups (suppliers, boiler_models, categories) are small and loaded once for
// the form dropdowns + management panels. The parts table reads from the
// parts_with_details view (via the RPC), which already carries the supplier name
// and model-name array, so no client-side joins are needed for display.
//
// Writes require an authenticated session (enforced by RLS, not just the UI).
// ============================================================================

import { supabase, isConfigured } from "./supabase-client.js";

var el = function (id) { return document.getElementById(id); };

var PAGE_SIZE = 20;

// ---------------------------------------------------------------------------
// Element references
// ---------------------------------------------------------------------------
var loginView = el("login-view");
var appView = el("app-view");
var headerActions = el("header-actions");
var userEmailEl = el("user-email");

var loginForm = el("login-form");
var loginMsg = el("login-msg");
var loginBtn = el("login-btn");

var partsTableWrap = el("parts-table-wrap");
var partsCountEl = el("parts-count");
var partsSearchEl = el("parts-search");
var partsCategoryFilter = el("parts-category-filter");
var partsPagerEl = el("parts-pager");

var partModal = el("part-modal");
var partForm = el("part-form");
var partFormMsg = el("part-form-msg");
var partModalTitle = el("part-modal-title");

var confirmModal = el("confirm-modal");

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
var data = {
  suppliers: [],    // { id, name }
  models: [],       // { id, name, supplier_id }
  categories: []    // [ "Hydraulics", ... ]
};

var pageState = { query: "", category: "ALL", page: 0 };
var partsCount = 0;
var currentRows = [];   // parts_with_details rows for the current page

function escapeHtml(text) {
  return String(text == null ? "" : text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function supplierName(id) {
  var match = data.suppliers.find(function (s) { return s.id === id; });
  return match ? match.name : "";
}

// ===========================================================================
// Auth
// ===========================================================================

function showLogin() {
  loginView.hidden = false;
  appView.hidden = true;
  headerActions.hidden = true;
}

function showApp(session) {
  loginView.hidden = true;
  appView.hidden = false;
  headerActions.hidden = false;
  userEmailEl.textContent = session.user.email;
}

loginForm.addEventListener("submit", async function (event) {
  event.preventDefault();
  loginMsg.textContent = "";
  loginBtn.disabled = true;
  loginBtn.textContent = "Signing in...";

  var result = await supabase.auth.signInWithPassword({
    email: el("login-email").value.trim(),
    password: el("login-password").value
  });

  loginBtn.disabled = false;
  loginBtn.textContent = "Sign in";

  if (result.error) {
    loginMsg.textContent = result.error.message;
  }
  // onAuthStateChange handles the view swap + data load.
});

el("sign-out-btn").addEventListener("click", async function () {
  await supabase.auth.signOut();
});

// ===========================================================================
// Data loading
// ===========================================================================

async function loadLookups() {
  var responses = await Promise.all([
    supabase.from("suppliers").select("*").order("name", { ascending: true }),
    supabase.from("boiler_models").select("*").order("name", { ascending: true }),
    supabase.from("part_categories").select("category, n").order("category", { ascending: true })
  ]);

  var firstError = responses.find(function (r) { return r.error; });
  if (firstError) {
    console.error(firstError.error);
    partsTableWrap.innerHTML =
      '<div class="state-panel"><div class="big">Could not load data</div><p>' +
      escapeHtml(firstError.error.message) + "</p></div>";
    return;
  }

  data.suppliers = responses[0].data || [];
  data.models = responses[1].data || [];
  data.categories = (responses[2].data || []).map(function (row) { return row.category; });

  renderCategoryFilter();
  renderSupplierControls();
  renderModelControls();
  renderLookups();
}

async function loadPartsPage() {
  partsTableWrap.innerHTML = '<div class="spinner-inline">Loading...</div>';

  var from = pageState.page * PAGE_SIZE;
  var to = from + PAGE_SIZE - 1;

  var response = await supabase
    .rpc("search_parts",
      {
        query: pageState.query.trim(),
        filter_category: pageState.category === "ALL" ? null : pageState.category
      },
      { count: "exact" })
    .range(from, to);

  if (response.error) {
    console.error(response.error);
    partsPagerEl.innerHTML = "";
    partsTableWrap.innerHTML =
      '<div class="state-panel"><div class="big">Could not load parts</div><p>' +
      escapeHtml(response.error.message) + "</p></div>";
    return;
  }

  partsCount = response.count || 0;
  currentRows = response.data || [];

  // If a delete emptied the current page, step back one and reload.
  if (currentRows.length === 0 && partsCount > 0 && pageState.page > 0) {
    pageState.page = Math.max(0, Math.ceil(partsCount / PAGE_SIZE) - 1);
    return loadPartsPage();
  }

  renderPartsTable();
}

// Reload lookups (counts/category list may have changed) plus the current page.
async function refresh() {
  await loadLookups();
  await loadPartsPage();
}

// ===========================================================================
// Parts table + pager
// ===========================================================================

function renderCategoryFilter() {
  partsCategoryFilter.innerHTML =
    '<option value="ALL">All categories</option>' +
    data.categories.map(function (c) {
      return '<option value="' + escapeHtml(c) + '">' + escapeHtml(c) + "</option>";
    }).join("");
  partsCategoryFilter.value = pageState.category;

  // Datalist suggestions for the part form's category input.
  el("category-options").innerHTML = data.categories.map(function (c) {
    return '<option value="' + escapeHtml(c) + '">';
  }).join("");
}

function isFiltered() {
  return pageState.query.trim() !== "" || pageState.category !== "ALL";
}

function renderPartsTable() {
  partsCountEl.innerHTML = "<strong>" + partsCount + "</strong> PART" +
    (partsCount === 1 ? "" : "S") + (isFiltered() ? " (filtered)" : "");

  if (partsCount === 0) {
    partsPagerEl.innerHTML = "";
    partsTableWrap.innerHTML =
      '<div class="state-panel"><div class="big">No parts</div><p>' +
      (isFiltered()
        ? "No parts match the current filter."
        : "The catalog is empty. Add your first part, or run seed.sql.") + "</p></div>";
    return;
  }

  var body = currentRows.map(function (row) {
    var models = row.models || [];
    var modelPills = models.slice(0, 3).map(function (name) {
      return '<span class="tag-pill">' + escapeHtml(name) + "</span>";
    }).join("");
    if (models.length > 3) modelPills += '<span class="tag-pill">+' + (models.length - 3) + "</span>";

    var warranty = row.replacement
      ? '<span class="row-warranty">Warranty</span>'
      : '<span class="row-sale">Sale</span>';

    return (
      "<tr>" +
        '<td class="cell-pn" data-label="Part No.">' + escapeHtml(row.part_number) + "</td>" +
        '<td data-label="Name / Models"><b>' + escapeHtml(row.name) + "</b><br>" + modelPills + "</td>" +
        '<td data-label="Category">' + escapeHtml(row.category) + "</td>" +
        '<td data-label="Supplier">' + escapeHtml(row.supplier || "") + "</td>" +
        '<td data-label="Price">' + (row.price != null ? "USD " + Number(row.price).toFixed(2) : "&mdash;") + "</td>" +
        '<td data-label="Stock">' + escapeHtml(row.stock) + "<br>" + warranty + "</td>" +
        '<td class="cell-actions">' +
          '<button type="button" class="btn btn-small" data-edit="' + row.id + '">Edit</button>' +
          '<button type="button" class="btn btn-small btn-danger" data-delete="' + row.id + '">Delete</button>' +
        "</td>" +
      "</tr>"
    );
  }).join("");

  partsTableWrap.innerHTML =
    '<table class="data-table"><thead><tr>' +
      "<th>Part No.</th><th>Name / Models</th><th>Category</th><th>Supplier</th>" +
      "<th>Price</th><th>Stock</th><th></th>" +
    "</tr></thead><tbody>" + body + "</tbody></table>";

  renderPartsPager();
}

function renderPartsPager() {
  var totalPages = Math.max(1, Math.ceil(partsCount / PAGE_SIZE));
  if (partsCount === 0) { partsPagerEl.innerHTML = ""; return; }
  var current = pageState.page + 1;
  partsPagerEl.innerHTML =
    '<button type="button" class="pager-btn" id="parts-prev"' + (pageState.page <= 0 ? " disabled" : "") + ">Prev</button>" +
    '<span class="pager-info">Page ' + current + " of " + totalPages + "</span>" +
    '<button type="button" class="pager-btn" id="parts-next"' + (current >= totalPages ? " disabled" : "") + ">Next</button>";

  var prev = el("parts-prev");
  var next = el("parts-next");
  if (prev) prev.addEventListener("click", function () { gotoPartsPage(pageState.page - 1); });
  if (next) next.addEventListener("click", function () { gotoPartsPage(pageState.page + 1); });
}

function gotoPartsPage(page) {
  pageState.page = page;
  loadPartsPage();
}

var partsSearchTimer = null;
partsSearchEl.addEventListener("input", function () {
  clearTimeout(partsSearchTimer);
  partsSearchTimer = setTimeout(function () {
    pageState.query = partsSearchEl.value;
    pageState.page = 0;
    loadPartsPage();
  }, 200);
});

partsCategoryFilter.addEventListener("change", function () {
  pageState.category = partsCategoryFilter.value;
  pageState.page = 0;
  loadPartsPage();
});

partsTableWrap.addEventListener("click", function (event) {
  var editBtn = event.target.closest("[data-edit]");
  if (editBtn) { openPartForm(Number(editBtn.getAttribute("data-edit"))); return; }
  var deleteBtn = event.target.closest("[data-delete]");
  if (deleteBtn) { confirmDeletePart(Number(deleteBtn.getAttribute("data-delete"))); }
});

el("add-part-btn").addEventListener("click", function () { openPartForm(null); });

// ===========================================================================
// Part form (create / edit)
// ===========================================================================

function renderSupplierControls() {
  var options = '<option value="">No supplier</option>' +
    data.suppliers.map(function (s) {
      return '<option value="' + s.id + '">' + escapeHtml(s.name) + "</option>";
    }).join("");
  el("part-supplier").innerHTML = options;
  el("model-add-supplier").innerHTML = options;
}

function renderModelControls() {
  // Group model <option>s by supplier for the multi-select.
  var grouped = {};
  data.models.forEach(function (m) {
    var key = m.supplier_id == null ? "Other" : supplierName(m.supplier_id) || "Other";
    (grouped[key] = grouped[key] || []).push(m);
  });
  var html = Object.keys(grouped).sort().map(function (group) {
    var opts = grouped[group].map(function (m) {
      return '<option value="' + m.id + '">' + escapeHtml(m.name) + "</option>";
    }).join("");
    return '<optgroup label="' + escapeHtml(group) + '">' + opts + "</optgroup>";
  }).join("");
  el("part-models").innerHTML = html;
}

function clearModelSelection() {
  Array.prototype.forEach.call(el("part-models").options, function (o) { o.selected = false; });
}

async function openPartForm(partId) {
  partForm.reset();
  partFormMsg.textContent = "";
  partFormMsg.className = "form-msg";
  el("part-id").value = "";
  clearModelSelection();

  if (partId == null) {
    partModalTitle.textContent = "New Part";
    el("part-stock").value = "in";
    openModal(partModal);
    el("part-number").focus();
    return;
  }

  // Edit: fetch the base part row (has supplier_id and all fields) plus its model ids.
  partModalTitle.textContent = "Edit Part";
  var partResponse = await supabase.from("parts").select("*").eq("id", partId).single();
  if (partResponse.error || !partResponse.data) {
    console.error(partResponse.error);
    alert("Could not load that part: " + (partResponse.error ? partResponse.error.message : "not found"));
    return;
  }
  var part = partResponse.data;

  el("part-id").value = part.id;
  el("part-number").value = part.part_number || "";
  el("part-name").value = part.name || "";
  el("part-category").value = part.category || "";
  el("part-supplier").value = part.supplier_id == null ? "" : String(part.supplier_id);
  el("part-price").value = part.price == null ? "" : part.price;
  el("part-stock").value = part.stock || "in";
  el("part-supersedes").value = part.supersedes || "";
  el("part-replacement").checked = !!part.replacement;
  el("part-description").value = part.description || "";
  el("part-keywords").value = (part.keywords || []).join(", ");

  var modelsResponse = await supabase.from("part_models").select("model_id").eq("part_id", partId);
  var selectedIds = (modelsResponse.data || []).map(function (r) { return String(r.model_id); });
  Array.prototype.forEach.call(el("part-models").options, function (o) {
    o.selected = selectedIds.indexOf(o.value) !== -1;
  });

  openModal(partModal);
  el("part-number").focus();
}

function parseKeywords(raw) {
  return raw.split(",")
    .map(function (k) { return k.trim(); })
    .filter(function (k) { return k.length > 0; });
}

function selectedModelIds() {
  return Array.prototype.filter
    .call(el("part-models").options, function (o) { return o.selected; })
    .map(function (o) { return Number(o.value); });
}

partForm.addEventListener("submit", async function (event) {
  event.preventDefault();
  partFormMsg.className = "form-msg";
  partFormMsg.textContent = "Saving...";
  el("part-save-btn").disabled = true;

  var idValue = el("part-id").value;
  var supplierValue = el("part-supplier").value;
  var priceValue = el("part-price").value;

  var row = {
    part_number: el("part-number").value.trim(),
    name: el("part-name").value.trim(),
    category: el("part-category").value.trim(),
    supplier_id: supplierValue === "" ? null : Number(supplierValue),
    price: priceValue === "" ? null : Number(priceValue),
    stock: el("part-stock").value,
    replacement: el("part-replacement").checked,
    description: el("part-description").value.trim() || null,
    keywords: parseKeywords(el("part-keywords").value),
    supersedes: el("part-supersedes").value.trim() || null
  };

  var partId;
  if (idValue) {
    partId = Number(idValue);
    var update = await supabase.from("parts").update(row).eq("id", partId);
    if (update.error) return failSave(update.error);
  } else {
    var insert = await supabase.from("parts").insert(row).select("id").single();
    if (insert.error) return failSave(insert.error);
    partId = insert.data.id;
  }

  // Sync the many-to-many model links: clear then re-insert the selection.
  var clear = await supabase.from("part_models").delete().eq("part_id", partId);
  if (clear.error) return failSave(clear.error);

  var modelIds = selectedModelIds();
  if (modelIds.length > 0) {
    var joinRows = modelIds.map(function (modelId) {
      return { part_id: partId, model_id: modelId };
    });
    var link = await supabase.from("part_models").insert(joinRows);
    if (link.error) return failSave(link.error);
  }

  el("part-save-btn").disabled = false;
  closeModal(partModal);
  await refresh();
});

function failSave(error) {
  console.error(error);
  partFormMsg.className = "form-msg error";
  partFormMsg.textContent = error.message || "Save failed.";
  el("part-save-btn").disabled = false;
}

// ===========================================================================
// Delete part (confirmation)
// ===========================================================================

var pendingConfirm = null;

function confirmDeletePart(partId) {
  var part = currentRows.find(function (p) { return p.id === partId; });
  if (!part) return;
  el("confirm-title").textContent = "Delete Part";
  el("confirm-text").innerHTML =
    "Delete <strong>" + escapeHtml(part.name) + "</strong> (" +
    escapeHtml(part.part_number) + ")? This cannot be undone.";
  el("confirm-msg").textContent = "";
  pendingConfirm = async function () {
    var del = await supabase.from("parts").delete().eq("id", partId);
    if (del.error) throw del.error;
    await refresh();
  };
  openModal(confirmModal);
}

el("confirm-ok-btn").addEventListener("click", async function () {
  if (!pendingConfirm) return;
  var btn = el("confirm-ok-btn");
  btn.disabled = true;
  try {
    await pendingConfirm();
    pendingConfirm = null;
    closeModal(confirmModal);
  } catch (error) {
    console.error(error);
    el("confirm-msg").textContent = error.message || "Delete failed.";
  } finally {
    btn.disabled = false;
  }
});

// ===========================================================================
// Lookups: suppliers & boiler models
// ===========================================================================

function renderLookups() {
  var supplierItems = data.suppliers.map(function (s) {
    return (
      "<li>" +
        '<span class="lk-name">' + escapeHtml(s.name) + "</span>" +
        "<span>" +
          '<button type="button" class="btn btn-small" data-rename-supplier="' + s.id + '">Rename</button> ' +
          '<button type="button" class="btn btn-small btn-danger" data-delete-supplier="' + s.id + '">Delete</button>' +
        "</span>" +
      "</li>"
    );
  }).join("");
  el("suppliers-list").innerHTML = supplierItems ||
    '<li><span class="lk-sub">No suppliers yet.</span></li>';

  var modelItems = data.models.map(function (m) {
    return (
      "<li>" +
        '<span><span class="lk-name">' + escapeHtml(m.name) + "</span> " +
          '<span class="lk-sub">' + escapeHtml(supplierName(m.supplier_id) || "no supplier") + "</span></span>" +
        "<span>" +
          '<button type="button" class="btn btn-small" data-rename-model="' + m.id + '">Rename</button> ' +
          '<button type="button" class="btn btn-small btn-danger" data-delete-model="' + m.id + '">Delete</button>' +
        "</span>" +
      "</li>"
    );
  }).join("");
  el("models-list").innerHTML = modelItems ||
    '<li><span class="lk-sub">No models yet.</span></li>';
}

el("supplier-add-form").addEventListener("submit", async function (event) {
  event.preventDefault();
  var name = el("supplier-add-name").value.trim();
  if (!name) return;
  var result = await supabase.from("suppliers").insert({ name: name });
  if (result.error) { alert(result.error.message); return; }
  el("supplier-add-name").value = "";
  await refresh();
});

el("model-add-form").addEventListener("submit", async function (event) {
  event.preventDefault();
  var name = el("model-add-name").value.trim();
  if (!name) return;
  var supplierValue = el("model-add-supplier").value;
  var result = await supabase.from("boiler_models").insert({
    name: name,
    supplier_id: supplierValue === "" ? null : Number(supplierValue)
  });
  if (result.error) { alert(result.error.message); return; }
  el("model-add-name").value = "";
  await refresh();
});

el("suppliers-list").addEventListener("click", async function (event) {
  var renameBtn = event.target.closest("[data-rename-supplier]");
  if (renameBtn) return renameRow("suppliers", Number(renameBtn.getAttribute("data-rename-supplier")), data.suppliers);
  var deleteBtn = event.target.closest("[data-delete-supplier]");
  if (deleteBtn) return deleteSupplier(Number(deleteBtn.getAttribute("data-delete-supplier")));
});

el("models-list").addEventListener("click", async function (event) {
  var renameBtn = event.target.closest("[data-rename-model]");
  if (renameBtn) return renameRow("boiler_models", Number(renameBtn.getAttribute("data-rename-model")), data.models);
  var deleteBtn = event.target.closest("[data-delete-model]");
  if (deleteBtn) return deleteModel(Number(deleteBtn.getAttribute("data-delete-model")));
});

async function renameRow(table, id, collection) {
  var current = collection.find(function (item) { return item.id === id; });
  if (!current) return;
  var next = window.prompt("Rename:", current.name);
  if (next == null) return;
  next = next.trim();
  if (!next || next === current.name) return;
  var result = await supabase.from(table).update({ name: next }).eq("id", id);
  if (result.error) { alert(result.error.message); return; }
  await refresh();
}

async function deleteSupplier(id) {
  var supplier = data.suppliers.find(function (s) { return s.id === id; });
  if (!supplier) return;
  var countResponse = await supabase
    .from("parts").select("id", { count: "exact", head: true }).eq("supplier_id", id);
  var count = countResponse.count || 0;
  var note = count > 0 ? " " + count + " part(s) will be left with no supplier." : "";
  if (!window.confirm('Delete supplier "' + supplier.name + '"?' + note)) return;
  var result = await supabase.from("suppliers").delete().eq("id", id);
  if (result.error) { alert(result.error.message); return; }
  await refresh();
}

async function deleteModel(id) {
  var model = data.models.find(function (m) { return m.id === id; });
  if (!model) return;
  var countResponse = await supabase
    .from("part_models").select("part_id", { count: "exact", head: true }).eq("model_id", id);
  var count = countResponse.count || 0;
  var note = count > 0 ? " It will be removed from " + count + " part(s)." : "";
  if (!window.confirm('Delete model "' + model.name + '"?' + note)) return;
  var result = await supabase.from("boiler_models").delete().eq("id", id);
  if (result.error) { alert(result.error.message); return; }
  await refresh();
}

// ===========================================================================
// Modal plumbing
// ===========================================================================

function openModal(modal) { modal.classList.add("open"); }
function closeModal(modal) { modal.classList.remove("open"); }

document.querySelectorAll("[data-close-part]").forEach(function (btn) {
  btn.addEventListener("click", function () { closeModal(partModal); });
});
document.querySelectorAll("[data-close-confirm]").forEach(function (btn) {
  btn.addEventListener("click", function () { closeModal(confirmModal); });
});

[partModal, confirmModal].forEach(function (modal) {
  modal.addEventListener("click", function (event) {
    if (event.target === modal) closeModal(modal);
  });
});

document.addEventListener("keydown", function (event) {
  if (event.key === "Escape") { closeModal(partModal); closeModal(confirmModal); }
});

// ===========================================================================
// Boot
// ===========================================================================

function showNotConfigured() {
  loginView.hidden = true;
  appView.hidden = true;
  document.body.insertAdjacentHTML("beforeend",
    '<div class="login-wrap"><div class="login-card">' +
    '<h2>Not configured</h2>' +
    '<div class="sub">Set your Supabase URL and anon key in ' +
    '<span style="font-family:var(--mono)">assets/js/config.js</span>, then reload.</div>' +
    "</div></div>");
}

async function loadAppData() {
  await loadLookups();
  await loadPartsPage();
}

// A valid login is not enough -- the account must also be in the admins table
// (is_admin RPC). Non-admins are signed out with a message. This mirrors the
// RLS write policies, so the UI never shows controls the user can't actually use.
async function onSignedIn(session) {
  var adminCheck = await supabase.rpc("is_admin");
  if (adminCheck.error || !adminCheck.data) {
    await supabase.auth.signOut();
    showLogin();
    loginMsg.textContent = "This account is not authorized for admin access.";
    return;
  }
  showApp(session);
  await loadAppData();
}

async function boot() {
  if (!isConfigured) { showNotConfigured(); return; }

  var sessionResponse = await supabase.auth.getSession();
  var session = sessionResponse.data.session;
  if (session) { await onSignedIn(session); }
  else { showLogin(); }

  supabase.auth.onAuthStateChange(function (event, session) {
    if (session) { onSignedIn(session); }
    else { showLogin(); }
  });
}

boot();
