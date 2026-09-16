import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

import getAssetDetails
    from '@salesforce/apex/CustomerAssetDetailsController.getAssetDetails';

import saveMaintenanceList
    from '@salesforce/apex/CustomerAssetDetailsController.saveMaintenanceList';

import MACHINE_MEDIA
    from '@salesforce/resourceUrl/MillTrack_Machine_Media';

import MANUAL_MEDIA
    from '@salesforce/resourceUrl/MillTrack_Machine_Manuals';

const MAX_MAINTENANCE_LENGTH = 32768;

export default class CustomerAssetDetails extends NavigationMixin(LightningElement) {
    _recordId;
    _isConnected = false;

    asset;
    serviceHistory = [];

    isLoading = true;
    isSavingMaintenance = false;
    isEditingMaintenance = false;

    loadError;
    maintenanceSaveError;
    maintenanceSaveMessage;

    maintenanceDraft = '';

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (value === this._recordId) return;

        this._recordId = value;

        if (this._isConnected && value) {
            this.loadAssetDetails();
        }
    }

    connectedCallback() {
        this._isConnected = true;

        if (this.recordId) {
            this.loadAssetDetails();
        } else {
            this.isLoading = false;
        }
    }


    // =========================================================
    // LOAD
    // =========================================================

    async loadAssetDetails() {
        if (!this.recordId) return;

        this.isLoading = true;
        this.loadError = undefined;

        try {
            const data = await getAssetDetails({
                assetId: this.recordId
            });

            this.asset = this.prepareAsset(data?.asset);

            this.serviceHistory = (data?.serviceHistory || []).map(
                (entry, index) => this.prepareHistoryEntry(entry, index)
            );

            this.maintenanceDraft = this.asset?.maintenanceList || '';
        } catch (error) {
            this.asset = undefined;
            this.serviceHistory = [];

            this.loadError = this.getErrorMessage(
                error,
                'Your machine information could not be loaded.'
            );
        } finally {
            this.isLoading = false;
        }
    }

    prepareAsset(asset) {
        if (!asset) return null;

        return {
            ...asset,

            manufacturerDisplay:
                asset.manufacturer ||
                'Not available',

            modelDisplay:
                asset.model ||
                'Not available',

            serialDisplay:
                asset.serialNumber ||
                'Not available',

            descriptionDisplay:
                asset.description ||
                'No machine description is available.',

            imageUrl:
                this.buildStaticResourceUrl(
                    MACHINE_MEDIA,
                    asset.portalImagePath
                ),

            manualUrl:
                this.buildStaticResourceUrl(
                    MANUAL_MEDIA,
                    asset.portalManualPath
                ),

            hasImage:
                !!asset.portalImagePath?.trim(),

            hasManual:
                !!asset.portalManualPath?.trim(),

            statusDisplay:
                asset.status ||
                'Status unavailable',

            statusClass:
                this.getAssetStatusClass(
                    asset.status
                )
        };
    }

    prepareHistoryEntry(entry, index) {
        const expanded = index === 0;

        return {
            ...entry,
            expanded,
            toggleLabel: expanded ? 'Hide Details' : 'View Details',
            ariaExpanded: expanded ? 'true' : 'false',
            statusClass: this.getHistoryStatusClass(entry.status),
            maintenanceTypeDisplay: entry.maintenanceType || 'Service Visit',
            problemSummaryDisplay: entry.problemSummary || 'No problem summary was recorded for this visit.',
            rootCauseDisplay: entry.rootCause || 'Not recorded',
            repairSummaryDisplay: entry.summary || 'No repair summary was recorded for this visit.',
            partsUsedDisplay: entry.partsUsed || 'No parts recorded',
            workOrderNumberDisplay: entry.workOrderNumber || 'Not available',
            laborHoursDisplay:
                entry.laborHours === null || entry.laborHours === undefined
                    ? 'Not recorded'
                    : `${entry.laborHours} hrs`
        };
    }


    // =========================================================
    // STATE
    // =========================================================

    get hasRecordId() {
        return !!this.recordId;
    }

    get hasLoadError() {
        return !!this.loadError;
    }

    get hasAsset() {
        return !!this.asset;
    }

    get hasMachineImage() {
        return this.asset?.hasImage === true;
    }

    get hasManual() {
        return this.asset?.hasManual === true;
    }

    get hasMaintenanceList() {
        return !!this.asset?.maintenanceList?.trim();
    }

    get hasServiceHistory() {
        return this.serviceHistory.length > 0;
    }

    get serviceHistoryCount() {
        return this.serviceHistory.length;
    }

    get machineImageUrl() {
        return this.asset?.imageUrl || null;
    }

    get manualUrl() {
        return this.asset?.manualUrl || null;
    }

    get assetName() {
        return this.asset?.name || 'Machine';
    }

    get maintenanceDisplay() {
        return this.asset?.maintenanceList || '';
    }

    get maintenanceCharacterCount() {
        return this.maintenanceDraft.length;
    }

    get maintenanceCharacterLabel() {
        return `${this.maintenanceCharacterCount.toLocaleString()} / ${MAX_MAINTENANCE_LENGTH.toLocaleString()}`;
    }

    get isMaintenanceSaveDisabled() {
        return this.isSavingMaintenance ||
            this.maintenanceDraft.length > MAX_MAINTENANCE_LENGTH;
    }

    get maintenanceSaveButtonLabel() {
        return this.isSavingMaintenance
            ? 'Saving...'
            : 'Save List';
    }

    get hasMaintenanceSaveError() {
        return !!this.maintenanceSaveError;
    }

    get hasMaintenanceSaveMessage() {
        return !!this.maintenanceSaveMessage;
    }


    // =========================================================
    // MAINTENANCE LIST
    // =========================================================

    handleEditMaintenance() {
        this.maintenanceDraft = this.asset?.maintenanceList || '';

        this.maintenanceSaveError = undefined;
        this.maintenanceSaveMessage = undefined;
        this.isEditingMaintenance = true;
    }

    handleMaintenanceInput(event) {
        this.maintenanceDraft = event.target.value || '';

        this.maintenanceSaveError = undefined;
        this.maintenanceSaveMessage = undefined;
    }

    handleCancelMaintenance() {
        this.maintenanceDraft = this.asset?.maintenanceList || '';

        this.maintenanceSaveError = undefined;
        this.maintenanceSaveMessage = undefined;
        this.isEditingMaintenance = false;
    }

    async handleSaveMaintenance() {
        if (
            this.isSavingMaintenance ||
            !this.recordId
        ) {
            return;
        }

        if (
            this.maintenanceDraft.length >
            MAX_MAINTENANCE_LENGTH
        ) {
            this.maintenanceSaveError =
                'The maintenance list is too long. Please shorten it before saving.';

            return;
        }

        this.isSavingMaintenance = true;
        this.maintenanceSaveError = undefined;
        this.maintenanceSaveMessage = undefined;

        try {
            const result = await saveMaintenanceList({
                assetId: this.recordId,
                maintenanceList: this.maintenanceDraft
            });

            if (!result?.success) {
                this.maintenanceSaveError =
                    result?.message ||
                    'The maintenance list could not be saved.';

                return;
            }

            this.asset = {
                ...this.asset,
                maintenanceList:
                    result.maintenanceList || ''
            };

            this.maintenanceDraft =
                result.maintenanceList || '';

            this.maintenanceSaveMessage =
                result.message ||
                'Maintenance list saved successfully.';

            this.isEditingMaintenance = false;
        } catch (error) {
            this.maintenanceSaveError = this.getErrorMessage(
                error,
                'The maintenance list could not be saved.'
            );
        } finally {
            this.isSavingMaintenance = false;
        }
    }


    // =========================================================
    // SERVICE HISTORY
    // =========================================================

    handleToggleHistory(event) {
        const historyId = event.currentTarget.dataset.id;

        this.serviceHistory = this.serviceHistory.map(entry => {
            if (entry.id !== historyId) {
                return entry;
            }

            const expanded = !entry.expanded;

            return {
                ...entry,

                expanded,

                toggleLabel:
                    expanded
                        ? 'Hide Details'
                        : 'View Details',

                ariaExpanded:
                    expanded
                        ? 'true'
                        : 'false'
            };
        });
    }

    handleViewWorkOrder(event) {
        const workOrderId = event.currentTarget.dataset.id;

        if (!workOrderId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',

            attributes: {
                recordId: workOrderId,
                objectApiName: 'WorkOrder',
                actionName: 'view'
            }
        });
    }


    // =========================================================
    // STATUS
    // =========================================================

    getAssetStatusClass(status) {
        switch (status) {
            case 'Active':
                return 'status-pill status-green';

            case 'Needs Service':
                return 'status-pill status-orange';

            case 'Temporary Fix Applied':
                return 'status-pill status-tan';

            case 'Out of Service':
                return 'status-pill status-red';

            case 'Retired':
                return 'status-pill status-gray';

            default:
                return 'status-pill status-blue';
        }
    }

    getHistoryStatusClass(status) {
        switch (status) {
            case 'Resolved':
                return 'history-status history-status-green';

            case 'Follow-up Required':
                return 'history-status history-status-orange';

            case 'Completed':
                return 'history-status history-status-blue';

            default:
                return 'history-status history-status-gray';
        }
    }


    // =========================================================
    // HELPERS
    // =========================================================

    buildStaticResourceUrl(baseUrl, relativePath) {
        if (!baseUrl || !relativePath) return null;

        const normalizedPath = relativePath
            .replace(/^\/+/, '')
            .trim();

        const encodedPath = normalizedPath
            .split('/')
            .map(segment => encodeURIComponent(segment))
            .join('/');

        return `${baseUrl}/${encodedPath}`;
    }

    handleRetryLoad() {
        this.loadAssetDetails();
    }

    getErrorMessage(error, fallbackMessage) {
        if (error?.body?.message) {
            return error.body.message;
        }

        if (Array.isArray(error?.body)) {
            return error.body
                .map(item => item.message)
                .filter(Boolean)
                .join(', ');
        }

        if (error?.message) {
            return error.message;
        }

        return fallbackMessage;
    }
}