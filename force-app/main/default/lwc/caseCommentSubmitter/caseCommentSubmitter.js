import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import getCaseComments             from '@salesforce/apex/CaseCommentController.getCaseComments';
import addCaseComment              from '@salesforce/apex/CaseCommentController.addCaseComment';
import getCaseInfo                 from '@salesforce/apex/CaseCommentController.getCaseInfo';
import fixFileVisibilityForCase    from '@salesforce/apex/CaseCommentController.fixFileVisibilityForCase';
import CURRENT_USER_ID             from '@salesforce/user/Id';

export default class CaseCommentSubmitter extends LightningElement {

    // ── API ───────────────────────────────────────────────────────────────────
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            fixFileVisibilityForCase({ caseId: value })
                .catch(function(err) { console.warn('fixFileVisibility error', err); });
        }
    }

    // ── Tracked State ─────────────────────────────────────────────────────────
    @track comments       = [];
    @track newCommentBody = '';
    @track isLoading      = true;
    @track isSubmitting   = false;
    @track errorMessage   = null;
    @track caseInfo       = null;
    @track pendingFiles   = [];
    @track sortNewest     = true;

    currentUserId = CURRENT_USER_ID;

    // ── Wire ──────────────────────────────────────────────────────────────────
    @wire(getCaseInfo, { caseId: '$_recordId' })
    wiredCaseInfo({ data, error }) {
        if (data)       this.caseInfo = data;
        else if (error) console.warn('getCaseInfo error', error);
    }

    @wire(getCaseComments, { caseId: '$_recordId' })
    wiredComments({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.comments = data.map(c => this._enrichComment(c));
        } else if (error) {
            this.errorMessage = this._extractError(error);
        }
    }

    // ── Computed ──────────────────────────────────────────────────────────────
    get isEmpty() {
        return !this.isLoading && this.comments.length === 0;
    }

    get commentCount() {
        return this.comments.length;
    }

    get charCount() {
        return this.newCommentBody.length;
    }

    get hasPendingFiles() {
        return this.pendingFiles.length > 0;
    }

    get submitDisabled() {
        return this.isSubmitting || this.newCommentBody.trim().length === 0;
    }

    get sortLabel() {
        return this.sortNewest ? '↓ Newest first' : '↑ Oldest first';
    }

    get sortedComments() {
        return this.sortNewest
            ? [].concat(this.comments).reverse()
            : [].concat(this.comments);
    }

    get charCountClass() {
        if (this.charCount > 3800) return 'scc-char-count scc-char-count--danger';
        if (this.charCount > 3500) return 'scc-char-count scc-char-count--warn';
        return 'scc-char-count';
    }

    get submitButtonClass() {
        return this.submitDisabled
            ? 'scc-btn scc-btn--primary scc-btn--disabled'
            : 'scc-btn scc-btn--primary';
    }

    get statusBadgeClass() {
        var status = this.caseInfo && this.caseInfo.status
            ? this.caseInfo.status.toLowerCase()
            : '';
        if (status === 'open' || status === 'new')             return 'scc-status scc-status--open';
        if (status === 'in progress' || status === 'working')  return 'scc-status scc-status--progress';
        if (status === 'closed'      || status === 'resolved') return 'scc-status scc-status--closed';
        return 'scc-status scc-status--default';
    }

    // ── Handlers ──────────────────────────────────────────────────────────────
    handleInput(event) {
        this.newCommentBody = event.target.value;
        var ta = event.target;
        ta.style.height = 'auto';
        ta.style.height = (Math.min(ta.scrollHeight, 200)) + 'px';
    }

    handleKeyDown(event) {
        if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
            event.preventDefault();
            this.handleSubmit();
        }
    }

    toggleSort() {
        this.sortNewest = !this.sortNewest;
    }

    handleUploadFinished(event) {
        var uploaded = event.detail.files;
        var self = this;
        uploaded.forEach(function(f) {
            var docId = f.documentId || f.contentDocumentId;
            if (docId && !self.pendingFiles.find(function(p) { return p.documentId === docId; })) {
                self.pendingFiles = self.pendingFiles.concat([{
                    documentId : docId,
                    name       : f.name
                }]);
            }
        });
    }

    handleRemovePendingFile(event) {
        var id = event.currentTarget.dataset.id;
        this.pendingFiles = this.pendingFiles.filter(function(f) { return f.documentId !== id; });
    }

    async handleSubmit() {
        if (this.submitDisabled) return;

        var body   = this.newCommentBody.trim();
        var docIds = this.pendingFiles.map(function(f) { return String(f.documentId); });

        this.newCommentBody = '';
        this.pendingFiles   = [];
        this.isSubmitting   = true;
        this.errorMessage   = null;

        var ta = this.template.querySelector('.scc-compose__textarea');
        if (ta) { ta.style.height = 'auto'; ta.value = ''; }

        try {
            var result = await addCaseComment({
                caseId             : this._recordId,
                commentBody        : body,
                contentDocumentIds : docIds.length > 0 ? docIds : null
            });

            this.comments = this.comments.concat([this._enrichComment(result)]);

            fixFileVisibilityForCase({ caseId: this._recordId })
                .catch(function(err) { console.warn('fixFileVisibility error', err); });

            this.dispatchEvent(new ShowToastEvent({
                title   : 'Comment sent',
                message : 'Your comment has been submitted.',
                variant : 'success'
            }));
        } catch (err) {
            console.error('addCaseComment error:', JSON.stringify(err));
            this.errorMessage   = this._extractError(err);
            this.newCommentBody = body;
            this.pendingFiles   = docIds.map(function(id, i) {
                return { documentId: id, name: 'File ' + (i + 1) };
            });
            if (ta) ta.value = body;
        } finally {
            this.isSubmitting = false;
        }
    }

    clearError() {
        this.errorMessage = null;
    }

    // ── Private ───────────────────────────────────────────────────────────────
    _enrichComment(c) {
        var isAgent = c.isAgent === true;
        var files = (c.files || []).map(function(f) {
            return Object.assign({}, f, {
                downloadUrl: f.downloadUrl
                    ? f.downloadUrl
                    : '/sfc/servlet.shepherd/document/download/' + f.contentDocumentId
            });
        });
        return Object.assign({}, c, {
            formattedDate : this._formatDate(c.createdDate),
            initials      : this._initials(c.authorName),
            roleBadge     : isAgent ? 'Support Agent' : 'Customer',
            badgeClass    : isAgent ? 'scc-badge scc-badge--agent' : 'scc-badge scc-badge--customer',
            hasFiles      : files.length > 0,
            files         : files
        });
    }

    _formatDate(isoString) {
        if (!isoString) return '';
        var d       = new Date(isoString);
        var now     = new Date();
        var diffMin = Math.floor((now - d) / 60000);
        var diffHr  = Math.floor(diffMin / 60);
        var diffDay = Math.floor(diffHr / 24);
        if (diffMin < 1)  return 'Just now';
        if (diffMin < 60) return diffMin + 'm ago';
        if (diffHr  < 24) return diffHr + 'h ago';
        if (diffDay < 7)  return diffDay + 'd ago';
        return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    }

    _initials(name) {
        if (!name) return '?';
        var parts = name.trim().split(/\s+/);
        if (parts.length === 1) return parts[0].charAt(0).toUpperCase();
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }

    _extractError(err) {
        if (typeof err === 'string') return err;
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message) return err.message;
        return 'An unexpected error occurred.';
    }
}