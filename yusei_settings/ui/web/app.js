/**
 * yusei-settings: Application Frontend Logic
 * Manages Windows 11-style navigation, theme galleries, and 5-stage safe apply workflow.
 */

let appCatalog = {};
let activeState = {};
let currentCategory = "waybar_layouts";
let pendingApply = null;
let previewingTarget = null;
let lastSnapshotId = null;

const CATEGORY_TO_API = {
  waybar_layouts: "waybar_layout",
  waybar_styles: "waybar_style",
  rofi_themes: "rofi_theme",
  kitty_themes: "kitty_theme",
  hyprland_animations: "hyprland_animation",
  wallpapers: "wallpaper",
};

function toApiCategory(category) {
  return CATEGORY_TO_API[category] || category;
}

// -----------------------------------------------------------------------------
// Security & HTTP Helpers
// -----------------------------------------------------------------------------
function escapeHtml(str) {
  if (str === null || str === undefined) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function sanitizeUrl(url) {
  if (!url) return "";
  const s = String(url).trim();
  if (/^(javascript|data|vbscript):/i.test(s.replace(/[\s\x00-\x1f]+/g, ""))) {
    return "";
  }
  return s;
}

function sanitizeCssColor(color) {
  if (!color) return "#141316";
  const s = String(color).trim();
  if (/^(#[0-9a-fA-F]{3,8}|(?:rgb|rgba|hsl|hsla)\([0-9.,%\s+-]+\)|[a-zA-Z]{1,30})$/.test(s)) {
    return s;
  }
  return "#141316";
}

async function apiFetch(url, opts = {}) {
  const method = (opts.method || "GET").toUpperCase();
  const fetchOpts = { ...opts, method };

  if (method === "POST") {
    fetchOpts.headers = {
      ...(opts.headers || {}),
      "Content-Type": "application/json",
    };
    if (fetchOpts.body === undefined || fetchOpts.body === null || fetchOpts.body === "") {
      fetchOpts.body = "{}";
    } else if (typeof fetchOpts.body !== "string") {
      fetchOpts.body = JSON.stringify(fetchOpts.body);
    }
  }

  const res = await fetch(url, fetchOpts);
  const rawText = await res.text();
  let data = null;

  if (rawText) {
    try {
      data = JSON.parse(rawText);
    } catch (_parseErr) {
      if (!res.ok) {
        const err = new Error(`HTTP ${res.status}: ${rawText.slice(0, 200)}`);
        err.status = res.status;
        throw err;
      }
      throw new Error("Phản hồi từ máy chủ không phải JSON hợp lệ.");
    }
  }

  if (!res.ok) {
    const msg = (data && (data.message || data.error)) || `HTTP ${res.status}${res.statusText ? ` ${res.statusText}` : ""}`;
    const err = new Error(msg);
    err.data = data;
    err.status = res.status;
    throw err;
  }

  if (data && typeof data === "object" && data.success === false) {
    const msg = data.message || "Thao tác không thành công.";
    const err = new Error(msg);
    err.data = data;
    err.status = res.status;
    throw err;
  }

  return data;
}

document.addEventListener("DOMContentLoaded", () => {
  initNavigation();
  initCategoryTabs();
  initGlobalSearch();
  initModalActions();
  initPreviewModalActions();
  initBackupButtons();
  initKeybindsAndMaintenance();
  initPowerManagement();
  fetchStateAndCatalog();
});

// -----------------------------------------------------------------------------
// 1. Navigation & Page Switching
// -----------------------------------------------------------------------------
function initNavigation() {
  const navItems = document.querySelectorAll(".nav-item");
  const pages = document.querySelectorAll(".settings-page");

  let powerPollInterval = null;

  navItems.forEach(item => {
    item.addEventListener("click", () => {
      navItems.forEach(i => i.classList.remove("active"));
      item.classList.add("active");

      const targetPageId = item.getAttribute("data-page");
      pages.forEach(page => {
        if (page.id === targetPageId) {
          page.style.display = "flex";
        } else {
          page.style.display = "none";
        }
      });

      if (powerPollInterval) {
        clearInterval(powerPollInterval);
        powerPollInterval = null;
      }

      if (targetPageId === "page-backup") {
        fetchSnapshots();
      } else if (targetPageId === "page-keybinds") {
        fetchKeybinds();
      } else if (targetPageId === "page-maintenance") {
        fetchSystemStatus();
      } else if (targetPageId === "page-power") {
        fetchPowerStatus();
        powerPollInterval = setInterval(fetchPowerStatus, 5000);
      }

      applyGlobalSearch();
    });
  });
}

// -----------------------------------------------------------------------------
// 1b. Global Search Filtering
// -----------------------------------------------------------------------------
function initGlobalSearch() {
  const globalSearch = document.getElementById("global-search");
  if (!globalSearch) return;
  globalSearch.addEventListener("input", applyGlobalSearch);
  globalSearch.addEventListener("search", applyGlobalSearch);
}

function setEmptySearchNote(container, visible, text) {
  if (!container) return;
  let note = container.querySelector(".search-empty-note");
  if (visible) {
    if (!note) {
      note = document.createElement("p");
      note.className = "search-empty-note";
      note.style.color = "var(--text-muted)";
      note.style.fontSize = "13px";
      note.style.gridColumn = "1 / -1";
      note.textContent = text;
      container.appendChild(note);
    } else {
      note.style.display = "";
    }
  } else if (note) {
    note.remove();
  }
}

function applyGlobalSearch() {
  const globalSearch = document.getElementById("global-search");
  const query = (globalSearch ? globalSearch.value : "").trim().toLowerCase();

  // 1. Gallery cards
  const galleryContainer = document.getElementById("gallery-container");
  if (galleryContainer) {
    const cards = galleryContainer.querySelectorAll(".theme-card");
    let visibleCards = 0;
    cards.forEach(card => {
      const text = (card.dataset.searchText || card.textContent || "").toLowerCase();
      const match = !query || text.includes(query);
      card.style.display = match ? "" : "none";
      if (match) visibleCards += 1;
    });
    setEmptySearchNote(
      galleryContainer,
      Boolean(query) && cards.length > 0 && visibleCards === 0,
      "Không tìm thấy mục nào khớp với từ khóa tìm kiếm."
    );
  }

  // 2. Keybind cards
  const keybindsContainer = document.getElementById("keybinds-container");
  const countBadge = document.getElementById("keybinds-count-badge");
  if (keybindsContainer) {
    const kbCards = keybindsContainer.querySelectorAll(".keybind-card");
    let visibleKb = 0;
    kbCards.forEach(card => {
      const text = (card.dataset.searchText || card.textContent || "").toLowerCase();
      const match = !query || text.includes(query);
      card.style.display = match ? "" : "none";
      if (match) visibleKb += 1;
    });
    if (countBadge && (allKeybinds.length > 0 || kbCards.length > 0)) {
      countBadge.textContent = `${visibleKb} phím tắt`;
    }
    setEmptySearchNote(
      keybindsContainer,
      Boolean(query) && kbCards.length > 0 && visibleKb === 0,
      "Không tìm thấy phím tắt khớp với từ khóa tìm kiếm."
    );
  }

  // 3. Settings sections, rows, and power profile cards
  const sections = document.querySelectorAll(".settings-page .settings-section-card");
  sections.forEach(section => {
    const rows = section.querySelectorAll(".settings-row");
    const profileCards = section.querySelectorAll(".power-profile-card");
    const metrics = section.querySelectorAll(".status-metric");

    if (!query) {
      section.style.display = "";
      rows.forEach(r => { r.style.display = ""; });
      profileCards.forEach(p => { p.style.display = ""; });
      metrics.forEach(m => { m.style.display = ""; });
      return;
    }

    const headerText = (section.querySelector(".settings-section-header")?.textContent || "").toLowerCase();
    if (headerText.includes(query)) {
      section.style.display = "";
      rows.forEach(r => { r.style.display = ""; });
      profileCards.forEach(p => { p.style.display = ""; });
      metrics.forEach(m => { m.style.display = ""; });
      return;
    }

    let anyChildMatch = false;

    if (rows.length > 0) {
      rows.forEach(row => {
        const match = (row.textContent || "").toLowerCase().includes(query);
        row.style.display = match ? "" : "none";
        if (match) anyChildMatch = true;
      });
    }

    if (profileCards.length > 0) {
      profileCards.forEach(card => {
        const match = (card.textContent || "").toLowerCase().includes(query);
        card.style.display = match ? "" : "none";
        if (match) anyChildMatch = true;
      });
    }

    if (metrics.length > 0) {
      metrics.forEach(metric => {
        const match = (metric.textContent || "").toLowerCase().includes(query);
        metric.style.display = match ? "" : "none";
        if (match) anyChildMatch = true;
      });
    }

    const consoleEl = section.querySelector(".maintenance-console");
    if (consoleEl && (consoleEl.textContent || "").toLowerCase().includes(query)) {
      anyChildMatch = true;
    }

    if (rows.length === 0 && profileCards.length === 0 && metrics.length === 0 && !consoleEl) {
      anyChildMatch = (section.textContent || "").toLowerCase().includes(query);
    }

    section.style.display = anyChildMatch ? "" : "none";
  });
}

// -----------------------------------------------------------------------------
// 2. Category Tab Switching (Giao diện & Layout)
// -----------------------------------------------------------------------------
function initCategoryTabs() {
  const tabs = document.querySelectorAll("#appearance-tabs .pill-tab");
  tabs.forEach(tab => {
    tab.addEventListener("click", () => {
      tabs.forEach(t => t.classList.remove("active"));
      tab.classList.add("active");

      currentCategory = tab.getAttribute("data-category");
      renderGallery();
    });
  });
}

// -----------------------------------------------------------------------------
// 3. Data Fetching
// -----------------------------------------------------------------------------
async function fetchStateAndCatalog() {
  try {
    const [stateRes, catRes] = await Promise.all([
      apiFetch("/api/state"),
      apiFetch("/api/catalog"),
    ]);
    activeState = stateRes || {};
    appCatalog = catRes || {};
    renderGallery();
  } catch (err) {
    console.error("Failed to fetch state or catalog:", err);
    showToast(`Lỗi tải trạng thái/danh mục: ${err.message}`, false, true);
  }
}

// -----------------------------------------------------------------------------
// 4. Gallery Rendering & Preview Modal
// -----------------------------------------------------------------------------
function buildPreviewHtml(item, maxSwatches = 5) {
  if (item.preview_svg) {
    return item.preview_svg;
  }
  if (item.relative_url) {
    const safeUrl = sanitizeUrl(item.relative_url);
    if (safeUrl) {
      return `<img src="${escapeHtml(safeUrl)}" alt="${escapeHtml(item.name || "")}" loading="lazy" />`;
    }
  }
  if (item.palette) {
    const bg = escapeHtml(sanitizeCssColor(item.palette.background));
    const swatches = Array.isArray(item.palette.swatches) ? item.palette.swatches.slice(0, maxSwatches) : [];
    return `<div style="display:flex; gap:6px; align-items:center; flex-wrap:wrap; justify-content:center;">
      <span style="display:inline-block; width:28px; height:28px; border-radius:50%; background:${bg}; border:1px solid #444;"></span>
      ${swatches.map(c => `<span style="display:inline-block; width:16px; height:24px; border-radius:4px; background:${escapeHtml(sanitizeCssColor(c))};"></span>`).join("")}
    </div>`;
  }
  return `<span style="font-size:28px;">🎨</span>`;
}

function renderGallery() {
  const container = document.getElementById("gallery-container");
  if (!container) return;
  container.innerHTML = "";

  const items = appCatalog[currentCategory] || [];
  if (items.length === 0) {
    container.innerHTML = `<p style="color: var(--text-muted); font-size: 13px;">Không tìm thấy mục nào trong danh mục này.</p>`;
    return;
  }

  items.forEach(item => {
    const card = document.createElement("div");
    card.className = "theme-card";

    const isActive = checkIsActive(currentCategory, item.id);
    if (isActive) {
      card.classList.add("active-card");
    }

    const previewContent = buildPreviewHtml(item, 5);
    const badgeLabel = item.position || item.theme_tag || item.style_type || (isActive ? "Đang chọn" : "Có sẵn");
    const descText = item.description || "Tùy chọn giao diện tương thích hoàn toàn.";

    card.dataset.searchText = `${item.name || ""} ${descText} ${item.id || ""} ${badgeLabel}`.toLowerCase();

    card.innerHTML = `
      <div class="card-preview-box">
        ${previewContent}
      </div>
      <div class="card-body">
        <div class="card-title-row">
          <h4 title="${escapeHtml(item.name)}">${escapeHtml(item.name)}</h4>
          <span class="card-badge ${isActive ? "active-badge" : ""}">${escapeHtml(badgeLabel)}</span>
        </div>
        <p class="card-desc">${escapeHtml(descText)}</p>
      </div>
      <div class="card-footer">
        <button class="btn btn-secondary btn-preview-item" data-id="${escapeHtml(item.id)}">Xem thử</button>
        <button class="btn btn-primary ${isActive ? "btn-disabled" : ""} btn-apply-item" data-id="${escapeHtml(item.id)}" ${isActive ? "disabled" : ""}>
          ${isActive ? "✓ Đang dùng" : "Áp dụng"}
        </button>
      </div>
    `;

    const applyBtn = card.querySelector(".btn-apply-item");
    if (!isActive && applyBtn) {
      applyBtn.addEventListener("click", () => {
        triggerApplyWorkflow(currentCategory, item);
      });
    }

    const previewBtn = card.querySelector(".btn-preview-item");
    if (previewBtn) {
      previewBtn.addEventListener("click", () => {
        openPreviewModal(currentCategory, item);
      });
    }

    container.appendChild(card);
  });

  applyGlobalSearch();
}

function checkIsActive(category, itemId) {
  if (!itemId) return false;
  if (category === "waybar_layouts") {
    return activeState.waybar_layout === itemId;
  } else if (category === "waybar_styles") {
    return activeState.waybar_style === itemId;
  } else if (category === "rofi_themes") {
    return activeState.rofi_theme === itemId;
  } else if (category === "kitty_themes") {
    return activeState.kitty_theme === itemId;
  } else if (category === "hyprland_animations") {
    return activeState.hyprland_animation === itemId;
  } else if (category === "wallpapers") {
    if (activeState.active_wallpaper !== undefined && activeState.active_wallpaper !== null) {
      return activeState.active_wallpaper === itemId;
    }
    return activeState.current_wallpaper === itemId || activeState.wallpaper === itemId;
  }
  return false;
}

function initPreviewModalActions() {
  const modal = document.getElementById("preview-modal");
  const closeBtn = document.getElementById("preview-btn-close");
  const applyBtn = document.getElementById("preview-btn-apply");
  if (!modal) return;

  const closePreview = () => {
    modal.classList.remove("open");
    previewingTarget = null;
  };

  if (closeBtn) {
    closeBtn.addEventListener("click", closePreview);
  }

  modal.addEventListener("click", (e) => {
    if (e.target === modal) {
      closePreview();
    }
  });

  if (applyBtn) {
    applyBtn.addEventListener("click", () => {
      if (!previewingTarget) return;
      const target = previewingTarget;
      closePreview();
      triggerApplyWorkflow(target.category, target.item);
    });
  }
}

function openPreviewModal(category, item) {
  const modal = document.getElementById("preview-modal");
  const titleEl = document.getElementById("preview-item-title");
  const subtitleEl = document.getElementById("preview-item-subtitle");
  const stageEl = document.getElementById("preview-stage");
  const metaEl = document.getElementById("preview-item-meta");
  const applyBtn = document.getElementById("preview-btn-apply");

  if (!modal || !stageEl || !metaEl) return;

  const isActive = checkIsActive(category, item.id);
  previewingTarget = { category, item };

  if (titleEl) {
    titleEl.textContent = item.name || item.id || "Xem trước";
  }
  if (subtitleEl) {
    subtitleEl.textContent = `${toApiCategory(category)} • ${item.id || ""}`;
  }

  stageEl.innerHTML = buildPreviewHtml(item, 8);

  const metaRows = [];
  if (item.description) {
    metaRows.push(`<div><strong>Mô tả:</strong> <span>${escapeHtml(item.description)}</span></div>`);
  }
  if (item.target_config) {
    metaRows.push(`<div><strong>Tệp cấu hình đích:</strong> <code>${escapeHtml(item.target_config)}</code></div>`);
  }
  if (item.file_path) {
    metaRows.push(`<div><strong>Nguồn:</strong> <code>${escapeHtml(item.file_path)}</code></div>`);
  }
  if (Array.isArray(item.modules) && item.modules.length > 0) {
    metaRows.push(`<div><strong>Modules:</strong> <span>${item.modules.map(m => escapeHtml(m)).join(", ")}</span></div>`);
  }
  if (item.palette && item.palette.background) {
    metaRows.push(`<div><strong>Nền / Chữ:</strong> <code>${escapeHtml(item.palette.background)}</code> / <code>${escapeHtml(item.palette.foreground || "")}</code></div>`);
  }
  if (metaRows.length === 0) {
    metaRows.push(`<div><span>Không có thông tin bổ sung.</span></div>`);
  }
  metaEl.innerHTML = metaRows.join("");

  if (applyBtn) {
    applyBtn.disabled = isActive;
    applyBtn.classList.toggle("btn-disabled", isActive);
    applyBtn.textContent = isActive ? "✓ Đang dùng" : "Áp dụng cấu hình này";
  }

  modal.classList.add("open");
}

// -----------------------------------------------------------------------------
// 5. 5-Stage Safe Apply Workflow
// -----------------------------------------------------------------------------
async function triggerApplyWorkflow(category, item) {
  const apiCategory = toApiCategory(category);
  pendingApply = { category, apiCategory, item };

  const errorBanner = document.getElementById("modal-error-banner");
  if (errorBanner) {
    errorBanner.style.display = "none";
    errorBanner.textContent = "";
  }

  try {
    // Stage 1 & 2: Call analyze API to list exact affected files
    const impact = await apiFetch("/api/analyze", {
      method: "POST",
      body: JSON.stringify({
        category: apiCategory,
        item_id: item.id,
        source_path: item.file_path,
      }),
    });

    // Populate modal
    const modalName = document.getElementById("modal-item-name");
    if (modalName) {
      modalName.textContent = `${item.name} (${apiCategory})`;
    }
    const list = document.getElementById("modal-affected-files");
    if (list) {
      list.innerHTML = "";
      (impact.affected_files || []).forEach(f => {
        const li = document.createElement("li");
        const actionEsc = escapeHtml((f.action || "").toUpperCase());
        const targetEsc = escapeHtml(f.target || "");
        const descEsc = escapeHtml(f.description || "");
        const sourcePart = f.source
          ? `<br/><span style="color:var(--text-muted); font-size:11px;">Nguồn: ${escapeHtml(f.source)}</span>`
          : "";
        li.innerHTML = `<strong>${actionEsc}</strong>: ${targetEsc} <br/><span style="color:var(--text-muted); font-size:11px;">&rarr; ${descEsc}</span>${sourcePart}`;
        list.appendChild(li);
      });
    }

    // Show Modal
    const modal = document.getElementById("confirm-modal");
    if (modal) {
      modal.classList.add("open");
    }
  } catch (err) {
    pendingApply = null;
    showToast(`Lỗi khi phân tích tác động tệp tin: ${err.message}`, false, true);
  }
}

function initModalActions() {
  const modal = document.getElementById("confirm-modal");
  const cancelBtn = document.getElementById("modal-btn-cancel");
  const confirmBtn = document.getElementById("modal-btn-confirm");
  const errorBanner = document.getElementById("modal-error-banner");

  const closeConfirmModal = () => {
    if (confirmBtn && confirmBtn.disabled) return;
    if (modal) modal.classList.remove("open");
    if (errorBanner) {
      errorBanner.style.display = "none";
      errorBanner.textContent = "";
    }
    pendingApply = null;
  };

  if (cancelBtn) {
    cancelBtn.addEventListener("click", closeConfirmModal);
  }

  if (modal) {
    modal.addEventListener("click", (e) => {
      if (e.target === modal) {
        closeConfirmModal();
      }
    });
  }

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      const previewModal = document.getElementById("preview-modal");
      if (previewModal && previewModal.classList.contains("open")) {
        previewModal.classList.remove("open");
        previewingTarget = null;
      } else if (modal && modal.classList.contains("open")) {
        closeConfirmModal();
      }
    }
  });

  if (confirmBtn) {
    confirmBtn.addEventListener("click", async () => {
      if (!pendingApply) return;
      confirmBtn.textContent = "Đang áp dụng...";
      confirmBtn.disabled = true;
      if (errorBanner) {
        errorBanner.style.display = "none";
        errorBanner.textContent = "";
      }

      try {
        const apiCategory = pendingApply.apiCategory || toApiCategory(pendingApply.category);
        // Stage 4 & 5: Apply change with explicit confirmation
        const result = await apiFetch("/api/apply", {
          method: "POST",
          body: JSON.stringify({
            category: apiCategory,
            item_id: pendingApply.item.id,
            source_path: pendingApply.item.file_path,
            confirmed: true,
          }),
        });

        const appliedName = pendingApply.item.name;
        lastSnapshotId = result.snapshot_id || null;
        pendingApply = null;
        if (modal) modal.classList.remove("open");
        showToast(`Đã áp dụng thành công: ${appliedName}!`, Boolean(lastSnapshotId));

        await fetchStateAndCatalog();
      } catch (err) {
        // Keep modal open and pendingApply intact so user can retry
        if (errorBanner) {
          errorBanner.textContent = `Áp dụng thất bại: ${err.message}. Bạn có thể thử lại hoặc bấm Hủy bỏ.`;
          errorBanner.style.display = "block";
        }
        showToast(`Áp dụng thất bại: ${err.message}`, false, true);
      } finally {
        confirmBtn.textContent = "Xác Nhận Áp Dụng";
        confirmBtn.disabled = false;
      }
    });
  }

  // Rollback Undo Button in Toast
  const undoBtn = document.getElementById("toast-btn-undo");
  if (undoBtn) {
    undoBtn.addEventListener("click", async () => {
      if (!lastSnapshotId) return;
      if (!confirm(`Bạn có chắc muốn hoàn tác về snapshot: ${lastSnapshotId}?`)) return;

      undoBtn.disabled = true;
      try {
        const result = await apiFetch("/api/rollback", {
          method: "POST",
          body: JSON.stringify({ snapshot_id: lastSnapshotId }),
        });
        lastSnapshotId = null;
        showToast(result.message || "Đã hoàn tác (Rollback) thành công trạng thái trước đó!");
        await Promise.all([fetchStateAndCatalog(), fetchSnapshots()]);
      } catch (err) {
        showToast(`Lỗi rollback: ${err.message}`, false, true);
      } finally {
        undoBtn.disabled = false;
      }
    });
  }
}

