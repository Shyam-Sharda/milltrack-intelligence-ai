import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';

import USER_ID from '@salesforce/user/Id';
import FIRST_NAME_FIELD from '@salesforce/schema/User.FirstName';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import MILLTRACK_LOGO from '@salesforce/resourceUrl/MillTrackLogo';


export default class MillTrackHeader extends NavigationMixin(LightningElement) {

    userId = USER_ID;
    isProfileMenuOpen = false;

    currentPageReference;


    // ================================
    // Logo
    // ================================

    logoUrl = MILLTRACK_LOGO;


    // ================================
    // Current User
    // ================================

    @wire(getRecord, {
        recordId: '$userId',
        fields: [FIRST_NAME_FIELD]
    })
    user;


    get customerName() {
        return getFieldValue(this.user.data, FIRST_NAME_FIELD) || 'Customer';
    }


    // ================================
    // Current Page
    // ================================

    @wire(CurrentPageReference)
    setCurrentPageReference(pageReference) {
        this.currentPageReference = pageReference;
    }


    get currentPageName() {
        return (
            this.currentPageReference?.attributes?.name ||
            this.currentPageReference?.attributes?.pageName ||
            ''
        );
    }


    get isHomePage() {
        const pageName = this.currentPageName.toLowerCase();

        return (
            pageName === 'home' ||
            pageName === ''
        );
    }


    get isReportIssuePage() {
        const pageName = this.currentPageName
            .toLowerCase()
            .replaceAll('_', ' ')
            .replaceAll('-', ' ');

        return pageName.includes('report an issue');
    }


    get homeNavClass() {
        return this.isHomePage
            ? 'nav-item nav-item-active'
            : 'nav-item';
    }


    get reportIssueNavClass() {
        return this.isReportIssuePage
            ? 'nav-item nav-item-active'
            : 'nav-item';
    }


    // ================================
    // Navigation
    // ================================

    handleHomeClick() {
        this.closeProfileMenu();

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Home'
            }
        });
    }


    handleReportIssueClick() {
        this.closeProfileMenu();

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Report_An_Issue__c'
            }
        });
    }


    // ================================
    // Help
    // ================================

    handleHelpClick() {
        /*
         * For version 1, Help sends the customer to
         * the Report an Issue page.
         *
         * We can later change this to open MillTrack AI
         * or display a dedicated Help menu.
         */
        this.handleReportIssueClick();
    }


    // ================================
    // Profile Menu
    // ================================

    toggleProfileMenu() {
        this.isProfileMenuOpen = !this.isProfileMenuOpen;
    }


    closeProfileMenu() {
        this.isProfileMenuOpen = false;
    }


    handleProfileClick() {
        /*
         * Decorative for version 1.
         * Keep the menu item visible without navigating.
         */
        this.closeProfileMenu();
    }


    // ================================
    // Logout
    // ================================

    handleLogout() {
        this.closeProfileMenu();

        window.location.assign('/secur/logout.jsp');
    }
}