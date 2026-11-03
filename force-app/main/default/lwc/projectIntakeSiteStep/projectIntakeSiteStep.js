import { LightningElement, api } from 'lwc';

const VALIDATABLE =
	'lightning-input, lightning-combobox, lightning-textarea, lightning-radio-group, c-project-intake-file-upload';
const POSITIVE_MESSAGE =
	'Must be greater than 0 (leave blank if not applicable).';

// Optional positive numbers of the Building Information section, in display order.
const BUILDING_NUMBERS = [
	{
		name: 'setbackDistanceFt',
		label: 'Setback Distance (ft)',
		placeholder: 'Edge of border to array edge'
	},
	{
		name: 'parapetHeightIn',
		label: 'Parapet Height (in)',
		placeholder: 'Avg. height from deck to top of wall'
	},
	{
		name: 'parapetWidthIn',
		label: 'Parapet Width (in)',
		placeholder: 'Parapet wall thickness'
	},
	{
		name: 'structuralLoadLimitPsf',
		label: 'Structural Load Limit (psf)',
		placeholder: 'Distributed load on roof structure'
	},
	{
		name: 'pointLoadLimitPsf',
		label: 'Point Load Limit (psf)',
		placeholder: 'Concentrated load per bracket'
	},
	{
		name: 'maxSystemWeightLbs',
		label: 'Maximum System Weight Limit (lbs)',
		placeholder: 'Per roof limit'
	}
];

export default class ProjectIntakeSiteStep extends LightningElement {
	@api values;
	@api options;
	@api visibility;
	@api uploadToken;

	positiveMessage = POSITIVE_MESSAGE;

	get v() {
		return this.values || {};
	}

	get opts() {
		return this.options || {};
	}

	get vis() {
		return this.visibility || {};
	}

	get showBuildingInfo() {
		return this.vis.buildingInfo === true;
	}

	get showSiteInfo() {
		return this.vis.siteInfo === true;
	}

	get codeStandardOptions() {
		return this.opts.codeStandard || [];
	}

	get roofSurfaceOptions() {
		return this.opts.roofSurface || [];
	}

	get constructionTypeOptions() {
		return this.opts.constructionType || [];
	}

	get buildingNumbers() {
		return BUILDING_NUMBERS.map((field) => ({
			...field,
			value: this.v[field.name]
		}));
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
