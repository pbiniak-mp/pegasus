import { LightningElement, api } from 'lwc';

// Progress indicator for the Project Intake form. Visited steps are buttons
// that emit stepselect; the container decides whether the jump is allowed.
export default class ProjectIntakeStepper extends LightningElement {
	@api steps = [];
	@api currentIndex = 0;
	@api maxVisitedIndex = 0;

	get current() {
		return Number(this.currentIndex) || 0;
	}

	get maxVisited() {
		return Math.max(Number(this.maxVisitedIndex) || 0, this.current);
	}

	get stepCount() {
		return (this.steps || []).length;
	}

	get stepNumber() {
		return this.current + 1;
	}

	get currentLabel() {
		const step = (this.steps || [])[this.current];
		return step ? step.label : '';
	}

	get progressStyle() {
		const percent =
			this.stepCount > 1
				? (this.current / (this.stepCount - 1)) * 100
				: 0;
		return `width: ${percent}%;`;
	}

	get items() {
		return (this.steps || []).map((step, index) => {
			const isCurrent = index === this.current;
			const isVisited = index <= this.maxVisited;
			const isComplete = index < this.maxVisited && !isCurrent;
			const classes = ['stepper-item'];
			if (isCurrent) {
				classes.push('stepper-item_current');
			} else if (isComplete) {
				classes.push('stepper-item_complete');
			} else if (isVisited) {
				classes.push('stepper-item_visited');
			}
			if (index <= this.maxVisited) {
				classes.push('stepper-item_reached');
			}
			let status = 'not started';
			if (isCurrent) {
				status = 'current step';
			} else if (isComplete) {
				status = 'completed';
			} else if (isVisited) {
				status = 'visited';
			}
			return {
				key: step.key,
				label: step.label,
				index,
				number: index + 1,
				itemClass: classes.join(' '),
				ariaCurrent: isCurrent ? 'step' : null,
				clickable: isVisited && !isCurrent,
				showCheck: isComplete,
				ariaLabel: `Step ${index + 1}: ${step.label}, ${status}`
			};
		});
	}

	handleClick(event) {
		const index = Number(event.currentTarget.dataset.index);
		if (
			Number.isNaN(index) ||
			index > this.maxVisited ||
			index === this.current
		) {
			return;
		}
		this.dispatchEvent(
			new CustomEvent('stepselect', { detail: { index } })
		);
	}
}
