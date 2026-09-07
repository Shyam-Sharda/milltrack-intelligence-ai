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
             *
             * Hide the "Need help with something else?" cue because
             * MillTrack AI is active again.
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
             * Salesforce will still display its normal:
             *
             * "MillTrack Customer AI left"
             *
             * transcript message.
             *
             * We then show our own helpful action immediately
             * underneath the MillTrack header.
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


        /*
         * Defensive fallback in case Enhanced Chat does not inject
         * the v2 Send Message API for some reason.
         */
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

            /*
             * Send the phrase as the authenticated customer.
             *
             * Customer AI already understands this phrase through
             * the New Issue Reset path.
             */
            await this.configuration.util.sendTextMessage(
                'Start a new issue'
            );


            /*
             * Hide the cue immediately after the action succeeds.
             *
             * PARTICIPANT_JOINED will also keep it hidden once
             * Agentforce rejoins.
             */
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

            /*
            * MillTrack uses credential-based verified users.
            *
            * For verified users Salesforce ends the current
            * Messaging Session rather than closing the persistent
            * Conversation.
            */
            const endSession =
                this.configuration?.util?.endSession;

            if (typeof endSession === 'function') {

                await endSession.call(
                    this.configuration.util
                );

                /*
                * PARTICIPANT_LEFT should fire when Agentforce leaves.
                * Our existing listener will then show:
                *
                * "Need help with something else?"
                */
                return;
            }

            /*
            * Defensive fallback for contexts where endSession
            * isn't exposed.
            */
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