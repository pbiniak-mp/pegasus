import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSendState from '@salesforce/apex/QuoteSendController.getSendState';
import markAsSent from '@salesforce/apex/QuoteSendController.markAsSent';

const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
const USD_PPW = new Intl.NumberFormat('en-US', {
	style: 'currency',
	currency: 'USD',
	minimumFractionDigits: 2,
	maximumFractionDigits: 2
});
const DATETIME_FMT = new Intl.DateTimeFormat('en-US', {
	month: 'short',
	day: 'numeric',
	year: 'numeric',
	hour: 'numeric',
	minute: '2-digit'
});

const KB = 1024;
const GENERIC_ERROR = 'Something went wrong. Please try again.';

export default class QuoteSendToClient extends LightningElement {
	@api recordId;

	state;
	isLoading = true;
	isSaving = false;
	errorMessage;
	selectedDocumentId;
	showConfirm = false;

	_wiredState;

	@wire(getSendState, { quoteId: '$recordId' })
	wiredSendState(result) {
		this._wiredState = result;
		const { data, error } = result;

		if (data) {
			this.state = data;
			this.errorMessage = undefined;
			this.preselectNewestDocument(data);
		} else if (error) {
			this.state = undefined;
			this.errorMessage = this.extractMessage(error);
		}

		if (data || error) {
			this.isLoading = false;
		}
	}

	// The newest PDF is nearly always the one that went out, so it starts selected.
	// Anything older is still one click away, and flagged if it predates the price.
	preselectNewestDocument(data) {
		if (this.selectedDocumentId) return;
		if (!data.documents || data.documents.length === 0) return;
		this.selectedDocumentId = data.documents[data.documents.length - 1].contentVersionId;
	}

	get hasError() {
		return !!this.errorMessage;
	}

	get isSent() {
		return this.state && this.state.sent === true;
	}

	get hasDocuments() {
		return !!(this.state && this.state.documents && this.state.documents.length > 0);
	}

	get documentRows() {
		if (!this.hasDocuments) return [];
		return this.state.documents.map((doc) => {
			const checked = doc.contentVersionId === this.selectedDocumentId;
			return {
				...doc,
				checked,
				rowClass: checked ? 'doc-row doc-row-selected' : 'doc-row',
				markClass: checked ? 'doc-mark doc-mark-on' : 'doc-mark',
				metaLabel: this.buildMetaLabel(doc)
			};
		});
	}

	buildMetaLabel(doc) {
		const parts = [DATETIME_FMT.format(new Date(doc.createdDate))];
		if (doc.createdByName) parts.push(doc.createdByName);
		if (doc.contentSize) parts.push(`${Math.round(doc.contentSize / KB)} KB`);
		return parts.join(' · ');
	}

	get selectedDocument() {
		if (!this.hasDocuments) return undefined;
		return this.state.documents.find(
			(doc) => doc.contentVersionId === this.selectedDocumentId
		);
	}

	get selectedIsStale() {
		const doc = this.selectedDocument;
		return !!(doc && doc.stale);
	}

	get selectedCreatedLabel() {
		const doc = this.selectedDocument;
		return doc ? DATETIME_FMT.format(new Date(doc.createdDate)) : '';
	}

	get lastPriceChangeLabel() {
		if (!this.state || !this.state.lastPriceChange) return '';
		return DATETIME_FMT.format(new Date(this.state.lastPriceChange));
	}

	get sentAtLabel() {
		if (!this.state || !this.state.sentAt) return '';
		return DATETIME_FMT.format(new Date(this.state.sentAt));
	}

	get sentDocumentLabel() {
		if (!this.state) return '';
		return this.state.sentDocumentTitle || this.state.sentDocumentId || '—';
	}

	get sentAmountLabel() {
		return this.formatCurrency(this.state && this.state.sentAmount);
	}

	get currentAmountLabel() {
		return this.formatCurrency(this.state && this.state.currentAmount);
	}

	get pricePerWattLabel() {
		if (!this.state || this.state.pricePerWatt === null || this.state.pricePerWatt === undefined) {
			return '';
		}
		return USD_PPW.format(this.state.pricePerWatt);
	}

	get sendDisabled() {
		return this.isSaving || !this.selectedDocumentId;
	}

	formatCurrency(value) {
		if (value === null || value === undefined) return '—';
		return USD.format(value);
	}

	handleSelectDocument(event) {
		this.selectedDocumentId = event.currentTarget.dataset.id;
		this.showConfirm = false;
	}

	handleSendClick() {
		this.showConfirm = true;
	}

	handleCancel() {
		this.showConfirm = false;
	}

	async handleConfirm() {
		this.isSaving = true;
		this.showConfirm = false;
		try {
			await markAsSent({
				quoteId: this.recordId,
				contentVersionId: this.selectedDocumentId
			});
			await refreshApex(this._wiredState);
			this.showToast('Success', 'Quote marked as sent to the client.', 'success');
		} catch (error) {
			this.showToast('Could not mark as sent', this.extractMessage(error), 'error');
		} finally {
			this.isSaving = false;
		}
	}

	extractMessage(error) {
		if (!error) return GENERIC_ERROR;
		if (error.body && error.body.message) return error.body.message;
		if (error.message) return error.message;
		return GENERIC_ERROR;
	}

	showToast(title, message, variant) {
		this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
	}
}
