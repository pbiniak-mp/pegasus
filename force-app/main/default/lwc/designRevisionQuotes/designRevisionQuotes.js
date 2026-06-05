import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getQuotesByRevision from '@salesforce/apex/DesignRevisionQuotesController.getQuotesByRevision';
import getQuoteStatusPicklistValues from '@salesforce/apex/DesignRevisionQuotesController.getQuoteStatusPicklistValues';
import updateQuoteStatus from '@salesforce/apex/DesignRevisionQuotesController.updateQuoteStatus';
import setQuoteActive from '@salesforce/apex/DesignRevisionQuotesController.setQuoteActive';
import { NavigationMixin } from 'lightning/navigation';

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

const STATUS_BORDER_MAP = {
	'Accepted': 'quote-card border-accepted',
	'Approved': 'quote-card border-accepted',
	'Denied':   'quote-card border-denied',
	'Rejected': 'quote-card border-denied',
	'Draft':    'quote-card border-draft',
	'Presented':'quote-card border-presented',
	'Needs Review': 'quote-card border-review',
	'In Review':'quote-card border-review'
};

const DATE_FMT = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
const USD_PPW = new Intl.NumberFormat('en-US', {
	style: 'currency',
	currency: 'USD',
	minimumFractionDigits: 2,
	maximumFractionDigits: 2
});

const EMPTY_MODAL = { visible: false, quoteId: null, quoteName: null, currentStatus: null, newStatus: null };

const TYPE_ORDER = ['Material', 'Stamp', 'Extra'];

export default class DesignRevisionQuotes extends NavigationMixin(LightningElement) {
	@api recordId;

	quotes = [];
	statusOptions = [];
	isLoading = true;
	isSaving = false;
	errorMessage;
	confirmModal = { ...EMPTY_MODAL };
	selectedType = TYPE_ORDER[0];
	_wiredQuotesResult;

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
				pricePerWattFormatted: q.pricePerWatt != null
					? `${USD_PPW.format(q.pricePerWatt)}/W`
					: null,
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
				active: q.active === true,
				linesExpanded: false,
				chevronClass: 'chevron-icon',
				isExpiringSoon: q.expirationDate
					? (new Date(q.expirationDate) - new Date()) / (1000 * 60 * 60 * 24) < 30
					: false,
				cardClass: (STATUS_BORDER_MAP[q.status] || 'quote-card border-draft')
					+ (q.active === true ? ' is-active' : ''),
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
			this.ensureValidSelection();
		} else if (error) {
			this.errorMessage = error.body?.message || 'Failed to load quotes.';
		}
	}

	handleNavigateToRecord(event) {
		event.stopPropagation();
		const quoteId = event.currentTarget.dataset.quoteid;
		this[NavigationMixin.Navigate]({
			type: 'standard__recordPage',
			attributes: {
				recordId: quoteId,
				actionName: 'view'
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

	handleSetActive(event) {
		event.stopPropagation();
		const quoteId = event.currentTarget.dataset.quoteid;
		this.isSaving = true;
		setQuoteActive({ quoteId })
			.then(() => refreshApex(this._wiredQuotesResult))
			.catch(error => {
				this.errorMessage = error.body?.message || 'Failed to set the active quote.';
			})
			.finally(() => {
				this.isSaving = false;
			});
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

	get typeTabs() {
		return TYPE_ORDER.map(type => {
			const count = this.quotes.filter(q => q.quoteType === type).length;
			const active = type === this.selectedType;
			return {
				type,
				label: type,
				count,
				tabClass: active ? 'type-tab type-tab--active' : 'type-tab',
				countClass: active ? 'tab-count tab-count--active' : 'tab-count'
			};
		});
	}

	get filteredQuotes() {
		return this.quotes.filter(q => q.quoteType === this.selectedType);
	}

	get noQuotesOfType() {
		return this.filteredQuotes.length === 0;
	}

	get selectedTypeLabel() {
		return this.selectedType;
	}

	handleSelectType(event) {
		this.selectedType = event.currentTarget.dataset.type;
	}

	// Keep the visible tab on a type that actually has quotes, without overriding a
	// manual selection that is still populated (e.g. after a status-change refresh).
	ensureValidSelection() {
		const hasSelected = this.quotes.some(q => q.quoteType === this.selectedType);
		if (!hasSelected) {
			const firstWithQuotes = TYPE_ORDER.find(type => this.quotes.some(q => q.quoteType === type));
			this.selectedType = firstWithQuotes || TYPE_ORDER[0];
		}
	}

	get hasError() {
		return !!this.errorMessage;
	}
}
