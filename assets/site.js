/* ══════════════════════════════════════════════════════════════════════════
   Car Collector Studio — shared site behaviour (nav, mobile nav, reveal
   animation, auth modal, FAQ accordion, nav dropdown). Loaded on every page
   so the marketing site behaves as one product rather than per-page copies.
   ══════════════════════════════════════════════════════════════════════════ */

/* Scroll-in reveal */
const observer = new IntersectionObserver((entries) => {
  entries.forEach(e => {
    if (e.isIntersecting) {
      e.target.classList.add('visible');
      observer.unobserve(e.target);
    }
  });
}, { threshold: 0.1 });
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.reveal').forEach(el => observer.observe(el));
  const yearEl = document.getElementById('footer-year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();
});

/* Nav contrast on scroll */
const siteNav = document.getElementById('site-nav');
function onNavScroll() {
  if (siteNav) siteNav.classList.toggle('nav-scrolled', window.scrollY > 32);
}
onNavScroll();
window.addEventListener('scroll', onNavScroll, { passive: true });

/* Mobile nav drawer */
const mobileNav = document.getElementById('mobile-nav');
const mobileNavOverlay = document.getElementById('mobile-nav-overlay');
const navBurger = document.getElementById('nav-burger');
function toggleMobileNav(open) {
  if (!mobileNav || !mobileNavOverlay || !navBurger) return;
  mobileNav.classList.toggle('open', open);
  mobileNavOverlay.classList.toggle('open', open);
  navBurger.setAttribute('aria-expanded', open ? 'true' : 'false');
  document.body.style.overflow = open ? 'hidden' : '';
}

/* Desktop nav dropdowns (Product / Resources) — click + keyboard, closes on
   outside click or Escape. Hover-to-open is handled purely in CSS for
   fine-pointer devices; this JS covers click/touch/keyboard. */
document.addEventListener('DOMContentLoaded', () => {
  const drops = document.querySelectorAll('.nav-drop');
  drops.forEach(drop => {
    const trigger = drop.querySelector('.nav-drop-trigger');
    if (!trigger) return;
    trigger.addEventListener('click', (e) => {
      e.stopPropagation();
      const isOpen = drop.classList.contains('open');
      drops.forEach(d => { d.classList.remove('open'); d.querySelector('.nav-drop-trigger')?.setAttribute('aria-expanded', 'false'); });
      if (!isOpen) {
        drop.classList.add('open');
        trigger.setAttribute('aria-expanded', 'true');
      }
    });
  });
  document.addEventListener('click', () => {
    drops.forEach(d => { d.classList.remove('open'); d.querySelector('.nav-drop-trigger')?.setAttribute('aria-expanded', 'false'); });
  });
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    toggleMobileNav(false);
    closeAuth();
    document.querySelectorAll('.nav-drop.open').forEach(d => {
      d.classList.remove('open');
      d.querySelector('.nav-drop-trigger')?.setAttribute('aria-expanded', 'false');
    });
  }
});

/* FAQ accordion */
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.faq-item').forEach(item => {
    const q = item.querySelector('.faq-q');
    const a = item.querySelector('.faq-a');
    if (!q || !a) return;
    q.addEventListener('click', () => {
      const isOpen = item.classList.contains('open');
      q.setAttribute('aria-expanded', (!isOpen).toString());
      item.classList.toggle('open', !isOpen);
      a.style.maxHeight = !isOpen ? a.scrollHeight + 'px' : '0px';
    });
  });
});

/* ══════════════════════════════════════════════════════════════════════════
   Auth — the landing page is the single entry point. Sign-up and sign-in
   happen here, then the user is handed to the app.

   NOTE ON THE HANDOFF: Supabase keeps its session in localStorage, which is
   scoped to the ORIGIN. A session created on carcollectorstudio.com is NOT
   visible at app.carcollectorstudio.com. So we pass the tokens in the URL
   FRAGMENT (after #), which browsers never send to the server and which
   supabase-js picks up automatically via detectSessionInUrl. The app strips
   it from the address bar on arrival.
   ══════════════════════════════════════════════════════════════════════════ */

