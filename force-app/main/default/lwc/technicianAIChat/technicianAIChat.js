import { LightningElement, api } from 'lwc';
import sendMessage from '@salesforce/apex/TechnicianAIChatController.sendMessage';

export default class TechnicianAIChat extends LightningElement {
    @api recordId;

    sessionId;
    draftMessage = '';
    isLoading = false;
    nextMessageId = 2;

    messages = [
        {
            id: 1,
            senderLabel: 'Technician AI',
            text:
                'I’m ready to help with this Work Order. Ask for a briefing, repair guidance, parts information, or machine history.',
            wrapperClass: 'assistant-message',
            bubbleClass: 'assistant-bubble'
        }
    ];

    get isSendDisabled() {
        return this.isLoading || !this.draftMessage.trim();
    }

    handleMessageChange(event) {
        this.draftMessage = event.target.value;
    }

    handleSuggestedPrompt(event) {
        const message = event.currentTarget.dataset.message;

        if (!message || this.isLoading) {
            return;
        }

        this.draftMessage = message;
        this.submitMessage(message);
    }

    handleSend() {
        const message = this.draftMessage.trim();

        if (!message || this.isLoading) {
            return;
        }

        this.submitMessage(message);
    }

    async submitMessage(message) {
        const cleanedMessage = message.trim();

        if (!cleanedMessage || this.isLoading) {
            return;
        }

        this.addMessage('Technician', cleanedMessage, true);

        this.draftMessage = '';
        this.isLoading = true;

        this.scrollToLatestMessage();

        try {
            const response = await sendMessage({
                workOrderId: this.recordId,
                userMessage: cleanedMessage,
                sessionId: this.sessionId
            });

            if (!response || !response.message) {
                throw new Error('Technician AI returned an empty response.');
            }

            this.sessionId = response.sessionId;

            this.addMessage('Technician AI', response.message, false);
        } catch (error) {
            this.addMessage('Technician AI', this.getErrorMessage(error), false, true);
        } finally {
            this.isLoading = false;
            this.scrollToLatestMessage();
        }
    }

    addMessage(senderLabel, text, isUserMessage, isError = false) {
        let wrapperClass = 'assistant-message';
        let bubbleClass = 'assistant-bubble';

        if (isUserMessage) {
            wrapperClass = 'user-message';
            bubbleClass = 'user-bubble';
        } else if (isError) {
            bubbleClass = 'assistant-bubble error-bubble';
        }

        const newMessage = {id: this.nextMessageId, senderLabel, text, wrapperClass, bubbleClass};

        this.nextMessageId += 1;
        this.messages = [...this.messages, newMessage];
    }

    getErrorMessage(error) {
        const serverMessage = error?.body?.message;

        if (serverMessage) {
            return `I couldn’t process that request. ${serverMessage}`;
        }

        if (error?.message) {
            return `I couldn’t process that request. ${error.message}`;
        }

        return ('I couldn’t process that request because an unexpected ' + 'error occurred. Please try again.');
    }

    scrollToLatestMessage() {
        window.requestAnimationFrame(() => {
            const messageHistory = this.template.querySelector('[data-id="messageHistory"]');

            if (messageHistory) {
                messageHistory.scrollTop = messageHistory.scrollHeight;
            }
        });
    }
}