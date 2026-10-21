import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import LOCALE from '@salesforce/i18n/locale';
import TASK_OBJECT from '@salesforce/schema/Task';
import TASK_TYPE_FIELD from '@salesforce/schema/Task.Task_Type__c';
import getOpenTasks from '@salesforce/apex/AccountTodoController.getOpenTasks';
import completeTask from '@salesforce/apex/AccountTodoController.completeTask';
import createTask from '@salesforce/apex/AccountTodoController.createTask';
import scheduleNext from '@salesforce/apex/AccountTodoController.scheduleNext';
import getTaskTypeOptions from '@salesforce/apex/AccountTodoController.getTaskTypeOptions';

const TYPE_ICONS = {
    Call: 'standard:call',
    'First Call': 'standard:call',
    'Web Meeting': 'standard:event',
    'First Meeting': 'standard:event',
    'In-Person Meeting': 'standard:event',
    'Other Meeting': 'standard:event',
    'Joint Sales Call': 'standard:event',
    Meal: 'standard:event',
    Networking: 'standard:event',
    'Distributor Event': 'standard:event',
    Training: 'standard:education',
    'Prospecting Visit': 'standard:location',
    'Drop-In': 'standard:location',
    Trial: 'standard:product',
    'Text Message': 'standard:sms',
};

const DATE_CHIPS = [
    { key: 'today', label: 'Today', offset: 0 },
    { key: 'tomorrow', label: 'Tomorrow', offset: 1 },
    { key: 'nextweek', label: 'Next week', offset: 7 },
];

// Rows shown per group before "Show more".
const GROUP_LIMIT = 5;
const DAY_MS = 86400000;

// Use the Salesforce user's calendar day, including around UTC midnight.
function calendarDate(offset = 0) {
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: TIME_ZONE,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
    }).formatToParts(new Date());
    const part = (type) => parts.find((item) => item.type === type).value;
    const date = new Date(
        `${part('year')}-${part('month')}-${part('day')}T00:00:00Z`,
    );
    date.setUTCDate(date.getUTCDate() + offset);
    return date.toISOString().slice(0, 10);
}

function dayDiff(isoDate, todayIso) {
    return Math.round(
        (Date.parse(`${isoDate}T00:00:00Z`) -
            Date.parse(`${todayIso}T00:00:00Z`)) /
            DAY_MS,
    );
}

function formatDate(isoDate, options) {
    return new Intl.DateTimeFormat(LOCALE, {
        timeZone: 'UTC',
        ...options,
    }).format(new Date(`${isoDate}T00:00:00Z`));
}

// Short, human due label: "3 days overdue", "Today", "Tomorrow", "Fri", "Oct 24".
function dueInfo(isoDate, todayIso) {
    if (!isoDate) {
        return { label: 'No due date', className: 'todo__due todo__due_none' };
    }
    const diff = dayDiff(isoDate, todayIso);
    if (diff < 0) {
        const days = -diff;
        return {
            label: days === 1 ? 'Yesterday' : `${days} days overdue`,
            className: 'todo__due todo__due_overdue',
        };
    }
    if (diff === 0) {
        return { label: 'Today', className: 'todo__due todo__due_today' };
    }
    if (diff === 1) {
        return { label: 'Tomorrow', className: 'todo__due' };
    }
    if (diff < 7) {
        return {
            label: formatDate(isoDate, { weekday: 'long' }),
            className: 'todo__due',
        };
    }
    return {
        label: formatDate(isoDate, { month: 'short', day: 'numeric' }),
        className: 'todo__due',
    };
}

function errorMessage(error) {
    return (
        error?.body?.message ||
        error?.message ||
        'Please try again or contact your administrator.'
    );
}

export default class AccountTodoList extends NavigationMixin(LightningElement) {
    @api recordId;
    tasks = [];
    myTasksOnly = false;
    isLoading = true;
    isBusy = false;
    loadError;
    actionError;
    typeError;
    typeOptions = [];
    taskRecordTypeId;
    wiredTaskResult;
    quickFocused = false;
    newSubject = '';
    newType = '';
    newDueDate = calendarDate(0);
    followUp;
    showOwnerPicker = false;
    completingId;
    expandedGroups = {};
    fallbackRequested = false;
    focusFollowUp = false;