// -----------------------------------------------------------------------------
// 6. Snapshots List & Manual Backup
// -----------------------------------------------------------------------------
function initBackupButtons() {
  const btnManualBackup = document.getElementById("btn-create-manual-backup");
  if (btnManualBackup) {
    const defaultLabel = btnManualBackup.textContent || "Tạo bản sao lưu mới";
    btnManualBackup.addEventListener("click", () => runSystemBackup(btnManualBackup, defaultLabel));
  }

  const btnInstantBackup = document.getElementById("btn-instant-backup");
  if (btnInstantBackup) {
    const defaultLabel = btnInstantBackup.textContent || "Tạo Snapshot Ngay";
    btnInstantBackup.addEventListener("click", () => runSystemBackup(btnInstantBackup, defaultLabel));
  }
}

async function runSystemBackup(buttonEl, defaultLabel) {
  const consoleEl = document.getElementById("maintenance-console");
  if (buttonEl) {
    buttonEl.disabled = true;
    buttonEl.textContent = "Đang tạo sao lưu...";
  }
  if (consoleEl) {
    consoleEl.textContent = ":: [Snapshot Backup] Đang thực thi scripts/03-backup.sh để tạo bản snapshot an toàn...\n";
  }

  try {
    const res = await apiFetch("/api/system/backup", { method: "POST" });
    if (consoleEl) {
      if (res.log) consoleEl.textContent += res.log;
      consoleEl.textContent += `\n✓ Đã tạo thành công bản snapshot: ${res.backup_dir || "latest"}\n`;
    }
    showToast(res.message || "Tạo bản snapshot sao lưu thành công!");
    await Promise.all([fetchSnapshots(), fetchSystemStatus()]);
  } catch (err) {
    if (consoleEl) {
      if (err.data && err.data.log) consoleEl.textContent += err.data.log;
      consoleEl.textContent += `\n❌ Lỗi tạo sao lưu: ${err.message}\n`;
    }
    showToast(`Lỗi tạo sao lưu: ${err.message}`, false, true);
  } finally {
    if (buttonEl) {
      buttonEl.disabled = false;
      buttonEl.textContent = defaultLabel;
    }
  }
}

