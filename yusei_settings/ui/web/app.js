/**
 * yusei-settings: Application Frontend Logic
 * Manages Windows 11-style navigation, theme galleries, and 5-stage safe apply workflow.
 */

let appCatalog = {};
let activeState = {};
let currentCategory = "waybar_layouts";
let pendingApply = null;
let lastSnapshotId = null;

document.addEventListener("DOMContentLoaded", () => {
  initNavigation();
  initCategoryTabs();
  initModalActions();
  fetchStateAndCatalog();
});

// -----------------------------------------------------------------------------
// 1. Navigation & Page Switching
// -----------------------------------------------------------------------------
function initNavigation() {
  const navItems = document.querySelectorAll(".nav-item");
  const pages = document.querySelectorAll(".settings-page");

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

      if (targetPageId === "page-backup") {
        fetchSnapshots();
      }
    });
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
      fetch("/api/state").then(r => r.json()),
      fetch("/api/catalog").then(r => r.json()),
    ]);
    activeState = stateRes || {};
    appCatalog = catRes || {};
    renderGallery();
  } catch (err) {
    console.error("Failed to fetch state or catalog:", err);
  }
}

// -----------------------------------------------------------------------------
// 4. Gallery Rendering (Cards with Visual Previews)
// -----------------------------------------------------------------------------
function renderGallery() {
  const container = document.getElementById("gallery-container");
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

    // Generate Preview HTML / SVG
    let previewContent = "";
    if (item.preview_svg) {
      previewContent = item.preview_svg;
    } else if (item.relative_url) {
      previewContent = `<img src="${item.relative_url}" alt="${item.name}" loading="lazy" />`;
    } else if (item.palette) {
      // Swatches preview
      previewContent = `<div style="display:flex; gap:6px; align-items:center;">
        <span style="display:inline-block; width:28px; height:28px; border-radius:50%; background:${item.palette.background}; border:1px solid #444;"></span>
        ${(item.palette.swatches || []).slice(0, 5).map(c => `<span style="display:inline-block; width:16px; height:24px; border-radius:4px; background:${c};"></span>`).join("")}
      </div>`;
    } else {
      previewContent = `<span style="font-size:24px;">🎨</span>`;
    }

    const badgeLabel = item.position || item.theme_tag || item.style_type || (isActive ? "Đang chọn" : "Có sẵn");

    card.innerHTML = `
      <div class="card-preview-box">
        ${previewContent}
      </div>
      <div class="card-body">
        <div class="card-title-row">
          <h4 title="${item.name}">${item.name}</h4>
          <span class="card-badge ${isActive ? 'active-badge' : ''}">${badgeLabel}</span>
        </div>
        <p class="card-desc">${item.description || "Tùy chọn giao diện tương thích hoàn toàn."}</p>
      </div>
      <div class="card-footer">
        <button class="btn btn-secondary btn-preview-item" data-id="${item.id}">Xem thử</button>
        <button class="btn btn-primary ${isActive ? 'btn-disabled' : ''} btn-apply-item" data-id="${item.id}">
          ${isActive ? '✓ Đang dùng' : 'Áp dụng'}
        </button>
      </div>
    `;

    // Bind Apply Action
    const applyBtn = card.querySelector(".btn-apply-item");
    if (!isActive) {
      applyBtn.addEventListener("click", () => {
        triggerApplyWorkflow(currentCategory, item);
      });
    }

    const previewBtn = card.querySelector(".btn-preview-item");
    previewBtn.addEventListener("click", () => {
      showToast(`Đang xem thử thông số: ${item.name}`);
    });

    container.appendChild(card);
  });
}

function checkIsActive(category, itemId) {
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
    return activeState.current_wallpaper === itemId;
  }
  return false;
}

// -----------------------------------------------------------------------------
// 5. 5-Stage Safe Apply Workflow
// -----------------------------------------------------------------------------
async function triggerApplyWorkflow(category, item) {
  pendingApply = { category, item };

  try {
    // Stage 1 & 2: Call analyze API to list exact affected files
    const res = await fetch("/api/analyze", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        category: category,
        item_id: item.id,
        source_path: item.file_path,
      }),
    });
    const impact = await res.json();

    // Populate modal
    document.getElementById("modal-item-name").innerText = `${item.name} (${category})`;
    const list = document.getElementById("modal-affected-files");
    list.innerHTML = "";

    (impact.affected_files || []).forEach(f => {
      const li = document.createElement("li");
      li.innerHTML = `<strong>${f.action.toUpperCase()}</strong>: ${f.target} <br/><span style="color:var(--text-muted); font-size:11px;">&rarr; ${f.description}</span>`;
      list.appendChild(li);
    });

    // Show Modal
    document.getElementById("confirm-modal").classList.add("open");
  } catch (err) {
    alert("Lỗi khi phân tích tác động tệp tin: " + err);
  }
}

