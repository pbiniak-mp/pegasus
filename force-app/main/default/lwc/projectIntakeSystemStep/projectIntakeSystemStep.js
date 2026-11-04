import { LightningElement, api } from 'lwc';
import { TEXT } from 'c/projectIntakeConstants';

const VALIDATABLE =
	'lightning-input, lightning-combobox, lightning-textarea, lightning-radio-group, c-project-intake-file-upload';
const LABEL_SEPARATOR = ' - ';

// 'Ballasted - Blocks used to ...' -> { title: 'Ballasted', description: 'Blocks used to ...' }
function splitLabel(label) {
	const text = label || '';
	const index = text.indexOf(LABEL_SEPARATOR);
	if (index < 0) {
		return { title: text, description: '' };
	}
	return {
		title: text.slice(0, index),
		description: text.slice(index + LABEL_SEPARATOR.length)
	};
}

export default class ProjectIntakeSystemStep extends LightningElement {
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

	get systemTypeOptions() {
		return this.opts.systemType || [];
	}

	get configurationOptions() {
		return this.opts.systemConfiguration || [];
	}

	get configurationDisabled() {
		return this.vis.systemConfigurationDisabled === true;
	}

	get configurationRequired() {
		return !this.configurationDisabled;
	}

	get tiltOptions() {
		return this.opts.panelTilt || [];
	}

	get tiltDisabled() {
		return (
			this.vis.panelTiltDisabled === true ||
			this.vis.panelTiltLocked === true
		);
	}

	get tiltRequired() {
		return this.tiltOptions.length > 0 && !this.tiltDisabled;
	}

	get tiltHelp() {
		return this.vis.panelTiltLocked === true
			? 'Set automatically for the selected configuration.'
			: null;
	}

	get showUl3741() {
		return this.vis.ul3741 === true;
	}

	get showBallast() {
		return this.vis.ballast === true;
	}

	get designPreferenceLocked() {
		return this.vis.designPreferenceLocked === true;
	}

	get designPreferenceCards() {
		const selected = this.v.designPreference;
		const locked = this.designPreferenceLocked;
		return (this.opts.designPreference || []).map((option) => {
			const { title, description } = splitLabel(option.label);
			const checked = option.value === selected;
			let cssClass = 'radio-card';
			if (checked) {
				cssClass += ' radio-card_checked';
			}
			if (locked) {
				cssClass += ' radio-card_disabled';
			}
			return {
				key: option.value,
				value: option.value,
				title,
				description,
				checked,
				cssClass
			};
		});
	}

	get hasDesignPreferenceOptions() {
		return this.designPreferenceCards.length > 0;
	}

	get ballastOptions() {
		return this.opts.ballastBlockSpecification || [];
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
