import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getHomeData from '@salesforce/apex/TechnicianHomeController.getHomeData';
import 	MillTrack_Intelligence_noBackground from '@salesforce/resourceUrl/MillTrack_Intelligence_noBackground';

export default class TechnicianHomeDashboard extends NavigationMixin(LightningElement) {
    homeData;
    currentVisit;
    upcomingVisits = [];
    serviceManuals = [];
    similarRepairs = [];
    technicianAvatarUrl = MillTrack_Intelligence_noBackground;

    wiredHomeResult;
    errorMessage;
    isLoading = true;

    // =========================================================
    // Load
    // =========================================================

    @wire(getHomeData)
    wiredHomeData(result) {
        this.wiredHomeResult = result;
        const { data, error } = result;

        if (data) {
            this.errorMessage = null;
            this.prepareHomeData(data);
            this.isLoading = false;
        } else if (error) {
            this.errorMessage = this.reduceError(error);
            this.clearData();
            this.isLoading = false;
        }
    }

    prepareHomeData(data) {
        this.homeData = data;
        this.currentVisit = data.currentVisit ? this.prepareVisit(data.currentVisit) : null;
        this.upcomingVisits = (data.upcomingVisits || []).map(visit => this.prepareVisit(visit));
        this.serviceManuals = (data.serviceManuals || []).map(manual => this.prepareManual(manual));

        this.similarRepairs = (data.similarRepairs || []).map((repair, index) => ({
            ...repair,
            key: repair.maintenanceLogId || repair.workOrderId || `repair-${index}`,
            maintenanceLogNameDisplay: repair.maintenanceLogName || 'Maintenance Log',
            problemSummaryDisplay: repair.problemSummary || 'No problem summary was recorded.',
            repairSummaryDisplay: repair.repairSummary || 'No repair summary was recorded.',
            isExpanded: false,
            toggleIcon: 'utility:chevronright'
        }));
    }

    clearData() {
        this.homeData = null;
        this.currentVisit = null;
        this.upcomingVisits = [];
        this.serviceManuals = [];
        this.similarRepairs = [];
    }

    // =========================================================
    // Visit Preparation
    // =========================================================

    prepareVisit(visit) {
        const scheduledDate = visit.scheduledVisit ? new Date(visit.scheduledVisit) : null;
        const rawSimilarRepairs = visit.similarRepairs?.length ? visit.similarRepairs : (visit.similarRepair ? [visit.similarRepair] : []);
        const similarRepairs = rawSimilarRepairs.map((repair, index) => this.prepareUpcomingSimilarRepair(repair, index));

        return {
            ...visit,
            subjectDisplay: visit.subject || 'Service Visit',
            priorityDisplay: visit.priority || 'Not Set',
            dispatchStatusDisplay: visit.dispatchStatus || visit.status || 'Scheduled',
            priorityClass: this.getPriorityClass(visit.priority),
            statusClass: this.getVisitStatusClass(visit.dispatchStatus),

            accountNameDisplay: visit.accountName || 'Customer not available',
            machineLabelDisplay: visit.machineLabel || visit.assetName || 'Machine not available',
            serialNumberDisplay: visit.serialNumber ? `S/N ${visit.serialNumber}` : 'Serial number unavailable',

            contactNameDisplay: visit.contactName || 'Contact not available',
            contactPhoneDisplay: visit.contactPhone || visit.contactEmail || 'Contact details unavailable',

            caseNumberDisplay: visit.caseNumber ? `Case ${visit.caseNumber}` : 'No linked Service Case',
            caseSubjectDisplay: visit.caseSubject || 'Case details unavailable',

            fullAddressDisplay: visit.fullAddress || 'Service location not available',
            cityDisplay: visit.city || 'Location not available',
            hasAddress: Boolean(visit.fullAddress),

            problemSummaryDisplay: visit.problemSummary || 'No problem summary has been recorded.',
            recommendedFixDisplay: visit.recommendedFixSummary || 'No recommended fix summary has been recorded.',
            recommendedToolsDisplay: visit.recommendedTools || 'No specific tools identified.',

            monthLabel: scheduledDate ? scheduledDate.toLocaleString('en-US', { month: 'short' }).toUpperCase() : 'TBD',
            dayLabel: scheduledDate ? scheduledDate.getDate() : '--',
            timeLabel: scheduledDate ? scheduledDate.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }) : 'Time TBD',