function initModalActions() {
  const modal = document.getElementById("confirm-modal");
  const cancelBtn = document.getElementById("modal-btn-cancel");
  const confirmBtn = document.getElementById("modal-btn-confirm");

  cancelBtn.addEventListener("click", () => {
    modal.classList.remove("open");
    pendingApply = null;
  });

  confirmBtn.addEventListener("click", async () => {
    if (!pendingApply) return;
    confirmBtn.innerText = "Đang áp dụng...";
    confirmBtn.disabled = true;

    try {
      // Stage 4 & 5: Apply change with explicit confirmation
      const res = await fetch("/api/apply", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          category: pendingApply.category,
          item_id: pendingApply.item.id,
          source_path: pendingApply.item.file_path,
          confirmed: true,
        }),
      });
      const result = await res.json();

      if (result.success) {
        modal.classList.remove("open");
        lastSnapshotId = result.snapshot_id;
        showToast(`Đã áp dụng thành công: ${pendingApply.item.name}!`, true);
        
        // Refresh state
        await fetchStateAndCatalog();
      } else {
        alert("Áp dụng thất bại: " + (result.message || "Lỗi không xác định"));
      }
    } catch (err) {
      alert("Lỗi kết nối tới Safety Engine: " + err);
    } finally {
      confirmBtn.innerText = "Xác Nhận Áp Dụng";
      confirmBtn.disabled = false;
      pendingApply = null;
    }
  });

  // Rollback Undo Button in Toast
  document.getElementById("toast-btn-undo").addEventListener("click", async () => {
    if (!lastSnapshotId) return;
    try {
      const res = await fetch("/api/rollback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ snapshot_id: lastSnapshotId }),
      });
      const result = await res.json();
      if (result.success) {
        showToast("Đã hoàn tác (Rollback) thành công trạng thái trước đó!");
        await fetchStateAndCatalog();
      } else {
        alert("Lỗi hoàn tác: " + result.message);
      }
    } catch (err) {
      alert("Lỗi rollback: " + err);
    }
  });
}

// -----------------------------------------------------------------------------
// 6. Snapshots List & Manual Backup
// -----------------------------------------------------------------------------
async function fetchSnapshots() {
  const container = document.getElementById("snapshots-list-container");
  try {
    const res = await fetch("/api/snapshots").then(r => r.json());
    if (!res || res.length === 0) {
      container.innerHTML = `<p style="color: var(--text-muted); font-size: 13px;">Chưa có bản snapshot sao lưu nào được ghi nhận.</p>`;
      return;
    }

    container.innerHTML = res.map(snap => `
      <div class="settings-row">
        <div class="row-label">
          <h4>${snap.snapshot_id}</h4>
          <p>Tạo lúc: ${snap.created_at} • ${snap.backed_up_files.length} tệp đã sao lưu</p>
        </div>
        <button class="btn btn-secondary btn-restore-snap" data-id="${snap.snapshot_id}">Khôi phục bản này</button>
      </div>
    `).join("");

    container.querySelectorAll(".btn-restore-snap").forEach(btn => {
      btn.addEventListener("click", async () => {
        const snapId = btn.getAttribute("data-id");
        if (confirm(`Bạn có chắc muốn khôi phục lại cấu hình từ snapshot: ${snapId}?`)) {
          const r = await fetch("/api/rollback", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ snapshot_id: snapId }),
          }).then(res => res.json());

          if (r.success) {
            showToast("Đã khôi phục thành công snapshot: " + snapId);
            fetchStateAndCatalog();
            fetchSnapshots();
          } else {
            alert("Khôi phục thất bại: " + r.message);
          }
        }
      });
    });

  } catch (err) {
    container.innerHTML = `<p style="color: #f2b8b5; font-size: 13px;">Lỗi khi tải lịch sử snapshot: ${err}</p>`;
  }
}

// -----------------------------------------------------------------------------
// 7. Toast Notification Utility
// -----------------------------------------------------------------------------
let toastTimer = null;
function showToast(message, showUndo = false) {
  const toast = document.getElementById("toast-notify");
  document.getElementById("toast-message").innerText = message;
  const undoBtn = document.getElementById("toast-btn-undo");
  undoBtn.style.display = showUndo ? "inline-block" : "none";

  toast.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.classList.remove("show");
  }, 6000);
}
