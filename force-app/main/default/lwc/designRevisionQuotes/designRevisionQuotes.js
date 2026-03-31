import { LightningElement, api, wire } from 'lwc';
import getQuotesByRevision from '@salesforce/apex/DesignRevisionQuotesController.getQuotesByRevision';
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

const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });

export default class DesignRevisionQuotes extends NavigationMixin(LightningElement) {
	@api recordId;

	quotes = [];
	isLoading = true;
	errorMessage;
	opportunityId;

	@wire(getRecord, { recordId: '$recordId', fields: [OPPORTUNITY_FIELD] })
	wiredRevision({ data, error }) {
		if (data) {
			this.opportunityId = getFieldValue(data, OPPORTUNITY_FIELD);
		}
	}

	@wire(getQuotesByRevision, { revisionId: '$recordId' })
	wiredQuotes({ data, error }) {
		this.isLoading = false;
		if (data) {
			this.quotes = data.map(q => ({
				...q,
				badgeClass: STATUS_BADGE_MAP[q.status] || 'badge badge-draft',
				grandTotalFormatted: q.grandTotal != null ? USD.format(q.grandTotal) : '—'
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

	get hasError() {
		return !!this.errorMessage;
	}
}
