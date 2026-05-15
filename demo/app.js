const initialComments = [
  {
    id: 1,
    author: 'Maya Chen',
    role: 'agent',
    createdAt: '2026-05-15T13:30:00Z',
    body: 'Reviewed the login telemetry. Password reset completed successfully, but the user is still hitting a stale session error.'
  },
  {
    id: 2,
    author: 'Jordan Rivera',
    role: 'customer',
    createdAt: '2026-05-15T14:05:00Z',
    body: 'I tried in Chrome and Safari. Same error after signing back in.'
  },
  {
    id: 3,
    author: 'Maya Chen',
    role: 'agent',
    createdAt: '2026-05-15T14:20:00Z',
    body: 'Requested HAR capture and screenshots. Waiting on customer confirmation.'
  }
];

const state = {
  comments: structuredClone(initialComments),
  attachments: [],
  sortNewest: true,
  viewerRole: 'agent',
  status: 'Waiting on Customer'
};

const els = {
  viewerRole: document.getElementById('viewerRole'),
  caseStatus: document.getElementById('caseStatus'),
  resetDemo: document.getElementById('resetDemo'),
  viewerLabel: document.getElementById('viewerLabel'),
  statusBadge: document.getElementById('statusBadge'),
  statusHint: document.getElementById('statusHint'),
  commentInput: document.getElementById('commentInput'),
  charCount: document.getElementById('charCount'),
  submitButton: document.getElementById('submitButton'),
  sortToggle: document.getElementById('sortToggle'),
  commentsList: document.getElementById('commentsList'),
  commentCount: document.getElementById('commentCount'),
  emptyState: document.getElementById('emptyState'),
  attachmentInput: document.getElementById('attachmentInput'),
  attachmentList: document.getElementById('attachmentList'),
  toast: document.getElementById('toast')
};

function formatDate(iso) {
  return new Date(iso).toLocaleString([], {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  });
}

function viewerName() {
  return state.viewerRole === 'agent' ? 'Support Agent' : 'Customer';
}

function computedStatusAfterComment() {
  if (state.status === 'Closed' || state.status === 'Resolved') {
    return state.status;
  }
  return state.viewerRole === 'agent' ? 'Waiting on Customer' : 'In Progress';
}

function badgeClass(status) {
  switch (status) {
    case 'New':
      return 'status-badge status-badge--new';
    case 'In Progress':
      return 'status-badge status-badge--progress';
    case 'Resolved':
      return 'status-badge status-badge--resolved';
    case 'Closed':
      return 'status-badge status-badge--closed';
    default:
      return 'status-badge status-badge--waiting';
  }
}

function showToast(message, type = 'success') {
  els.toast.textContent = message;
  els.toast.className = `toast show toast--${type}`;
  window.clearTimeout(showToast._timer);
  showToast._timer = window.setTimeout(() => {
    els.toast.className = 'toast';
  }, 2600);
}

function renderAttachments() {
  els.attachmentList.innerHTML = '';
  state.attachments.forEach((fileName, index) => {
    const pill = document.createElement('div');
    pill.className = 'attachment-pill';
    pill.innerHTML = `<span>${fileName}</span><button type="button" aria-label="Remove attachment">✕</button>`;
    pill.querySelector('button').addEventListener('click', () => {
      state.attachments.splice(index, 1);
      renderAttachments();
    });
    els.attachmentList.appendChild(pill);
  });
}

function renderComments() {
  const comments = state.sortNewest
    ? [...state.comments].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
    : [...state.comments].sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));

  els.commentsList.innerHTML = '';
  els.commentCount.textContent = `${state.comments.length} comment${state.comments.length === 1 ? '' : 's'}`;
  els.emptyState.classList.toggle('hidden', state.comments.length > 0);

  comments.forEach(comment => {
    const item = document.createElement('article');
    item.className = 'comment-item';
    item.innerHTML = `
      <div class="comment-item__header">
        <div>
          <span class="comment-item__author">${comment.author}</span>
          <span class="comment-item__role">${comment.role === 'agent' ? 'Agent' : 'Customer'}</span>
        </div>
        <span class="meta-label">${formatDate(comment.createdAt)}</span>
      </div>
      <div class="comment-item__body">${comment.body}</div>
      ${comment.attachments?.length ? `<div class="attachment-list">${comment.attachments.map(name => `<span class="attachment-pill"><span>${name}</span></span>`).join('')}</div>` : ''}
    `;
    els.commentsList.appendChild(item);
  });
}

