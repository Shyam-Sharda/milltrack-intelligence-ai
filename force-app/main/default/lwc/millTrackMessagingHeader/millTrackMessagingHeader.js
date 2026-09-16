import { LightningElement, api } from 'lwc';

import MILLTRACK_AGENT_AVATAR from '@salesforce/resourceUrl/MillTrack_Agent_Avatar';

import {
    dispatchMessagingEvent,
    assignMessagingEventHandler,
    MESSAGING_EVENT
} from 'lightningsnapin/eventStore';


export default class MillTrackMessagingHeader extends LightningElement {

    botAvatarUrl = MILLTRACK_AGENT_AVATAR;

    // Enhanced Chat v2 injects this configuration object.
    @api configuration = {};

    // Salesforce conversation status.
    @api conversationStatus;


    // =========================================================
    // UI STATE
    // =========================================================

    showMenu = false;

    showNewIssueCue = false;

    isStartingNewIssue = false;

    startError = '';


    // =========================================================
    // BUTTON LABEL
    // =========================================================

    get startButtonLabel() {
        return this.isStartingNewIssue
            ? 'Starting...'
            : 'Start New Issue';
    }


    // =========================================================
    // INITIALIZE MESSAGING EVENT LISTENERS
    // =========================================================

    connectedCallback() {

        try {

            /*
             * Agentforce has joined/rejoined.
             */
            assignMessagingEventHandler(
                MESSAGING_EVENT.PARTICIPANT_JOINED,
                () => {

                    this.showNewIssueCue = false;
                    this.startError = '';

                }
            );


            /*
             * Agentforce has left.
             *
             * Show the Start New Issue cue underneath
             * the MillTrack header.
             */
            assignMessagingEventHandler(
                MESSAGING_EVENT.PARTICIPANT_LEFT,
                () => {

                    this.showNewIssueCue = true;
                    this.showMenu = false;

                }
            );

        } catch (error) {

            /*
             * Header event listeners are an enhancement.
             * Never allow them to break the messaging window.
             */
            console.error(
                'MillTrack Messaging Header event initialization failed.',
                error
            );

        }

    }


    // =========================================================
    // START NEW ISSUE
    // =========================================================

    async handleStartNewIssue() {

        if (this.isStartingNewIssue) {
            return;
        }

        this.showMenu = false;
        this.startError = '';

        const sendTextMessage =
            this.configuration?.util?.sendTextMessage;


        if (typeof sendTextMessage !== 'function') {

            this.startError =
                'Please type "Start a new issue" below to continue.';

            console.error(
                'MillTrack: Enhanced Chat sendTextMessage API is unavailable.'
            );

            return;
        }


        this.isStartingNewIssue = true;


        try {

            await this.configuration.util.sendTextMessage(
                'Start a new issue'
            );


            this.showNewIssueCue = false;

        } catch (error) {

            console.error(
                'MillTrack: Unable to start a new issue.',
                error
            );


            this.startError =
                'Unable to start automatically. Please type "Start a new issue" below.';

        } finally {

            this.isStartingNewIssue = false;

        }

    }


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

            const endSession =
                this.configuration?.util?.endSession;


            if (typeof endSession === 'function') {

                await endSession.call(
                    this.configuration.util
                );

                return;
            }


            dispatchMessagingEvent(
                MESSAGING_EVENT.CLOSE_CONVERSATION,
                {}
            );

        } catch (error) {

            console.error(
                'MillTrack: Unable to end chat.',
                error
            );


            this.startError =
                'Unable to end the current chat. Please try again.';

        }

    }


    // =========================================================
    // MINIMIZE CHAT
    // =========================================================

    handleMinimize() {

        this.showMenu = false;


        dispatchMessagingEvent(
            MESSAGING_EVENT.MINIMIZE_BUTTON_CLICK,
            {}
        );

    }

}