async function fetchSnapshots() {
  const container = document.getElementById("snapshots-list-container");
  if (!container) return;
  try {
    const res = await apiFetch("/api/snapshots");
    if (!Array.isArray(res) || res.length === 0) {
      container.innerHTML = `<p style="color: var(--text-muted); font-size: 13px;">Chưa có bản snapshot sao lưu nào được ghi nhận.</p>`;
      return;
    }

    container.innerHTML = res.map(snap => {
      const files = Array.isArray(snap.backed_up_files) ? snap.backed_up_files : [];
      const newFiles = Array.isArray(snap.non_existent_files) ? snap.non_existent_files : [];
      const fileNames = files
        .map(f => (typeof f === "string" ? f : (f && (f.original_path || f.backup_file)) || ""))
        .filter(Boolean)
        .map(f => escapeHtml(f));
      const filesSummary = fileNames.length > 0
        ? `<div style="font-size:11px; color:var(--text-muted); margin-top:3px; font-family:monospace;">${fileNames.join(", ")}</div>`
        : "";
      const snapIdEsc = escapeHtml(snap.snapshot_id || "");
      const createdEsc = escapeHtml(snap.created_at || "--");
      const countText = `${files.length} tệp đã sao lưu${newFiles.length ? ` • ${newFiles.length} tệp tạo mới` : ""}`;

      return `
        <div class="settings-row">
          <div class="row-label">
            <h4>${snapIdEsc}</h4>
            <p>Tạo lúc: ${createdEsc} • ${escapeHtml(countText)}</p>
            ${filesSummary}
          </div>
          <button class="btn btn-secondary btn-restore-snap" data-id="${snapIdEsc}">Khôi phục bản này</button>
        </div>
      `;
    }).join("");

    container.querySelectorAll(".btn-restore-snap").forEach(btn => {
      btn.addEventListener("click", async () => {
        const snapId = btn.getAttribute("data-id");
        if (!snapId) return;
        if (!confirm(`Bạn có chắc muốn khôi phục lại cấu hình từ snapshot: ${snapId}?`)) return;

        const origLabel = btn.textContent;
        btn.disabled = true;
        btn.textContent = "Đang khôi phục...";
        try {
          const r = await apiFetch("/api/rollback", {
            method: "POST",
            body: JSON.stringify({ snapshot_id: snapId }),
          });
          showToast(r.message || `Đã khôi phục thành công snapshot: ${snapId}`);
          await Promise.all([fetchStateAndCatalog(), fetchSnapshots()]);
        } catch (err) {
          showToast(`Khôi phục thất bại: ${err.message}`, false, true);
        } finally {
          btn.disabled = false;
          btn.textContent = origLabel;
        }
      });
    });

    applyGlobalSearch();
  } catch (err) {
    container.innerHTML = `<p style="color: #f2b8b5; font-size: 13px;">Lỗi khi tải lịch sử snapshot: ${escapeHtml(err.message)}</p>`;
    showToast(`Lỗi khi tải lịch sử snapshot: ${err.message}`, false, true);
  }
}