function renderHeader() {
  els.viewerLabel.textContent = viewerName();
  els.statusBadge.textContent = state.status;
  els.statusBadge.className = badgeClass(state.status);
  els.statusHint.textContent = state.viewerRole === 'agent'
    ? 'Agent comments move the case to Waiting on Customer unless it is Closed or Resolved.'
    : 'Customer comments move the case to In Progress unless it is Closed or Resolved.';
}

function renderComposerState() {
  const length = els.commentInput.value.length;
  els.charCount.textContent = `${length} / 4000`;
  els.charCount.style.color = length > 3800 ? 'var(--danger)' : length > 3500 ? 'var(--warning)' : 'var(--grey-500)';
  els.submitButton.disabled = els.commentInput.value.trim().length === 0;
}

function resetDemo() {
  state.comments = structuredClone(initialComments);
  state.attachments = [];
  state.sortNewest = true;
  state.viewerRole = 'agent';
  state.status = 'Waiting on Customer';
  els.viewerRole.value = 'agent';
  els.caseStatus.value = 'Waiting on Customer';
  els.commentInput.value = '';
  els.sortToggle.textContent = '↓ Newest first';
  renderHeader();
  renderComposerState();
  renderAttachments();
  renderComments();
  showToast('Demo reset to sample Salesforce case data.');
}

els.viewerRole.addEventListener('change', (event) => {
  state.viewerRole = event.target.value;
  renderHeader();
});

els.caseStatus.addEventListener('change', (event) => {
  state.status = event.target.value;
  renderHeader();
});

els.commentInput.addEventListener('input', renderComposerState);

els.sortToggle.addEventListener('click', () => {
  state.sortNewest = !state.sortNewest;
  els.sortToggle.textContent = state.sortNewest ? '↓ Newest first' : '↑ Oldest first';
  renderComments();
});

els.attachmentInput.addEventListener('change', (event) => {
  const files = Array.from(event.target.files || []);
  files.forEach(file => state.attachments.push(file.name));
  event.target.value = '';
  renderAttachments();
  if (files.length) {
    showToast(`${files.length} attachment${files.length === 1 ? '' : 's'} added to pending upload.`);
  }
});

els.submitButton.addEventListener('click', () => {
  const body = els.commentInput.value.trim();
  if (!body) {
    showToast('Comment body is required.', 'error');
    return;
  }

  els.submitButton.disabled = true;
  els.submitButton.textContent = 'Submitting…';

  window.setTimeout(() => {
    state.comments.push({
      id: Date.now(),
      author: state.viewerRole === 'agent' ? 'Demo Agent' : 'Demo Customer',
      role: state.viewerRole,
      createdAt: new Date().toISOString(),
      body,
      attachments: [...state.attachments]
    });

    const previousStatus = state.status;
    state.status = computedStatusAfterComment();
    els.caseStatus.value = state.status;

    els.commentInput.value = '';
    state.attachments = [];
    els.submitButton.textContent = 'Submit comment';

    renderHeader();
    renderComposerState();
    renderAttachments();
    renderComments();

    const statusMessage = previousStatus === state.status
      ? `Comment submitted. Case remains ${state.status}.`
      : `Comment submitted. Case moved from ${previousStatus} to ${state.status}.`;
    showToast(statusMessage, 'success');
  }, 700);
});

els.resetDemo.addEventListener('click', resetDemo);

renderHeader();
renderComposerState();
renderAttachments();
renderComments();
