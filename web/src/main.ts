import './style.css';
import {
  createUserWithEmailAndPassword,
  GoogleAuthProvider,
  onAuthStateChanged,
  sendEmailVerification,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
  updateProfile,
  type User,
} from 'firebase/auth';
import { auth, usingEmulators } from './firebase';
import * as data from './data';
import { $, $$, attempt, describeError, esc, relativeDays } from './html';

const app = $('#app');
let user: User | null = null;
// While creating an account, Firebase reports the new user before its name is
// saved; hold rendering until sign-up has finished so the name is right.
let holdRouting = false;
const PENDING_JOIN = 'sohail.pendingJoin';

// ---- routing ------------------------------------------------------------------

function go(path: string) {
  history.pushState({}, '', path);
  void route();
}
window.addEventListener('popstate', () => void route());
document.addEventListener('click', (e) => {
  const a = (e.target as HTMLElement).closest<HTMLAnchorElement>('a[data-link]');
  if (a && !e.metaKey && !e.ctrlKey) {
    e.preventDefault();
    go(a.getAttribute('href')!);
  }
});

async function route() {
  const path = location.pathname;
  const join = path.match(/^\/join\/([A-Za-z0-9-]+)$/);
  if (join) {
    const code = data.normaliseCode(join[1]);
    if (!user) {
      try { sessionStorage.setItem(PENDING_JOIN, code); } catch { /* private mode */ }
      return renderAuth('Sign in or create an account to join the family.');
    }
    try { sessionStorage.removeItem(PENDING_JOIN); } catch { /* ignore */ }
    return renderJoin(code);
  }
  if (!user) return renderAuth();
  let pending: string | null = null;
  try { pending = sessionStorage.getItem(PENDING_JOIN); sessionStorage.removeItem(PENDING_JOIN); } catch { /* ignore */ }
  if (pending) return go(`/join/${pending}`);

  const family = path.match(/^\/family\/([A-Za-z0-9]+)$/);
  if (family) return renderFamily(family[1]);
  if (path === '/account') return renderAccount();
  if (path !== '/') history.replaceState({}, '', '/');
  return renderDashboard();
}

onAuthStateChanged(auth, (u) => {
  user = u;
  if (!holdRouting) void route();
});

// ---- layout ---------------------------------------------------------------------

function shell(content: string): string {
  return `
    ${usingEmulators ? '<div class="emu">Local test mode: using the Firebase emulators, not a real project.</div>' : ''}
    <header class="top">
      <a href="/" data-link class="brand"><span class="eyes" aria-hidden="true"><i></i><i></i></span>Sohail</a>
      <nav>
        <a href="/" data-link>Families</a>
        <a href="/robot">Virtual robot</a>
        <a href="/account" data-link>Account</a>
        <button class="link" id="sign-out" type="button">Sign out</button>
      </nav>
    </header>
    <main class="page">${content}</main>`;
}

function bindShell() {
  $('#sign-out')?.addEventListener('click', () => signOut(auth).then(() => go('/')));
}

function loading() {
  app.innerHTML = shell('<p class="muted">Loading…</p>');
  bindShell();
}

function copyButton(text: string, label = 'Copy') {
  return `<button type="button" class="btn small ghost" data-copy="${esc(text)}">${esc(label)}</button>`;
}

function bindCopy(root: ParentNode = document) {
  $$<HTMLButtonElement>('[data-copy]', root).forEach((b) =>
    b.addEventListener('click', async () => {
      const text = b.dataset.copy!;
      try {
        await navigator.clipboard.writeText(text);
        const old = b.textContent;
        b.textContent = 'Copied';
        setTimeout(() => (b.textContent = old), 1500);
      } catch {
        window.prompt('Copy this:', text);
      }
    }),
  );
}

// ---- sign in / sign up ------------------------------------------------------------

