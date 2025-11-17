// TypeScript source for Yankovinator homepage interactivity
// Copyright (C) 2025, Shyamal Suhana Chandra
// Enhanced with modern UX patterns and animations

interface ParodyResponse {
    success: boolean;
    parody?: string[];
    error?: string;
}

class YankovinatorUI {
    private generateBtn: HTMLButtonElement | null;
    private originalLyrics: HTMLTextAreaElement | null;
    private parodyOutput: HTMLElement | null;
    private copyButtons: NodeListOf<HTMLButtonElement>;
    private observer: IntersectionObserver | null = null;

    constructor() {
        this.generateBtn = document.getElementById('generateBtn') as HTMLButtonElement;
        this.originalLyrics = document.getElementById('originalLyrics') as HTMLTextAreaElement;
        this.parodyOutput = document.getElementById('parodyOutput');
        this.copyButtons = document.querySelectorAll('.copy-btn');

        this.init();
    }

    private init(): void {
        // Initialize event listeners
        if (this.generateBtn) {
            this.generateBtn.addEventListener('click', () => this.handleGenerate());
        }

        // Copy button functionality with enhanced feedback
        this.copyButtons.forEach(btn => {
            btn.addEventListener('click', () => this.handleCopy(btn));
        });

        // Enhanced smooth scroll
        this.initSmoothScroll();

        // Advanced scroll animations with Intersection Observer
        this.initScrollAnimations();

        // Typing effect for code window
        this.initTypingEffect();

        // Parallax effects
        this.initParallax();

        // SVG and icon animations
        this.initSVGAnimations();

        // Cursor effects
        this.initCursorEffects();

        // Performance optimizations
        this.initPerformanceOptimizations();
    }

    private async handleGenerate(): Promise<void> {
        if (!this.originalLyrics || !this.parodyOutput || !this.generateBtn) return;

        const lyrics = this.originalLyrics.value.trim();
        if (!lyrics) {
            this.showError('Please enter some lyrics first!');
            this.shakeElement(this.originalLyrics);
            return;
        }

        // Enhanced loading state
        this.generateBtn.disabled = true;
        this.generateBtn.innerHTML = '<span class="loading"></span> <span>Generating parody...</span>';
        this.generateBtn.classList.add('generating');
        
        this.parodyOutput.innerHTML = '<div class="loading-state"><div class="loading-spinner"></div><p class="placeholder">✨ Creating your parody with perfect syllable matching...</p></div>';
        this.parodyOutput.classList.add('loading');

        try {
            // Simulate API call with progress
            const parody = await this.simulateParodyGeneration(lyrics);
            this.displayParody(parody);
        } catch (error) {
            this.showError('Failed to generate parody. Please try again.');
            console.error('Parody generation error:', error);
        } finally {
            this.generateBtn.disabled = false;
            this.generateBtn.innerHTML = '<span>Generate Parody</span><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12h14M12 5l7 7-7 7"/></svg>';
            this.generateBtn.classList.remove('generating');
            this.parodyOutput.classList.remove('loading');
        }
    }

