import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getQuotesByRevision from '@salesforce/apex/DesignRevisionQuotesController.getQuotesByRevision';
import getQuoteStatusPicklistValues from '@salesforce/apex/DesignRevisionQuotesController.getQuoteStatusPicklistValues';
import updateQuoteStatus from '@salesforce/apex/DesignRevisionQuotesController.updateQuoteStatus';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import OPPORTUNITY_FIELD from '@salesforce/schema/Design_Revision__c.Opportunity__c';

const STATUS_BADGE_MAP = {
	'Accepted': 'badge badge-accepted',
	'Denied':   'badge badge-denied',
	'Draft':    'badge badge-draft',
	'Presented':'badge badge-presented',
	'Approved': 'badge badge-accepted',
	'Rejected': 'badge badge-denied',
	'Needs Review': 'badge badge-review',
	'In Review':'badge badge-review'
};

const DATE_FMT = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });

const EMPTY_MODAL = { visible: false, quoteId: null, quoteName: null, currentStatus: null, newStatus: null };

export default class DesignRevisionQuotes extends NavigationMixin(LightningElement) {
	@api recordId;

	quotes = [];
	statusOptions = [];
	isLoading = true;
	errorMessage;
	opportunityId;
	confirmModal = { ...EMPTY_MODAL };
	_wiredQuotesResult;

	@wire(getRecord, { recordId: '$recordId', fields: [OPPORTUNITY_FIELD] })
	wiredRevision({ data, error }) {
		if (data) {
			this.opportunityId = getFieldValue(data, OPPORTUNITY_FIELD);
		}
	}

	@wire(getQuoteStatusPicklistValues)
	wiredPicklist({ data, error }) {
		if (data) {
			this.statusOptions = data.map(opt => ({ label: opt.label, value: opt.value }));
		}
	}

	@wire(getQuotesByRevision, { revisionId: '$recordId' })
	wiredQuotes(result) {
		this._wiredQuotesResult = result;
		const { data, error } = result;
		this.isLoading = false;
		if (data) {
			this.quotes = data.map(q => ({
				...q,
				badgeClass: STATUS_BADGE_MAP[q.status] || 'badge badge-draft',
				grandTotalFormatted: q.grandTotal != null ? USD.format(q.grandTotal) : '—',
				expirationDate: q.expirationDate
					? DATE_FMT.format(new Date(q.expirationDate))
					: null,
				revNumber: q.revNumber || null,
				createdByName: q.createdByName || null,
				totalLineItems: q.totalLineItems || 0,
				lineItems: (q.lineItems || []).map(li => ({
					productName: li.productName || '—',
					quantity: li.quantity,
					unitPrice: li.unitPrice != null ? USD.format(li.unitPrice) : '—'
				})),
				linesExpanded: false,
				chevronClass: 'chevron-icon',
				isExpiringSoon: q.expirationDate
					? (new Date(q.expirationDate) - new Date()) / (1000 * 60 * 60 * 24) < 30
					: false,
				cardClass: (() => {
					const expiring = q.expirationDate &&
						(new Date(q.expirationDate) - new Date()) / (1000 * 60 * 60 * 24) < 30;
					if (q.status === 'Accepted' || q.status === 'Approved') return 'quote-card accepted';
					if (expiring) return 'quote-card expiring';
					return 'quote-card';
				})(),
				expiryDotClass: (() => {
					const expiring = q.expirationDate &&
						(new Date(q.expirationDate) - new Date()) / (1000 * 60 * 60 * 24) < 30;
					return expiring ? 'expiry-dot dot-warn' : 'expiry-dot dot-ok';
				})(),
				expiryTextClass: (() => {
					const expiring = q.expirationDate &&
						(new Date(q.expirationDate) - new Date()) / (1000 * 60 * 60 * 24) < 30;
					return expiring ? 'expiry-warn' : 'expiry-ok';
				})()
			}));
		} else if (error) {
			this.errorMessage = error.body?.message || 'Failed to load quotes.';
		}
	}

	handleNewQuote() {
		this[NavigationMixin.Navigate]({
			type: 'standard__objectPage',
			attributes: {
				objectApiName: 'Quote',
				actionName: 'new'
			},
			state: {
				defaultFieldValues: `OpportunityId=${this.opportunityId},Design_Revision__c=${this.recordId}`
			}
		});
	}

	handleActionClick(event) {
		const quoteId = event.currentTarget.dataset.quoteid;
		const quote = this.quotes.find(q => q.id === quoteId);
		this.confirmModal = {
			visible: true,
			quoteId,
			quoteName: quote.name,
			currentStatus: quote.status,
			newStatus: quote.status
		};
	}

	handleModalStatusChange(event) {
		this.confirmModal = { ...this.confirmModal, newStatus: event.detail.value };
	}

	handleConfirm() {
		updateQuoteStatus({ quoteId: this.confirmModal.quoteId, newStatus: this.confirmModal.newStatus })
			.then(() => {
				this.confirmModal = { ...EMPTY_MODAL };
				return refreshApex(this._wiredQuotesResult);
			})
			.catch(error => {
				this.errorMessage = error.body?.message || 'Update failed.';
				this.confirmModal = { ...EMPTY_MODAL };
			});
	}

	handleCancel() {
		this.confirmModal = { ...EMPTY_MODAL };
	}

	handleToggleLines(event) {
		const quoteId = event.currentTarget.dataset.quoteid;
		this.quotes = this.quotes.map(q => {
			if (q.id !== quoteId) return q;
			const expanded = !q.linesExpanded;
			return {
				...q,
				linesExpanded: expanded,
				chevronClass: expanded ? 'chevron-icon open' : 'chevron-icon'
			};
		});
	}

	get isConfirmDisabled() {
		return this.confirmModal.newStatus === this.confirmModal.currentStatus;
	}

	get materialQuotes() {
		return this.quotes.filter(q => q.quoteType === 'Material');
	}

	get stampQuotes() {
		return this.quotes.filter(q => q.quoteType === 'Stamp');
	}

	get noMaterial() {
		return this.materialQuotes.length === 0;
	}

	get noStamp() {
		return this.stampQuotes.length === 0;
	}

	get materialCount() { return this.materialQuotes.length; }
	get stampCount() { return this.stampQuotes.length; }

	get hasError() {
		return !!this.errorMessage;
	}
}
