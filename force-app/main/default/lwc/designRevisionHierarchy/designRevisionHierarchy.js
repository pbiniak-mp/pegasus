import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRevisionHierarchy from '@salesforce/apex/DesignRevisionHierarchyController.getRevisionHierarchy';

const COLUMNS = [
    {
        label: 'Name',
        type: 'url',
        fieldName: 'recordUrl',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    { label: 'Revision Number', fieldName: 'revisionNumber', type: 'text' },
    { label: 'Revision Reason', fieldName: 'revisionReason', type: 'text' },
    { label: 'Project Notes', fieldName: 'projectNotes', type: 'text' }
];

export default class DesignRevisionHierarchy extends NavigationMixin(LightningElement) {
    @api recordId;

    columns = COLUMNS;
    expandedRows = [];
    data;
    error;

    @wire(getRevisionHierarchy, { opportunityId: '$recordId' })
    wiredHierarchy({ data, error }) {
        if (data) {
            this.data = data.map(node => this.remapChildren(node));
            this.expandedRows = this.collectExpandedIds(this.data);
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message ?? 'An unexpected error occurred.';
            this.data = undefined;
        }
    }

    collectExpandedIds(nodes) {
        let ids = [];
        for (const node of nodes) {
            if (node._children?.length) {
                ids.push(node.id);
                ids = ids.concat(this.collectExpandedIds(node._children));
            }
        }
        return ids;
    }

    remapChildren(node) {
        const { children, ...rest } = node;
        return {
            ...rest,
            _children: children?.length ? children.map(child => this.remapChildren(child)) : undefined
        };
    }

    handleNew() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Design_Revision__c',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: 'Opportunity__c=' + this.recordId
            }
        });
    }
}
