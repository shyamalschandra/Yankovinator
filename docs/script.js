"use strict";
class YankovinatorUI {
    constructor() {
        this.generateBtn = document.getElementById("generateBtn");
        this.originalLyrics = document.getElementById("originalLyrics");
        this.parodyOutput = document.getElementById("parodyOutput");
        this.init();
    }
    init() {
        this.initTabs();
        this.initCopy();
        this.initSmoothScroll();
        this.initHeroTypewriter();
        if (this.generateBtn) {
            this.generateBtn.addEventListener("click", () => void this.handleGenerate());
        }
    }
    initTabs() {
        const buttons = document.querySelectorAll(".seg[data-tab]");
        buttons.forEach((button) => {
            button.addEventListener("click", () => {
                const target = button.getAttribute("data-tab");
                if (!target)
                    return;
                buttons.forEach((b) => {
                    b.classList.toggle("active", b === button);
                    b.setAttribute("aria-selected", b === button ? "true" : "false");
                });
                document.querySelectorAll(".tab-panel").forEach((panel) => {
                    const on = panel.id === `${target}-tab`;
                    panel.classList.toggle("active", on);
                    panel.hidden = !on;
                });
            });
        });
    }
    initCopy() {
        document.querySelectorAll(".copy-btn").forEach((btn) => {
            btn.addEventListener("click", async () => {
                const text = btn.getAttribute("data-copy") ?? "";
                try {
                    await navigator.clipboard.writeText(text);
                    const prev = btn.textContent;
                    btn.textContent = "Copied";
                    btn.classList.add("copied");
                    window.setTimeout(() => {
                        btn.textContent = prev;
                        btn.classList.remove("copied");
                    }, 1400);
                }
                catch {
                    btn.textContent = "Failed";
                }
            });
        });
    }
    initSmoothScroll() {
        document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
            anchor.addEventListener("click", (event) => {
                const id = anchor.getAttribute("href");
                if (!id || id === "#")
                    return;
                const el = document.querySelector(id);
                if (!el)
                    return;
                event.preventDefault();
                el.scrollIntoView({ behavior: "smooth", block: "start" });
            });
        });
    }
    initHeroTypewriter() {
        const host = document.querySelector(".typed");
        if (!host)
            return;
        const raw = host.getAttribute("data-lines");
        if (!raw)
            return;
        let lines = [];
        try {
            lines = JSON.parse(raw);
        }
        catch {
            return;
        }
        if (!lines.length)
            return;
        let lineIndex = 0;
        let charIndex = 0;
        let deleting = false;
        const tick = () => {
            const current = lines[lineIndex] ?? "";
            if (!deleting) {
                charIndex = Math.min(charIndex + 1, current.length);
                host.textContent = current.slice(0, charIndex);
                if (charIndex === current.length) {
                    deleting = true;
                    window.setTimeout(tick, 1600);
                    return;
                }
            }
            else {
                charIndex = Math.max(charIndex - 1, 0);
                host.textContent = current.slice(0, charIndex);
                if (charIndex === 0) {
                    deleting = false;
                    lineIndex = (lineIndex + 1) % lines.length;
                }
            }
            window.setTimeout(tick, deleting ? 22 : 36);
        };
        tick();
    }
    async handleGenerate() {
        if (!this.originalLyrics || !this.parodyOutput || !this.generateBtn)
            return;
        const lyrics = this.originalLyrics.value.trim();
        if (!lyrics) {
            this.parodyOutput.innerHTML = `<p class="placeholder">Enter a couple of lines first.</p>`;
            return;
        }
        this.generateBtn.disabled = true;
        this.generateBtn.textContent = "Generating…";
        this.parodyOutput.innerHTML = `<p class="placeholder">Matching syllables…</p>`;
        await new Promise((r) => window.setTimeout(r, 700));
        const sample = lyrics
            .split("\n")
            .filter(Boolean)
            .map((line) => this.illustrativeTwist(line));
        this.parodyOutput.innerHTML = sample.map((l) => `<p class="line">${this.escape(l)}</p>`).join("");
        this.generateBtn.disabled = false;
        this.generateBtn.textContent = "Generate sample";
    }
    illustrativeTwist(line) {
        return line
            .replace(/long/gi, "swift")
            .replace(/time/gi, "climb")
            .replace(/touchdown/gi, "splashdown")
            .replace(/gonna/gi, "bound to");
    }
    escape(value) {
        return value
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }
}
document.addEventListener("DOMContentLoaded", () => {
    new YankovinatorUI();
});
