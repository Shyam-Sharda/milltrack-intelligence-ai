import { LightningElement, wire } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import FIRST_NAME_FIELD from '@salesforce/schema/User.FirstName';
import 	MillTrack_Intelligence_noBackground from '@salesforce/resourceUrl/MillTrack_Intelligence_noBackground';

export default class ManagerHomeWorkspace extends LightningElement {

    managerFirstName = 'Manager';
    millTrackLogoUrl = 	MillTrack_Intelligence_noBackground;


    // =========================================================
    // Current User
    // =========================================================

    @wire(getRecord, {
        recordId: USER_ID,
        fields: [FIRST_NAME_FIELD]
    })
    wiredCurrentUser({ data }) {
        if (data) {
            this.managerFirstName = getFieldValue(data, FIRST_NAME_FIELD) || 'Manager';
        }
    }
}