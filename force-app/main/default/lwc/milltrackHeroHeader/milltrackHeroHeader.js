import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import USER_FIRST_NAME from '@salesforce/schema/User.FirstName';

export default class MilltrackHeroHeader extends LightningElement {
    @api title = 'MillTrack';
    @api subtitle = '';
    @api greetingPrefix = 'Welcome back';

    userFirstName;

    @wire(getRecord, {
        recordId: USER_ID,
        fields: [USER_FIRST_NAME]
    })
    wiredUser({ data }) {
        if (data) {
            this.userFirstName = getFieldValue(data, USER_FIRST_NAME);
        }
    }

    get greeting() {
        return this.userFirstName
            ? `${this.greetingPrefix}, ${this.userFirstName}`
            : this.greetingPrefix;
    }
}