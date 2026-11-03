// Shared constants for the public Project Intake form (Experience Cloud, guest user).

export const STEPS = [
	{ key: 'project', label: 'Project' },
	{ key: 'module', label: 'Module & Size' },
	{ key: 'system', label: 'Pegasus System' },
	{ key: 'site', label: 'Site Details' },
	{ key: 'contact', label: 'Contact' },
	{ key: 'review', label: 'Review' }
];

export const FILE_CATEGORIES = { LAYOUT: 'LAYOUT', SPEC: 'SPEC' };

// Keep in sync with the Project Intake limits in Constants.cls.
export const FILE_LIMITS = {
	LAYOUT: {
		maxFiles: 1,
		maxSizeBytes: 20971520,
		accept: '.pdf,.dwg,.dxf,.jpg,.jpeg,.png,.gif',
		label: 'Module Layout (PDF or DWG)'
	},
	SPEC: {
		maxFiles: 2,
		maxSizeBytes: 5242880,
		accept: '.pdf,.jpg,.jpeg,.png,.gif',
		label: 'Module Spec Sheet'
	}
};

export const DEFAULT_REDIRECT_URL =
	'https://www.pegasussolar.com/form-received/';

export const DESIGN_PREFERENCE = {
	BALLASTED:
		'Ballasted - Blocks used to resist active forces. No penetrations.',
	HYBRID: 'Hybrid - Mix of anchors and ballast to resist active forces. Usually to meet load limits or seismic forces.',
	ATTACHED:
		'Attached - Fully anchored to resist active forces. No ballast blocks.'
};

export const SYSTEM_TYPE = {
	FLAT_ROOF: 'Flat Roof',
	PITCHED_ROOF: 'Pitched Roof',
	GROUND_MOUNT: 'Ground Mount'
};

export const DISTRIBUTOR_TYPE = { DIRECT: 'Direct', INDIRECT: 'Indirect' };

export const TEXT = {
	intro: 'Please carefully review all project information before submitting to Pegasus®. The data provided in this form will dictate the design results. The ultimate safety and reliability of the final racking design relies on the accuracy of the intake information provided. Pegasus® recommends all critical details of the delivered design documents be closely reviewed prior to submittal of any permit package and/or system installation. We look forward to being your solar racking provider!',
	ballastWarning:
		'Warning: failure to confirm ballast selection weight and/or physical size could result in under ballasting, which can risk property damage, personal injury, or loss of life. Pegasus does not produce or procure ballast block. Incorrect or unconfirmed ballast dimensions can greatly impact the cost and feasibility of the racking design. Lower tilt product offerings will have reduced block capacity as block size increases. The standard sizes listed are considered nominal. Actual block dimensions will increase efficiency of the final design.',
	consentTerms:
		'The data provided on this form dictates the design results unless otherwise corrected, clarified, or stated. Any information provided through this form takes priority over any conflicting information communicated via other means. The ultimate safety and reliability of the final racking design will rely on the accuracy of the intake information provided. Pegasus Solar recommends all critical details of the delivered design documents be reviewed prior to submittal of any permit package and/or system installation. Pegasus does not perform site surveys and is not liable for any incorrect or missing information provided. Pegasus uses satellite imagery via Google Maps to define building dimensions when not explicitly stated on a provided site/building/roof plan. By accepting the terms stated in this form you consent that any special site or building conditions not stated in the project/building/site information sections via this form will not be considered in the design. It is the sole responsibility of the party(ies) completing this form to obtain this information for use by Pegasus. Pegasus makes reasonable efforts to acquire the correct site criteria on your behalf. If you are aware of site specific design criteria (special wind, snow, or seismic requirements), add this information to the Project Notes. If you are aware of any special conditions (local fire code design requirements, specific structural requirements, or roofing system limitations), you must add this information for consideration.',
	consentAcknowledgement:
		'By checking the box above, you acknowledge your consent to the terms outlined above.'
};

const KB = 1024;
const MB = KB * 1024;

// Human readable size: '820 B', '512 KB', '4.2 MB'.
export function formatFileSize(bytes) {
	const size = Number(bytes);
	if (bytes === null || bytes === undefined || Number.isNaN(size)) {
		return '';
	}
	if (size < KB) {
		return `${size} B`;
	}
	if (size < MB) {
		return `${Math.round(size / KB)} KB`;
	}
	return `${Number((size / MB).toFixed(1))} MB`;
}
