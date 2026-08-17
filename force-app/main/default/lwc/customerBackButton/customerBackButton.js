import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class CustomerBackButton extends NavigationMixin(
    LightningElement
) {
    handleBack() {
        if (window.history.length > 1) {
            window.history.back();
            return;
        }

        this.navigateHome();
    }

    navigateHome() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Home'
            }
        });
    }
}