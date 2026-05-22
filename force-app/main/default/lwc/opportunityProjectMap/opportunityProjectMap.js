import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import PROJECT_STREET from '@salesforce/schema/Opportunity.Project_Street__c';
import PROJECT_CITY from '@salesforce/schema/Opportunity.Project_City__c';
import PROJECT_STATE from '@salesforce/schema/Opportunity.Project_State__c';
import PROJECT_POSTAL from '@salesforce/schema/Opportunity.Project_PostalCode__c';
import PROJECT_COUNTRY from '@salesforce/schema/Opportunity.Project_Country__c';

const FIELDS = [PROJECT_STREET, PROJECT_CITY, PROJECT_STATE, PROJECT_POSTAL, PROJECT_COUNTRY];

export default class OpportunityProjectMap extends LightningElement {
	@api recordId;

	@wire(getRecord, { recordId: '$recordId', fields: FIELDS })
	opportunity;

	get isLoading() {
		return !this.opportunity || (!this.opportunity.data && !this.opportunity.error);
	}

	get hasError() {
		return !!(this.opportunity && this.opportunity.error);
	}

	get errorMessage() {
		const err = this.opportunity && this.opportunity.error;
		if (!err) return '';
		if (Array.isArray(err.body)) return err.body.map(e => e.message).join(', ');
		if (err.body && err.body.message) return err.body.message;
		return err.message || 'Unable to load address.';
	}

	get street() { return getFieldValue(this.opportunity.data, PROJECT_STREET); }
	get city() { return getFieldValue(this.opportunity.data, PROJECT_CITY); }
	get state() { return getFieldValue(this.opportunity.data, PROJECT_STATE); }
	get postal() { return getFieldValue(this.opportunity.data, PROJECT_POSTAL); }
	get country() { return getFieldValue(this.opportunity.data, PROJECT_COUNTRY); }

	get hasAddress() {
		if (!this.opportunity || !this.opportunity.data) return false;
		return !!(this.street || this.city || this.state || this.postal || this.country);
	}

	get formattedAddressLine1() {
		return this.street || '';
	}

	get formattedAddressLine2() {
		const parts = [];
		if (this.city) parts.push(this.city);
		const stateZip = [this.state, this.postal].filter(Boolean).join(' ');
		if (stateZip) parts.push(stateZip);
		if (this.country) parts.push(this.country);
		return parts.join(', ');
	}

	get mapMarkers() {
		if (!this.hasAddress) return [];
		return [
			{
				location: {
					Street: this.street || '',
					City: this.city || '',
					State: this.state || '',
					PostalCode: this.postal || '',
					Country: this.country || ''
				},
				title: 'Project Site',
				description: this.formattedAddressLine2
			}
		];
	}

	get directionsUrl() {
		if (!this.hasAddress) return null;
		const query = encodeURIComponent(
			[this.street, this.city, this.state, this.postal, this.country].filter(Boolean).join(', ')
		);
		return `https://www.google.com/maps/dir/?api=1&destination=${query}`;
	}
}
