import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getProgress from '@salesforce/apex/CustomerProgressTrackerController.getProgress';

export default class CustomerWorkOrderProgress extends LightningElement {
    @api recordId;

    progress;
    errorMessage;
    wiredProgressResult;
    isRefreshing = false;

    @wire(getProgress, { recordId: '$recordId' })
    wiredProgress(result) {
        this.wiredProgressResult = result;

        const { data, error } = result;

        if (data) {
            const stages = Array.isArray(data.stages) ? data.stages : [];
            const currentStage = stages.find((stage) => stage.state === 'current');

            this.progress = {
                ...data,
                stages,
                currentStep: currentStage ? currentStage.key : undefined
            };

            this.errorMessage = undefined;
        } else if (error) {
            this.progress = undefined;
            this.errorMessage = this.normalizeError(error);
        }
    }

    get hasProgress() {
        return Boolean(this.progress);
    }

    get showTracker() {
        return this.hasProgress && !this.progress.isCancelled;
    }

    get showCancelledState() {
        return this.hasProgress && this.progress.isCancelled;
    }

    get isLoading() {
        return Boolean(this.recordId) && !this.progress && !this.errorMessage;
    }

    get isMissingRecordId() {
        return !this.recordId;
    }

    get cardTitle() {
        if (this.progress?.workOrderNumber) {
            return `Service Progress · ${this.progress.workOrderNumber}`;
        }

        return 'Service Progress';
    }

    @api
    async refresh() {
        if (!this.wiredProgressResult || this.isRefreshing) {
            return;
        }

        this.isRefreshing = true;

        try {
            await refreshApex(this.wiredProgressResult);
        } finally {
            this.isRefreshing = false;
        }
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map((item) => item.message)
                .filter(Boolean)
                .join(', ');
        }

        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.message) {
            return error.message;
        }

        return 'The service progress could not be loaded. Please try again.';
    }
}