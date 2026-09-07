import { LightningElement, wire } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import FIRST_NAME_FIELD from '@salesforce/schema/User.FirstName';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

export default class MillTrackWelcome extends LightningElement {
    userId = USER_ID;

    @wire(getRecord, {
        recordId: '$userId',
        fields: [FIRST_NAME_FIELD]
    })
    user;

    get firstName() {
        return getFieldValue(this.user.data, FIRST_NAME_FIELD);
    }

    get welcomeTitle() {
        return this.firstName
            ? `Welcome to MillTrack, ${this.firstName}`
            : 'Welcome to MillTrack';
    }
}