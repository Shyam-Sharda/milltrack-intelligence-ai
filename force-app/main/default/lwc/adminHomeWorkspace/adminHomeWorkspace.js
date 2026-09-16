import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getHomeData from '@salesforce/apex/AdminHomeController.getHomeData';

export default class AdminHomeWorkspace extends NavigationMixin(LightningElement) {
    isLoading = true;
    isRefreshing = false;
    errorMessage;

    wiredHomeResult;

    recentlyViewed = [];
    sections = [];


    // =========================================================
    // Load Data
    // =========================================================

    @wire(getHomeData)
    wiredHome(result) {
        this.wiredHomeResult = result;

        const { data, error } = result;

        if (data) {
            this.prepareHomeData(data);
            this.errorMessage = undefined;
            this.isLoading = false;
        } else if (error) {
            this.recentlyViewed = [];
            this.sections = [];
            this.errorMessage = this.normalizeError(error);
            this.isLoading = false;
        }
    }

    prepareHomeData(data) {
        this.recentlyViewed = (data.recentlyViewed || []).map((item) => ({
            ...item,
            iconName: this.getObjectIcon(item.objectApiName),
            iconClass: `recent-icon ${this.getObjectIconClass(item.objectApiName)}`
        }));

        this.sections = [
            {
                key: 'customerSetup',
                sectionClass: 'workspace-section section-blue',
                eyebrow: 'Customer Setup',
                title: 'Customer Setup',
                subtitle: 'Recently added customers, contacts, and machines.',
                cards: [
                    this.buildCard(
                        'accounts',
                        'Recent Accounts',
                        'Account',
                        'utility:company',
                        (data.accounts || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'Account',
                            primaryText: item.name,
                            secondaryText: item.phone || 'No phone recorded',
                            tertiaryText: item.billingAddress || 'No billing address recorded',
                            createdDate: item.createdDate
                        }))
                    ),

                    this.buildCard(
                        'contacts',
                        'Recent Contacts',
                        'Contact',
                        'utility:user',
                        (data.contacts || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'Contact',
                            primaryText: item.name,
                            secondaryText: item.accountName || 'No account',
                            tertiaryText: this.joinParts([
                                item.mobile,
                                item.email
                            ]),
                            createdDate: item.createdDate
                        }))
                    ),

