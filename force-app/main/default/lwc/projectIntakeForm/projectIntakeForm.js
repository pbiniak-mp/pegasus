import { LightningElement, api } from 'lwc';
import getFormOptions from '@salesforce/apex/ProjectIntakeController.getFormOptions';
import createUploadToken from '@salesforce/apex/ProjectIntakeController.createUploadToken';
import submitIntake from '@salesforce/apex/ProjectIntakeController.submitIntake';
import PEGASUS_LOGO from '@salesforce/resourceUrl/PegasusLogo';
import { DEFAULT_REDIRECT_URL, STEPS } from 'c/projectIntakeConstants';
import {
	applyFieldChange,
	buildRequest,
	buildViewOptions,
	createInitialValues,
	getVisibility
} from 'c/projectIntakeRules';

const LOAD_ERROR =
	'We could not load the form. Please check your connection and try again.';
const SUBMIT_ERROR =
	'We could not submit your project. Please try again in a moment.';

// Only absolute http(s) or site-relative URLs are accepted as redirect targets.
const SAFE_URL = /^(https?:\/\/|\/(?!\/))/i;

// Flattens Apex / UI API errors into one user-facing message.
function reduceErrors(error) {
	const errors = Array.isArray(error) ? error : [error];
	return errors
		.filter((item) => item)
		.map((item) => {
			if (typeof item === 'string') {
				return item;
			}
			if (Array.isArray(item.body)) {
				return item.body.map((entry) => entry && entry.message);
			}
			if (item.body && typeof item.body.message === 'string') {
				return item.body.message;
			}
			return null;
		})
		.flat()
		.filter((message) => message)
		.join(', ');
}

export default class ProjectIntakeForm extends LightningElement {
	@api redirectUrl = DEFAULT_REDIRECT_URL;

	logoUrl = PEGASUS_LOGO;
	steps = STEPS;

	values = createInitialValues();
	formOptions;
	viewOptions = {};
	visibility = getVisibility(this.values);
	uploadToken;

	currentIndex = 0;
	maxVisitedIndex = 0;

	isLoading = true;
	loadError;
	isSubmitting = false;
	submitError;
	isDirty = false;
	isSubmitted = false;

	connectedCallback() {
		window.addEventListener('beforeunload', this.handleBeforeUnload);
		this.loadForm();
	}

	disconnectedCallback() {
		this.removeUnloadListener();
	}

	// Loading

	async loadForm() {
		this.isLoading = true;
		this.loadError = undefined;
		try {
			const [options, token] = await Promise.all([
				getFormOptions(),
				this.uploadToken
					? Promise.resolve(this.uploadToken)
					: createUploadToken()
			]);
			this.formOptions = options || {};
			this.uploadToken = token;
			this.values = { ...this.values, uploadToken: token };
			this.refreshDerived();
		} catch {
			this.loadError = LOAD_ERROR;
		} finally {
			this.isLoading = false;
		}
	}

	handleRetry() {
		this.loadForm();
	}

	refreshDerived() {
		this.visibility = getVisibility(this.values);
		this.viewOptions = buildViewOptions(this.values, this.formOptions);
	}

	// Step state

	get currentStep() {
		return STEPS[this.currentIndex];
	}

	get currentKey() {
		return this.currentStep.key;
	}

	get isProjectStep() {
		return this.currentKey === 'project';
	}

	get isModuleStep() {
		return this.currentKey === 'module';
	}

	get isSystemStep() {
		return this.currentKey === 'system';
	}

	get isSiteStep() {
		return this.currentKey === 'site';
	}

	get isContactStep() {
		return this.currentKey === 'contact';
	}

	get isReviewStep() {
		return this.currentKey === 'review';
	}

	get showBack() {
		return this.currentIndex > 0;
	}

	get primaryLabel() {
		if (!this.isReviewStep) {
			return 'Next';
		}
		return this.isSubmitting ? 'Submitting...' : 'Submit project';
	}

	get primaryIcon() {
		return this.isReviewStep ? 'utility:send' : 'utility:chevronright';
	}

	// Handlers

	handleFieldChange(event) {
		const { name, value } = event.detail || {};
		if (!name) {
			return;
		}
		this.values = applyFieldChange(
			this.values,
			name,
			value,
			this.formOptions
		);
		this.refreshDerived();
		this.isDirty = true;
	}

	handlePrimary() {
		if (this.isReviewStep) {
			this.handleSubmit();
		} else {
			this.handleNext();
		}
	}

	handleNext() {
		if (!this.validateActiveStep()) {
			return;
		}
		this.goToIndex(this.currentIndex + 1);
	}

	handleBack() {
		this.goToIndex(this.currentIndex - 1);
	}

	handleStepSelect(event) {
		const index = Number(event.detail && event.detail.index);
		if (Number.isNaN(index) || index > this.maxVisitedIndex) {
			return;
		}
		// Jumping forward must not skip validation of the current step.
		if (index > this.currentIndex && !this.validateActiveStep()) {
			return;
		}
		this.goToIndex(index);
	}

	handleEditStep(event) {
		const stepKey = event.detail && event.detail.stepKey;
		const index = STEPS.findIndex((step) => step.key === stepKey);
		if (index >= 0) {
			this.goToIndex(index);
		}
	}

	validateActiveStep() {
		const step = this.refs && this.refs.activeStep;
		return !step || step.validate() !== false;
	}

	goToIndex(index) {
		const target = Math.max(0, Math.min(index, STEPS.length - 1));
		if (target === this.currentIndex) {
			return;
		}
		this.currentIndex = target;
		this.maxVisitedIndex = Math.max(this.maxVisitedIndex, target);
		this.submitError = undefined;
		this.scrollToTop();
	}

	scrollToTop() {
		const card = this.refs && this.refs.card;
		if (card && typeof card.scrollIntoView === 'function') {
			card.scrollIntoView({ behavior: 'smooth', block: 'start' });
		}
	}

	// Submit

	async handleSubmit() {
		if (this.isSubmitting) {
			return;
		}
		this.isSubmitting = true;
		this.submitError = undefined;
		try {
			await submitIntake({
				requestJson: JSON.stringify(buildRequest(this.values))
			});
			this.isSubmitted = true;
			this.removeUnloadListener();
			window.location.assign(this.targetUrl);
		} catch (error) {
			this.submitError = reduceErrors(error) || SUBMIT_ERROR;
			this.isSubmitting = false;
		}
	}

	get targetUrl() {
		const url = (this.redirectUrl || '').trim();
		return SAFE_URL.test(url) ? url : DEFAULT_REDIRECT_URL;
	}

	// Leave-page warning

	handleBeforeUnload = (event) => {
		if (this.isDirty && !this.isSubmitted) {
			event.preventDefault();
			event.returnValue = '';
		}
	};

	removeUnloadListener() {
		window.removeEventListener('beforeunload', this.handleBeforeUnload);
	}
}
