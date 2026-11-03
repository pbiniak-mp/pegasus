// Pure business rules for the Project Intake form: dependent picklists,
// forced values, conditional visibility and the submit payload.
import {
	DESIGN_PREFERENCE,
	DISTRIBUTOR_TYPE,
	FILE_CATEGORIES,
	SYSTEM_TYPE
} from 'c/projectIntakeConstants';

// Marks a system type without configuration or tilt restrictions.
const UNRESTRICTED = 'UNRESTRICTED';

// Dependency matrix, keyed by System Type, then System Configuration.
// tilts: allowed Panel Tilt values (a single value is auto-selected and locked).
// designPreference: forced (and locked) Design Preference for that configuration.
// A System Type missing from this table is treated as UNRESTRICTED.
const SYSTEM_MATRIX = {
	[SYSTEM_TYPE.FLAT_ROOF]: {
		'Flush Mount': {
			tilts: ['0°'],
			designPreference: DESIGN_PREFERENCE.ATTACHED
		},
		'South Facing': { tilts: ['5°', '7°', '10°', '15°'] },
		'East/West Facing': { tilts: ['7°', '10°'] }
	},
	[SYSTEM_TYPE.GROUND_MOUNT]: {
		'South Facing': { tilts: ['15°', '20°'] },
		'East/West Facing': { tilts: ['10°'] }
	},
	[SYSTEM_TYPE.PITCHED_ROOF]: UNRESTRICTED
};

// Request fields by type, in payload order. Everything else is a String.
const STRING_FIELDS = [
	'projectName',
	'countryCode',
	'street',
	'city',
	'stateCode',
	'postalCode',
	'projectNotes',
	'plannedInstallDate',
	'moduleManufacturer',
	'moduleWattage',
	'moduleModelNumber',
	'systemType',
	'systemConfiguration',
	'panelTilt',
	'designPreference',
	'ballastBlockSpecification',
	'codeStandard',
	'roofSurface',
	'constructionType',
	'company',
	'firstName',
	'lastName',
	'email',
	'phone',
	'distributorType',
	'knownDisty'
];

const NUMBER_FIELDS = [
	'projectWattageKw',
	'buildingHeightFt',
	'setbackDistanceFt',
	'roofPitch',
	'parapetHeightIn',
	'parapetWidthIn',
	'structuralLoadLimitPsf',
	'pointLoadLimitPsf',
	'maxSystemWeightLbs',
	'groundSlope',
	'arrayAzimuth'
];

const BOOLEAN_FIELDS = ['ul3741Compliance', 'landfillLocation', 'legalConsent'];

// Fields that are only sent when the matching visibility flag is true.
const CONDITIONAL_FIELDS = {
	ul3741: ['ul3741Compliance'],
	ballast: ['ballastBlockSpecification'],
	buildingInfo: [
		'roofSurface',
		'buildingHeightFt',
		'setbackDistanceFt',
		'roofPitch',
		'parapetHeightIn',
		'parapetWidthIn',
		'structuralLoadLimitPsf',
		'pointLoadLimitPsf',
		'maxSystemWeightLbs',
		'constructionType'
	],
	siteInfo: ['groundSlope', 'arrayAzimuth', 'landfillLocation'],
	knownDisty: ['knownDisty']
};

const DEFAULT_COUNTRY = 'US';

// Initial values object owned by projectIntakeForm.
export function createInitialValues() {
	const values = {};
	STRING_FIELDS.forEach((field) => {
		values[field] = null;
	});
	NUMBER_FIELDS.forEach((field) => {
		values[field] = null;
	});
	BOOLEAN_FIELDS.forEach((field) => {
		values[field] = false;
	});
	values.countryCode = DEFAULT_COUNTRY;
	values.uploadToken = null;
	values.files = { [FILE_CATEGORIES.LAYOUT]: [], [FILE_CATEGORIES.SPEC]: [] };
	return values;
}

function isBlank(value) {
	return value === null || value === undefined || value === '';
}

function systemRules(systemType) {
	if (isBlank(systemType)) {
		return null;
	}
	return SYSTEM_MATRIX[systemType] || UNRESTRICTED;
}

// Allowed configuration values: null = all, [] = none.
function allowedConfigurations(systemType) {
	const rules = systemRules(systemType);
	if (rules === null) {
		return [];
	}
	return rules === UNRESTRICTED ? null : Object.keys(rules);
}

function configurationRule(systemType, systemConfiguration) {
	const rules = systemRules(systemType);
	if (rules === null || rules === UNRESTRICTED) {
		return null;
	}
	return rules[systemConfiguration] || null;
}

// Allowed tilt values: null = all, [] = none.
function allowedTilts(systemType, systemConfiguration) {
	const rules = systemRules(systemType);
	if (rules === null) {
		return [];
	}
	if (rules === UNRESTRICTED) {
		return null;
	}
	const rule = configurationRule(systemType, systemConfiguration);
	return rule ? rule.tilts : [];
}

function filterOptions(allOptions, allowedValues) {
	const options = Array.isArray(allOptions) ? allOptions : [];
	if (allowedValues === null) {
		return [...options];
	}
	return options.filter((option) => allowedValues.includes(option.value));
}