function renderAuth(note = '') {
  app.innerHTML = `
    ${usingEmulators ? '<div class="emu">Local test mode: using the Firebase emulators, not a real project.</div>' : ''}
    <main class="auth">
      <section class="pitch">
        <div class="eyes big" aria-hidden="true"><i></i><i></i></div>
        <h1>Sohail family accounts</h1>
        <p>One account for your family's robots and phones. Create a family, invite the people you trust, and register your robots so only your family can talk to them.</p>
      </section>
      <section class="card auth-card">
        ${note ? `<p class="note">${esc(note)}</p>` : ''}
        <div class="tabs" role="tablist">
          <button role="tab" id="tab-in" aria-selected="true" type="button">Sign in</button>
          <button role="tab" id="tab-up" aria-selected="false" type="button">Create account</button>
        </div>
        <form id="auth-form" novalidate>
          <label class="field" id="name-field" hidden>Your name
            <input id="name" autocomplete="name" maxlength="40" placeholder="Shown to your family and on robots">
          </label>
          <label class="field">Email
            <input id="email" type="email" autocomplete="email" required>
          </label>
          <label class="field">Password
            <input id="password" type="password" autocomplete="current-password" minlength="8" required>
          </label>
          <p class="error" id="auth-error" role="alert"></p>
          <button class="btn primary wide" id="auth-submit" type="submit">Sign in</button>
          <button class="link" id="forgot" type="button">Forgot your password?</button>
        </form>
        <div class="or"><span>or</span></div>
        <button class="btn wide" id="google" type="button">Continue with Google</button>
      </section>
    </main>`;

  let mode: 'in' | 'up' = 'in';
  const setMode = (m: 'in' | 'up') => {
    mode = m;
    $('#tab-in').setAttribute('aria-selected', String(m === 'in'));
    $('#tab-up').setAttribute('aria-selected', String(m === 'up'));
    $('#name-field').hidden = m === 'in';
    $('#auth-submit').textContent = m === 'in' ? 'Sign in' : 'Create account';
    $<HTMLInputElement>('#password').autocomplete = m === 'in' ? 'current-password' : 'new-password';
    $('#forgot').hidden = m === 'up';
    $('#auth-error').textContent = '';
  };
  $('#tab-in').addEventListener('click', () => setMode('in'));
  $('#tab-up').addEventListener('click', () => setMode('up'));

  const err = $('#auth-error');
  $('#auth-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const email = $<HTMLInputElement>('#email').value.trim();
    const password = $<HTMLInputElement>('#password').value;
    const name = $<HTMLInputElement>('#name').value.trim();
    void attempt($<HTMLButtonElement>('#auth-submit'), err, async () => {
      if (mode === 'in') {
        await signInWithEmailAndPassword(auth, email, password);
        return;
      }
      if (!name) throw new Error('Enter your name.');
      if (password.length < 8) throw new Error('Use a password with at least 8 characters.');
      holdRouting = true;
      try {
        const cred = await createUserWithEmailAndPassword(auth, email, password);
        await updateProfile(cred.user, { displayName: name });
        await data.saveProfile(cred.user, name);
        await sendEmailVerification(cred.user).catch(() => undefined);
      } finally {
        holdRouting = false;
        void route();
      }
    });
  });

  $('#forgot').addEventListener('click', () => {
    const email = $<HTMLInputElement>('#email').value.trim();
    void attempt($<HTMLButtonElement>('#forgot'), err, async () => {
      if (!email) throw new Error('Enter your email above first.');
      await sendPasswordResetEmail(auth, email);
      err.textContent = `If an account exists for ${email}, a reset link is on its way.`;
    });
  });

  $('#google').addEventListener('click', () =>
    attempt($<HTMLButtonElement>('#google'), err, async () => {
      const cred = await signInWithPopup(auth, new GoogleAuthProvider());
      await data.saveProfile(cred.user, data.nameOf(cred.user)).catch(() => undefined);
    }),
  );
}

