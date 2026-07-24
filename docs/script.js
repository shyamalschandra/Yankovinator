"use strict";
class YankovinatorUI {
    constructor() {
        this.observer = null;
        this.typeText = (element, text, index = 0) => {
            if (index < text.length) {
                element.textContent = text.substring(0, index + 1);
                const delay = text[index] === ' ' ? 100 : 30;
                setTimeout(() => this.typeText(element, text, index + 1), delay);
            }
        };
        this.generateBtn = document.getElementById('generateBtn');
        this.originalLyrics = document.getElementById('originalLyrics');
        this.parodyOutput = document.getElementById('parodyOutput');
        this.copyButtons = document.querySelectorAll('.copy-btn');
        this.init();
    }
    init() {
        if (this.generateBtn) {
            this.generateBtn.addEventListener('click', () => this.handleGenerate());
        }
        this.copyButtons.forEach(btn => {
            btn.addEventListener('click', () => this.handleCopy(btn));
        });
        this.initSmoothScroll();
        this.initScrollAnimations();
        this.initTypingEffect();
        this.initParallax();
        this.initSVGAnimations();
        this.initCursorEffects();
        this.initPerformanceOptimizations();
    }
    async handleGenerate() {
        if (!this.originalLyrics || !this.parodyOutput || !this.generateBtn)
            return;
        const lyrics = this.originalLyrics.value.trim();
        if (!lyrics) {
            this.showError('Please enter some lyrics first!');
            this.shakeElement(this.originalLyrics);
            return;
        }
        this.generateBtn.disabled = true;
        this.generateBtn.innerHTML = '<span class="loading"></span> <span>Generating parody...</span>';
        this.generateBtn.classList.add('generating');
        this.parodyOutput.innerHTML = '<div class="loading-state"><div class="loading-spinner"></div><p class="placeholder">✨ Creating your parody with perfect syllable matching...</p></div>';
        this.parodyOutput.classList.add('loading');
        try {
            const parody = await this.simulateParodyGeneration(lyrics);
            this.displayParody(parody);
        }
        catch (error) {
            this.showError('Failed to generate parody. Please try again.');
            console.error('Parody generation error:', error);
        }
        finally {
            this.generateBtn.disabled = false;
            this.generateBtn.innerHTML = '<span>Generate Parody</span><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12h14M12 5l7 7-7 7"/></svg>';
            this.generateBtn.classList.remove('generating');
            this.parodyOutput.classList.remove('loading');
        }
    }
    async simulateParodyGeneration(lyrics) {
        const progressSteps = [
            'Analyzing syllable structure...',
            'Detecting rhyme scheme...',
            'Generating with AI...',
            'Refining word choices...',
            'Finalizing parody...'
        ];
        for (let i = 0; i < progressSteps.length; i++) {
            await new Promise(resolve => setTimeout(resolve, 400));
            if (this.parodyOutput) {
                const progress = ((i + 1) / progressSteps.length) * 100;
                this.parodyOutput.innerHTML = `
                    <div class="loading-state">
                        <div class="loading-spinner"></div>
                        <p class="placeholder">${progressSteps[i]}</p>
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: ${progress}%"></div>
                        </div>
                    </div>
                `;
            }
        }
        const lines = lyrics.split('\n').filter(line => line.trim());
        const parodyLines = lines.map((line, index) => {
            const words = line.split(' ');
            const substituted = words.map(word => {
                const substitutions = {
                    'I': 'We',
                    'you': 'they',
                    'stay': 'play',
                    'grave': 'wave',
                    'die': 'fly',
                    'love': 'soar',
                    'want': 'need',
                    'heart': 'soul',
                    'dream': 'hope',
                    'night': 'light'
                };
                const lowerWord = word.toLowerCase().replace(/[^\w]/g, '');
                return substitutions[lowerWord] || word;
            });
            return substituted.join(' ');
        });
        return parodyLines;
    }
    displayParody(parody) {
        if (!this.parodyOutput)
            return;
        const formattedParody = parody.map(line => line.trim()).join('\n');
        this.parodyOutput.innerHTML = `<pre class="parody-text">${this.escapeHtml(formattedParody)}</pre>`;
        this.parodyOutput.style.opacity = '0';
        this.parodyOutput.style.transform = 'translateY(20px)';
        setTimeout(() => {
            if (this.parodyOutput) {
                this.parodyOutput.style.transition = 'all 0.6s cubic-bezier(0.4, 0, 0.2, 1)';
                this.parodyOutput.style.opacity = '1';
                this.parodyOutput.style.transform = 'translateY(0)';
                this.parodyOutput.classList.add('success');
                setTimeout(() => {
                    if (this.parodyOutput) {
                        this.parodyOutput.classList.remove('success');
                    }
                }, 2000);
            }
        }, 10);
    }
    showError(message) {
        if (!this.parodyOutput)
            return;
        this.parodyOutput.innerHTML = `<p class="error">❌ ${this.escapeHtml(message)}</p>`;
        this.parodyOutput.classList.add('error-shake');
        setTimeout(() => {
            if (this.parodyOutput) {
                this.parodyOutput.classList.remove('error-shake');
            }
        }, 500);
    }
    shakeElement(element) {
        element.classList.add('shake');
        setTimeout(() => {
            element.classList.remove('shake');
        }, 500);
    }
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
    handleCopy(button) {
        const codeBlock = button.parentElement?.querySelector('code');
        if (!codeBlock)
            return;
        const text = codeBlock.textContent || '';
        navigator.clipboard.writeText(text).then(() => {
            button.classList.add('copied');
            const originalHTML = button.innerHTML;
            button.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6L9 17l-5-5"/></svg>';
            this.createRipple(button);
            setTimeout(() => {
                button.classList.remove('copied');
                button.innerHTML = originalHTML;
            }, 2000);
        }).catch(err => {
            console.error('Failed to copy:', err);
            this.showError('Failed to copy to clipboard');
        });
    }
    createRipple(element) {
        const ripple = document.createElement('span');
        ripple.classList.add('ripple');
        element.appendChild(ripple);
        setTimeout(() => {
            ripple.remove();
        }, 600);
    }
    initSmoothScroll() {
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', (e) => {
                const href = e.currentTarget.getAttribute('href');
                if (!href || href === '#')
                    return;
                e.preventDefault();
                const target = document.querySelector(href);
                if (target) {
                    const offset = 80;
                    const targetPosition = target.offsetTop - offset;
                    window.scrollTo({
                        top: targetPosition,
                        behavior: 'smooth'
                    });
                }
            });
        });
    }
    initScrollAnimations() {
        const observerOptions = {
            threshold: 0.1,
            rootMargin: '0px 0px -100px 0px'
        };
        this.observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('animate-in');
                }
            });
        }, observerOptions);
        document.querySelectorAll('.feature-card, .step-card').forEach(card => {
            this.observer?.observe(card);
        });
        document.querySelectorAll('section').forEach(section => {
            this.observer?.observe(section);
        });
    }
    initTypingEffect() {
        const typingElements = document.querySelectorAll('.typing');
        typingElements.forEach((element, index) => {
            const text = element.textContent || '';
            element.textContent = '';
            element.classList.remove('typing');
            setTimeout(() => {
                this.typeText(element, text);
            }, index * 800);
        });
    }
    initParallax() {
        let ticking = false;
        window.addEventListener('scroll', () => {
            if (!ticking) {
                window.requestAnimationFrame(() => {
                    const scrolled = window.pageYOffset;
                    const parallaxElements = document.querySelectorAll('.floating-circle');
                    parallaxElements.forEach((element, index) => {
                        const speed = 0.3 + (index * 0.15);
                        const yPos = -(scrolled * speed);
                        element.style.transform = `translateY(${yPos}px)`;
                    });
                    ticking = false;
                });
                ticking = true;
            }
        }, { passive: true });
    }
    initSVGAnimations() {
        const svgIcons = document.querySelectorAll('.feature-icon svg, .doc-icon svg');
        svgIcons.forEach(icon => {
            icon.addEventListener('mouseenter', () => {
                icon.classList.add('svg-hover');
            });
            icon.addEventListener('mouseleave', () => {
                icon.classList.remove('svg-hover');
            });
        });
        const logo = document.querySelector('.logo-icon');
        if (logo) {
            let lastScroll = 0;
            window.addEventListener('scroll', () => {
                const currentScroll = window.pageYOffset;
                const scrollDelta = currentScroll - lastScroll;
                const rotation = currentScroll * 0.1 + (scrollDelta * 0.5);
                logo.style.transform = `rotate(${rotation}deg)`;
                lastScroll = currentScroll;
            }, { passive: true });
        }
        this.initNavbarScroll();
        this.initInstallTabs();
    }
    initInstallTabs() {
        const tabButtons = document.querySelectorAll('.tab-btn');
        const tabContents = document.querySelectorAll('.tab-content');
        tabButtons.forEach(button => {
            button.addEventListener('click', () => {
                const targetTab = button.getAttribute('data-tab');
                tabButtons.forEach(btn => {
                    btn.classList.remove('active');
                    btn.setAttribute('aria-selected', 'false');
                });
                tabContents.forEach(content => content.classList.remove('active'));
                button.classList.add('active');
                button.setAttribute('aria-selected', 'true');
                const targetContent = document.getElementById(`${targetTab}-tab`);
                if (targetContent) {
                    targetContent.classList.add('active');
                }
            });
        });
    }
    initNavbarScroll() {
        const navbar = document.querySelector('.navbar');
        if (!navbar)
            return;
        let lastScroll = 0;
        window.addEventListener('scroll', () => {
            const currentScroll = window.pageYOffset;
            if (currentScroll > 50) {
                navbar.classList.add('scrolled');
            }
            else {
                navbar.classList.remove('scrolled');
            }
            lastScroll = currentScroll;
        }, { passive: true });
    }
    initCursorEffects() {
        if (window.innerWidth > 768) {
            let cursorTrail = [];
            const maxTrails = 5;
            document.addEventListener('mousemove', (e) => {
                const trail = document.createElement('div');
                trail.className = 'cursor-trail';
                trail.style.left = e.clientX + 'px';
                trail.style.top = e.clientY + 'px';
                document.body.appendChild(trail);
                cursorTrail.push(trail);
                if (cursorTrail.length > maxTrails) {
                    const oldTrail = cursorTrail.shift();
                    if (oldTrail) {
                        oldTrail.remove();
                    }
                }
                setTimeout(() => {
                    trail.style.opacity = '0';
                    trail.style.transform = 'scale(0)';
                    setTimeout(() => trail.remove(), 300);
                }, 100);
            }, { passive: true });
        }
    }
    initPerformanceOptimizations() {
        if ('IntersectionObserver' in window) {
            const imageObserver = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        const img = entry.target;
                        if (img.dataset.src) {
                            img.src = img.dataset.src;
                            img.removeAttribute('data-src');
                            imageObserver.unobserve(img);
                        }
                    }
                });
            });
            document.querySelectorAll('img[data-src]').forEach(img => {
                imageObserver.observe(img);
            });
        }
        let scrollTimeout;
        window.addEventListener('scroll', () => {
            if (scrollTimeout) {
                window.cancelAnimationFrame(scrollTimeout);
            }
            scrollTimeout = window.requestAnimationFrame(() => {
            });
        }, { passive: true });
    }
}
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        new YankovinatorUI();
    });
}
else {
    new YankovinatorUI();
}
const style = document.createElement('style');
style.textContent = `
    .parody-text {
        color: var(--text-primary);
        line-height: 1.8;
        margin: 0;
        font-size: 1.1rem;
    }
    
    .error {
        color: #f5576c;
        font-style: italic;
        font-size: 1.1rem;
        padding: 1rem;
        background: rgba(245, 87, 108, 0.1);
        border-radius: 8px;
        border-left: 4px solid #f5576c;
    }
    
    .error-shake {
        animation: shake 0.5s ease;
    }
    
    @keyframes shake {
        0%, 100% { transform: translateX(0); }
        25% { transform: translateX(-10px); }
        75% { transform: translateX(10px); }
    }
    
    .shake {
        animation: shake 0.5s ease;
    }
    
    .feature-card,
    .step-card {
        opacity: 0;
        transform: translateY(40px);
        transition: all 0.6s cubic-bezier(0.4, 0, 0.2, 1);
    }
    
    .feature-card.animate-in,
    .step-card.animate-in {
        opacity: 1;
        transform: translateY(0);
    }
    
    .svg-hover {
        transform: scale(1.15) rotate(5deg) !important;
        transition: transform 0.4s cubic-bezier(0.4, 0, 0.2, 1) !important;
    }
    
    .feature-icon svg,
    .doc-icon svg {
        transition: transform 0.4s cubic-bezier(0.4, 0, 0.2, 1);
    }
    
    .loading-state {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        padding: 2rem;
        gap: 1.5rem;
    }
    
    .loading-spinner {
        width: 50px;
        height: 50px;
        border: 4px solid rgba(102, 126, 234, 0.2);
        border-top-color: #667eea;
        border-radius: 50%;
        animation: spin 1s linear infinite;
    }
    
    .progress-bar {
        width: 100%;
        max-width: 300px;
        height: 4px;
        background: rgba(255, 255, 255, 0.1);
        border-radius: 2px;
        overflow: hidden;
    }
    
    .progress-fill {
        height: 100%;
        background: var(--primary-gradient);
        border-radius: 2px;
        transition: width 0.3s ease;
    }
    
    .parody-output.success {
        animation: successPulse 0.6s ease;
    }
    
    @keyframes successPulse {
        0%, 100% { transform: scale(1); }
        50% { transform: scale(1.02); }
    }
    
    .btn.generating {
        pointer-events: none;
        opacity: 0.8;
    }
    
    .cursor-trail {
        position: fixed;
        width: 8px;
        height: 8px;
        background: rgba(102, 126, 234, 0.6);
        border-radius: 50%;
        pointer-events: none;
        z-index: 9999;
        transform: translate(-50%, -50%);
        transition: opacity 0.3s, transform 0.3s;
    }
    
    .ripple {
        position: absolute;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.6);
        transform: scale(0);
        animation: rippleAnimation 0.6s ease-out;
        pointer-events: none;
        width: 100px;
        height: 100px;
        top: 50%;
        left: 50%;
        margin-top: -50px;
        margin-left: -50px;
    }
    
    @keyframes rippleAnimation {
        to {
            transform: scale(2);
            opacity: 0;
        }
    }
`;
document.head.appendChild(style);