// -----------------------------------------------------------------------------
// 7. Toast Notification Utility
// -----------------------------------------------------------------------------
let toastTimer = null;
function showToast(message, showUndo = false, isError = false) {
  const toast = document.getElementById("toast-notify");
  const msgEl = document.getElementById("toast-message");
  const undoBtn = document.getElementById("toast-btn-undo");
  if (!toast || !msgEl) return;

  msgEl.textContent = message;
  toast.classList.toggle("toast-error", Boolean(isError));
  if (undoBtn) {
    undoBtn.style.display = showUndo ? "inline-block" : "none";
  }

  toast.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.classList.remove("show");
  }, 6000);
}

// -----------------------------------------------------------------------------
// 8. Keybinds Cheat Sheet & Maintenance Controller
// -----------------------------------------------------------------------------
let allKeybinds = [];
let allKeybindCategories = [];
let activeKeybindCategory = "all";

function initKeybindsAndMaintenance() {
  const searchInput = document.getElementById("keybinds-search");
  if (searchInput) {
    searchInput.addEventListener("input", () => {
      renderKeybinds();
    });
  }

  const btnCheckUpdate = document.getElementById("btn-check-update");
  if (btnCheckUpdate) {
    btnCheckUpdate.addEventListener("click", checkSystemUpdate);
  }

  const btnApplyUpdate = document.getElementById("btn-apply-update");
  if (btnApplyUpdate) {
    btnApplyUpdate.addEventListener("click", applySystemUpdate);
  }
}