    private async simulateParodyGeneration(lyrics: string): Promise<string[]> {
        // Enhanced simulation with progress updates
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

        // Split lyrics into lines
        const lines = lyrics.split('\n').filter(line => line.trim());
        
        // Generate a simple parody (in production, this would call the actual API)
        const parodyLines = lines.map((line, index) => {
            // Enhanced word substitution for demo
            const words = line.split(' ');
            const substituted = words.map(word => {
                const substitutions: { [key: string]: string } = {
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

    private displayParody(parody: string[]): void {
        if (!this.parodyOutput) return;

        const formattedParody = parody.map(line => line.trim()).join('\n');
        this.parodyOutput.innerHTML = `<pre class="parody-text">${this.escapeHtml(formattedParody)}</pre>`;
        
        // Enhanced fade-in animation with stagger
        this.parodyOutput.style.opacity = '0';
        this.parodyOutput.style.transform = 'translateY(20px)';
        
        setTimeout(() => {
            if (this.parodyOutput) {
                this.parodyOutput.style.transition = 'all 0.6s cubic-bezier(0.4, 0, 0.2, 1)';
                this.parodyOutput.style.opacity = '1';
                this.parodyOutput.style.transform = 'translateY(0)';
                
                // Add success animation
                this.parodyOutput.classList.add('success');
                setTimeout(() => {
                    if (this.parodyOutput) {
                        this.parodyOutput.classList.remove('success');
                    }
                }, 2000);
            }
        }, 10);
    }

    private showError(message: string): void {
        if (!this.parodyOutput) return;
        this.parodyOutput.innerHTML = `<p class="error">❌ ${this.escapeHtml(message)}</p>`;
        this.parodyOutput.classList.add('error-shake');
        setTimeout(() => {
            if (this.parodyOutput) {
                this.parodyOutput.classList.remove('error-shake');
            }
        }, 500);
    }

    private shakeElement(element: HTMLElement): void {
        element.classList.add('shake');
        setTimeout(() => {
            element.classList.remove('shake');
        }, 500);
    }

    private escapeHtml(text: string): string {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    private handleCopy(button: HTMLButtonElement): void {
        const codeBlock = button.parentElement?.querySelector('code');
        if (!codeBlock) return;

        const text = codeBlock.textContent || '';
        navigator.clipboard.writeText(text).then(() => {
            // Enhanced copy feedback
            button.classList.add('copied');
            const originalHTML = button.innerHTML;
            button.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6L9 17l-5-5"/></svg>';
            
            // Add ripple effect
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

    private createRipple(element: HTMLElement): void {
        const ripple = document.createElement('span');
        ripple.classList.add('ripple');
        element.appendChild(ripple);
        
        setTimeout(() => {
            ripple.remove();
        }, 600);
    }

    private initSmoothScroll(): void {
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', (e) => {
                const href = (e.currentTarget as HTMLAnchorElement).getAttribute('href');
                if (!href || href === '#') return;
                
                e.preventDefault();
                const target = document.querySelector(href);
                if (target) {
                    const offset = 80; // Account for fixed navbar
                    const targetPosition = (target as HTMLElement).offsetTop - offset;
                    
                    window.scrollTo({
                        top: targetPosition,
                        behavior: 'smooth'
                    });
                }
            });
        });
    }

    private initScrollAnimations(): void {
        const observerOptions: IntersectionObserverInit = {
            threshold: 0.1,
            rootMargin: '0px 0px -100px 0px'
        };

        this.observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('animate-in');
                    // Optional: unobserve after animation
                    // this.observer?.unobserve(entry.target);
                }
            });
        }, observerOptions);

        // Observe feature cards and step cards
        document.querySelectorAll('.feature-card, .step-card').forEach(card => {
            this.observer?.observe(card);
        });

        // Observe sections for fade-in
        document.querySelectorAll('section').forEach(section => {
            this.observer?.observe(section);
        });
    }

    private initTypingEffect(): void {
        const typingElements = document.querySelectorAll('.typing');
        typingElements.forEach((element, index) => {
            const text = element.textContent || '';
            element.textContent = '';
            element.classList.remove('typing');
            
            setTimeout(() => {
                this.typeText(element as HTMLElement, text);
            }, index * 800);
        });
    }

    private typeText = (element: HTMLElement, text: string, index: number = 0): void => {
        if (index < text.length) {
            element.textContent = text.substring(0, index + 1);
            const delay = text[index] === ' ' ? 100 : 30; // Faster for spaces
            setTimeout(() => this.typeText(element, text, index + 1), delay);
        }
    }

    private initParallax(): void {
        let ticking = false;

        window.addEventListener('scroll', () => {
            if (!ticking) {
                window.requestAnimationFrame(() => {
                    const scrolled = window.pageYOffset;
                    const parallaxElements = document.querySelectorAll('.floating-circle');
                    
                    parallaxElements.forEach((element, index) => {
                        const speed = 0.3 + (index * 0.15);
                        const yPos = -(scrolled * speed);
                        (element as SVGElement).style.transform = `translateY(${yPos}px)`;
                    });
                    
                    ticking = false;
                });
                ticking = true;
            }
        }, { passive: true });
    }

    private initSVGAnimations(): void {
        // Enhanced hover effects for SVG icons
        const svgIcons = document.querySelectorAll('.feature-icon svg, .doc-icon svg');
        svgIcons.forEach(icon => {
            icon.addEventListener('mouseenter', () => {
                icon.classList.add('svg-hover');
            });
            icon.addEventListener('mouseleave', () => {
                icon.classList.remove('svg-hover');
            });
        });

        // Animate logo on scroll with smooth rotation
        const logo = document.querySelector('.logo-icon');
        if (logo) {
            let lastScroll = 0;
            window.addEventListener('scroll', () => {
                const currentScroll = window.pageYOffset;
                const scrollDelta = currentScroll - lastScroll;
                const rotation = currentScroll * 0.1 + (scrollDelta * 0.5);
                (logo as SVGElement).style.transform = `rotate(${rotation}deg)`;
                lastScroll = currentScroll;
            }, { passive: true });
        }

        // Navbar scroll effect
        this.initNavbarScroll();
        
        // Tab functionality for installation methods
        this.initInstallTabs();
    }
    
    private initInstallTabs(): void {
        const tabButtons = document.querySelectorAll('.tab-btn');
        const tabContents = document.querySelectorAll('.tab-content');
        
        tabButtons.forEach(button => {
            button.addEventListener('click', () => {
                const targetTab = button.getAttribute('data-tab');
                
                // Remove active class from all buttons and contents
                tabButtons.forEach(btn => {
                    btn.classList.remove('active');
                    btn.setAttribute('aria-selected', 'false');
                });
                tabContents.forEach(content => content.classList.remove('active'));
                
                // Add active class to clicked button and corresponding content
                button.classList.add('active');
                button.setAttribute('aria-selected', 'true');
                const targetContent = document.getElementById(`${targetTab}-tab`);
                if (targetContent) {
                    targetContent.classList.add('active');
                }
            });
        });
    }

    private initNavbarScroll(): void {
        const navbar = document.querySelector('.navbar');
        if (!navbar) return;

        let lastScroll = 0;
        window.addEventListener('scroll', () => {
            const currentScroll = window.pageYOffset;
            
            if (currentScroll > 50) {
                navbar.classList.add('scrolled');
            } else {
                navbar.classList.remove('scrolled');
            }
            
            lastScroll = currentScroll;
        }, { passive: true });
    }

    private initCursorEffects(): void {
        // Add custom cursor trail on desktop
        if (window.innerWidth > 768) {
            let cursorTrail: HTMLElement[] = [];
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

    private initPerformanceOptimizations(): void {
        // Lazy load images if any are added later
        if ('IntersectionObserver' in window) {
            const imageObserver = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        const img = entry.target as HTMLImageElement;
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

        // Debounce scroll events
        let scrollTimeout: number;
        window.addEventListener('scroll', () => {
            if (scrollTimeout) {
                window.cancelAnimationFrame(scrollTimeout);
            }
            scrollTimeout = window.requestAnimationFrame(() => {
                // Scroll-based animations handled here
            });
        }, { passive: true });
    }
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        new YankovinatorUI();
    });
} else {
    new YankovinatorUI();
}

// Add enhanced CSS classes for animations
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
