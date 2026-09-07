import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

export default class MillTrackPageHero extends LightningElement {
    currentPageReference;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageReference) {
        this.currentPageReference = pageReference;
    }


    /* =========================================
       Current Page Information
       ========================================= */

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


    /* =========================================
       Page Type Detection
       ========================================= */

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
        const pageName = this.pageName.toLowerCase();

        return pageName === 'report_an_issue__c';
    }

    /* =========================================
       Page Content
       ========================================= */

    get pageTitle() {
        if (this.isAssetPage) {
            return 'Milling Machine Details';
        }

        if (this.isCasePage) {
            return 'Service Request Details';
        }

        if (this.isWorkOrderPage) {
            return 'Service Visit Details';
        }

        if (this.isReportIssuePage) {
            return 'Report a Machine Issue';
        }

        return 'MillTrack';
    }

    get pageSubtitle() {
        if (this.isAssetPage) {
            return 'Review your machine information, service history, and current service activity in one place.';
        }

        if (this.isCasePage) {
            return 'Review the current status and details of your MillTrack service request.';
        }

        if (this.isWorkOrderPage) {
            return 'Track the scheduling and progress of your MillTrack service visit.';
        }

        if (this.isReportIssuePage) {
            return 'Select the affected machine and tell us what is happening. MillTrack will create a service request for your account.';
        }

        return '';
    }
}