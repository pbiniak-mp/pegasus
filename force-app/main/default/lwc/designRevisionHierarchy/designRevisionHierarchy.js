import { LightningElement, api, wire } from 'lwc';
import getRevisionHierarchy from '@salesforce/apex/DesignRevisionHierarchyController.getRevisionHierarchy';

const COLUMNS = [
    {
        label: 'Name',
        type: 'url',
        fieldName: 'recordUrl',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    { label: 'Revision Number', fieldName: 'revisionNumber', type: 'number' },
    { label: 'Revision Reason', fieldName: 'revisionReason', type: 'text' },
    { label: 'Project Notes', fieldName: 'projectNotes', type: 'text' }
];

export default class DesignRevisionHierarchy extends LightningElement {
    @api recordId;

    columns = COLUMNS;
    expandedRows = [];
    data;
    error;

    @wire(getRevisionHierarchy, { opportunityId: '$recordId' })
    wiredHierarchy({ data, error }) {
        if (data) {
            this.data = data.map(node => this.remapChildren(node));
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message ?? 'An unexpected error occurred.';
            this.data = undefined;
        }
    }

    remapChildren(node) {
        const { children, ...rest } = node;
        return {
            ...rest,
            _children: children?.length ? children.map(child => this.remapChildren(child)) : undefined
        };
    }
}
