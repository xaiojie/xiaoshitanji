/* 小食痰记 · 官网交互 */

/* 下载地址集中配置：App Store 正式链接填在这里即可全站生效。
   留空时按钮保持禁用状态，显示「即将上线」。 */
const DOWNLOAD_URL = "";
const DOWNLOAD_LABEL = "在 App Store 下载";

/* ---------- 下载入口 ---------- */

function hydrateDownload() {
  const nodes = document.querySelectorAll("[data-download]");
  const ready = DOWNLOAD_URL.trim().length > 0;

  nodes.forEach((node) => {
    if (!ready) {
      if (node.tagName === "BUTTON") {
        node.disabled = true;
      } else {
        node.setAttribute("aria-disabled", "true");
        node.setAttribute("role", "link");
        node.setAttribute("tabindex", "-1");
        node.addEventListener("click", (event) => event.preventDefault());
      }
      return;
    }

    if (node.tagName === "BUTTON") {
      const link = document.createElement("a");
      link.className = node.className;
      link.href = DOWNLOAD_URL;
      link.rel = "noreferrer";
      link.setAttribute("aria-label", `${DOWNLOAD_LABEL}（App Store）`);
      const main = node.querySelector(".cta__main");
      link.innerHTML = `<span class="cta__main">${DOWNLOAD_LABEL}</span>`;
      if (main) link.setAttribute("data-label", main.textContent.trim());
      node.replaceWith(link);
    } else {
      node.href = DOWNLOAD_URL;
      node.removeAttribute("aria-disabled");
      const main = node.querySelector(".cta__main");
      if (main) main.textContent = DOWNLOAD_LABEL;
    }
  });
}

/* ---------- 手机菜单 ---------- */

function setupMenu() {
  const toggle = document.querySelector(".menu-toggle");
  const panel = document.getElementById("mobile-menu");
  if (!toggle || !panel) return;

  const setOpen = (open, { restoreFocus = false } = {}) => {
    toggle.setAttribute("aria-expanded", String(open));
    toggle.setAttribute("aria-label", open ? "关闭菜单" : "打开菜单");
    panel.hidden = !open;
    document.body.classList.toggle("menu-open", open);
    if (!open && restoreFocus) toggle.focus();
  };

  toggle.addEventListener("click", () => {
    setOpen(toggle.getAttribute("aria-expanded") !== "true");
  });

  panel.addEventListener("click", (event) => {
    if (event.target.closest("a")) setOpen(false);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
      setOpen(false, { restoreFocus: true });
    }
  });

  window.addEventListener("resize", () => {
    if (window.innerWidth > 767) setOpen(false);
  });
}

/* ---------- 界面一览：标签与横滑 ---------- */

function setupTabs() {
  const root = document.querySelector("[data-tabs]");
  if (!root) return;

  const tabs = Array.from(root.querySelectorAll('[role="tab"]'));
  const panels = tabs.map((tab) => document.getElementById(tab.getAttribute("aria-controls")));
  const track = root.querySelector(".tabs__track");
  const viewport = root.querySelector(".tabs__viewport");
  if (!tabs.length || !track || !viewport) return;

  let index = 0;

  const render = (next, { focus = false } = {}) => {
    index = (next + tabs.length) % tabs.length;
    tabs.forEach((tab, i) => {
      const active = i === index;
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
      const panel = panels[i];
      if (!panel) return;
      panel.removeAttribute("hidden");
      panel.toggleAttribute("inert", !active);
    });
    track.style.transform = `translateX(-${index * 100}%)`;
    if (focus) tabs[index].focus();
  };

  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => render(i));
    tab.addEventListener("keydown", (event) => {
      const map = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 };
      if (event.key in map) {
        event.preventDefault();
        render(map[event.key], { focus: true });
      }
    });
  });

  /* 触摸横滑：限制在组件内部，纵向滚动不受影响 */
  let startX = 0;
  let startY = 0;
  let dragging = false;

  viewport.addEventListener("touchstart", (event) => {
    if (event.touches.length !== 1) return;
    startX = event.touches[0].clientX;
    startY = event.touches[0].clientY;
    dragging = true;
  }, { passive: true });

  viewport.addEventListener("touchend", (event) => {
    if (!dragging) return;
    dragging = false;
    const touch = event.changedTouches[0];
    const dx = touch.clientX - startX;
    const dy = touch.clientY - startY;
    if (Math.abs(dx) > 44 && Math.abs(dx) > Math.abs(dy) * 1.4) {
      render(index + (dx < 0 ? 1 : -1));
    }
  }, { passive: true });

  render(0);
}

/* ---------- 截图灯箱 ---------- */

function setupLightbox() {
  const dialog = document.getElementById("lightbox");
  if (!dialog) return;

  const image = dialog.querySelector(".lightbox__image");
  const close = dialog.querySelector(".lightbox__close");
  let trigger = null;

  document.querySelectorAll("[data-lightbox]").forEach((button) => {
    button.addEventListener("click", () => {
      trigger = button;
      image.src = button.getAttribute("data-lightbox");
      image.alt = button.getAttribute("data-alt") || image.alt;
      const scroll = window.scrollY;
      dialog.showModal();
      dialog.dataset.scroll = String(scroll);
    });
  });

  const dismiss = () => dialog.close();

  close.addEventListener("click", dismiss);
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dismiss();
  });
  dialog.addEventListener("close", () => {
    image.removeAttribute("src");
    const scroll = Number(dialog.dataset.scroll || 0);
    window.scrollTo({ top: scroll, behavior: "instant" in window ? "instant" : "auto" });
    if (trigger) trigger.focus({ preventScroll: true });
    trigger = null;
  });
}

/* ---------- 入场动效 ---------- */

function setupReveal() {
  const targets = document.querySelectorAll(".section__copy, .shot--main, .column, .tabs, .note");
  if (!targets.length) return;

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduced || !("IntersectionObserver" in window)) return;

  targets.forEach((el) => el.classList.add("reveal"));

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-in");
        observer.unobserve(entry.target);
      }
    });
  }, { rootMargin: "0px 0px -6% 0px", threshold: 0.05 });

  targets.forEach((el) => observer.observe(el));
}

hydrateDownload();
setupMenu();
setupTabs();
setupLightbox();
setupReveal();