async function fetchKeybinds() {
  const container = document.getElementById("keybinds-container");
  if (!container) return;
  try {
    const res = await apiFetch("/api/keybinds");
    allKeybinds = (res && res.keybinds) || [];
    allKeybindCategories = (res && res.categories) || [];
    renderKeybindCategoryPills();
    renderKeybinds();
  } catch (err) {
    container.innerHTML = `<p style="color: #f2b8b5; font-size: 13px;">Lỗi khi tải danh sách phím tắt: ${escapeHtml(err.message)}</p>`;
    showToast(`Lỗi khi tải danh sách phím tắt: ${err.message}`, false, true);
  }
}

function renderKeybindCategoryPills() {
  const pillsContainer = document.getElementById("keybinds-category-pills");
  if (!pillsContainer) return;

  pillsContainer.innerHTML = "";
  const allPill = document.createElement("div");
  allPill.className = `pill-tab ${activeKeybindCategory === "all" ? "active" : ""}`;
  allPill.textContent = `Tất cả (${allKeybinds.length})`;
  allPill.addEventListener("click", () => {
    activeKeybindCategory = "all";
    document.querySelectorAll("#keybinds-category-pills .pill-tab").forEach(p => p.classList.remove("active"));
    allPill.classList.add("active");
    renderKeybinds();
  });
  pillsContainer.appendChild(allPill);

  allKeybindCategories.forEach(cat => {
    const pill = document.createElement("div");
    pill.className = `pill-tab ${activeKeybindCategory === cat.id ? "active" : ""}`;
    pill.textContent = `${cat.name} (${cat.count || 0})`;
    pill.addEventListener("click", () => {
      activeKeybindCategory = cat.id;
      document.querySelectorAll("#keybinds-category-pills .pill-tab").forEach(p => p.classList.remove("active"));
      pill.classList.add("active");
      renderKeybinds();
    });
    pillsContainer.appendChild(pill);
  });
}

