import { LightningElement, api } from 'lwc';
import {
	FILE_CATEGORIES,
	FILE_LIMITS,
	STEPS,
	formatFileSize
} from 'c/projectIntakeConstants';

const EMPTY = '-';

function isBlank(value) {
	return value === null || value === undefined || value === '';
}

function stepLabel(key) {
	const step = STEPS.find((item) => item.key === key);
	return step ? step.label : key;
}

function formatDate(isoDate) {
	if (isBlank(isoDate)) {
		return EMPTY;
	}
	const date = new Date(`${isoDate}T00:00:00Z`);
	if (Number.isNaN(date.getTime())) {
		return isoDate;
	}
	return new Intl.DateTimeFormat('en-US', {
		timeZone: 'UTC',
		year: 'numeric',
		month: 'long',
		day: 'numeric'
	}).format(date);
}

function fileName(file) {
	const title = file.title || '';
	const ext = file.extension ? `.${file.extension}` : '';
	if (!ext || title.toLowerCase().endsWith(ext.toLowerCase())) {
		return title;
	}
	return `${title}${ext}`;
}

export default class ProjectIntakeReviewStep extends LightningElement {
	@api values;
	@api options;
	@api visibility;
	@api uploadToken;

	@api
	validate() {
		return true;
	}

	get v() {
		return this.values || {};
	}

	get opts() {
		return this.options || {};
	}

	get vis() {
		return this.visibility || {};
	}

	get sections() {
		return [
			this.section('project', this.projectItems),
			this.section('module', this.moduleItems),
			this.section('system', this.systemItems),
			this.section('site', this.siteItems),
			this.section('contact', this.contactItems)
		];
	}

	get projectItems() {
		return [
			this.text('projectName', 'Project Name'),
			this.picklist('countryCode', 'Country', 'countries'),
			this.picklist('stateCode', 'State / Province', 'states'),
			this.text('street', 'Street'),
			this.text('city', 'City'),
			this.text('postalCode', 'Zip / Postal Code'),
			{
				key: 'plannedInstallDate',
				label: 'Planned Install Date',
				value: formatDate(this.v.plannedInstallDate)
			},
			{ ...this.text('projectNotes', 'Project Notes'), isFull: true },
			this.files(FILE_CATEGORIES.LAYOUT)
		];
	}

	get moduleItems() {
		return [
			this.number('projectWattageKw', 'Project Wattage (kW)'),
			this.picklist('moduleManufacturer', 'Module Manufacturer'),
			this.picklist('moduleWattage', 'Module Wattage (W)'),
			this.text('moduleModelNumber', 'Module Model Number'),
			this.files(FILE_CATEGORIES.SPEC)
		];
	}

	get systemItems() {
		const items = [
			this.picklist('systemType', 'System Type'),
			this.picklist('systemConfiguration', 'System Configuration'),
			this.picklist('panelTilt', 'Panel Tilt')
		];
		if (this.vis.ul3741) {
			items.push(this.bool('ul3741Compliance', 'UL 3741 compliance'));
		}
		items.push({
			...this.picklist('designPreference', 'Design Preference'),
			isFull: true
		});
		if (this.vis.ballast) {
			items.push(
				this.picklist(
					'ballastBlockSpecification',
					'Ballast Block Specification'
				)
			);
		}
		return items;
	}

	get siteItems() {
		const items = [this.picklist('codeStandard', 'ASCE Code')];
		if (this.vis.buildingInfo) {
			items.push(
				this.number('buildingHeightFt', 'Building Height (ft)'),
				this.number('roofPitch', 'Roof Pitch (°)'),
				this.number('setbackDistanceFt', 'Setback Distance (ft)'),
				this.number('parapetHeightIn', 'Parapet Height (in)'),
				this.number('parapetWidthIn', 'Parapet Width (in)'),
				this.number(
					'structuralLoadLimitPsf',
					'Structural Load Limit (psf)'
				),
				this.number('pointLoadLimitPsf', 'Point Load Limit (psf)'),
				this.number(
					'maxSystemWeightLbs',
					'Maximum System Weight Limit (lbs)'
				),
				this.picklist('roofSurface', 'Roof Surface'),
				this.picklist(
					'constructionType',
					'Existing or New Construction'
				)
			);
		}
		if (this.vis.siteInfo) {
			items.push(
				this.number('groundSlope', 'Ground Slope (°)'),
				this.number('arrayAzimuth', 'Array Azimuth (°)'),
				this.bool(
					'landfillLocation',
					'Landfill Location (No Penetrations)'
				)
			);
		}
		return items;
	}

	get contactItems() {
		const items = [
			this.text('company', 'Company'),
			this.text('firstName', 'First Name'),
			this.text('lastName', 'Last Name'),
			this.text('email', 'Email'),
			this.text('phone', 'Phone'),
			this.picklist('distributorType', 'Purchasing', 'distributorType')
		];
		if (this.vis.knownDisty) {
			items.push(this.text('knownDisty', 'Distribution Partner'));
		}
		items.push(this.bool('legalConsent', 'I Consent & Agree'));
		return items;
	}

	section(stepKey, items) {
		const title = stepLabel(stepKey);
		return {
			key: stepKey,
			stepKey,
			title,
			editLabel: `Edit ${title}`,
			items: items.map((item) => ({
				...item,
				cssClass: item.isFull
					? 'review__item review__item_full'
					: 'review__item'
			}))
		};
	}

	text(name, label) {
		const value = this.v[name];
		return { key: name, label, value: isBlank(value) ? EMPTY : value };
	}

	number(name, label) {
		const value = this.v[name];
		return {
			key: name,
			label,
			value: isBlank(value) ? EMPTY : String(value)
		};
	}

	bool(name, label) {
		return {
			key: name,
			label,
			value: this.v[name] === true ? 'Yes' : 'No'
		};
	}

	// Picklist values are shown with their labels from options; optionsKey defaults to the field name.
	picklist(name, label, optionsKey = name) {
		const value = this.v[name];
		if (isBlank(value)) {
			return { key: name, label, value: EMPTY };
		}
		const option = (this.opts[optionsKey] || []).find(
			(item) => item.value === value
		);
		return { key: name, label, value: option ? option.label : value };
	}

	files(category) {
		const list = (this.v.files && this.v.files[category]) || [];
		const limits = FILE_LIMITS[category] || {};
		return {
			key: `files-${category}`,
			label: limits.label || category,
			value: list.length ? '' : EMPTY,
			isFull: true,
			hasFiles: list.length > 0,
			files: list.map((file) => ({
				key: file.contentVersionId,
				name: fileName(file),
				size: formatFileSize(file.sizeBytes)
			}))
		};
	}

	handleEdit(event) {
		const stepKey = event.currentTarget.dataset.stepKey;
		this.dispatchEvent(
			new CustomEvent('editstep', { detail: { stepKey } })
		);
	}
}