// ---- dashboard ---------------------------------------------------------------------

async function renderDashboard() {
  loading();
  const families = await data.myFamilies(user!.uid);
  const roleLabel: Record<data.Role, string> = { owner: 'Owner', adult: 'Adult', child: 'Child' };
  app.innerHTML = shell(`
    ${!user!.emailVerified && user!.providerData.some((p) => p.providerId === 'password')
      ? `<div class="banner">Check your inbox to verify ${esc(user!.email)}. <button class="link" id="resend" type="button">Send again</button></div>`
      : ''}
    <h1>Hello, ${esc(data.nameOf(user!))}</h1>
    <section class="section">
      <h2>Your families</h2>
      ${families.length === 0
        ? '<p class="muted">You are not in a family yet. Create one, or join with a code someone sent you.</p>'
        : `<ul class="list">${families.map((f) => `
            <li><a class="row-link" href="/family/${esc(f.id)}" data-link>
              <span class="row-title">${esc(f.name)}</span>
              <span class="pill ${f.role}">${roleLabel[f.role]}</span>
            </a></li>`).join('')}</ul>`}
    </section>
    <div class="grid2">
      <section class="card">
        <h2>Create a family</h2>
        <form id="create">
          <label class="field">Family name<input id="family-name" maxlength="40" required placeholder="The Khans"></label>
          <p class="error" id="create-error" role="alert"></p>
          <button class="btn primary" id="create-btn" type="submit">Create family</button>
        </form>
      </section>
      <section class="card">
        <h2>Join a family</h2>
        <form id="join">
          <label class="field">Invite code<input id="join-code" maxlength="20" required placeholder="ABCD-EFGH-23" autocapitalize="characters"></label>
          <p class="error" id="join-error" role="alert"></p>
          <button class="btn" id="join-btn" type="submit">Continue</button>
        </form>
      </section>
    </div>`);
  bindShell();

  $('#resend')?.addEventListener('click', () =>
    attempt($<HTMLButtonElement>('#resend'), null, async () => {
      await sendEmailVerification(user!);
      $('#resend').textContent = 'Sent';
    }),
  );
  $('#create').addEventListener('submit', (e) => {
    e.preventDefault();
    const name = $<HTMLInputElement>('#family-name').value.trim();
    void attempt($<HTMLButtonElement>('#create-btn'), $('#create-error'), async () => {
      if (!name) throw new Error('Give the family a name.');
      const id = await data.createFamily(user!, name);
      go(`/family/${id}`);
    });
  });
  $('#join').addEventListener('submit', (e) => {
    e.preventDefault();
    const code = data.normaliseCode($<HTMLInputElement>('#join-code').value);
    if (code.length !== 10) {
      $('#join-error').textContent = 'Invite codes have 10 letters and digits.';
      return;
    }
    go(`/join/${code}`);
  });
}

// ---- joining ---------------------------------------------------------------------------

async function renderJoin(code: string) {
  loading();
  let invite: data.Invite | null = null;
  let problem = '';
  try {
    invite = await data.getInvite(code);
  } catch (e) {
    problem = describeError(e);
  }
  if (!invite || invite.expiresAt <= new Date()) {
    app.innerHTML = shell(`
      <section class="card narrow">
        <h1>Invite not valid</h1>
        <p>${esc(problem || 'This invite code does not exist, has expired, or was cancelled. Ask for a new one.')}</p>
        <a class="btn" href="/" data-link>Back to your families</a>
      </section>`);
    return bindShell();
  }
  if (await data.isMemberOf(invite.familyId, user!.uid)) return go(`/family/${invite.familyId}`);

  const inv = invite;
  app.innerHTML = shell(`
    <section class="card narrow">
      <p class="eyebrow">Invitation</p>
      <h1>Join ${esc(inv.familyName)}</h1>
      <p>You will join as <strong>${inv.role === 'child' ? 'a child' : 'an adult'}</strong>${inv.role === 'child'
        ? '. Adults in the family manage robots and invites.' : ' and can add robots and invite others.'}</p>
      <p class="muted">You will appear to the family as <strong>${esc(data.nameOf(user!))}</strong>. This invite ${relativeDays(inv.expiresAt)}.</p>
      <p class="error" id="join-error" role="alert"></p>
      <div class="actions">
        <button class="btn primary" id="accept" type="button">Join family</button>
        <a class="btn ghost" href="/" data-link>Not now</a>
      </div>
    </section>`);
  bindShell();
  $('#accept').addEventListener('click', () =>
    attempt($<HTMLButtonElement>('#accept'), $('#join-error'), async () => {
      await data.joinFamily(inv, user!);
      go(`/family/${inv.familyId}`);
    }),
  );
}