function renderKeybinds() {
  const container = document.getElementById("keybinds-container");
  const countBadge = document.getElementById("keybinds-count-badge");
  if (!container) return;
  const query = (document.getElementById("keybinds-search")?.value || "").toLowerCase().trim();

  let filtered = allKeybinds;

  if (activeKeybindCategory !== "all") {
    filtered = filtered.filter(b => b.category_id === activeKeybindCategory);
  }

  if (query) {
    filtered = filtered.filter(b => {
      const desc = (b.description || "").toLowerCase();
      const combo = (b.combo_display || "").toLowerCase();
      const cmd = (b.command || b.args || "").toLowerCase();
      const cat = (b.category || "").toLowerCase();
      return desc.includes(query) || combo.includes(query) || cmd.includes(query) || cat.includes(query);
    });
  }

  if (countBadge) {
    countBadge.textContent = `${filtered.length} phím tắt`;
  }

  if (filtered.length === 0) {
    container.innerHTML = `<p style="color: var(--text-muted); font-size: 13px; grid-column: 1 / -1;">Không tìm thấy phím tắt phù hợp với tìm kiếm.</p>`;
    return;
  }

  container.innerHTML = filtered.map(b => {
    const keyBadges = (b.keys || []).map(k => `<kbd class="key-badge">${escapeHtml(k)}</kbd>`).join('<span class="key-separator">+</span>');
    const dispatcher = b.dispatcher ? `<span class="dispatcher-badge">${escapeHtml(b.dispatcher)}</span>` : "";
    const desc = escapeHtml(b.description || b.dispatcher || "Phím tắt");
    const cmdText = b.command || b.args || "";
    const cmd = cmdText ? `<div class="keybind-cmd">${escapeHtml(cmdText)}</div>` : "";
    const category = escapeHtml(b.category || "");

    return `
      <div class="keybind-card">
        <div class="keybind-card-header">
          <div class="key-combo">${keyBadges}</div>
          ${dispatcher}
        </div>
        <div class="keybind-card-body">
          <div class="keybind-desc">${desc}</div>
          ${cmd}
          <span class="keybind-category-tag">${category}</span>
        </div>
      </div>
    `;
  }).join("");

  container.querySelectorAll(".keybind-card").forEach((card, idx) => {
    const b = filtered[idx];
    if (b) {
      card.dataset.searchText = `${b.description || ""} ${b.combo_display || ""} ${b.command || b.args || ""} ${b.dispatcher || ""} ${b.category || ""}`.toLowerCase();
    }
  });

  applyGlobalSearch();
}

