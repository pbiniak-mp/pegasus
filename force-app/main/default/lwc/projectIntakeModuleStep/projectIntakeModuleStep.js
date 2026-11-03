import { LightningElement, api } from 'lwc';
import { FILE_CATEGORIES, FILE_LIMITS } from 'c/projectIntakeConstants';

const VALIDATABLE =
	'lightning-input, lightning-combobox, lightning-textarea, lightning-radio-group, c-project-intake-file-upload';

export default class ProjectIntakeModuleStep extends LightningElement {
	@api values;
	@api options;
	@api visibility;
	@api uploadToken;

	specLimits = FILE_LIMITS[FILE_CATEGORIES.SPEC];
	specCategory = FILE_CATEGORIES.SPEC;

	get v() {
		return this.values || {};
	}

	get opts() {
		return this.options || {};
	}

	get manufacturerOptions() {
		return this.opts.moduleManufacturer || [];
	}

	get wattageOptions() {
		return this.opts.moduleWattage || [];
	}

	get specFiles() {
		return (this.v.files && this.v.files[FILE_CATEGORIES.SPEC]) || [];
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