    @wire(getOpenTasks, { recordId: '$recordId', myTasksOnly: '$myTasksOnly' })
    wiredTasks(result) {
        this.wiredTaskResult = result;
        const { data, error } = result;
        if (data) {
            this.tasks = data;
            this.loadError = undefined;
            this.isLoading = false;
        } else if (error) {
            this.tasks = [];
            this.loadError = errorMessage(error);
            this.isLoading = false;
        }
    }

    @wire(getObjectInfo, { objectApiName: TASK_OBJECT })
    wiredTaskInfo({ data, error }) {
        if (data) this.taskRecordTypeId = data.defaultRecordTypeId;
        else if (error) this.loadFallbackTypes();
    }

    @wire(getPicklistValues, {
        recordTypeId: '$taskRecordTypeId',
        fieldApiName: TASK_TYPE_FIELD,
    })
    wiredTaskTypes({ data, error }) {
        if (data) {
            this.typeOptions = data.values;
            this.typeError = undefined;
        } else if (error) this.loadFallbackTypes();
    }

    async loadFallbackTypes() {
        // Task metadata is not supported by UI API in API 65.0 orgs.
        if (this.fallbackRequested) return;
        this.fallbackRequested = true;
        try {
            this.typeOptions = await getTaskTypeOptions();
            this.typeError = undefined;
        } catch (error) {
            this.typeError = errorMessage(error);
        }
    }

    renderedCallback() {
        if (this.focusFollowUp) {
            this.focusFollowUp = false;
            this.template
                .querySelector('[data-form="followup"] lightning-input')
                ?.focus();
        }
    }

    // ---------- Header ----------

    get openCount() {
        return this.tasks.length;
    }

    get overdueCount() {
        const today = calendarDate();
        return this.tasks.filter(
            (task) => task.ActivityDate && task.ActivityDate < today,
        ).length;
    }

    get countBadgeClass() {
        return this.overdueCount
            ? 'todo__count todo__count_alert'
            : 'todo__count';
    }

    get isAllFilter() {
        return String(!this.myTasksOnly);
    }

    get isMineFilter() {
        return String(this.myTasksOnly);
    }

    get allFilterClass() {
        return this.myTasksOnly
            ? 'todo__segment'
            : 'todo__segment todo__segment_active';
    }

    get mineFilterClass() {
        return this.myTasksOnly
            ? 'todo__segment todo__segment_active'
            : 'todo__segment';
    }

    // ---------- Quick add ----------

    get showQuickDetails() {
        return this.quickFocused || Boolean(this.newSubject);
    }

    get quickAddClass() {
        return this.showQuickDetails
            ? 'todo__quick todo__quick_open'
            : 'todo__quick';
    }

    get quickDateChips() {
        return this.dateChips(this.newDueDate);
    }

    get followUpDateChips() {
        return this.dateChips(this.followUp?.dueDate);
    }

    dateChips(selected) {
        return DATE_CHIPS.map((chip) => ({
            ...chip,
            className:
                calendarDate(chip.offset) === selected
                    ? 'todo__chip todo__chip_selected'
                    : 'todo__chip',
        }));
    }

    get activityTypeOptions() {
        return [{ label: 'No type', value: '' }, ...this.typeOptions];
    }

    // ---------- State ----------

    get errorText() {
        return this.loadError || this.actionError || this.typeError;
    }

    get showEmptyState() {
        return (
            !this.isLoading &&
            !this.loadError &&
            !this.followUp &&
            this.tasks.length === 0
        );
    }

    get emptyText() {
        return this.myTasksOnly
            ? 'You have no open to dos here.'
            : 'No open to dos for this record.';
    }

    get disableAdd() {
        return this.isBusy || Boolean(this.followUp);
    }

    get disableCreate() {
        return this.disableSave || !this.newSubject?.trim();
    }

    get disableSave() {
        return this.isBusy || Boolean(this.typeError);
    }

    get disableRows() {
        return this.isBusy || Boolean(this.followUp);
    }

    get showSpinner() {
        return this.isLoading || (this.isBusy && !this.completingId);
    }

    // ---------- Groups ----------

