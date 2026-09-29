import { LightningElement, api } from 'lwc';
import MILLTRACK_AGENT_AVATAR from '@salesforce/resourceUrl/MillTrack_Agent_Avatar';
import { dispatchMessagingEvent, MESSAGING_EVENT} from 'lightningsnapin/eventStore';

export default class MillTrackMessagingHeader extends LightningElement {
    botAvatarUrl = MILLTRACK_AGENT_AVATAR;

    @api configuration = {};
    @api conversationStatus;

    showMenu = false;
    startError = '';

    // =========================================================
    // HEADER MENU
    // =========================================================

    handleMenuToggle() {
        this.showMenu = !this.showMenu;
    }

    // =========================================================
    // END CHAT
    // =========================================================

    async handleEndChat() {
        this.showMenu = false;
        this.startError = '';

        try {
            const endSession = this.configuration?.util?.endSession;

            if (typeof endSession === 'function') {
                await endSession.call(
                    this.configuration.util
                );

                return;
            }

            dispatchMessagingEvent(MESSAGING_EVENT.CLOSE_CONVERSATION, {});
        } catch (error) {
            console.error('MillTrack: Unable to end chat.', error);

            this.startError = 'Unable to end the current chat. Please try again.';
        }
    }

    // =========================================================
    // MINIMIZE CHAT
    // =========================================================

    handleMinimize() {
        this.showMenu = false;

        dispatchMessagingEvent(MESSAGING_EVENT.MINIMIZE_BUTTON_CLICK, {});
    }
}