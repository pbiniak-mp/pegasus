import { LightningElement, api } from 'lwc';
import { TEXT } from 'c/projectIntakeConstants';

const VALIDATABLE =
	'lightning-input, lightning-combobox, lightning-textarea, lightning-radio-group, c-project-intake-file-upload';

export default class ProjectIntakeContactStep extends LightningElement {
	@api values;
	@api options;
	@api visibility;
	@api uploadToken;

	text = TEXT;

	get v() {
		return this.values || {};
	}

	get opts() {
		return this.options || {};
	}

	get vis() {
		return this.visibility || {};
	}

	get distributorTypeOptions() {
		return this.opts.distributorType || [];
	}

	get showKnownDisty() {
		return this.vis.knownDisty === true;
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

	emitChange(name, value) {
		this.dispatchEvent(
			new CustomEvent('fieldchange', { detail: { name, value } })
		);
	}
}