    get groups() {
        const today = calendarDate();
        const groups = [
            { key: 'overdue', label: 'Overdue', tasks: [] },
            { key: 'today', label: 'Today', tasks: [] },
            { key: 'upcoming', label: 'Upcoming', tasks: [] },
            { key: 'undated', label: 'No due date', tasks: [] },
        ];
        const sorted = [...this.tasks].sort((a, b) => {
            const dateOrder = (a.ActivityDate || '9999-12-31').localeCompare(
                b.ActivityDate || '9999-12-31',
            );
            return (
                dateOrder || (a.Subject || '').localeCompare(b.Subject || '')
            );
        });
        sorted.forEach((task) => {
            let index = 3;
            if (task.ActivityDate) {
                if (task.ActivityDate < today) index = 0;
                else if (task.ActivityDate === today) index = 1;
                else index = 2;
            }
            groups[index].tasks.push(this.decorate(task, today));
        });
        return groups
            .filter((group) => group.tasks.length > 0)
            .map((group) => {
                const expanded = this.expandedGroups[group.key];
                const hidden = group.tasks.length - GROUP_LIMIT;
                return {
                    ...group,
                    count: group.tasks.length,
                    headingClass:
                        group.key === 'overdue'
                            ? 'todo__group-heading todo__group-heading_overdue'
                            : 'todo__group-heading',
                    visibleTasks: expanded
                        ? group.tasks
                        : group.tasks.slice(0, GROUP_LIMIT),
                    moreCount: hidden > 0 ? hidden : 0,
                    moreLabel: expanded ? 'Show less' : `Show ${hidden} more`,
                };
            });
    }

    decorate(task, today) {
        const due = dueInfo(task.ActivityDate, today);
        const isMine = task.OwnerId === USER_ID;
        // Skip the record we are already on; show the contact first, else the related record.
        const who = task.WhoId !== this.recordId ? task.Who?.Name : null;
        const what = task.WhatId !== this.recordId ? task.What?.Name : null;
        const subject = task.Subject || 'Untitled to do';
        return {
            ...task,
            iconName: TYPE_ICONS[task.Task_Type__c] || 'standard:task',
            typeLabel: task.Task_Type__c || 'Task',
            subjectLabel: subject,
            tooltip: task.Description
                ? `${subject}\n\n${task.Description}`
                : subject,
            completeLabel: `Mark "${subject}" as done`,
            href: `/lightning/r/Task/${task.Id}/view`,
            dueLabel: due.label,
            dueClass: due.className,
            relatedName: [who, what].filter(Boolean).join(', '),
            ownerLabel: isMine ? null : task.Owner?.Name,
            isHighPriority: task.Priority === 'High',
            rowClass:
                task.Id === this.completingId
                    ? 'todo__row todo__row_completing'
                    : 'todo__row',
        };
    }

    // ---------- Handlers ----------

    handleFilter(event) {
        const myTasksOnly = event.currentTarget.dataset.filter === 'mine';
        if (this.myTasksOnly === myTasksOnly) return;
        this.myTasksOnly = myTasksOnly;
        this.isLoading = true;
        this.tasks = [];
    }

    handleToggleGroup(event) {
        const key = event.currentTarget.dataset.group;
        this.expandedGroups = {
            ...this.expandedGroups,
            [key]: !this.expandedGroups[key],
        };
    }

