import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

export default class MillTrackPageHero extends LightningElement {
    currentPageReference;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageReference) {
        this.currentPageReference = pageReference;
    }


    // =========================================================
    // Current Page Information
    // =========================================================

    get objectApiName() {
        return (
            this.currentPageReference?.attributes?.objectApiName ||
            this.currentPageReference?.state?.objectApiName ||
            ''
        );
    }

    get pageName() {
        return (
            this.currentPageReference?.attributes?.name ||
            this.currentPageReference?.attributes?.pageName ||
            ''
        );
    }


    // =========================================================
    // Page Type Detection
    // =========================================================

    get isAssetPage() {
        const objectName = this.objectApiName.toLowerCase();
        const pageName = this.pageName.toLowerCase();

        return (
            objectName === 'asset' ||
            pageName === 'asset_detail__c'
        );
    }

    get isCasePage() {
        const objectName = this.objectApiName.toLowerCase();
        const pageName = this.pageName.toLowerCase();

        return (
            objectName === 'case' ||
            pageName === 'case_detail__c'
        );
    }

    get isWorkOrderPage() {
        const objectName = this.objectApiName.toLowerCase();
        const pageName = this.pageName.toLowerCase();

        return (
            objectName === 'workorder' ||
            pageName === 'work_order_detail__c'
        );
    }

    get isReportIssuePage() {
        return this.pageName.toLowerCase() === 'report_an_issue__c';
    }


    // =========================================================
    // Main Page Content
    // =========================================================

    get pageTitle() {
        if (this.isAssetPage) return 'Milling Machine Details';
        if (this.isCasePage) return 'Service Request Details';
        if (this.isWorkOrderPage) return 'Service Visit Details';
        if (this.isReportIssuePage) return 'Report a Machine Issue';

        return 'MillTrack Customer Portal';
    }

    get pageSubtitle() {
        if (this.isAssetPage) {
            return 'Review your machine information, resources, maintenance plan, and service history in one place.';
        }

        if (this.isCasePage) {
            return 'Review the current status and details of your MillTrack service request.';
        }

        if (this.isWorkOrderPage) {
            return 'Track the scheduling, progress, and service activity for your MillTrack visit.';
        }

        if (this.isReportIssuePage) {
            return 'Select the affected machine and tell us what is happening. MillTrack will create a service request for your account.';
        }

        return 'Manage your machines, service activity, and MillTrack support from one secure workspace.';
    }


    // =========================================================
    // Context Panel
    // =========================================================

    get contextEyebrow() {
        if (this.isAssetPage) return 'Machine Workspace';
        if (this.isCasePage) return 'Service Request';
        if (this.isWorkOrderPage) return 'Service Visit';
        if (this.isReportIssuePage) return 'Customer Support';

        return 'Customer Portal';
    }

    get contextTitle() {
        if (this.isAssetPage) return 'Machine Overview';
        if (this.isCasePage) return 'Request Tracking';
        if (this.isWorkOrderPage) return 'Visit Tracking';
        if (this.isReportIssuePage) return 'Report an Issue';

        return 'MillTrack Workspace';
    }

    get contextSubtitle() {
        if (this.isAssetPage) {
            return 'Details • Manual • Service History';
        }

        if (this.isCasePage) {
            return 'Status • Details • Updates';
        }

        if (this.isWorkOrderPage) {
            return 'Schedule • Progress • Service';
        }

        if (this.isReportIssuePage) {
            return 'Machine • Issue • Review';
        }

        return 'Machines • Service • Support';
    }
}