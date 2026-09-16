import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getServiceIntelligence from '@salesforce/apex/ManagerServiceIntelligenceController.getServiceIntelligence';

const PERIODS = [
    { days: 30, label: '30 Days' },
    { days: 90, label: '90 Days' },
    { days: 180, label: '6 Months' },
    { days: 365, label: '1 Year' }
];

export default class ManagerServiceIntelligence extends NavigationMixin(LightningElement) {

    selectedDaysBack = 90;
    intelligenceData;
    models = [];
    expandedModelKey;

    isLoading = true;
    errorMessage;


    // =========================================================
    // Lifecycle
    // =========================================================

    connectedCallback() {
        this.loadIntelligence();
    }


    renderedCallback() {
        const serviceLoadBars = this.template.querySelectorAll('.service-load-fill');

        serviceLoadBars.forEach(bar => {
            const width = Math.max(0, Math.min(Number(bar.dataset.width || 0), 100));
            bar.style.width = `${width}%`;
        });
    }


    // =========================================================
    // Load
    // =========================================================

    async loadIntelligence() {
        this.isLoading = true;
        this.errorMessage = null;

        try {
            const data = await getServiceIntelligence({ daysBack: this.selectedDaysBack });

            this.intelligenceData = data;
            this.models = this.prepareModels(data?.models || []);
        } catch (error) {
            this.intelligenceData = null;
            this.models = [];
            this.expandedModelKey = null;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }


    // =========================================================
    // Model Preparation
    // =========================================================

    prepareModels(models) {
        return models.map(modelRecord => {
            const modelKey = `${modelRecord.manufacturer || ''}|${modelRecord.model || ''}|${modelRecord.machineLabel || ''}`;
            const isExpanded = modelKey === this.expandedModelKey;
            const serviceLoadPercent = Math.max(0, Math.min(Number(modelRecord.serviceLoadPercent || 0), 100));

            return {
                ...modelRecord,
                modelKey,
                isExpanded,
                serviceLoadPercent,

                visitLabel: `${modelRecord.serviceVisitCount || 0} ${modelRecord.serviceVisitCount === 1 ? 'Visit' : 'Visits'}`,
                laborHoursDisplay: this.formatHours(modelRecord.laborHours),

                rankClass: this.getRankClass(modelRecord.rank),

                expandLabel: isExpanded ? 'Hide Latest Activity' : 'View Latest Activity',
                expandIcon: isExpanded ? 'utility:chevronup' : 'utility:chevrondown',

                latestMaintenanceLogDisplay: modelRecord.latestMaintenanceLogName || 'Maintenance Log',
                latestDateLabel: this.formatDate(modelRecord.latestMaintenanceDate),
                latestAccountDisplay: modelRecord.latestAccountName || 'Customer unavailable',
                latestCaseDisplay: modelRecord.latestCaseNumber ? `Case ${modelRecord.latestCaseNumber}` : 'No linked Service Case',
                latestCaseSubjectDisplay: modelRecord.latestCaseSubject || 'No Case subject available.',
                latestTechnicianDisplay: modelRecord.latestTechnicianName || 'Technician unavailable',

                latestProblemSummaryDisplay: modelRecord.latestProblemSummary || 'No problem summary was recorded.',
                latestRootCauseDisplay: modelRecord.latestRootCause || 'No root cause was recorded.',
                latestSummaryDisplay: modelRecord.latestRepairSummary || 'No service summary was recorded.',

                latestOutcomeClass: `latest-outcome-badge ${this.getLatestOutcomeClass(modelRecord.latestOutcomeKey)}`,
                showLatestMaintenanceAction: Boolean(modelRecord.latestMaintenanceLogId),
                hasLatestActivity: Boolean(modelRecord.latestMaintenanceLogId)
            };
        });
    }


    // =========================================================
    // Reporting Period
    // =========================================================

    async handlePeriodChange(event) {
        const daysBack = Number(event.currentTarget.dataset.days);

        if (!daysBack || daysBack === this.selectedDaysBack) return;

        this.selectedDaysBack = daysBack;
        this.expandedModelKey = null;

        await this.loadIntelligence();
    }


    async handleRefresh() {
        await this.loadIntelligence();
    }


    // =========================================================
    // Expand / Collapse
    // =========================================================

    handleToggleModel(event) {
        const modelKey = event.currentTarget.dataset.key;

        this.expandedModelKey = this.expandedModelKey === modelKey ? null : modelKey;
        this.models = this.prepareModels(this.intelligenceData?.models || []);
    }


    // =========================================================
    // Navigation
    // =========================================================

    handleOpenMaintenanceLog(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Maintenance_Log__c', actionName: 'view' }
        });
    }


    // =========================================================
    // Styling
    // =========================================================

    getRankClass(rank) {
        if (rank === 1) return 'rank-badge rank-badge_first';
        if (rank === 2) return 'rank-badge rank-badge_second';
        if (rank === 3) return 'rank-badge rank-badge_third';

        return 'rank-badge';
    }


    getLatestOutcomeClass(outcomeKey) {
        switch (outcomeKey) {
            case 'RESOLVED': return 'latest-outcome_resolved';
            case 'FOLLOW_UP': return 'latest-outcome_follow-up';
            case 'TEMPORARY_REPAIR': return 'latest-outcome_temporary';
            default: return 'latest-outcome_service';
        }
    }


    // =========================================================
    // Display Getters
    // =========================================================

    get periodOptions() {
        return PERIODS.map(period => ({
            ...period,
            buttonClass: period.days === this.selectedDaysBack
                ? 'period-button period-button_selected'
                : 'period-button'
        }));
    }


    get periodLabel() {
        const selectedPeriod = PERIODS.find(period => period.days === this.selectedDaysBack);
        return selectedPeriod ? selectedPeriod.label : `${this.selectedDaysBack} Days`;
    }


    get totalServiceVisits() {
        return this.intelligenceData?.totalServiceVisits || 0;
    }


    get totalIssues() {
        return this.intelligenceData?.totalIssues || 0;
    }


    get totalLaborHours() {
        return this.formatHours(this.intelligenceData?.totalLaborHours || 0);
    }


    get totalFollowUps() {
        return this.intelligenceData?.totalFollowUps || 0;
    }


    get totalResolvedVisits() {
        return this.intelligenceData?.totalResolvedVisits || 0;
    }


    get modelCount() {
        return this.intelligenceData?.modelCount || 0;
    }


    get hasModels() {
        return this.models.length > 0;
    }


    get hasError() {
        return Boolean(this.errorMessage);
    }


    get reportingRangeLabel() {
        const startDate = this.formatDate(this.intelligenceData?.startDate);
        const endDate = this.formatDate(this.intelligenceData?.endDate);

        if (!startDate || !endDate) return '';

        return `${startDate} – ${endDate}`;
    }


    get resolvedSummaryLabel() {
        const count = this.totalResolvedVisits;
        return `${count} resolved ${count === 1 ? 'visit' : 'visits'}`;
    }


    // =========================================================
    // Formatting
    // =========================================================

    formatHours(value) {
        const hours = Number(value || 0);

        if (Number.isInteger(hours)) return `${hours}`;
        return hours.toFixed(1);
    }


    formatDate(dateValue) {
        if (!dateValue) return '';

        const parts = String(dateValue).split('-');

        if (parts.length === 3) {
            const [year, month, day] = parts.map(Number);
            const localDate = new Date(year, month - 1, day);

            return localDate.toLocaleDateString('en-US', {
                month: 'short',
                day: 'numeric',
                year: 'numeric'
            });
        }

        return '';
    }


    // =========================================================
    // Errors
    // =========================================================

    reduceError(error) {
        if (!error) return 'An unexpected error occurred while loading service intelligence.';
        if (Array.isArray(error.body)) return error.body.map(item => item.message).join(', ');
        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;

        return 'An unexpected error occurred while loading service intelligence.';
    }
}