async function fetchSystemStatus() {
  try {
    const res = await apiFetch("/api/system/status");
    const branchEl = document.getElementById("maint-git-branch");
    const commitEl = document.getElementById("maint-git-commit");
    const statusEl = document.getElementById("maint-config-status");
    const backupEl = document.getElementById("maint-last-backup");

    if (branchEl) branchEl.textContent = res.git_branch || "main";
    if (commitEl) commitEl.textContent = res.git_hash || (res.git_commit ? res.git_commit.slice(0, 8) : "--");
    if (statusEl) statusEl.textContent = res.dirty ? "Có thay đổi (Dirty)" : "Sạch (Clean)";
    if (backupEl) backupEl.textContent = res.last_backup || "Chưa có";
  } catch (err) {
    console.error("Failed to fetch system status:", err);
    showToast(`Lỗi tải trạng thái hệ thống: ${err.message}`, false, true);
  }
}

async function checkSystemUpdate() {
  const consoleEl = document.getElementById("maintenance-console");
  const btn = document.getElementById("btn-check-update");
  const origLabel = btn ? btn.textContent : "";

  if (btn) {
    btn.disabled = true;
    btn.textContent = "Đang kiểm tra...";
  }
  if (consoleEl) {
    consoleEl.textContent = ":: [Update Check] Đang kiểm tra bản cập nhật từ kho lưu trữ Git...\n";
  }

  try {
    const res = await apiFetch("/api/system/update/check");
    const cannotCheck = res.checked === false || res.update_available === null || res.update_available === undefined;

    if (consoleEl) {
      consoleEl.textContent += `Commit hiện tại: ${res.current_commit || "N/A"}\n`;
      if (res.remote_commit) {
        consoleEl.textContent += `Commit từ xa: ${res.remote_commit}\n`;
      }
      if (typeof res.behind === "number") {
        consoleEl.textContent += `Số commit phía sau: ${res.behind}\n`;
      }
    }

    let statusText = "";
    if (cannotCheck) {
      statusText = `Không kiểm tra được${res.message ? ` (${res.message})` : ""}`;
      if (consoleEl) consoleEl.textContent += `Trạng thái: ${statusText}\n`;
      showToast(statusText, false, true);
    } else if (res.update_available) {
      const behindText = typeof res.behind === "number" && res.behind > 0 ? ` (tụt ${res.behind} commit)` : "";
      statusText = `Có bản cập nhật mới${behindText}${res.message ? `: ${res.message}` : ""}`;
      if (consoleEl) consoleEl.textContent += `Trạng thái: ${statusText}\n`;
      showToast(statusText);
    } else {
      statusText = res.message || "Hệ thống đang ở phiên bản mới nhất.";
      if (consoleEl) consoleEl.textContent += `Trạng thái: ${statusText}\n`;
      showToast(statusText);
    }
  } catch (err) {
    if (consoleEl) {
      consoleEl.textContent += `Không kiểm tra được: ${err.message}\n`;
    }
    showToast(`Không kiểm tra được: ${err.message}`, false, true);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = origLabel || "Kiểm tra bản cập nhật";
    }
  }
}

async function applySystemUpdate() {
  const consoleEl = document.getElementById("maintenance-console");
  const btn = document.getElementById("btn-apply-update");
  const origLabel = btn ? btn.textContent : "";

  if (btn) {
    btn.disabled = true;
    btn.textContent = "Đang kiểm tra (Dry-run)...";
  }
  if (consoleEl) {
    consoleEl.textContent = ":: [Update Preview] Đang chạy mô phỏng cập nhật (dry-run)...\n";
  }

  try {
    // Step 1: Preview update changes without applying
    const previewRes = await apiFetch("/api/system/update/apply", {
      method: "POST",
      body: JSON.stringify({ confirmed: false, dry_run: true }),
    });

    if (consoleEl && previewRes.log) {
      consoleEl.textContent += previewRes.log + "\n";
    }

    // Step 2: Require explicit confirmation before executing real update
    const proceed = confirm(
      "Đã hoàn tất chạy thử (dry-run). Hãy xem nhật ký tại Activity Console.\n\nBạn có chắc chắn muốn áp dụng cập nhật hệ thống thật ngay bây giờ?"
    );
    if (!proceed) {
      if (consoleEl) {
        consoleEl.textContent += "\n:: [Update Apply] Người dùng đã hủy thao tác cập nhật.\n";
      }
      showToast("Đã hủy áp dụng cập nhật.");
      return;
    }

    if (btn) {
      btn.textContent = "Đang áp dụng cập nhật...";
    }
    if (consoleEl) {
      consoleEl.textContent += "\n:: [Update Apply] Đang tiến hành cập nhật hệ thống...\n";
    }

    const applyRes = await apiFetch("/api/system/update/apply", {
      method: "POST",
      body: JSON.stringify({ confirmed: true, dry_run: false }),
    });

    if (consoleEl) {
      if (applyRes.log) consoleEl.textContent += applyRes.log + "\n";
      consoleEl.textContent += "\n✓ Cập nhật hệ thống thành công!\n";
    }
    showToast(applyRes.message || "Cập nhật hệ thống thành công!");
    await Promise.all([fetchSystemStatus(), fetchStateAndCatalog()]);
  } catch (err) {
    if (consoleEl) {
      if (err.data && err.data.log) {
        consoleEl.textContent += err.data.log + "\n";
      }
      consoleEl.textContent += `\n❌ Cập nhật thất bại: ${err.message}\n`;
    }
    showToast(`Cập nhật thất bại: ${err.message}`, false, true);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = origLabel || "Cập nhật hệ thống";
    }
  }
}