    handleNavigate(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'Task',
                actionName: 'view',
            },
        });
    }

    handleQuickFocus() {
        this.quickFocused = true;
        this.actionError = undefined;
    }

    handleQuickKeyup(event) {
        if (event.key === 'Enter') {
            this.newSubject = event.target.value;
            this.handleCreate();
        } else if (event.key === 'Escape') {
            this.handleCancelQuick();
        }
    }

    handleCancelQuick() {
        this.quickFocused = false;
        this.newSubject = '';
        this.newType = '';
        this.newDueDate = calendarDate(0);
        this.actionError = undefined;
    }

    handleNewField(event) {
        const field = event.target.name;
        if (field === 'subject') this.newSubject = event.target.value;
        if (field === 'taskType') this.newType = event.detail.value;
        if (field === 'dueDate') this.newDueDate = event.target.value;
    }

    handleDateChip(event) {
        const { form, offset } = event.currentTarget.dataset;
        const date = calendarDate(Number(offset));
        if (form === 'followup') {
            this.followUp = { ...this.followUp, dueDate: date };
        } else {
            this.newDueDate = date;
        }
    }

    handleFollowUpField(event) {
        const field = event.currentTarget.dataset.field || event.target.name;
        const value =
            field === 'ownerId'
                ? event.detail.recordId
                : field === 'taskType'
                  ? event.detail.value
                  : event.target.value;
        this.followUp = { ...this.followUp, [field]: value };
    }

    handleShowOwnerPicker() {
        this.showOwnerPicker = true;
    }

    validateForm(form) {
        const inputs = [
            ...this.template.querySelectorAll(
                `[data-form="${form}"] lightning-input, [data-form="${form}"] lightning-record-picker`,
            ),
        ];
        return inputs.reduce((valid, input) => {
            input.reportValidity();
            return input.checkValidity() && valid;
        }, true);
    }

    async handleCreate() {
        if (this.disableCreate || !this.validateForm('quick')) return;
        this.isBusy = true;
        this.actionError = undefined;
        try {
            const id = await createTask({
                recordId: this.recordId,
                subject: this.newSubject.trim(),
                taskType: this.newType || null,
                dueDate: this.newDueDate || null,
            });
            this.handleCancelQuick();
            await this.refreshAfterSave([id, this.recordId]);
        } catch (error) {
            this.actionError = errorMessage(error);
        } finally {
            this.isBusy = false;
        }
    }

    async handleComplete(event) {
        if (this.isBusy || this.followUp) return;
        const task = this.tasks.find(
            (item) => item.Id === event.currentTarget.dataset.id,
        );
        if (!task) return;
        this.isBusy = true;
        this.completingId = task.Id;
        this.actionError = undefined;
        try {
            await completeTask({ taskId: task.Id, recordId: this.recordId });
            this.followUp = {
                task,
                subject: '',
                taskType: task.Task_Type__c || '',
                dueDate: calendarDate(1),
                ownerId: USER_ID,
            };
            this.showOwnerPicker = false;
            this.quickFocused = false;
            this.focusFollowUp = true;
            this.tasks = this.tasks.filter((item) => item.Id !== task.Id);
            await this.refreshAfterSave(this.relatedIds(task));
        } catch (error) {
            this.actionError = errorMessage(error);
        } finally {
            this.completingId = undefined;
            this.isBusy = false;
        }
    }

    handleSkipFollowUp() {
        this.followUp = undefined;
        this.showOwnerPicker = false;
        this.actionError = undefined;
    }

    async handleScheduleNext() {
        if (this.isBusy || !this.validateForm('followup')) return;
        this.isBusy = true;
        this.actionError = undefined;
        const { task, subject, taskType, dueDate, ownerId } = this.followUp;
        try {
            const id = await scheduleNext({
                taskId: task.Id,
                recordId: this.recordId,
                subject,
                taskType: taskType || null,
                dueDate: dueDate || null,
                ownerId,
            });
            this.followUp = undefined;
            this.showOwnerPicker = false;
            await this.refreshAfterSave([...this.relatedIds(task), id]);
        } catch (error) {
            this.actionError = errorMessage(error);
        } finally {
            this.isBusy = false;
        }
    }

    relatedIds(task) {
        return [
            this.recordId,
            task.Id,
            task.AccountId,
            task.WhoId,
            task.WhatId,
        ];
    }

    async refreshAfterSave(ids) {
        // A successful write must never be presented as a failed write if refresh fails.
        const uniqueIds = [...new Set(ids.filter(Boolean))];
        const results = await Promise.allSettled([
            refreshApex(this.wiredTaskResult),
            notifyRecordUpdateAvailable(
                uniqueIds.map((recordId) => ({ recordId })),
            ),
        ]);
        this.dispatchEvent(new RefreshEvent());
        if (results.some((result) => result.status === 'rejected')) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Activity saved',
                    message:
                        'Refresh the page to see the latest activity timeline.',
                    variant: 'warning',
                }),
            );
        }
    }

    async handleRefresh() {
        this.isBusy = true;
        this.actionError = undefined;
        try {
            await refreshApex(this.wiredTaskResult);
        } catch (error) {
            this.actionError = errorMessage(error);
        } finally {
            this.isBusy = false;
        }
    }
}