                    this.buildCard(
                        'assets',
                        'Recent Assets',
                        'Asset',
                        'utility:settings',
                        (data.assets || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'Asset',
                            primaryText: item.name,
                            secondaryText: this.joinParts([
                                item.manufacturer,
                                item.model
                            ]),
                            tertiaryText: this.joinParts([
                                item.serialNumber
                                    ? `S/N ${item.serialNumber}`
                                    : null,
                                item.accountName
                            ]),
                            createdDate: item.createdDate
                        }))
                    )
                ]
            },

            {
                key: 'serviceOperations',
                sectionClass: 'workspace-section section-orange',
                eyebrow: 'Service Operations',
                title: 'Service Operations',
                subtitle: 'Newest customer issues, service visits, and maintenance activity.',
                cards: [
                    this.buildCard(
                        'cases',
                        'Recent Cases',
                        'Case',
                        'utility:case',
                        (data.cases || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'Case',
                            primaryText: item.caseNumber
                                ? `Case #${item.caseNumber}`
                                : 'Service Request',
                            secondaryText: item.subject || 'No subject',
                            tertiaryText: this.joinParts([
                                item.accountName,
                                item.assetName
                            ]),
                            badge: item.status,
                            badgeClass: this.getStatusBadgeClass(item.status),
                            createdDate: item.createdDate
                        }))
                    ),

                    this.buildCard(
                        'workOrders',
                        'Recent Work Orders',
                        'WorkOrder',
                        'standard:work_order',
                        (data.workOrders || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'WorkOrder',
                            primaryText: item.workOrderNumber
                                ? `Work Order #${item.workOrderNumber}`
                                : 'Work Order',
                            secondaryText: item.subject || 'No subject',
                            tertiaryText: item.assetName || 'No machine linked',
                            badge: item.displayStatus,
                            badgeClass: this.getStatusBadgeClass(item.displayStatus),
                            createdDate: item.createdDate,
                            dateLabel: item.scheduledVisit
                                ? 'Scheduled'
                                : 'Added',
                            dateValue: item.scheduledVisit || item.createdDate
                        }))
                    ),

                    this.buildCard(
                        'maintenanceLogs',
                        'Maintenance Logs',
                        'Maintenance_Log__c',
                        'utility:record',
                        (data.maintenanceLogs || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'Maintenance_Log__c',
                            primaryText: item.maintenanceNumber || 'Maintenance Log',
                            secondaryText: item.rootCause || 'Root cause not recorded',
                            tertiaryText: item.maintenanceDate
                                ? 'Maintenance recorded'
                                : 'No maintenance date recorded',
                            badge: item.outcome,
                            badgeClass: this.getMaintenanceBadgeClass(item.outcome),
                            createdDate: item.createdDate,
                            dateLabel: item.maintenanceDate
                                ? 'Maintenance'
                                : 'Added',
                            dateValue: item.maintenanceDate || item.createdDate
                        }))
                    )
                ]
            },

            {
                key: 'partsKnowledge',
                sectionClass: 'workspace-section section-teal',
                eyebrow: 'Parts & Knowledge',
                title: 'Parts & Knowledge',
                subtitle: 'Newest parts, service-part activity, and technical documents.',
                cards: [
                    this.buildCard(
                        'partCatalogs',
                        'Part Catalog',
                        'Part_Catalog__c',
                        'utility:package',
                        (data.partCatalogs || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'Part_Catalog__c',
                            primaryText: item.name,
                            secondaryText: item.partNumber
                                ? `Part #${item.partNumber}`
                                : 'No part number',
                            tertiaryText: this.joinParts([
                                item.manufacturer,
                                item.compatibleModel
                            ]),
                            createdDate: item.createdDate
                        }))
                    ),

                    this.buildCard(
                        'workOrderParts',
                        'Work Order Parts',
                        'Work_Order_Part__c',
                        'utility:cart',
                        (data.workOrderParts || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'Work_Order_Part__c',
                            primaryText: item.partNumber || 'Work Order Part',
                            secondaryText: item.partCatalogName || 'No catalog part',
                            tertiaryText: this.joinParts([
                                item.machineName,
                                item.workOrderNumber
                                    ? `WO #${item.workOrderNumber}`
                                    : null
                            ]),
                            createdDate: item.createdDate
                        }))
                    ),

                    this.buildCard(
                        'serviceManuals',
                        'Service Manuals',
                        'Service_Manual__c',
                        'utility:knowledge_base',
                        (data.serviceManuals || []).map((item) => ({
                            id: item.id,
                            objectApiName: 'Service_Manual__c',
                            primaryText: item.title,
                            secondaryText: this.joinParts([
                                item.manufacturer,
                                item.model
                            ]),
                            tertiaryText: item.documentType || 'Document type not recorded',
                            createdDate: item.createdDate
                        }))
                    )
                ]
            }
        ];
    }


    // =========================================================
    // Card Preparation
    // =========================================================

    buildCard(key, title, objectApiName, iconName, records) {
        return {
            key,
            title,
            objectApiName,
            iconName,
            records: records.map((record) => ({
                ...record,
                hasSecondary: Boolean(record.secondaryText),
                hasTertiary: Boolean(record.tertiaryText),
                hasBadge: Boolean(record.badge),
                dateLabel: record.dateLabel || 'Added',
                dateValue: record.dateValue || record.createdDate
            })),
            hasRecords: records.length > 0
        };
    }

    joinParts(parts) {
        const values = (parts || []).filter(Boolean);
        return values.length ? values.join(' · ') : '';
    }


    // =========================================================
    // Recently Viewed
    // =========================================================

    get hasRecentlyViewed() {
        return this.recentlyViewed.length > 0;
    }

    getObjectIcon(objectApiName) {
        switch (objectApiName) {
            case 'Account':
                return 'utility:company';

            case 'Contact':
                return 'utility:user';

            case 'Asset':
                return 'utility:settings';

            case 'Case':
                return 'utility:case';

            case 'WorkOrder':
                return 'standard:work_order';

            case 'Maintenance_Log__c':
                return 'utility:record';

            case 'Part_Catalog__c':
                return 'utility:package';

            case 'Work_Order_Part__c':
                return 'utility:cart';

            case 'Service_Manual__c':
                return 'utility:knowledge_base';

            default:
                return 'utility:record';
        }
    }

    getObjectIconClass(objectApiName) {
        switch (objectApiName) {
            case 'Account':
            case 'Contact':
            case 'Asset':
                return 'recent-icon-blue';

            case 'Case':
            case 'WorkOrder':
            case 'Maintenance_Log__c':
                return 'recent-icon-orange';

            case 'Part_Catalog__c':
            case 'Work_Order_Part__c':
            case 'Service_Manual__c':
                return 'recent-icon-teal';

            default:
                return 'recent-icon-neutral';
        }
    }


    // =========================================================
    // Badges
    // =========================================================

    getStatusBadgeClass(status) {
        const normalized = (status || '').toLowerCase();

        if (
            normalized.includes('completed') ||
            normalized.includes('closed') ||
            normalized.includes('resolved')
        ) {
            return 'record-badge badge-success';
        }

        if (
            normalized.includes('waiting') ||
            normalized.includes('parts') ||
            normalized.includes('temporary') ||
            normalized.includes('follow-up')
        ) {
            return 'record-badge badge-warning';
        }

        if (
            normalized.includes('progress') ||
            normalized.includes('scheduled') ||
            normalized.includes('assigned')
        ) {
            return 'record-badge badge-info';
        }

        if (normalized.includes('cancel')) {
            return 'record-badge badge-danger';
        }

        return 'record-badge badge-neutral';
    }

    getMaintenanceBadgeClass(outcome) {
        if (outcome === 'Issue Resolved') {
            return 'record-badge badge-success';
        }

        if (outcome === 'Follow-Up Required') {
            return 'record-badge badge-warning';
        }

        return 'record-badge badge-neutral';
    }


    // =========================================================
    // Refresh
    // =========================================================

    async handleRefresh() {
        if (!this.wiredHomeResult || this.isRefreshing) {
            return;
        }

        this.isRefreshing = true;

        try {
            await refreshApex(this.wiredHomeResult);
        } finally {
            this.isRefreshing = false;
        }
    }


    // =========================================================
    // Navigation
    // =========================================================

    handleRecordOpen(event) {
        const recordId = event.currentTarget.dataset.id;
        const objectApiName = event.currentTarget.dataset.object;

        if (!recordId || !objectApiName) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    handleViewAll(event) {
        const objectApiName = event.currentTarget.dataset.object;

        if (!objectApiName) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName,
                actionName: 'list'
            },
            state: {
                filterName: this.getAllListViewName(objectApiName)
            }
        });
    }

    getAllListViewName(objectApiName) {
        const allListViews = {
            Account: 'AllAccounts',
            Contact: 'AllContacts',
            Asset: 'AllAssets',
            Case: 'All_Cases',
            WorkOrder: 'My_Assigned_Work_Orders',
            Maintenance_Log__c: 'All',
            Part_Catalog__c: 'All',
            Work_Order_Part__c: 'All',
            Service_Manual__c: 'All'
        };

        return allListViews[objectApiName] || 'Recent';
    }

    // =========================================================
    // Error Handling
    // =========================================================

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

        return 'The Admin workspace could not be loaded. Please refresh the page and try again.';
    }
}