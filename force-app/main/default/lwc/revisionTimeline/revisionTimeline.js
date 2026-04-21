import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRevisionsByOpportunity from '@salesforce/apex/RevisionTimelineController.getRevisionsByOpportunity';

const STATUS_BADGE_MAP = {
    'In Progress': 'badge badge-inprogress',
    'In Review': 'badge badge-inreview',
    'Complete': 'badge badge-complete'
};

export default class RevisionTimeline extends NavigationMixin(LightningElement) {
    @api recordId;

    revisions = [];
    isLoading = true;
    errorMessage;

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && this.revisions.length === 0;
    }

    @wire(getRevisionsByOpportunity, { opportunityId: '$recordId' })
    wiredRevisions({ data, error }) {
        if (data) {
            const sorted = [...data].sort((a, b) => {
                if (a.isActive === b.isActive) return 0;
                return a.isActive ? -1 : 1;
            });
            this.revisions = sorted.map((rev, index) => ({
                ...rev,
                isExpanded: rev.isActive === true,
                showLine: index < sorted.length - 1,
                statusBadgeClass: STATUS_BADGE_MAP[rev.status] || 'badge badge-inprogress',
                get chevronClass() {
                    return this.isExpanded ? 'tl-chevron open' : 'tl-chevron';
                }
            }));
            this.errorMessage = undefined;
            this.isLoading = false;
        } else if (error) {
            this.errorMessage = error.body?.message || 'An error occurred loading revisions.';
            this.isLoading = false;
        }
    }

    handleNavigateToRecord(event) {
        event.stopPropagation();
        const revId = event.currentTarget.dataset.revid;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: revId,
                actionName: 'view'
            }
        });
    }

    handleToggle(event) {
        const revId = event.currentTarget.dataset.revid;
        this.revisions = this.revisions.map(rev => {
            if (rev.id === revId) {
                return {
                    ...rev,
                    isExpanded: !rev.isExpanded,
                    get chevronClass() {
                        return this.isExpanded ? 'tl-chevron open' : 'tl-chevron';
                    }
                };
            }
            return rev;
        });
    }
}