function isAllowed(value, allowedValues) {
	return allowedValues === null || allowedValues.includes(value);
}

export function getConfigurationOptions(systemType, allOptions) {
	return filterOptions(allOptions, allowedConfigurations(systemType));
}

export function getTiltOptions(systemType, systemConfiguration, allOptions) {
	return filterOptions(
		allOptions,
		allowedTilts(systemType, systemConfiguration)
	);
}

export function getVisibility(values) {
	const v = values || {};
	const configurations = allowedConfigurations(v.systemType);
	const tilts = allowedTilts(v.systemType, v.systemConfiguration);
	const rule = configurationRule(v.systemType, v.systemConfiguration);
	return {
		ul3741: v.systemType === SYSTEM_TYPE.FLAT_ROOF,
		ballast:
			v.designPreference === DESIGN_PREFERENCE.BALLASTED ||
			v.designPreference === DESIGN_PREFERENCE.HYBRID,
		buildingInfo: v.systemType !== SYSTEM_TYPE.GROUND_MOUNT,
		siteInfo: v.systemType === SYSTEM_TYPE.GROUND_MOUNT,
		knownDisty: v.distributorType === DISTRIBUTOR_TYPE.INDIRECT,
		designPreferenceLocked: Boolean(rule && rule.designPreference),
		panelTiltLocked: tilts !== null && tilts.length === 1,
		systemConfigurationDisabled:
			configurations !== null && configurations.length === 0,
		panelTiltDisabled: tilts !== null && tilts.length === 0
	};
}

// Clears dependent values that are no longer valid and applies forced values.
function applySystemRules(values) {
	const next = { ...values };
	if (
		!isBlank(next.systemConfiguration) &&
		!isAllowed(
			next.systemConfiguration,
			allowedConfigurations(next.systemType)
		)
	) {
		next.systemConfiguration = null;
	}

	const tilts = allowedTilts(next.systemType, next.systemConfiguration);
	if (tilts !== null && tilts.length === 1) {
		next.panelTilt = tilts[0];
	} else if (!isBlank(next.panelTilt) && !isAllowed(next.panelTilt, tilts)) {
		next.panelTilt = null;
	}

	// Releasing the lock keeps the forced value, the user may change it.
	const rule = configurationRule(next.systemType, next.systemConfiguration);
	if (rule && rule.designPreference) {
		next.designPreference = rule.designPreference;
	}
	return next;
}

function statesFor(countryCode, formOptions) {
	const statesByCountry = (formOptions && formOptions.statesByCountry) || {};
	return statesByCountry[countryCode] || [];
}

export function applyFieldChange(values, name, value, formOptions) {
	let next = { ...(values || {}), [name]: value };
	if (name === 'countryCode' && !isBlank(next.stateCode)) {
		const states = statesFor(value, formOptions);
		if (!states.some((state) => state.value === next.stateCode)) {
			next.stateCode = null;
		}
	}
	next = applySystemRules(next);
	return next;
}

export function buildViewOptions(values, formOptions) {
	const v = values || {};
	const picklists = (formOptions && formOptions.picklists) || {};
	return {
		...picklists,
		countries: (formOptions && formOptions.countries) || [],
		states: statesFor(v.countryCode, formOptions),
		systemConfiguration: getConfigurationOptions(
			v.systemType,
			picklists.systemConfiguration
		),
		panelTilt: getTiltOptions(
			v.systemType,
			v.systemConfiguration,
			picklists.panelTilt
		)
	};
}

function toStringValue(value) {
	if (isBlank(value)) {
		return null;
	}
	const text = String(value).trim();
	return text === '' ? null : text;
}

function toNumberValue(value) {
	if (isBlank(value)) {
		return null;
	}
	const number = Number(value);
	return Number.isFinite(number) ? number : null;
}

function toBooleanValue(value) {
	return value === true || value === 'true';
}

function flattenFiles(files) {
	const buckets = files || {};
	const result = [];
	Object.values(FILE_CATEGORIES).forEach((category) => {
		(buckets[category] || []).forEach((file) => {
			if (file && file.contentVersionId) {
				result.push({
					contentVersionId: file.contentVersionId,
					category
				});
			}
		});
	});
	return result;
}

export function buildRequest(values) {
	const v = values || {};
	const request = {};
	STRING_FIELDS.forEach((field) => {
		request[field] = toStringValue(v[field]);
	});
	NUMBER_FIELDS.forEach((field) => {
		request[field] = toNumberValue(v[field]);
	});
	BOOLEAN_FIELDS.forEach((field) => {
		request[field] = toBooleanValue(v[field]);
	});

	const visibility = getVisibility(v);
	Object.keys(CONDITIONAL_FIELDS).forEach((flag) => {
		if (!visibility[flag]) {
			CONDITIONAL_FIELDS[flag].forEach((field) => {
				request[field] = null;
			});
		}
	});

	request.uploadToken = toStringValue(v.uploadToken);
	request.files = flattenFiles(v.files);
	return request;
}