const SUPABASE_URL = 'https://soxhpqgyffwsnneznpdm.supabase.co';
const SUPABASE_KEY = 'sb_publishable_uv2RmHZiI-GfJvwq6A4WAg_H3cdW0ZI';
const APP_URL      = 'https://app.carcollectorstudio.com';

let authMode = 'signup';

function openAuth(mode, prefillEmail) {
  setMode(mode || 'signup');
  if (prefillEmail) document.getElementById('auth-email').value = prefillEmail;
  document.getElementById('auth-overlay').classList.add('open');
  setTimeout(() => {
    const f = prefillEmail ? 'auth-password' : (authMode === 'signup' ? 'auth-name' : 'auth-email');
    document.getElementById(f).focus();
  }, 60);
}

function closeAuth() {
  document.getElementById('auth-overlay').classList.remove('open');
  showMsg('', null);
}

function setMode(mode) {
  authMode = mode;
  const signup = mode === 'signup';
  document.getElementById('auth-title').textContent = signup ? 'Start your free trial' : 'Welcome back';
  document.getElementById('auth-sub').textContent   = signup
    ? '14 days free · No credit card required'
    : 'Sign in to your collection';
  document.getElementById('name-field').style.display = signup ? 'block' : 'none';
  document.getElementById('auth-submit').textContent  = signup ? 'Create account' : 'Sign in';
  document.getElementById('auth-password').setAttribute('autocomplete', signup ? 'new-password' : 'current-password');
  document.getElementById('auth-switch').innerHTML = signup
    ? 'Already have an account? <a onclick="setMode(\'signin\')">Sign in</a>'
    : "Don't have an account? <a onclick=\"setMode('signup')\">Start free trial</a>";
  document.getElementById('auth-forgot').style.display = signup ? 'none' : 'block';
  showMsg('', null);
}

function showMsg(text, kind) {
  const el = document.getElementById('auth-msg');
  el.textContent = text;
  el.className = 'auth-msg' + (kind ? ' ' + kind : '');
}

function busy(on, label) {
  const b = document.getElementById('auth-submit');
  b.disabled = on;
  b.textContent = on ? 'Please wait…' : label;
}

async function submitAuth(e) {
  e.preventDefault();
  const email    = document.getElementById('auth-email').value.trim();
  const password = document.getElementById('auth-password').value;
  const name     = document.getElementById('auth-name').value.trim();
  const signup   = authMode === 'signup';
  busy(true);
  showMsg('', null);

  try {
    const endpoint = signup ? '/auth/v1/signup' : '/auth/v1/token?grant_type=password';
    const body = signup
      ? { email, password, data: { full_name: name } }
      : { email, password };

    const res = await fetch(SUPABASE_URL + endpoint, {
      method: 'POST',
      headers: { 'apikey': SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json();

    if (!res.ok) {
      showMsg(data.error_description || data.msg || data.message || 'Something went wrong', 'error');
      busy(false, signup ? 'Create account' : 'Sign in');
      return;
    }

    // Signup with email confirmation on: no session is returned yet.
    if (!data.access_token) {
      showMsg('Check your email to confirm your account, then sign in. '
            + 'It may land in your spam folder.', 'ok');
      busy(false, 'Create account');
      return;
    }

    handoffToApp(data.access_token, data.refresh_token);
  } catch (err) {
    showMsg('Network error: ' + err.message, 'error');
    busy(false, signup ? 'Create account' : 'Sign in');
  }
}

function handoffToApp(accessToken, refreshToken) {
  showMsg('Signed in — taking you to your collection…', 'ok');
  const frag = new URLSearchParams({
    access_token:  accessToken,
    refresh_token: refreshToken,
    token_type:    'bearer',
    type:          'signin',
  });
  window.location.href = APP_URL + '/#' + frag.toString();
}

async function sendReset() {
  const email = document.getElementById('auth-email').value.trim();
  if (!email) { showMsg('Enter your email address first', 'error'); return; }
  try {
    const res = await fetch(SUPABASE_URL + '/auth/v1/recover', {
      method: 'POST',
      headers: { 'apikey': SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, redirect_to: APP_URL + '/reset-password' }),
    });
    if (res.ok) showMsg('Password reset link sent — check your email (and spam).', 'ok');
    else showMsg('Could not send reset email', 'error');
  } catch (err) {
    showMsg('Network error: ' + err.message, 'error');
  }
}