            similarRepairs,
            hasSimilarRepairs: similarRepairs.length > 0
        };
    }

    prepareUpcomingSimilarRepair(repair, index) {
        return {
            ...repair,
            key: repair.maintenanceLogId || repair.workOrderId || `upcoming-repair-${index}`,
            maintenanceLogNameDisplay: repair.maintenanceLogName || 'Maintenance Log'
        };
    }

    // =========================================================
    // Manuals
    // =========================================================

    prepareManual(manual) {
        return {
            ...manual,
            thumbnailUrl: `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=${manual.contentVersionId}`,
            brandLabel: this.getManualBrand(manual.title)
        };
    }

    getManualBrand(title) {
        const normalizedTitle = (title || '').toLowerCase();
        if (normalizedTitle.includes('ceramill')) return 'CERAMILL';
        if (normalizedTitle.includes('dwx') || normalizedTitle.includes('roland')) return 'ROLAND';
        return 'SERVICE MANUAL';
    }

    // =========================================================
    // Display Getters
    // =========================================================

    get technicianFirstName() { return this.homeData?.technicianFirstName || 'Technician'; }
    get hasError() { return Boolean(this.errorMessage); }
    get hasUpcomingVisits() { return this.upcomingVisits.length > 0; }
    get hasServiceManuals() { return this.serviceManuals.length > 0; }
    get hasSimilarRepairs() { return this.similarRepairs.length > 0; }

    get currentVisitHeading() {
        if (!this.currentVisit) return 'Service Visit';
        if (this.currentVisit.isInProgress) return 'Current Service Visit';
        if (this.isToday(this.currentVisit.scheduledVisit)) return 'Today’s Next Service Visit';
        return 'Next Service Visit';
    }

    get currentVisitEyebrow() {
        if (!this.currentVisit) return 'YOUR SERVICE SCHEDULE';
        return this.currentVisit.isInProgress ? 'ACTIVE JOB' : 'UP NEXT';
    }

    // =========================================================
    // Styling
    // =========================================================

    getPriorityClass(priority) {
        switch ((priority || '').toLowerCase()) {
            case 'critical': return 'badge priority-critical';
            case 'high': return 'badge priority-high';
            case 'medium': return 'badge priority-medium';
            case 'low': return 'badge priority-low';
            default: return 'badge priority-default';
        }
    }

    getVisitStatusClass(status) {
        const normalizedStatus = (status || '').toLowerCase();
        if (normalizedStatus === 'in progress') return 'badge status-progress';
        if (normalizedStatus === 'ready_to_assign' || normalizedStatus === 'ready to assign') return 'badge status-ready';
        if (normalizedStatus === 'waiting on parts') return 'badge status-waiting';
        return 'badge status-scheduled';
    }

    // =========================================================
    // Similar Repairs
    // =========================================================

    handleToggleSimilarRepair(event) {
        const maintenanceLogId = event.currentTarget.dataset.id;
        if (!maintenanceLogId) return;

        this.similarRepairs = this.similarRepairs.map(repair => {
            const isTarget = repair.maintenanceLogId === maintenanceLogId;
            const isExpanded = isTarget ? !repair.isExpanded : false;
            return { ...repair, isExpanded, toggleIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright' };
        });
    }

    // =========================================================
    // Navigation
    // =========================================================

    handleOpenWorkOrder(event) {
        const workOrderId = event.currentTarget.dataset.id;
        if (!workOrderId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: workOrderId, objectApiName: 'WorkOrder', actionName: 'view' }
        });
    }

    handleOpenHistoricalRepair(event) {
        const maintenanceLogId = event.currentTarget.dataset.id;
        if (!maintenanceLogId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: maintenanceLogId, objectApiName: 'Maintenance_Log__c', actionName: 'view' }
        });
    }

    handleViewAllWorkOrders() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'WorkOrder', actionName: 'list' },
            state: { filterName: 'My_Assigned_Work_Orders' }
        });
    }

    handleDirections(event) {
        const address = event.currentTarget.dataset.address;
        if (!address) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(address)}` }
        });
    }

    handleOpenManual(event) {
        const contentDocumentId = event.currentTarget.dataset.documentId;
        if (!contentDocumentId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: contentDocumentId }
        });
    }

    // =========================================================
    // Refresh
    // =========================================================

    async handleRefresh() {
        if (!this.wiredHomeResult) return;

        this.isLoading = true;

        try {
            await refreshApex(this.wiredHomeResult);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================
    // Misc
    // =========================================================

    handleThumbnailError(event) { event.target.classList.add('thumbnail-hidden'); }

    isToday(dateValue) {
        if (!dateValue) return false;

        const value = new Date(dateValue);
        const today = new Date();

        return value.getFullYear() === today.getFullYear()
            && value.getMonth() === today.getMonth()
            && value.getDate() === today.getDate();
    }

    reduceError(error) {
        if (!error) return 'An unexpected error occurred.';
        if (Array.isArray(error.body)) return error.body.map(item => item.message).join(', ');
        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;
        return 'An unexpected error occurred while loading the Technician Workspace.';
    }
}