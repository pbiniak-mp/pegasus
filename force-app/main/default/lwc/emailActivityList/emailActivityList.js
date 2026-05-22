import { LightningElement, api, wire } from 'lwc';
import getEmailsForRecord from '@salesforce/apex/EmailActivityListController.getEmailsForRecord';

const PREVIEW_LENGTH = 150;

const STATUS_LABELS = {
	'0': 'New',
	'1': 'Read',
	'2': 'Replied',
	'3': 'Sent',
	'4': 'Forwarded',
	'5': 'Draft'
};

const DATE_FMT = new Intl.DateTimeFormat('en-US', {
	month: 'short',
	day: 'numeric',
	year: 'numeric',
	hour: 'numeric',
	minute: '2-digit'
});

export default class EmailActivityList extends LightningElement {
	@api recordId;

	emails = [];
	isLoading = true;
	errorMessage;

	@wire(getEmailsForRecord, { recordId: '$recordId' })
	wiredEmails({ data, error }) {
		this.isLoading = false;
		if (data) {
			this.emails = data.map(e => this.decorate(e));
			this.errorMessage = undefined;
		} else if (error) {
			this.errorMessage = error.body?.message || 'Unable to load emails for this record.';
			this.emails = [];
		}
	}

	decorate(email) {
		const text = email.TextBody || '';
		const preview = text.length > PREVIEW_LENGTH
			? text.substring(0, PREVIEW_LENGTH) + '...'
			: text;
		const incoming = email.Incoming === true;
		const statusLabel = STATUS_LABELS[email.Status] || email.Status || '';

		return {
			id: email.Id,
			subject: email.Subject || '(No subject)',
			fromName: email.FromName,
			fromAddress: email.FromAddress,
			fromDisplay: email.FromName
				? `${email.FromName} <${email.FromAddress || ''}>`
				: (email.FromAddress || 'Unknown sender'),
			toAddress: email.ToAddress,
			ccAddress: email.CcAddress,
			textBody: text,
			preview,
			messageDate: email.MessageDate
				? DATE_FMT.format(new Date(email.MessageDate))
				: (email.CreatedDate ? DATE_FMT.format(new Date(email.CreatedDate)) : ''),
			hasAttachment: email.HasAttachment === true,
			incoming,
			directionIcon: incoming ? 'utility:download' : 'utility:upload',
			directionLabel: incoming ? 'Inbound' : 'Outbound',
			statusLabel,
			cardClass: incoming
				? 'slds-box slds-m-bottom_small email-card email-inbound'
				: 'slds-box slds-m-bottom_small email-card email-outbound',
			expanded: false,
			toggleIcon: 'utility:chevronright'
		};
	}

	handleToggle(event) {
		const emailId = event.currentTarget.dataset.id;
		this.emails = this.emails.map(e => {
			if (e.id !== emailId) return e;
			const expanded = !e.expanded;
			return {
				...e,
				expanded,
				toggleIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright'
			};
		});
	}

	get hasEmails() {
		return this.emails.length > 0;
	}

	get isEmpty() {
		return !this.isLoading && !this.errorMessage && this.emails.length === 0;
	}

	get hasError() {
		return !!this.errorMessage;
	}

	get cardTitle() {
		return `Emails (${this.emails.length})`;
	}
}