// -----------------------------------------------------------------------------
// 9. Power & Battery Management View
// -----------------------------------------------------------------------------
function initPowerManagement() {
  const cardEco = document.getElementById("card-profile-eco");
  const cardBal = document.getElementById("card-profile-balanced");
  const cardTurbo = document.getElementById("card-profile-turbo");
  const toggleAuto = document.getElementById("toggle-auto-60hz");
  const btnRefresh = document.getElementById("btn-refresh-power");
  const btnToggleHz = document.getElementById("btn-manual-toggle-hz");

  if (cardEco) cardEco.addEventListener("click", () => setPowerProfile("eco"));
  if (cardBal) cardBal.addEventListener("click", () => setPowerProfile("balanced"));
  if (cardTurbo) cardTurbo.addEventListener("click", () => setPowerProfile("turbo"));

  if (toggleAuto) {
    toggleAuto.addEventListener("change", (e) => {
      toggleAuto60Hz(e.target.checked);
    });
  }

  if (btnRefresh) {
    btnRefresh.addEventListener("click", () => {
      fetchPowerStatus();
    });
  }

  if (btnToggleHz) {
    btnToggleHz.addEventListener("click", () => {
      toggleRefreshRateManual();
    });
  }
}

async function fetchPowerStatus() {
  try {
    const data = await apiFetch("/api/power/status");
    if (!data) return;

    // Battery gauge
    const fillEl = document.getElementById("power-battery-fill");
    const percentEl = document.getElementById("power-battery-percent");
    const pct = data.battery_percent !== undefined ? data.battery_percent : 100;

    if (fillEl) {
      fillEl.style.width = `${pct}%`;
      fillEl.className = "battery-gauge-fill";
      if (data.battery_status === "Charging") {
        fillEl.classList.add("charging");
      } else if (pct <= 20) {
        fillEl.classList.add("low");
      } else if (pct <= 35) {
        fillEl.classList.add("warning");
      }
    }
    if (percentEl) {
      percentEl.textContent = `${pct}%`;
    }

    // Status metrics
    const sourceEl = document.getElementById("power-source-val");
    if (sourceEl) {
      sourceEl.textContent = data.ac_online ? "🔌 Cắm sạc AC (Mains)" : "🔋 Dùng pin (Battery)";
      sourceEl.style.color = data.ac_online ? "var(--accent)" : "#ffcc66";
    }

    const statusEl = document.getElementById("power-status-val");
    if (statusEl) {
      statusEl.textContent = data.battery_status || "--";
    }

    const wattsEl = document.getElementById("power-watts-val");
    if (wattsEl) {
      wattsEl.textContent = `${data.power_watts !== undefined ? data.power_watts : 0} W`;
    }

    const timeEl = document.getElementById("power-time-val");
    if (timeEl) {
      timeEl.textContent = data.time_remaining || "--";
    }

    const hzEl = document.getElementById("power-hz-val");
    if (hzEl) {
      hzEl.textContent = `${data.monitor_name || "Display"} • ${data.current_hz || 60} Hz (Tối đa ${data.max_hz || 60} Hz)`;
    }

    // Active Profile Card
    const curProfile = (data.profile || "balanced").toLowerCase();
    ["eco", "balanced", "turbo"].forEach(p => {
      const card = document.getElementById(`card-profile-${p}`);
      if (card) {
        card.classList.toggle("active", p === curProfile);
      }
    });

    // Auto 60Hz Toggle
    const toggleAuto = document.getElementById("toggle-auto-60hz");
    if (toggleAuto && data.auto_60hz !== undefined) {
      toggleAuto.checked = Boolean(data.auto_60hz);
    }
  } catch (err) {
    console.error("Failed to fetch power status:", err);
    showToast(`Lỗi tải trạng thái nguồn điện: ${err.message}`, false, true);
  }
}

async function setPowerProfile(profile) {
  try {
    const res = await apiFetch("/api/power/profile", {
      method: "POST",
      body: JSON.stringify({ profile }),
    });
    showToast(res.message || `Đã chuyển sang profile ${profile}!`);
    await fetchPowerStatus();
  } catch (err) {
    showToast(`Lỗi: ${err.message}`, false, true);
  }
}

async function toggleAuto60Hz(enabled) {
  const toggleAuto = document.getElementById("toggle-auto-60hz");
  if (toggleAuto) toggleAuto.disabled = true;
  try {
    const res = await apiFetch("/api/power/config", {
      method: "POST",
      body: JSON.stringify({ auto_60hz: enabled }),
    });
    showToast(res.message || (enabled ? "Đã bật tự động hạ 60Hz khi dùng pin" : "Đã tắt tự động 60Hz khi dùng pin"));
    await fetchPowerStatus();
  } catch (err) {
    if (toggleAuto) toggleAuto.checked = !enabled;
    showToast(`Lỗi: ${err.message}`, false, true);
  } finally {
    if (toggleAuto) toggleAuto.disabled = false;
  }
}

async function toggleRefreshRateManual() {
  const btnToggleHz = document.getElementById("btn-manual-toggle-hz");
  if (btnToggleHz) btnToggleHz.disabled = true;
  try {
    const res = await apiFetch("/api/power/toggle-hz", {
      method: "POST",
    });
    showToast(res.message || `Đã chuyển đổi tần số quét sang ${res.current_hz}Hz!`);
    await fetchPowerStatus();
  } catch (err) {
    showToast(`Lỗi: ${err.message}`, false, true);
  } finally {
    if (btnToggleHz) btnToggleHz.disabled = false;
  }
}