// ---- family page --------------------------------------------------------------------------

async function renderFamily(id: string) {
  loading();
  let family: data.Family | null = null;
  try {
    family = await data.getFamily(id);
  } catch {
    family = null;
  }
  if (!family) {
    app.innerHTML = shell(`
      <section class="card narrow"><h1>Family not found</h1>
      <p>It does not exist or you are not a member.</p><a class="btn" href="/" data-link>Back</a></section>`);
    return bindShell();
  }
  const fam = family;
  const people = await data.members(id);
  const me = people.find((m) => m.uid === user!.uid);
  const isOwner = me?.role === 'owner';
  const isAdult = isOwner || me?.role === 'adult';
  const [invites, robots] = await Promise.all([isAdult ? data.listInvites(id) : Promise.resolve([]), data.listRobots(id)]);
  const server = fam.server;
  const inviteLink = (code: string) => `${location.origin}/join/${code}`;
  const pretty = (code: string) => `${code.slice(0, 4)}-${code.slice(4, 8)}-${code.slice(8)}`;

  app.innerHTML = shell(`
    <p class="crumbs"><a href="/" data-link>Families</a> / ${esc(fam.name)}</p>
    <div class="title-row">
      <h1 id="family-title">${esc(fam.name)}</h1>
      ${isOwner ? '<button class="btn small ghost" id="rename" type="button">Rename</button>' : ''}
    </div>

    <section class="section">
      <h2>Connect your app and robots</h2>
      <p class="muted">Every phone and robot in this family uses the same group and message server.</p>
      <dl class="kv">
        <div><dt>Family group</dt><dd><code id="group-id">${esc(fam.id)}</code> ${copyButton(fam.id)}</dd></div>
        <div><dt>Message server</dt><dd>${server
          ? `<code>${esc(server.host)}:${server.port}</code> ${server.tls ? '<span class="pill">TLS</span>' : ''}`
          : '<span class="muted">Not set yet</span>'}</dd></div>
      </dl>
      <details class="how">
        <summary>Where do these go?</summary>
        <ul>
          <li><strong>Sohail app:</strong> Settings → Family group, Server address, Port${server?.tls ? ', Use TLS on' : ''}.</li>
          <li><strong>Robots:</strong> <code>idf.py menuconfig</code> → Sohail robot → Group id, and Broker URI
            <code>${server ? esc(`${server.tls ? 'mqtts' : 'mqtt'}://${server.host}:${server.port}`) : 'mqtt://your-server:1883'}</code>.</li>
        </ul>
      </details>
      ${isOwner ? `
      <form id="server-form" class="inline-form">
        <label class="field">Server address<input id="srv-host" maxlength="253" value="${esc(server?.host ?? '')}" placeholder="192.168.1.25 or broker.example.com"></label>
        <label class="field short">Port<input id="srv-port" type="number" min="1" max="65535" value="${server?.port ?? 1883}"></label>
        <label class="check"><input id="srv-tls" type="checkbox" ${server?.tls ? 'checked' : ''}> TLS</label>
        <button class="btn" id="srv-save" type="submit">Save server</button>
        <p class="error" id="srv-error" role="alert"></p>
      </form>` : ''}
    </section>

    <section class="section">
      <h2>Members <span class="count">${people.length}</span></h2>
      <ul class="list">${people.map((m) => `
        <li class="row" data-uid="${esc(m.uid)}">
          <span class="row-title">${esc(m.displayName)}${m.uid === user!.uid ? ' <span class="muted">(you)</span>' : ''}</span>
          ${isOwner && m.role !== 'owner'
            ? `<select class="role" aria-label="Role for ${esc(m.displayName)}">
                 <option value="adult" ${m.role === 'adult' ? 'selected' : ''}>Adult</option>
                 <option value="child" ${m.role === 'child' ? 'selected' : ''}>Child</option>
               </select>
               <button class="btn small ghost danger remove-member" type="button">Remove</button>`
            : `<span class="pill ${m.role}">${m.role[0].toUpperCase() + m.role.slice(1)}</span>`}
          ${m.uid === user!.uid && m.role !== 'owner' ? '<button class="btn small ghost danger" id="leave" type="button">Leave family</button>' : ''}
        </li>`).join('')}
      </ul>
      <p class="error" id="members-error" role="alert"></p>
    </section>

    ${isAdult ? `
    <section class="section">
      <h2>Invite someone</h2>
      <form id="invite-form" class="inline-form">
        <label class="field short">Joins as
          <select id="invite-role"><option value="adult">Adult</option><option value="child">Child</option></select>
        </label>
        <button class="btn primary" id="invite-btn" type="submit">Create invite link</button>
      </form>
      <p class="error" id="invite-error" role="alert"></p>
      ${invites.length ? `<ul class="list">${invites.map((i) => `
        <li class="row invite" data-code="${esc(i.code)}">
          <span class="row-title"><code class="code">${esc(pretty(i.code))}</code>
            <span class="muted">${i.role === 'child' ? 'Child' : 'Adult'} · ${esc(relativeDays(i.expiresAt))}</span></span>
          ${copyButton(inviteLink(i.code), 'Copy link')}
          <button class="btn small ghost danger revoke" type="button">Cancel</button>
        </li>`).join('')}</ul>` : '<p class="muted">No open invites. Links work for 7 days and anyone with the link can join, so share them privately.</p>'}
    </section>` : ''}

    <section class="section">
      <h2>Robots <span class="count">${robots.length}</span></h2>
      ${robots.length ? `<ul class="list">${robots.map((r) => `
        <li class="row robot" data-id="${esc(r.id)}">
          <span class="row-title">${esc(r.name)} <code class="muted">${esc(r.id)}</code></span>
          ${isAdult ? `<button class="btn small ghost rename-robot" type="button">Rename</button>
            <button class="btn small ghost danger remove-robot" type="button">Remove</button>` : ''}
        </li>`).join('')}</ul>` : '<p class="muted">No robots registered yet.</p>'}
      ${isAdult ? `
      <form id="robot-form" class="inline-form">
        <label class="field">Robot ID<input id="robot-id" placeholder="sohail-a1b2c3" maxlength="13" autocapitalize="none" spellcheck="false"></label>
        <label class="field">Name<input id="robot-name" maxlength="40" placeholder="Kitchen"></label>
        <button class="btn" id="robot-btn" type="submit">Add robot</button>
      </form>
      <p class="hint">The ID is shown in the Sohail app's robot list once the robot is online, and in the robot's serial log at start-up. No robot yet? Try the <a href="/robot">virtual robot</a>.</p>
      <p class="error" id="robot-error" role="alert"></p>` : ''}
    </section>

    ${isOwner ? `
    <section class="section danger-zone">
      <h2>Delete family</h2>
      <p class="muted">Removes every member, invite and robot registration. Robots and phones keep working until you change their settings.</p>
      <form id="delete-form" class="inline-form">
        <label class="field">Type the family name to confirm<input id="delete-confirm" autocomplete="off"></label>
        <button class="btn danger" id="delete-btn" type="submit">Delete family</button>
      </form>
      <p class="error" id="delete-error" role="alert"></p>
    </section>` : ''}
  `);
  bindShell();
  bindCopy();
  const reload = () => renderFamily(id);

  $('#rename')?.addEventListener('click', () => {
    const title = $('#family-title');
    title.outerHTML = `<form id="rename-form" class="inline-form"><input id="rename-input" maxlength="40" value="${esc(fam.name)}" aria-label="Family name">
      <button class="btn small primary" id="rename-save" type="submit">Save</button></form>`;
    $('#rename').remove();
    $<HTMLInputElement>('#rename-input').focus();
    $('#rename-form').addEventListener('submit', (e) => {
      e.preventDefault();
      const name = $<HTMLInputElement>('#rename-input').value.trim();
      void attempt($<HTMLButtonElement>('#rename-save'), $('#members-error'), async () => {
        if (!name) throw new Error('The family needs a name.');
        await data.renameFamily(id, name);
        await reload();
      });
    });
  });

  $('#server-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const host = $<HTMLInputElement>('#srv-host').value.trim();
    const port = Number($<HTMLInputElement>('#srv-port').value);
    const tls = $<HTMLInputElement>('#srv-tls').checked;
    void attempt($<HTMLButtonElement>('#srv-save'), $('#srv-error'), async () => {
      if (!host || /\s|\//.test(host)) throw new Error('Enter a host name or IP address, without mqtt:// or a path.');
      if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('The port is a number from 1 to 65535.');
      await data.saveServer(id, { host, port, tls });
      await reload();
    });
  });

  $$<HTMLSelectElement>('select.role').forEach((sel) =>
    sel.addEventListener('change', () => {
      const uid = sel.closest<HTMLElement>('[data-uid]')!.dataset.uid!;
      void attempt(null, $('#members-error'), async () => {
        await data.setRole(id, uid, sel.value as 'adult' | 'child');
        await reload();
      });
    }),
  );
  $$<HTMLButtonElement>('.remove-member').forEach((b) =>
    b.addEventListener('click', () => {
      const row = b.closest<HTMLElement>('[data-uid]')!;
      if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Confirm remove'; return; }
      void attempt(b, $('#members-error'), async () => {
        await data.removeMember(id, row.dataset.uid!);
        await reload();
      });
    }),
  );
  $('#leave')?.addEventListener('click', (e) => {
    const b = e.currentTarget as HTMLButtonElement;
    if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Confirm leave'; return; }
    void attempt(b, $('#members-error'), async () => {
      await data.removeMember(id, user!.uid);
      go('/');
    });
  });

  $('#invite-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const role = $<HTMLSelectElement>('#invite-role').value as 'adult' | 'child';
    void attempt($<HTMLButtonElement>('#invite-btn'), $('#invite-error'), async () => {
      await data.createInvite(fam, role, user!.uid);
      await reload();
    });
  });
  $$<HTMLButtonElement>('.revoke').forEach((b) =>
    b.addEventListener('click', () =>
      attempt(b, $('#invite-error'), async () => {
        await data.revokeInvite(b.closest<HTMLElement>('[data-code]')!.dataset.code!);
        await reload();
      }),
    ),
  );

  $('#robot-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    const deviceId = $<HTMLInputElement>('#robot-id').value.trim().toLowerCase();
    const name = $<HTMLInputElement>('#robot-name').value.trim() || deviceId;
    void attempt($<HTMLButtonElement>('#robot-btn'), $('#robot-error'), async () => {
      if (!data.isDeviceId(deviceId)) throw new Error('Robot IDs look like sohail-a1b2c3 (6 letters a-f or digits).');
      if (robots.some((r) => r.id === deviceId)) throw new Error('That robot is already in this family.');
      try {
        await data.addRobot(id, deviceId, name, user!.uid);
      } catch (err) {
        if ((err as { code?: string }).code === 'permission-denied') {
          throw new Error('That robot is registered to another family. Its family must remove it first.');
        }
        throw err;
      }
      await reload();
    });
  });
  $$<HTMLButtonElement>('.rename-robot').forEach((b) =>
    b.addEventListener('click', () => {
      const row = b.closest<HTMLElement>('[data-id]')!;
      const robot = robots.find((r) => r.id === row.dataset.id)!;
      row.querySelector('.row-title')!.innerHTML =
        `<input class="robot-rename" maxlength="40" value="${esc(robot.name)}" aria-label="Robot name">`;
      b.textContent = 'Save';
      const input = row.querySelector<HTMLInputElement>('.robot-rename')!;
      input.focus();
      b.addEventListener('click', () =>
        attempt(b, $('#robot-error'), async () => {
          const name = input.value.trim();
          if (!name) throw new Error('Give the robot a name.');
          await data.renameRobot(robot.id, name);
          await reload();
        }), { once: true });
    }, { once: true }),
  );
  $$<HTMLButtonElement>('.remove-robot').forEach((b) =>
    b.addEventListener('click', () => {
      if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Confirm remove'; return; }
      void attempt(b, $('#robot-error'), async () => {
        await data.removeRobot(b.closest<HTMLElement>('[data-id]')!.dataset.id!);
        await reload();
      });
    }),
  );

  $('#delete-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    void attempt($<HTMLButtonElement>('#delete-btn'), $('#delete-error'), async () => {
      if ($<HTMLInputElement>('#delete-confirm').value.trim() !== fam.name) {
        throw new Error(`Type "${fam.name}" exactly to confirm.`);
      }
      await data.deleteFamily(id, user!.uid);
      go('/');
    });
  });
}

// ---- account ----------------------------------------------------------------------------------

function renderAccount() {
  const u = user!;
  const passwordUser = u.providerData.some((p) => p.providerId === 'password');
  app.innerHTML = shell(`
    <h1>Account</h1>
    <section class="card narrow">
      <form id="profile">
        <label class="field">Your name<input id="profile-name" maxlength="40" value="${esc(data.nameOf(u))}"></label>
        <p class="hint">New families and invites use this name. Existing family memberships keep the name you joined with.</p>
        <p class="error" id="profile-error" role="alert"></p>
        <button class="btn primary" id="profile-save" type="submit">Save name</button>
      </form>
      <dl class="kv">
        <div><dt>Email</dt><dd>${esc(u.email ?? '')} ${u.emailVerified ? '<span class="pill">Verified</span>' : '<span class="pill warn">Not verified</span>'}</dd></div>
        <div><dt>Signed in with</dt><dd>${passwordUser ? 'Email and password' : 'Google'}</dd></div>
      </dl>
      ${passwordUser ? '<button class="btn ghost" id="reset" type="button">Email me a password reset link</button>' : ''}
      <p class="muted" id="account-msg" role="status"></p>
    </section>`);
  bindShell();
  $('#profile').addEventListener('submit', (e) => {
    e.preventDefault();
    const name = $<HTMLInputElement>('#profile-name').value.trim();
    void attempt($<HTMLButtonElement>('#profile-save'), $('#profile-error'), async () => {
      if (!name) throw new Error('Enter your name.');
      await updateProfile(u, { displayName: name });
      await data.saveProfile(u, name);
      $('#account-msg').textContent = 'Saved.';
    });
  });
  $('#reset')?.addEventListener('click', () =>
    attempt($<HTMLButtonElement>('#reset'), $('#profile-error'), async () => {
      await sendPasswordResetEmail(auth, u.email!);
      $('#account-msg').textContent = `Reset link sent to ${u.email}.`;
    }),
  );
}
