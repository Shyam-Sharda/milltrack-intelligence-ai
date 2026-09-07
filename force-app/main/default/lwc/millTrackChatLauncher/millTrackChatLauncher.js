import { LightningElement } from 'lwc';

export default class MillTrackChatLauncher extends LightningElement {
    handleLaunch() {
        window.dispatchEvent(
            new CustomEvent('milltracklaunchchat')
        );
    }
}