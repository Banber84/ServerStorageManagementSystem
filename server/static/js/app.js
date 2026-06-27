(function () {
  const formatter = new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });

  document.querySelectorAll("time[data-time]").forEach((node) => {
    const raw = node.dataset.time;
    if (!raw) return;
    const date = new Date(raw);
    if (Number.isNaN(date.getTime())) return;
    node.textContent = formatter.format(date).replace(/\//g, "-");
    node.title = raw;
  });

  const labelMap = {
    login: "登录",
    mount: "挂载",
    system: "系统",
    sync: "同步",
    agent: "Agent",
    storage: "存储",
    quota: "配额",
    user: "用户",
    error: "错误",
    warning: "警告",
    info: "信息",
  };

  const levelMap = {
    warn: ["warning", "warn", "offline", "exceeded"],
    error: ["error", "fail", "failed", "denied"],
  };

  function logLevel(type, message) {
    const text = `${type || ""} ${message || ""}`.toLowerCase();
    if (levelMap.error.some((key) => text.includes(key))) return ["danger", "ERROR"];
    if (levelMap.warn.some((key) => text.includes(key))) return ["warning", "WARN"];
    return ["info", "INFO"];
  }

  document.querySelectorAll("[data-log-type-label]").forEach((node) => {
    const raw = node.dataset.logType || "";
    const key = raw.toLowerCase();
    node.textContent = labelMap[key] || raw || "未分类";
  });

  document.querySelectorAll("[data-log-level]").forEach((node) => {
    const row = node.closest("[data-log-row]");
    const type = row ? row.dataset.logType || "" : "";
    const message = row ? row.dataset.logMessage || "" : "";
    const [className, label] = logLevel(type, message);
    node.className = `badge ${className}`;
    node.textContent = label;
    if (row) {
      row.dataset.logLevel = label;
    }
  });

  const logFilters = document.querySelector("[data-log-filters]");
  if (logFilters) {
    const typeInput = logFilters.querySelector("[data-filter-type]");
    const levelInput = logFilters.querySelector("[data-filter-level]");
    const keywordInput = logFilters.querySelector("[data-filter-keyword]");
    const keyOnlyInput = logFilters.querySelector("[data-filter-key-only]");
    const rows = Array.from(document.querySelectorAll("[data-log-row]"));

    const applyFilters = () => {
      const type = typeInput ? typeInput.value.toLowerCase() : "";
      const level = levelInput ? levelInput.value.toUpperCase() : "";
      const keyword = keywordInput ? keywordInput.value.trim().toLowerCase() : "";
      const keyOnly = keyOnlyInput ? keyOnlyInput.checked : false;

      rows.forEach((row) => {
        const rowType = (row.dataset.logType || "").toLowerCase();
        const rowLevel = (row.dataset.logLevel || "INFO").toUpperCase();
        const rowText = row.textContent.toLowerCase();
        const visible =
          (!type || rowType === type) &&
          (!level || rowLevel === level) &&
          (!keyOnly || rowLevel === "WARN" || rowLevel === "ERROR") &&
          (!keyword || rowText.includes(keyword));
        row.classList.toggle("is-hidden", !visible);
      });
    };

    [typeInput, levelInput, keywordInput, keyOnlyInput].forEach((input) => {
      if (!input) return;
      input.addEventListener("input", applyFilters);
      input.addEventListener("change", applyFilters);
    });
    applyFilters();
  });

  document.querySelectorAll("form[data-confirm]").forEach((form) => {
    form.addEventListener("submit", (event) => {
      const message = form.dataset.confirm || "确认执行该操作？";
      if (!window.confirm(message)) {
        event.preventDefault();
      }
    });
  });
})();
