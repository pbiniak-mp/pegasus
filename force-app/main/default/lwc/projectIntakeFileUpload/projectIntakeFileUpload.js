import { LightningElement, api } from 'lwc';
import getUploadedFiles from '@salesforce/apex/ProjectIntakeController.getUploadedFiles';
import removeUploadedFile from '@salesforce/apex/ProjectIntakeController.removeUploadedFile';
import { formatFileSize } from 'c/projectIntakeConstants';

const IMAGE_EXTENSIONS = ['jpg', 'jpeg', 'png', 'gif'];
const REQUIRED_MESSAGE = 'Please upload at least one file.';
const UPLOAD_ERROR =
	'We could not process the uploaded file. Please try again.';
const REMOVE_ERROR = 'We could not remove the file. Please try again.';

function reduceError(error, fallback) {
	return (error && error.body && error.body.message) || fallback;
}

function iconFor(extension) {
	const ext = (extension || '').toLowerCase();
	if (ext === 'pdf') {
		return 'doctype:pdf';
	}
	if (IMAGE_EXTENSIONS.includes(ext)) {
		return 'doctype:image';
	}
	return 'doctype:unknown';
}

function displayName(file) {
	const title = file.title || '';
	const ext = file.extension ? `.${file.extension}` : '';
	if (!ext || title.toLowerCase().endsWith(ext.toLowerCase())) {
		return title;
	}
	return `${title}${ext}`;
}

// Keeps only the fileInfo keys the form stores in values.files.
function toFileInfo(result) {
	return {
		contentVersionId: result.contentVersionId,
		title: result.title,
		extension: result.extension,
		sizeBytes: result.sizeBytes,
		category: result.category
	};
}

export default class ProjectIntakeFileUpload extends LightningElement {
	@api category;
	@api label;
	@api accept;
	@api maxFiles;
	@api maxSizeBytes;
	@api token;
	@api files;
	@api required = false;

	isBusy = false;
	errors = [];
	showRequiredError = false;

	@api
	validate() {
		const valid = !this.required || this.fileList.length > 0;
		this.showRequiredError = !valid;
		return valid;
	}

	get fileList() {
		return Array.isArray(this.files) ? this.files : [];
	}

	get fileLimit() {
		const limit = Number(this.maxFiles);
		return limit > 0 ? limit : 1;
	}

	get fileFieldValue() {
		return this.token ? `${this.token}|${this.category}` : '';
	}

	get isMultiple() {
		return this.fileLimit > 1;
	}

	get isFull() {
		return this.fileList.length >= this.fileLimit;
	}

	get showUploader() {
		return !this.isFull;
	}

	get uploadDisabled() {
		return !this.token || this.isBusy;
	}

	get uploadLabel() {
		return this.isMultiple ? 'Upload files' : 'Upload file';
	}

	get helperText() {
		const types = (this.accept || '')
			.split(',')
			.map((item) => item.trim().replace(/^\./, '').toUpperCase())
			.filter((item) => item && item !== 'JPEG');
		const parts = [];
		if (types.length) {
			parts.push(`Allowed: ${types.join(', ')}.`);
		}
		if (this.maxSizeBytes) {
			parts.push(`Max ${formatFileSize(Number(this.maxSizeBytes))}.`);
		}
		if (this.isMultiple) {
			parts.push(`Up to ${this.fileLimit} files.`);
		}
		return parts.join(' ');
	}

	get hasFiles() {
		return this.fileList.length > 0;
	}

	get fileRows() {
		return this.fileList.map((file) => {
			const name = displayName(file);
			return {
				key: file.contentVersionId,
				contentVersionId: file.contentVersionId,
				name,
				size: file.sizeBytes ? formatFileSize(file.sizeBytes) : '',
				icon: iconFor(file.extension),
				removeLabel: `Remove ${name}`,
				removeDisabled: this.isBusy
			};
		});
	}

	get hasErrors() {
		return this.errors.length > 0;
	}

	get requiredErrorVisible() {
		return this.showRequiredError && !this.hasFiles;
	}

	get requiredMessage() {
		return REQUIRED_MESSAGE;
	}

	get containerClass() {
		return this.requiredErrorVisible
			? 'file-upload file-upload_invalid'
			: 'file-upload';
	}

	async handleUploadFinished(event) {
		const uploaded = (event.detail && event.detail.files) || [];
		const contentVersionIds = uploaded
			.map((file) => file.contentVersionId)
			.filter((id) => id);
		if (!contentVersionIds.length) {
			return;
		}

		this.isBusy = true;
		this.errors = [];
		const errors = [];
		try {
			const results =
				(await getUploadedFiles({
					token: this.token,
					contentVersionIds
				})) || [];
			const kept = [];
			const overflow = [];
			let slots = this.fileLimit - this.fileList.length;
			results.forEach((result) => {
				if (!result.isValid) {
					errors.push({
						key: result.contentVersionId,
						message: `${displayName(result)}: ${result.errorMessage || UPLOAD_ERROR}`
					});
				} else if (slots > 0) {
					kept.push(toFileInfo(result));
					slots -= 1;
				} else {
					overflow.push(result);
				}
			});

			// lightning-file-upload cannot cap the number of files, so extra ones are removed again.
			for (const result of overflow) {
				errors.push({
					key: result.contentVersionId,
					message: `${displayName(result)}: only ${this.fileLimit} file(s) allowed, the file was not added.`
				});
				try {
					// eslint-disable-next-line no-await-in-loop
					await removeUploadedFile({
						token: this.token,
						contentVersionId: result.contentVersionId
					});
				} catch {
					// The orphaned file is harmless; the server never links it to the lead.
				}
			}

			if (kept.length) {
				this.showRequiredError = false;
				this.emitFiles([...this.fileList, ...kept]);
			}
		} catch (error) {
			errors.push({
				key: 'upload',
				message: reduceError(error, UPLOAD_ERROR)
			});
		} finally {
			this.errors = errors;
			this.isBusy = false;
		}
	}

	async handleRemove(event) {
		const contentVersionId = event.currentTarget.dataset.id;
		if (!contentVersionId || this.isBusy) {
			return;
		}
		this.isBusy = true;
		this.errors = [];
		try {
			await removeUploadedFile({ token: this.token, contentVersionId });
			this.emitFiles(
				this.fileList.filter(
					(file) => file.contentVersionId !== contentVersionId
				)
			);
		} catch (error) {
			this.errors = [
				{ key: 'remove', message: reduceError(error, REMOVE_ERROR) }
			];
		} finally {
			this.isBusy = false;
		}
	}

	emitFiles(files) {
		this.dispatchEvent(
			new CustomEvent('fileschange', {
				detail: { category: this.category, files }
			})
		);
	}
}
