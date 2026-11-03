import { LightningElement, api } from 'lwc';
import { FILE_CATEGORIES, FILE_LIMITS, TEXT } from 'c/projectIntakeConstants';

const VALIDATABLE =
	'lightning-input, lightning-combobox, lightning-textarea, lightning-radio-group, c-project-intake-file-upload';
const NOTES_MAX_LENGTH = 3000;

function todayIso() {
	const now = new Date();
	const pad = (part) => String(part).padStart(2, '0');
	return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

export default class ProjectIntakeProjectStep extends LightningElement {
	@api values;
	@api options;
	@api visibility;
	@api uploadToken;

	text = TEXT;
	layoutLimits = FILE_LIMITS[FILE_CATEGORIES.LAYOUT];
	layoutCategory = FILE_CATEGORIES.LAYOUT;
	notesMaxLength = NOTES_MAX_LENGTH;
	minInstallDate = todayIso();

	get v() {
		return this.values || {};
	}

	get opts() {
		return this.options || {};
	}

	get countryOptions() {
		return this.opts.countries || [];
	}

	get stateOptions() {
		return this.opts.states || [];
	}

	get stateDisabled() {
		return this.stateOptions.length === 0;
	}

	get layoutFiles() {
		return (this.v.files && this.v.files[FILE_CATEGORIES.LAYOUT]) || [];
	}

	get notesRemaining() {
		const used = (this.v.projectNotes || '').length;
		return `${Math.max(NOTES_MAX_LENGTH - used, 0)} characters remaining`;
	}

	@api
	validate() {
		let firstInvalid;
		let valid = true;
		this.template.querySelectorAll(VALIDATABLE).forEach((element) => {
			const elementValid =
				typeof element.validate === 'function'
					? element.validate()
					: element.reportValidity();
			if (elementValid === false) {
				valid = false;
				firstInvalid = firstInvalid || element;
			}
		});
		if (firstInvalid) {
			if (typeof firstInvalid.focus === 'function') {
				firstInvalid.focus();
			}
			if (typeof firstInvalid.scrollIntoView === 'function') {
				firstInvalid.scrollIntoView({
					behavior: 'smooth',
					block: 'center'
				});
			}
		}
		return valid;
	}

	handleChange(event) {
		const target = event.target;
		let value;
		if (target.type === 'checkbox') {
			value = target.checked === true;
		} else if (target.type === 'number') {
			const number =
				target.value === '' ||
				target.value === null ||
				target.value === undefined
					? null
					: Number(target.value);
			value = Number.isNaN(number) ? null : number;
		} else {
			value = target.value;
		}
		this.emitChange(target.dataset.name, value);
	}

	handleFilesChange(event) {
		const { category, files } = event.detail;
		this.emitChange('files', {
			...(this.v.files || {}),
			[category]: files
		});
	}

	emitChange(name, value) {
		this.dispatchEvent(
			new CustomEvent('fieldchange', { detail: { name, value } })
		);
	}
}
