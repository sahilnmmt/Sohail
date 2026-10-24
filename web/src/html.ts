// Tiny rendering helpers. Every value that came from a user goes through esc().
export function esc(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export const $ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) =>
  root.querySelector(sel) as T;
export const $$ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) =>
  Array.from(root.querySelectorAll(sel)) as T[];

/** Run an async action from a form or button, showing errors in `errorEl`. */
export async function attempt(button: HTMLButtonElement | null, errorEl: Element | null, fn: () => Promise<void>) {
  if (errorEl) errorEl.textContent = '';
  const label = button?.textContent;
  if (button) {
    button.disabled = true;
    button.textContent = 'Working…';
  }
  try {
    await fn();
  } catch (e) {
    if (errorEl) errorEl.textContent = describeError(e);
    else console.error(e);
  } finally {
    if (button && button.isConnected) {
      button.disabled = false;
      button.textContent = label ?? '';
    }
  }
}

const AUTH_MESSAGES: Record<string, string> = {
  'auth/email-already-in-use': 'An account with this email already exists. Sign in instead.',
  'auth/invalid-credential': 'Email or password is wrong.',
  'auth/wrong-password': 'Email or password is wrong.',
  'auth/user-not-found': 'Email or password is wrong.',
  'auth/invalid-email': 'That email address does not look right.',
  'auth/weak-password': 'Use a password with at least 8 characters.',
  'auth/missing-password': 'Enter your password.',
  'auth/too-many-requests': 'Too many attempts. Wait a few minutes and try again.',
  'auth/popup-closed-by-user': 'The Google window was closed before signing in.',
  'auth/network-request-failed': 'No connection to Firebase. Check your internet connection.',
  'permission-denied': 'You do not have permission to do that.',
  unavailable: 'No connection to the database. Check your internet connection.',
};

export function describeError(e: unknown): string {
  const code = (e as { code?: string })?.code ?? '';
  if (AUTH_MESSAGES[code]) return AUTH_MESSAGES[code];
  if (e instanceof Error && e.message && !code) return e.message;
  return `Something went wrong (${code || 'unknown error'}).`;
}

export function relativeDays(d: Date): string {
  const days = Math.ceil((d.getTime() - Date.now()) / 86_400_000);
  return days <= 1 ? 'expires within a day' : `expires in ${days} days`;
}
